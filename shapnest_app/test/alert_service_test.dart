import 'package:flutter_test/flutter_test.dart';
import 'package:shapnest_app/models/node_data.dart';
import 'package:shapnest_app/models/shapnest_protocol.dart';
import 'package:shapnest_app/services/alert_service.dart';
import 'package:shapnest_app/services/distance_engine.dart';
import 'package:shapnest_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SHAPNEST Mandatory Verification Suite (12 Requirements)', () {
    late AlertService alertService;
    late NotificationService notificationService;

    setUp(() {
      alertService = AlertService();
      alertService.resetForTesting();
      notificationService = NotificationService();
      notificationService.resetForTesting();
    });

    // ------------------------------------------------------------------------
    // 1. App startup with all four boards absent produces zero Yellow/Red proximity notifications
    // ------------------------------------------------------------------------
    test('1. App startup with all four boards absent produces zero Yellow/Red proximity notifications', () {
      // Boards absent: nodes initialized with default states (offline, null RSSI)
      final nodes = NodeData.createDefaultNodes();
      for (final node in nodes) {
        expect(node.directState, equals(NodeState.offline));
        expect(node.wbState, equals(NodeState.offline));
        expect(node.directFilteredRssi, isNull);
        expect(node.wbFilteredRssi, isNull);
      }

      // Check alert service at startup
      expect(alertService.normalNotificationCount, equals(0));
      expect(alertService.urgentNotificationCount, equals(0));
      expect(alertService.loudAlarmTriggerCount, equals(0));
      expect(alertService.vibrationCount, equals(0));
      expect(alertService.offlineNotificationCount, equals(0));
      expect(alertService.wristbandOfflineNotificationCount, equals(0));
      expect(alertService.currentActiveAlert, isNull);
      expect(notificationService.sentNotifications, isEmpty);
    });

    // ------------------------------------------------------------------------
    // 2. Missing RSSI cannot trigger a proximity alert
    // ------------------------------------------------------------------------
    test('2. Missing RSSI (null, zero, sentinel -128, out of bounds) cannot trigger a proximity alert', () {
      // Node is online, but receives null RSSI
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: null);
      // Zero RSSI
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: 0);
      // Sentinel -128 dBm offline RSSI
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: ShapnestProtocol.rssiOffline);
      // Extremely low out-of-range RSSI (-110 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -110);
      // Impossibly high out-of-range RSSI (-5 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -5);

      // Node marked offline: should never trigger proximity alert
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -50,
        isNodeOnline: false,
      );

      expect(alertService.getConfirmedZone(1), equals(ProximityZone.safe));
      expect(alertService.normalNotificationCount, equals(0));
      expect(alertService.urgentNotificationCount, equals(0));
      expect(alertService.loudAlarmTriggerCount, equals(0));
      expect(notificationService.sentNotifications, isEmpty);
    });

    // ------------------------------------------------------------------------
    // 3. A genuine Yellow entry produces one normal notification
    // ------------------------------------------------------------------------
    test('3. A genuine Yellow entry produces one normal notification', () {
      // 1st sample in Yellow zone (-68 dBm): candidate is Yellow, but unconfirmed
      alertService.processWristbandTelemetry(
        nodeId: 1,
        nodeName: 'Fan',
        rssi: -68,
      );
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
      expect(alertService.loudAlarmTriggerCount, equals(0)); // NO loud alarm in Yellow!
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
    // 4. A genuine Red entry produces one urgent notification and alarm
    // ------------------------------------------------------------------------
    test('4. A genuine Red entry produces one urgent notification and alarm', () {
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
      expect(alertService.vibrationCount, equals(1)); // Physical vibration!

      expect(alertService.currentActiveAlert, isNotNull);
      final alert = alertService.currentActiveAlert!;
      expect(alert.zone, equals(ProximityZone.danger));
      expect(alert.title, contains('URGENT'));
      expect(alert.body, equals('URGENT: Your child is very near the iron.'));
      expect(alert.body, isNot(contains('m')));
      expect(alert.body, isNot(contains('cm')));
    });

    // ------------------------------------------------------------------------
    // 5. Repeated packets and RSSI boundary fluctuations do not create duplicate alerts
    // ------------------------------------------------------------------------
    test('5. Repeated packets and RSSI boundary fluctuations do not create duplicate alerts', () {
      // Establish in Yellow Zone (-68 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -68);
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -68);
      expect(alertService.normalNotificationCount, equals(1));

      // 10 repeated packets inside Yellow Zone
      for (int i = 0; i < 10; i++) {
        alertService.processWristbandTelemetry(
          nodeId: 1,
          nodeName: 'Fan',
          rssi: -67 - (i % 4),
        );
      }
      expect(alertService.normalNotificationCount, equals(1)); // Strictly 1 alert

      // Boundary fluctuation: single spike into Red (-58 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -58);
      // Immediately drops back to Yellow (-66 dBm)
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -66);

      // Transient spike rejected by confirmation filter: no switch, no alarm!
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.warning));
      expect(alertService.loudAlarmTriggerCount, equals(0));
      expect(alertService.normalNotificationCount, equals(1));
    });

    // ------------------------------------------------------------------------
    // 6. A node that disconnects while Yellow clears its stale RSSI and zone state
    // ------------------------------------------------------------------------
    test('6. A node that disconnects while Yellow clears its stale RSSI and zone state', () {
      final distanceEngine = DistanceEngine();

      // Put Node 1 in Yellow
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -68);
      alertService.processWristbandTelemetry(nodeId: 1, nodeName: 'Fan', rssi: -68);
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.warning));
      expect(alertService.currentActiveAlert, isNotNull);

      // Node disconnects: clear distance engine and notify alertService
      distanceEngine.clearWbDistance(1);
      alertService.handleNodeOffline(1, 'Fan');

      // Stale zone state and active banner cleared
      expect(alertService.getConfirmedZone(1), equals(ProximityZone.safe));
      expect(alertService.currentActiveAlert, isNull);
      expect(alertService.isNodeOnline(1), isFalse);
    });

    // ------------------------------------------------------------------------
    // 7. No new proximity alert is generated from stale data after disconnection
    // ------------------------------------------------------------------------
    test('7. No new proximity alert is generated from stale data after disconnection', () {
      // Put Node 2 in Red
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -52);
      alertService.processWristbandTelemetry(nodeId: 2, nodeName: 'Iron', rssi: -52);
      expect(alertService.urgentNotificationCount, equals(1));

      // Node disconnects
      alertService.handleNodeOffline(2, 'Iron');
      expect(alertService.getConfirmedZone(2), equals(ProximityZone.safe));

      // Disconnected node receives stale or invalid RSSI
      alertService.processWristbandTelemetry(
        nodeId: 2,
        nodeName: 'Iron',
        rssi: -52,
        isNodeOnline: false, // Node is offline
      );

      // No new proximity notification is generated!
      expect(alertService.urgentNotificationCount, equals(1));
      expect(alertService.loudAlarmTriggerCount, equals(1));
      expect(alertService.getConfirmedZone(2), equals(ProximityZone.safe));
    });

    // ------------------------------------------------------------------------
    // 8. A wristband that has never connected does not generate repeated disconnection notifications
    // ------------------------------------------------------------------------
    test('8. A wristband that has never connected does not generate repeated disconnection notifications', () {
      // Wristband never connected since app start
      expect(alertService.hasWristbandEverConnected, isFalse);
      expect(alertService.isWristbandOnline, isFalse);

      // Watchdog timeout ticks occur while wristband is absent
      for (int i = 0; i < 5; i++) {
        alertService.handleWristbandOffline();
      }

      // Zero wristband disconnection notifications sent
      expect(alertService.wristbandOfflineNotificationCount, equals(0));
      expect(notificationService.sentNotifications.where((n) => n['title'] == 'Wristband Disconnected'), isEmpty);
    });

    // ------------------------------------------------------------------------
    // 9. A wristband that connects and then disconnects generates exactly one disconnection notification
    // ------------------------------------------------------------------------
    test('9. A wristband that connects and then disconnects generates exactly one disconnection notification', () {
      // Case B: First valid telemetry arrives
      alertService.handleWristbandOnline();
      expect(alertService.hasWristbandEverConnected, isTrue);
      expect(alertService.isWristbandOnline, isTrue);

      // Telemetry silence -> timeout confirmed offline
      alertService.handleWristbandOffline();

      expect(alertService.isWristbandOnline, isFalse);
      expect(alertService.wristbandOfflineNotificationCount, equals(1));

      // Notification contents verified
      final notifs = notificationService.sentNotifications.where((n) => n['title'] == 'Wristband Disconnected').toList();
      expect(notifs.length, equals(1));
      expect(notifs.first['body'], equals('Warning: Child wristband disconnected.'));
    });

    // ------------------------------------------------------------------------
    // 10. Remaining Offline does not generate repeated messages
    // ------------------------------------------------------------------------
    test('10. Remaining Offline does not generate repeated messages', () {
      alertService.handleWristbandOnline();
      alertService.handleWristbandOffline();
      expect(alertService.wristbandOfflineNotificationCount, equals(1));

      // 10 subsequent periodic watchdog checks while remaining offline
      for (int i = 0; i < 10; i++) {
        alertService.handleWristbandOffline();
      }

      // Notification count remains strictly 1
      expect(alertService.wristbandOfflineNotificationCount, equals(1));
      final notifs = notificationService.sentNotifications.where((n) => n['title'] == 'Wristband Disconnected').toList();
      expect(notifs.length, equals(1));
    });

    // ------------------------------------------------------------------------
    // 11. Reconnection restores Online status and permits one notification on the next genuine disconnection
    // ------------------------------------------------------------------------
    test('11. Reconnection restores Online status and permits one notification on the next genuine disconnection', () {
      // 1st connection and disconnection
      alertService.handleWristbandOnline();
      alertService.handleWristbandOffline();
      expect(alertService.wristbandOfflineNotificationCount, equals(1));

      // Wristband reconnects (restores Online status and re-arms)
      alertService.handleWristbandOnline();
      expect(alertService.isWristbandOnline, isTrue);

      // Later disconnects again
      alertService.handleWristbandOffline();
      expect(alertService.wristbandOfflineNotificationCount, equals(2));

      final notifs = notificationService.sentNotifications.where((n) => n['title'] == 'Wristband Disconnected').toList();
      expect(notifs.length, equals(2));
    });

    // ------------------------------------------------------------------------
    // 12. One node disconnecting does not incorrectly mark the other nodes Offline
    // ------------------------------------------------------------------------
    test('12. One node disconnecting does not incorrectly mark the other nodes Offline', () {
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
    // Bonus: Safe Zone Recovery Alert Verification
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
