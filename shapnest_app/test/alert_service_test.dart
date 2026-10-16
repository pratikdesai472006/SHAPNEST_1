import 'package:flutter_test/flutter_test.dart';
import 'package:shapnest_app/models/shapnest_protocol.dart';
import 'package:shapnest_app/services/alert_service.dart';
import 'package:shapnest_app/services/distance_engine.dart';
import 'package:shapnest_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SHAPNEST AlertService & Offline Monitoring Tests', () {
    late AlertService alertService;
    late NotificationService notificationService;

    setUp(() {
      alertService = AlertService();
      alertService.resetForTesting();
      notificationService = NotificationService();
      notificationService.resetForTesting();
    });

    // ------------------------------------------------------------------------
    // Requirement 1: Yellow Zone entry produces one normal notification and no loud alarm
    // ------------------------------------------------------------------------
    test('1. Yellow Zone entry produces one normal notification and no loud alarm', () {
      // 2 consecutive readings in Yellow zone (-68 dBm)
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -68,
      );
      // 1st sample: candidate is Yellow, but not yet confirmed (requires 2 samples)
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.safe));
      expect(alertService.normalNotificationCount, equals(0));

      // 2nd sample: confirmed entry into Yellow Zone!
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -68,
      );

      expect(alertService.getConfirmedZone(1), equals(ProximityZone.warning));
      expect(alertService.normalNotificationCount, equals(1));
      expect(alertService.loudAlarmTriggerCount, equals(0)); // NO loud alarm!
      expect(alertService.vibrationCount, equals(0));

      expect(alertService.currentActiveAlert, isNotNull);
      final alert = alertService.currentActiveAlert!;
      expect(alert.zone, equals(ProximityZone.warning));
      expect(alert.title, contains('Warning'));
      expect(alert.body, equals('Warning: Your child is near the fan.'));
      // No exact distance in message
      expect(alert.body, isNot(contains('m')));
      expect(alert.body, isNot(contains('cm')));
    });

    // ------------------------------------------------------------------------
    // Requirement 2: Red Zone entry produces one urgent notification and triggers the loud alarm
    // ------------------------------------------------------------------------
    test('2. Red Zone entry produces one urgent notification and triggers the loud alarm', () {
      // 2 consecutive readings in Red zone (-55 dBm >= -60 dBm)
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -55,
      );
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -54,
      );

      expect(alertService.getConfirmedZone(2), equals(ProximityZone.danger));
      expect(alertService.urgentNotificationCount, equals(1));
      expect(alertService.loudAlarmTriggerCount, equals(1)); // Loud alarm triggered!
      expect(alertService.vibrationCount, equals(1));

      expect(alertService.currentActiveAlert, isNotNull);
      final alert = alertService.currentActiveAlert!;
      expect(alert.zone, equals(ProximityZone.danger));
      expect(alert.title, contains('URGENT'));
      expect(alert.body, equals('URGENT: Your child is very near the iron.'));
      // No exact distance in message
      expect(alert.body, isNot(contains('m')));
      expect(alert.body, isNot(contains('cm')));
    });

    // ------------------------------------------------------------------------
    // Requirement 3: Repeated Red readings do not repeatedly trigger the alarm
    // ------------------------------------------------------------------------
    test('3. Repeated Red readings do not repeatedly trigger the alarm', () {
      // Enter Red zone (2 samples)
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -55,
      );
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -55,
      );
      expect(alertService.loudAlarmTriggerCount, equals(1));
      expect(alertService.urgentNotificationCount, equals(1));

      // 10 repeated packets while child remains in Red Zone (-52 to -58 dBm)
      for (int i = 0; i < 10; i++) {
        alertService.processWristbandTelemetry(
          nodeId: 2,
          nodeName: 'Iron',
          rssi: -53 - (i % 5),
        );
      }

      // Counts must remain strictly 1 (no repeat spam while in Red!)
      expect(alertService.loudAlarmTriggerCount, equals(1));
      expect(alertService.urgentNotificationCount, equals(1));
    });

    // ------------------------------------------------------------------------
    // Requirement 4: RSSI fluctuations around the boundary do not cause rapid zone switching
    // ------------------------------------------------------------------------
    test('4. RSSI fluctuations around boundary do not cause rapid zone switching', () {
      // Establish in Yellow Zone (-68 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -68);
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -68);
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.warning));
      expect(alertService.loudAlarmTriggerCount, equals(0));

      // Single transient spike to -58 dBm (crosses Red threshold >= -60)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -58);
      // Next sample drops back to -66 dBm (Yellow)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -66);

      // Must NOT switch to Red on single spike!
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.warning));
      expect(alertService.loudAlarmTriggerCount, equals(0));

      // Now establish in Red Zone (-55 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -55);
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -55);
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.danger));
      expect(alertService.loudAlarmTriggerCount, equals(1));

      // Hysteresis test:
      // Red entry is -60 dBm. Exit is -63 dBm.
      // Reading fluctuates to -61 dBm and -62 dBm (below -60, but above -63 exit threshold)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -61);
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -62);

      // Hysteresis keeps zone in Red! Does NOT immediately reverse!
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.danger));
      expect(alertService.loudAlarmTriggerCount, equals(1));
    });

    // ------------------------------------------------------------------------
    // Requirement 5: Leaving Red and subsequently re-entering Red permits a new alert
    // ------------------------------------------------------------------------
    test('5. Leaving Red and subsequently re-entering Red permits a new alert', () {
      // 1st entry into Red
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -52);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -52);
      expect(alertService.loudAlarmTriggerCount, equals(1));
      expect(alertService.getConfirmedZone(2), equals(ProximityZone.danger));

      // Child clearly leaves Red to Safe (-82 dBm, 2 samples)
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -82);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -82);
      expect(alertService.getConfirmedZone(2), equals(ProximityZone.safe));

      // Child re-enters Red (-55 dBm, 2 samples)
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -55);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -55);

      // System confirms re-entry and triggers a new alarm!
      expect(alertService.loudAlarmTriggerCount, equals(2));
      expect(alertService.urgentNotificationCount, equals(2));
    });

    // ------------------------------------------------------------------------
    // Requirement 6: A node going offline produces one notification after the timeout
    // ------------------------------------------------------------------------
    test('6. A node going offline produces one notification after the timeout', () {
      // Mark node online
      alertService.setNodeOnline(2, 'Iron');
      expect(alertService.isNodeOnline(2), isTrue);

      // Timeout expires -> node goes offline
      alertService.handleNodeOffline(2, 'Iron');

      expect(alertService.isNodeOnline(2), isFalse);
      expect(alertService.offlineNotificationCount, equals(1));

      // Check notification sent
      expect(notificationService.sentNotifications.length, equals(1));
      final notif = notificationService.sentNotifications.first;
      expect(notif['title'], equals('Node Disconnected'));
      expect(notif['body'], equals('Warning: The iron node has disconnected.'));
    });

    // ------------------------------------------------------------------------
    // Requirement 7: Continued offline status does not generate repeated notifications
    // ------------------------------------------------------------------------
    test('7. Continued offline status does not generate repeated notifications', () {
      alertService.setNodeOnline(2, 'Iron');
      alertService.handleNodeOffline(2, 'Iron');
      expect(alertService.offlineNotificationCount, equals(1));

      // Repeated timeout watchdog ticks while node remains offline
      for (int i = 0; i < 5; i++) {
        alertService.handleNodeOffline(2, 'Iron');
      }

      // Must remain exactly 1 notification!
      expect(alertService.offlineNotificationCount, equals(1));
      expect(notificationService.sentNotifications.length, equals(1));
    });

    // ------------------------------------------------------------------------
    // Requirement 8: A node reconnecting returns to Online
    // ------------------------------------------------------------------------
    test('8. A node reconnecting returns to Online', () {
      alertService.setNodeOnline(3, 'Door');
      alertService.handleNodeOffline(3, 'Door');
      expect(alertService.isNodeOnline(3), isFalse);

      // Reconnecting packet arrives
      alertService.setNodeOnline(3, 'Door');
      expect(alertService.isNodeOnline(3), isTrue);

      // Future disconnection can now notify again
      alertService.handleNodeOffline(3, 'Door');
      expect(alertService.offlineNotificationCount, equals(2));
    });

    // ------------------------------------------------------------------------
    // Requirement 9: Stale telemetry is not treated as a current proximity measurement
    // ------------------------------------------------------------------------
    test('9. Stale telemetry is not treated as a current proximity measurement', () {
      // Put node in Red Zone
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -50);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -50);
      expect(alertService.getConfirmedZone(2), equals(ProximityZone.danger));
      expect(alertService.currentActiveAlert, isNotNull);

      // Invalid / offline RSSI values are safely ignored and do not update proximity
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: ShapnestProtocol.rssiOffline,
      );
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: null,
      );

      // When node is confirmed disconnected, its old Red Zone state is cleared
      alertService.handleNodeOffline(2, 'Iron');
      expect(alertService.getConfirmedZone(2), equals(ProximityZone.safe));
      expect(alertService.currentActiveAlert, isNull); // old active alert cleared!
    });

    // ------------------------------------------------------------------------
    // Requirement 10: One node's disconnection does not incorrectly mark other nodes Offline
    // ------------------------------------------------------------------------
    test('10. One node\'s disconnection does not incorrectly mark other nodes Offline', () {
      alertService.setNodeOnline(1, 'Fan');
      alertService.setNodeOnline(2, 'Iron');
      alertService.setNodeOnline(3, 'Door');

      expect(alertService.isNodeOnline(1), isTrue);
      expect(alertService.isNodeOnline(2), isTrue);
      expect(alertService.isNodeOnline(3), isTrue);

      // Node 2 (Iron) goes offline
      alertService.handleNodeOffline(2, 'Iron');

      // Node 2 is offline, but Nodes 1 and 3 MUST remain online!
      expect(alertService.isNodeOnline(2), isFalse);
      expect(alertService.isNodeOnline(1), isTrue);
      expect(alertService.isNodeOnline(3), isTrue);
    });

    // ------------------------------------------------------------------------
    // Safe Zone Recovery Alert Test
    // ------------------------------------------------------------------------
    test('Safe zone recovery alert triggers when child moves away from hazard', () {
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -55);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -55);
      expect(alertService.currentActiveAlert!.zone, equals(ProximityZone.danger));

      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -82);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -82);

      expect(alertService.getConfirmedZone(2), equals(ProximityZone.safe));
      expect(alertService.alertLog.first.title, contains('Safe'));
      expect(alertService.alertLog.first.body, contains('moved away'));
    });
  });
}
