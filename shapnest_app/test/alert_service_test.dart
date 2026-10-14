import 'package:flutter_test/flutter_test.dart';
import 'package:shapnest_app/services/alert_service.dart';
import 'package:shapnest_app/services/distance_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlertService Timing & Zone Tests', () {
    late AlertService alertService;

    setUp(() {
      alertService = AlertService();
    });

    test('Immediate first message upon entering Yellow Caution Zone when hazard active', () {
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -68,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: true,
        hazardDescription: 'Fan is spinning',
      );

      expect(alertService.currentActiveAlert, isNotNull);
      final alert = alertService.currentActiveAlert!;
      expect(alert.zone, equals(ProximityZone.warning));
      expect(alert.title, contains('CAUTION'));
      expect(alert.body, contains('Fan'));
      expect(alert.body, contains('-68 dBm'));
      expect(alertService.alertLog.length, equals(1));
    });

    test('Condition gating: Inactive hazard in Red Zone does NOT trigger alarm (otherwise nothing to do)', () {
      // Child is close (strong signal -55 dBm), but Fan is OFF (isHazardActive: false)
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -55,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: false,
        hazardDescription: 'Fan is powered OFF',
      );

      // Inactive hazard -> suppressed
      expect(alertService.currentActiveAlert, isNull);
      expect(alertService.alertLog, isEmpty);
    });

    test('Yellow Zone does NOT spam before 1 minute (60s) has elapsed', () {
      // 1st alert: enter Yellow zone
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -68,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: true,
        hazardDescription: 'Fan is spinning',
      );
      expect(alertService.alertLog.length, equals(1));

      // Immediate follow-up: still in Yellow zone
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -70,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: true,
        hazardDescription: 'Fan is spinning',
      );
      // Count should still be 1 (no repeat yet)
      expect(alertService.alertLog.length, equals(1));
    });

    test('Immediate first message upon entering Red Danger Zone when hazard active', () {
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -55,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: true,
        hazardDescription: 'Iron is HOT (75°C)',
      );

      expect(alertService.currentActiveAlert, isNotNull);
      final alert = alertService.currentActiveAlert!;
      expect(alert.zone, equals(ProximityZone.danger));
      expect(alert.title, contains('CRITICAL DANGER'));
      expect(alert.body, contains('Iron'));
      expect(alert.body, contains('-55 dBm'));
      expect(alert.body, contains('Iron is HOT (75°C)'));
      expect(alertService.alertLog.length, equals(1));
    });

    test('Safe zone recovery alert triggers when child moves away from hazard', () {
      // Enter Red
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -55,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: true,
        hazardDescription: 'Iron is HOT (75°C)',
      );
      expect(alertService.currentActiveAlert!.zone, equals(ProximityZone.danger));

      // Move away to Safe (< -75 dBm)
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -82,
        dangerRssiDbm: -60,
        warningRssiDbm: -75,
        isHazardActive: true,
        hazardDescription: 'Iron is HOT (75°C)',
      );

      expect(alertService.currentActiveAlert, isNotNull);
      final recoveryAlert = alertService.currentActiveAlert!;
      expect(recoveryAlert.zone, equals(ProximityZone.safe));
      expect(recoveryAlert.title, contains('SAFE ZONE'));
      expect(recoveryAlert.body, contains('safely moved away'));
    });
  });
}
