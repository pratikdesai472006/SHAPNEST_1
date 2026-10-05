import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shapnest_app/services/distance_engine.dart';
import 'package:shapnest_app/services/kalman_filter.dart';
import 'package:shapnest_app/services/theme_service.dart';

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

      // Simulate 20 noisy samples with realistic +/- 3 dBm Rayleigh fading
      final noisySamples = [
        -57, -61, -58, -62, -59, -60, -58, -61, -57, -62,
        -59, -60, -58, -61, -60, -59, -58, -61, -59, -60
      ];

      final recordedDistances = <double>[];
      for (final raw in noisySamples) {
        final res = engine.processRssi(nodeId: nodeId, rawRssi: raw);
        recordedDistances.add(res.distanceMeters);
      }

      // In the old filter, a 5 dBm swing would cause ~40 cm jitter.
      // With our Dual-Regime Kalman + Deadband, max distance spread should be <= 6 cm!
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
}
