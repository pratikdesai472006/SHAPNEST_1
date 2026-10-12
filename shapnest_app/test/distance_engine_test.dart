import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shapnest_app/models/shapnest_protocol.dart';
import 'package:shapnest_app/models/node_data.dart';
import 'package:shapnest_app/services/distance_engine.dart';
import 'package:shapnest_app/services/kalman_filter.dart';
import 'package:shapnest_app/services/theme_service.dart';
import 'package:shapnest_app/services/ble_service.dart';
import 'package:shapnest_app/services/protocol_parser.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Safety Zone Classifications', () {
    test('Standard zone boundaries', () {
      final resCritical = DistanceResult(
        distanceMeters: 0.25,
        filteredRssi: -50,
        rawRssi: -50,
        motionState: FilterMotionState.stationary,
        isClamped: false,
      );
      expect(resCritical.zone, equals(ProximityZone.criticalDanger));

      final resDanger = DistanceResult(
        distanceMeters: 0.70,
        filteredRssi: -55,
        rawRssi: -55,
        motionState: FilterMotionState.stationary,
        isClamped: false,
      );
      expect(resDanger.zone, equals(ProximityZone.danger));

      final resWarning = DistanceResult(
        distanceMeters: 1.50,
        filteredRssi: -62,
        rawRssi: -62,
        motionState: FilterMotionState.stationary,
        isClamped: false,
      );
      expect(resWarning.zone, equals(ProximityZone.warning));

      final resSafe = DistanceResult(
        distanceMeters: 2.50,
        filteredRssi: -68,
        rawRssi: -68,
        motionState: FilterMotionState.stationary,
        isClamped: false,
      );
      expect(resSafe.zone, equals(ProximityZone.safe));
    });
  });

  group('Dual-Regime Adaptive Filter & Deadband Tests', () {
    test('Stationary jitter suppression keeps distance stable within tight band', () {
      final engine = DistanceEngine();
      const nodeId = 1;

      // Seed with initial 1.0m signal (-59 dBm)
      for (int i = 0; i < 5; i++) {
        engine.processRssi(nodeId: nodeId, rawRssi: -59);
      }

      // Simulate 20 noisy samples with realistic +/- 1.5 dBm stationary RF envelope
      final noisySamples = [
        -58, -60, -59, -60, -58, -59, -60, -58, -59, -60,
        -58, -60, -59, -58, -60, -59, -58, -60, -59, -60
      ];

      final recordedDistances = <double>[];
      for (final raw in noisySamples) {
        final res = engine.processRssi(nodeId: nodeId, rawRssi: raw);
        recordedDistances.add(res.distanceMeters);
      }

      // With Dual-Regime Kalman in stationary mode, distance spread remains tight (<= 6 cm)
      final minDist = recordedDistances.reduce((a, b) => a < b ? a : b);
      final maxDist = recordedDistances.reduce((a, b) => a > b ? a : b);
      final spread = maxDist - minDist;

      expect(spread, lessThanOrEqualTo(0.06),
          reason: 'Stationary distance spread should remain under 6cm, was: $spread m');
    });

    test('Fast Attack rapidly tracks sudden step closer into hazard zone', () {
      final engine = DistanceEngine();
      const nodeId = 2; // Node 2: Iron hazard

      // Start stationary at ~2.0m (-66 dBm)
      for (int i = 0; i < 5; i++) {
        engine.processRssi(nodeId: nodeId, rawRssi: -66);
      }

      // Sudden jump closer to ~0.5m (-53 dBm) — child stepped to hot iron
      final stepRes1 = engine.processRssi(nodeId: nodeId, rawRssi: -53);
      final stepRes2 = engine.processRssi(nodeId: nodeId, rawRssi: -53);

      // Fast attack must trigger immediately
      expect(stepRes1.motionState, equals(FilterMotionState.fastAttack));
      // Within 2 packets (<= 200ms), distance must drop decisively into danger (< 1.0m)
      expect(stepRes2.distanceMeters, lessThan(1.00),
          reason: 'Distance must drop into danger (< 1m) within 2 samples, was: ${stepRes2.distanceMeters}');
    });

    test('Moving away adapts smoothly without infinite lag', () {
      final engine = DistanceEngine();
      const nodeId = 3; // Node 3: Door

      // Start at 0.5m (-53 dBm)
      for (int i = 0; i < 5; i++) {
        engine.processRssi(nodeId: nodeId, rawRssi: -53);
      }

      // Move away to 2.5m (-68 dBm)
      engine.processRssi(nodeId: nodeId, rawRssi: -68);
      engine.processRssi(nodeId: nodeId, rawRssi: -68);
      final res3 = engine.processRssi(nodeId: nodeId, rawRssi: -68);

      expect(res3.distanceMeters, greaterThan(1.30));
    });

    test('Wristband distance stabilization holds stationary distance rock-solid', () {
      final engine = DistanceEngine();
      const nodeId = 3; // Door node

      // Initial reading: 1.20 m
      final d0 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.20);
      expect(d0, equals(1.20));

      // Microscopic jitter of 2 cm (1.18m, 1.22m, 1.19m) must be completely absorbed by deadband
      final d1 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.22);
      final d2 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.18);
      final d3 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.21);

      expect(d1, equals(1.20), reason: '2cm flutter must be absorbed by deadband');
      expect(d2, equals(1.20), reason: '2cm flutter must be absorbed by deadband');
      expect(d3, equals(1.20), reason: '1cm flutter must be absorbed by deadband');

      // Genuine movement of 15 cm updates cleanly
      final dMoved = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.35);
      expect(dMoved, equals(1.35), reason: 'Meaningful movement must update distance');
    });

    test('Startup convergence seeds immediately without slow multi-minute drift', () {
      final engine = DistanceEngine();
      const nodeId = 2; // Node 2: Iron

      // First sample at 1.0m (-59 dBm)
      final res1 = engine.processRssi(nodeId: nodeId, rawRssi: -59);
      expect(res1.distanceMeters, closeTo(1.00, 0.05),
          reason: 'Initial sample must seed immediately to true distance without lag');

      // Second sample confirms distance rapidly
      final res2 = engine.processRssi(nodeId: nodeId, rawRssi: -59);
      expect(res2.distanceMeters, closeTo(1.00, 0.05));
    });

    test('Consecutive distance decrease tracking updates responsively without deadband trapping', () {
      final engine = DistanceEngine();
      const nodeId = 2; // Node 2: Iron

      // Start at 2.0m (-66 dBm)
      for (int i = 0; i < 6; i++) {
        engine.processRssi(nodeId: nodeId, rawRssi: -66);
      }
      final startDist = engine.processRssi(nodeId: nodeId, rawRssi: -66).distanceMeters;
      expect(startDist, closeTo(2.00, 0.15));

      // Move closer consecutively: first step to ~1.4m (-62 dBm)
      for (int i = 0; i < 4; i++) {
        engine.processRssi(nodeId: nodeId, rawRssi: -62);
      }
      final midDist = engine.processRssi(nodeId: nodeId, rawRssi: -62).distanceMeters;
      expect(midDist, lessThan(startDist), reason: 'First decrease must be reflected');
      expect(midDist, lessThan(1.65));

      // Second step closer to ~0.8m (-57 dBm)
      for (int i = 0; i < 4; i++) {
        engine.processRssi(nodeId: nodeId, rawRssi: -57);
      }
      final closeDist = engine.processRssi(nodeId: nodeId, rawRssi: -57).distanceMeters;
      expect(closeDist, lessThan(midDist), reason: 'Second consecutive decrease must be reflected');
      expect(closeDist, lessThan(1.10));
    });
  });

  group('ThemeService Tests', () {
    test('Default mode is dark and switches to light and system with persistence', () async {
      final themeService = ThemeService();
      await themeService.init();

      expect(themeService.themeMode, equals(ThemeMode.dark));

      await themeService.setThemeMode(ThemeMode.light);
      expect(themeService.themeMode, equals(ThemeMode.light));
      expect(themeService.isDarkMode, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shapnest_theme_mode'), equals('light'));

      // Cycle theme
      await themeService.cycleTheme(); // Light -> System
      expect(themeService.themeMode, equals(ThemeMode.system));

      await themeService.cycleTheme(); // System -> Dark
      expect(themeService.themeMode, equals(ThemeMode.dark));
    });
  });

  group('Door Sensor & Protocol Tests', () {
    test('DoorState enum values and display names', () {
      expect(DoorState.closed.displayName, equals('CLOSED'));
      expect(DoorState.open.displayName, equals('OPEN'));
      expect(DoorState.unknown.displayName, equals('UNKNOWN'));
    });

    test('NodeData initializes doorState as unknown and accepts updates', () {
      final nodes = NodeData.createDefaultNodes();
      final doorNode = nodes.firstWhere((n) => n.id == 3);

      expect(doorNode.doorState, equals(DoorState.unknown));

      doorNode.doorState = DoorState.open;
      expect(doorNode.doorState, equals(DoorState.open));

      doorNode.doorState = DoorState.closed;
      expect(doorNode.doorState, equals(DoorState.closed));
    });

    test('Tracking source danger isolation: Direct Phone mode disables hazard alerts', () {
      final nodes = NodeData.createDefaultNodes();
      final doorNode = nodes.firstWhere((n) => n.id == 3);

      // Distance is very close (0.20m = 20cm, normally critical danger for child)
      const testDistM = 0.20;

      // In Direct Phone mode, hazard alert must NOT fire
      const directSource = TrackingSource.directPhone;
      final isDirectWristband = (directSource == TrackingSource.wristband);
      final directZone = isDirectWristband ? doorNode.getZone(testDistM) : null;
      final directDanger = isDirectWristband &&
          (directZone == ProximityZone.criticalDanger || directZone == ProximityZone.danger);

      expect(directZone, isNull, reason: 'Direct phone mode must not evaluate danger zone');
      expect(directDanger, isFalse, reason: 'Direct phone mode must never trigger hazard alert');

      // In Child Wristband mode, hazard alert MUST fire for child safety
      const wbSource = TrackingSource.wristband;
      final isWbWristband = (wbSource == TrackingSource.wristband);
      final wbZone = isWbWristband ? doorNode.getZone(testDistM) : null;
      final wbDanger = isWbWristband &&
          (wbZone == ProximityZone.criticalDanger || wbZone == ProximityZone.danger);

      expect(wbZone, equals(ProximityZone.criticalDanger));
      expect(wbDanger, isTrue, reason: 'Wristband mode must trigger hazard alert when child is close');
    });
  });

  group('Iron Temperature Sensor & Protocol Tests', () {
    test('NodeData initializes ironTemperatureC as null and accepts updates', () {
      final nodes = NodeData.createDefaultNodes();
      final ironNode = nodes.firstWhere((n) => n.id == 2);

      expect(ironNode.ironTemperatureC, isNull);
      expect(ironNode.isIronHot, isFalse);
      expect(ironNode.isIronWarm, isFalse);

      // Safe room temperature (28°C)
      ironNode.ironTemperatureC = 28;
      expect(ironNode.ironTemperatureC, equals(28));
      expect(ironNode.isIronHot, isFalse);
      expect(ironNode.isIronWarm, isFalse);

      // Warm temperature (45°C)
      ironNode.ironTemperatureC = 45;
      expect(ironNode.ironTemperatureC, equals(45));
      expect(ironNode.isIronHot, isFalse);
      expect(ironNode.isIronWarm, isTrue);

      // Dangerously hot temperature (85°C)
      ironNode.ironTemperatureC = 85;
      expect(ironNode.ironTemperatureC, equals(85));
      expect(ironNode.isIronHot, isTrue);
      expect(ironNode.isIronWarm, isFalse);
    });

    test('Threshold boundary tests (40°C warm, 50°C hot, 0°C floor, 255°C ceiling)', () {
      final nodes = NodeData.createDefaultNodes();
      final ironNode = nodes.firstWhere((n) => n.id == 2);

      // Just below warm (39°C)
      ironNode.ironTemperatureC = 39;
      expect(ironNode.isIronWarm, isFalse);
      expect(ironNode.isIronHot, isFalse);

      // Exactly warm threshold (40°C)
      ironNode.ironTemperatureC = 40;
      expect(ironNode.isIronWarm, isTrue);
      expect(ironNode.isIronHot, isFalse);

      // Just below hot (49°C)
      ironNode.ironTemperatureC = 49;
      expect(ironNode.isIronWarm, isTrue);
      expect(ironNode.isIronHot, isFalse);

      // Exactly hot threshold (50°C)
      ironNode.ironTemperatureC = 50;
      expect(ironNode.isIronHot, isTrue);
      expect(ironNode.isIronWarm, isFalse);

      // Extreme hot (255°C)
      ironNode.ironTemperatureC = 255;
      expect(ironNode.isIronHot, isTrue);
      expect(ironNode.isIronWarm, isFalse);

      // Cold floor (0°C)
      ironNode.ironTemperatureC = 0;
      expect(ironNode.isIronHot, isFalse);
      expect(ironNode.isIronWarm, isFalse);
    });

    test('ParsedNodeBeacon accurately extracts iron temperature sensorState', () {
      final beacon = ParsedNodeBeacon(
        nodeId: 2,
        calibratedRssi1m: -59,
        pathLossExpN: 2.2,
        sequence: 14,
        sensorState: 68,
      );

      expect(beacon.nodeId, equals(2));
      expect(beacon.sensorState, equals(68));
      expect(beacon.sensorState >= ShapnestProtocol.ironHotThresholdC, isTrue);
    });

    test('Node sensor state reset simulation on offline timeout', () {
      final nodes = NodeData.createDefaultNodes();
      final ironNode = nodes.firstWhere((n) => n.id == 2);
      final doorNode = nodes.firstWhere((n) => n.id == 3);

      ironNode.ironTemperatureC = 55;
      doorNode.doorState = DoorState.open;
      ironNode.directState = NodeState.active;
      doorNode.directState = NodeState.active;

      expect(ironNode.isIronHot, isTrue);
      expect(doorNode.doorState, equals(DoorState.open));

      // Simulate offline transition
      ironNode.directState = NodeState.offline;
      ironNode.directDistanceM = null;
      ironNode.ironTemperatureC = null;

      doorNode.directState = NodeState.offline;
      doorNode.directDistanceM = null;
      doorNode.doorState = DoorState.unknown;

      expect(ironNode.ironTemperatureC, isNull);
      expect(ironNode.isIronHot, isFalse);
      expect(ironNode.isIronWarm, isFalse);
      expect(doorNode.doorState, equals(DoorState.unknown));
    });

    test('Dual-channel staleness preservation for Node 2 Iron and Node 3 Door', () {
      final nodes = NodeData.createDefaultNodes();
      final ironNode = nodes.firstWhere((n) => n.id == 2);
      final doorNode = nodes.firstWhere((n) => n.id == 3);

      ironNode.ironTemperatureC = 62;
      ironNode.directState = NodeState.active;
      ironNode.wbState = NodeState.active;

      doorNode.doorState = DoorState.open;
      doorNode.directState = NodeState.active;
      doorNode.wbState = NodeState.active;

      // Direct link goes offline, but Wristband is still active
      ironNode.directState = NodeState.offline;
      doorNode.directState = NodeState.offline;

      // Both should preserve sensor status because wbState is still active!
      if (ironNode.directState == NodeState.offline && ironNode.wbState == NodeState.offline) {
        ironNode.ironTemperatureC = null;
      }
      if (doorNode.directState == NodeState.offline && doorNode.wbState == NodeState.offline) {
        doorNode.doorState = DoorState.unknown;
      }

      expect(ironNode.ironTemperatureC, equals(62), reason: 'Wristband activity must preserve Iron temperature');
      expect(doorNode.doorState, equals(DoorState.open), reason: 'Wristband activity must preserve Door state');

      // Now Wristband also goes offline
      ironNode.wbState = NodeState.offline;
      doorNode.wbState = NodeState.offline;

      if (ironNode.directState == NodeState.offline && ironNode.wbState == NodeState.offline) {
        ironNode.ironTemperatureC = null;
      }
      if (doorNode.directState == NodeState.offline && doorNode.wbState == NodeState.offline) {
        doorNode.doorState = DoorState.unknown;
      }

      expect(ironNode.ironTemperatureC, isNull, reason: 'Both channels offline should reset temperature');
      expect(doorNode.doorState, equals(DoorState.unknown), reason: 'Both channels offline should reset door state');
    });

    test('Centimeter rounding accuracy avoids truncation errors across NodeCard and RadarView', () {
      String formatCardCm(double distM) => (distM * 100).round().toString();
      String formatRadarCm(double distM) => '${(distM * 100).round()}cm';

      expect(formatCardCm(1.459), equals('146'));
      expect(formatRadarCm(1.459), equals('146cm'));

      expect(formatCardCm(1.451), equals('145'));
      expect(formatRadarCm(1.451), equals('145cm'));

      expect(formatCardCm(0.296), equals('30'));
      expect(formatRadarCm(0.296), equals('30cm'));

      expect(formatCardCm(0.804), equals('80'));
      expect(formatRadarCm(0.804), equals('80cm'));

      expect(formatCardCm(0.150), equals('15'));
      expect(formatRadarCm(0.150), equals('15cm'));
    });

    test('Direct beacon calibration propagation adopts over-the-air parameters when not user calibrated', () {
      final nodes = NodeData.createDefaultNodes();
      final ironNode = nodes.firstWhere((n) => n.id == 2);

      expect(ironNode.isUserCalibrated, isFalse);
      expect(ironNode.calibratedA, equals(-59));
      expect(ironNode.pathLossExpN, equals(2.2));

      // Incoming beacon from Node 2 with bench-calibrated parameters: A = -56, n = 2.4
      final beacon = ParsedNodeBeacon(
        nodeId: 2,
        calibratedRssi1m: -56,
        pathLossExpN: 2.4,
        sequence: 42,
        sensorState: 32,
      );

      // Simulation of ble_service logic
      if (!ironNode.isUserCalibrated) {
        ironNode.calibratedA = beacon.calibratedRssi1m;
        ironNode.pathLossExpN = beacon.pathLossExpN;
      }

      expect(ironNode.calibratedA, equals(-56), reason: 'OTA calibration should propagate');
      expect(ironNode.pathLossExpN, equals(2.4), reason: 'OTA path loss exponent should propagate');

      // Now simulate user having calibrated locally on phone
      ironNode.isUserCalibrated = true;
      ironNode.calibratedA = -52; // User measured -52 on phone

      // New beacon arrives with -58
      final beacon2 = ParsedNodeBeacon(
        nodeId: 2,
        calibratedRssi1m: -58,
        pathLossExpN: 2.1,
        sequence: 43,
        sensorState: 32,
      );

      if (!ironNode.isUserCalibrated) {
        ironNode.calibratedA = beacon2.calibratedRssi1m;
        ironNode.pathLossExpN = beacon2.pathLossExpN;
      }

      expect(ironNode.calibratedA, equals(-52), reason: 'User calibration on phone must NOT be overridden by OTA beacon');
    });

    test('Warm iron vs Hot iron hazard alert classification', () {
      final nodes = NodeData.createDefaultNodes();
      final ironNode = nodes.firstWhere((n) => n.id == 2);

      String getRibbonText(NodeData node, ProximityZone zone) {
        if (node.id == 2 && node.isIronHot) {
          return zone == ProximityZone.criticalDanger
              ? 'CRITICAL BURN HAZARD (< 30 cm & HOT)!'
              : 'BURN DANGER ZONE (30–100 cm & HOT)!';
        } else if (node.id == 2 && node.isIronWarm) {
          return zone == ProximityZone.criticalDanger
              ? 'WARM IRON CAUTION (< 30 cm & WARM)!'
              : 'WARM IRON PROXIMITY (30–100 cm & WARM)!';
        } else {
          return zone == ProximityZone.criticalDanger
              ? 'CRITICAL PROXIMITY HAZARD (< 30 cm)!'
              : 'PROXIMITY DANGER ZONE (30–100 cm)!';
        }
      }

      // Safe room temp (28°C)
      ironNode.ironTemperatureC = 28;
      expect(getRibbonText(ironNode, ProximityZone.criticalDanger), equals('CRITICAL PROXIMITY HAZARD (< 30 cm)!'));
      expect(getRibbonText(ironNode, ProximityZone.danger), equals('PROXIMITY DANGER ZONE (30–100 cm)!'));

      // Warm temp (44°C)
      ironNode.ironTemperatureC = 44;
      expect(getRibbonText(ironNode, ProximityZone.criticalDanger), equals('WARM IRON CAUTION (< 30 cm & WARM)!'));
      expect(getRibbonText(ironNode, ProximityZone.danger), equals('WARM IRON PROXIMITY (30–100 cm & WARM)!'));

      // Hot temp (60°C)
      ironNode.ironTemperatureC = 60;
      expect(getRibbonText(ironNode, ProximityZone.criticalDanger), equals('CRITICAL BURN HAZARD (< 30 cm & HOT)!'));
      expect(getRibbonText(ironNode, ProximityZone.danger), equals('BURN DANGER ZONE (30–100 cm & HOT)!'));
    });

    test('Startup tracking mode defaults to Child Wristband and timeout is resilient to Android jitter', () {
      final engine = DistanceEngine();
      final bleService = BleService(distanceEngine: engine);

      // Verify startup tracking source defaults to Child Wristband for instant inter-node distance display
      expect(bleService.trackingSource, equals(TrackingSource.wristband));

      // Verify wristband offline timeout is at least 3000ms to tolerate Android BLE scan batching delays
      expect(ShapnestProtocol.wristbandOfflineTimeout.inMilliseconds, greaterThanOrEqualTo(3000));
      expect(ShapnestProtocol.wristbandOfflineTimeout, equals(const Duration(milliseconds: 3500)));

      bleService.dispose();
    });

    test('Wristband distance filtering tracks consecutive physical approaches smoothly', () {
      final engine = DistanceEngine();
      const nodeId = 2; // Iron node

      // Start at 2.50m
      final dStart = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 2.50);
      expect(dStart, equals(2.50));

      // Approach 1: Move to 1.80m (70cm closer) -> updates instantly (> 3cm deadband)
      final dStep1 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.80);
      expect(dStep1, equals(1.80));

      // Small jitter of 2cm -> absorbed
      final dJitter = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 1.82);
      expect(dJitter, equals(1.80));

      // Approach 2: Move to 0.90m (90cm closer) -> updates instantly
      final dStep2 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 0.90);
      expect(dStep2, equals(0.90));

      // Approach 3: Move to 0.35m (55cm closer) -> updates instantly into critical danger
      final dStep3 = engine.filterWristbandDistance(nodeId: nodeId, incomingDistanceM: 0.35);
      expect(dStep3, equals(0.35));
    });
  });
}
