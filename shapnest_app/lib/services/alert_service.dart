import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/shapnest_protocol.dart';
import 'distance_engine.dart';
import 'notification_service.dart';

class SafetyAlertMessage {
  final int nodeId;
  final String nodeName;
  final ProximityZone zone;
  final int? rssi;
  final double? distanceM;
  final bool isHazardActive;
  final String hazardDescription;
  final String title;
  final String body;
  final DateTime timestamp;

  SafetyAlertMessage({
    required this.nodeId,
    required this.nodeName,
    required this.zone,
    this.rssi,
    this.distanceM,
    this.isHazardActive = true,
    this.hazardDescription = '',
    required this.title,
    required this.body,
    required this.timestamp,
  });

  bool get isDanger => zone == ProximityZone.danger;
  bool get isWarning => zone == ProximityZone.warning;
  bool get isSafe => zone == ProximityZone.safe;
}

/// AlertService manages:
/// 1. Consecutive reading confirmation & hysteresis to prevent boundary false alarms.
/// 2. Yellow Zone: One normal phone notification (no loud alarm).
/// 3. Red Zone: Urgent phone notification + loud alarm & vibration on confirmed transition (no repeat spam).
/// 4. Leaving and re-entering zone permits new alerts.
/// 5. Node offline monitoring: Single notification on disconnection, clears old Red state, no repeats while offline.
class AlertService extends ChangeNotifier {
  // Configurable thresholds & parameters
  int confirmationSamples = ShapnestProtocol.defaultZoneConfirmationSamples; // 2 samples
  int hysteresisMarginDbm = ShapnestProtocol.rssiHysteresisMarginDbm; // 3 dB margin

  // Per-node state tracking
  final Map<int, ProximityZone> _confirmedZone = {};
  final Map<int, ProximityZone?> _candidateZone = {};
  final Map<int, int> _candidateCount = {};
  final Map<int, ProximityZone?> _lastAlertedZone = {};
  final Map<int, DateTime?> _lastRedAlertTime = {};
  final Map<int, bool> _hasNotifiedOffline = {};
  final Map<int, bool> _isOnline = {};

  // Child Wristband Connection Lifecycle Tracking
  bool _hasWristbandEverConnected = false;
  bool _isWristbandOnline = false;
  bool _hasNotifiedWristbandOffline = false;

  SafetyAlertMessage? _currentActiveAlert;
  final List<SafetyAlertMessage> _alertLog = [];

  // Testing & diagnostic counters
  int loudAlarmTriggerCount = 0;
  int vibrationCount = 0;
  int normalNotificationCount = 0;
  int urgentNotificationCount = 0;
  int offlineNotificationCount = 0;
  int wristbandOfflineNotificationCount = 0;

  SafetyAlertMessage? get currentActiveAlert => _currentActiveAlert;
  List<SafetyAlertMessage> get alertLog => List.unmodifiable(_alertLog);

  ProximityZone getConfirmedZone(int nodeId) =>
      _confirmedZone[nodeId] ?? ProximityZone.safe;

  bool isNodeOnline(int nodeId) => _isOnline[nodeId] ?? false;
  bool get isWristbandOnline => _isWristbandOnline;
  bool get hasWristbandEverConnected => _hasWristbandEverConnected;

  /// Mark wristband online on valid telemetry arrival (re-arms disconnection alerts)
  void handleWristbandOnline() {
    _hasWristbandEverConnected = true;
    final wasOffline = !_isWristbandOnline;
    _isWristbandOnline = true;
    _hasNotifiedWristbandOffline = false;
    if (wasOffline && _currentActiveAlert?.nodeId == 999) {
      _currentActiveAlert = null;
    }
    notifyListeners();
  }

  /// Mark wristband offline after confirmed silence timeout
  /// - Case A: Never connected -> Not connected / Offline without spam notification
  /// - Case B: Was online, now offline -> Exactly ONE notification: "Warning: Child wristband disconnected."
  void handleWristbandOffline() {
    if (!_hasWristbandEverConnected) {
      _isWristbandOnline = false;
      return;
    }

    if (_isWristbandOnline && !_hasNotifiedWristbandOffline) {
      _isWristbandOnline = false;
      _hasNotifiedWristbandOffline = true;
      wristbandOfflineNotificationCount++;

      final alert = SafetyAlertMessage(
        nodeId: 999,
        nodeName: 'Child Wristband',
        zone: ProximityZone.danger,
        title: '⚠️ Wristband Disconnected',
        body: 'Warning: Child wristband disconnected.',
        isHazardActive: true,
        hazardDescription: 'Wristband connection lost',
        timestamp: DateTime.now(),
      );

      _currentActiveAlert = alert;
      _alertLog.insert(0, alert);
      if (_alertLog.length > 50) _alertLog.removeLast();

      // Trigger mobile alert tone and vibration so user actually notices
      _triggerMobileAlarmAndVibration();

      NotificationService().showWristbandOfflineNotification();
      notifyListeners();
    } else {
      _isWristbandOnline = false;
    }
  }

  /// Dismiss the current active alert banner
  void dismissActiveAlert() {
    _currentActiveAlert = null;
    notifyListeners();
  }

  /// Reset all state for unit testing
  void resetForTesting() {
    _confirmedZone.clear();
    _candidateZone.clear();
    _candidateCount.clear();
    _lastAlertedZone.clear();
    _lastRedAlertTime.clear();
    _hasNotifiedOffline.clear();
    _isOnline.clear();
    _hasWristbandEverConnected = false;
    _isWristbandOnline = false;
    _hasNotifiedWristbandOffline = false;
    _currentActiveAlert = null;
    _alertLog.clear();
    loudAlarmTriggerCount = 0;
    vibrationCount = 0;
    normalNotificationCount = 0;
    urgentNotificationCount = 0;
    offlineNotificationCount = 0;
    wristbandOfflineNotificationCount = 0;
    confirmationSamples = ShapnestProtocol.defaultZoneConfirmationSamples;
    hysteresisMarginDbm = ShapnestProtocol.rssiHysteresisMarginDbm;
  }

  /// Triggers mobile alarm sound and physical vibration
  void _triggerMobileAlarmAndVibration() {
    loudAlarmTriggerCount++;
    vibrationCount++;
    try {
      SystemSound.play(SystemSoundType.alert).catchError((_) {});
      HapticFeedback.heavyImpact().catchError((_) {});
      HapticFeedback.vibrate().catchError((_) {});
    } catch (_) {
      // Graceful fallback in environments without sound/vibrator hardware
    }
  }

  /// Process incoming RSSI telemetry with boundary stability and hysteresis.
  /// - Yellow Zone: One normal phone notification (no loud alarm).
  /// - Red Zone: Urgent phone notification + loud alarm & vibration.
  /// - Boundary stability: requires [confirmationSamples] consecutive readings and hysteresis margin.
  /// - No repeat spam while staying in the same zone.
  void processWristbandTelemetry({
    required int nodeId,
    required String nodeName,
    int? rssi,
    double? distanceM,
    bool isHazardActive = true,
    String hazardDescription = '',
    bool isNodeOnline = true,
    int dangerRssiDbm = ShapnestProtocol.defaultRedZoneEntryRssiDbm, // -60
    int warningRssiDbm = ShapnestProtocol.defaultYellowZoneEntryRssiDbm, // -74
    double dangerDistanceM = 0.30,
    double warningDistanceM = 0.70,
    String unit = 'm',
  }) {
    // 0. A node that is offline must NEVER produce a proximity alert
    if (!isNodeOnline) {
      _candidateZone[nodeId] = null;
      _candidateCount[nodeId] = 0;
      return;
    }

    // 1. Handle missing/invalid/zero RSSI readings safely
    // Zero, null, out-of-range, or sentinel offline values must NEVER trigger an alert
    if (rssi == null ||
        rssi == 0 ||
        rssi == ShapnestProtocol.rssiOffline ||
        rssi < -105 ||
        rssi > -15) {
      return;
    }

    // 2. Mark node online
    _isOnline[nodeId] = true;
    _hasNotifiedOffline[nodeId] = false;

    final currentZone = _confirmedZone[nodeId] ?? ProximityZone.safe;

    // 3. Evaluate candidate zone using Hysteresis thresholds
    ProximityZone candidate;
    if (currentZone == ProximityZone.safe) {
      if (rssi >= dangerRssiDbm) {
        candidate = ProximityZone.danger;
      } else if (rssi >= warningRssiDbm) {
        candidate = ProximityZone.warning;
      } else {
        candidate = ProximityZone.safe;
      }
    } else if (currentZone == ProximityZone.warning) {
      if (rssi >= dangerRssiDbm) {
        candidate = ProximityZone.danger;
      } else if (rssi < (warningRssiDbm - hysteresisMarginDbm)) {
        // Must drop below exit threshold (-74 - 3 = -77 dBm) to exit to Safe
        candidate = ProximityZone.safe;
      } else {
        // Hysteresis holds in Yellow
        candidate = ProximityZone.warning;
      }
    } else {
      // currentZone == ProximityZone.danger (Red)
      if (rssi < (dangerRssiDbm - hysteresisMarginDbm)) {
        // Must drop below exit threshold (-60 - 3 = -63 dBm) to exit Red
        if (rssi >= (warningRssiDbm - hysteresisMarginDbm)) {
          candidate = ProximityZone.warning;
        } else {
          candidate = ProximityZone.safe;
        }
      } else {
        // Hysteresis holds in Red
        candidate = ProximityZone.danger;
      }
    }

    // 4. Consecutive readings verification
    if (candidate == currentZone) {
      // Child remains in same confirmed zone -> reset candidate counters
      _candidateZone[nodeId] = null;
      _candidateCount[nodeId] = 0;

      // REQUIREMENT 3: Immediate and continuous 5-second interval message
      // while child in red zone and iron is hot or door is open.
      if (currentZone == ProximityZone.danger && isHazardActive) {
        final lastRedTime = _lastRedAlertTime[nodeId];
        final now = DateTime.now();
        if (lastRedTime != null && now.difference(lastRedTime).inMilliseconds >= 5000) {
          _lastRedAlertTime[nodeId] = now;
          urgentNotificationCount++;

          final alert = SafetyAlertMessage(
            nodeId: nodeId,
            nodeName: nodeName,
            zone: ProximityZone.danger,
            rssi: rssi,
            distanceM: null,
            isHazardActive: isHazardActive,
            hazardDescription: hazardDescription,
            title: '🚨 URGENT: Child Very Near $nodeName',
            body: 'URGENT: Your child is very near the ${nodeName.toLowerCase()}${hazardDescription.isNotEmpty ? " ($hazardDescription)" : ""}.',
            timestamp: now,
          );

          _currentActiveAlert = alert;
          _alertLog.insert(0, alert);
          if (_alertLog.length > 50) _alertLog.removeLast();

          _triggerMobileAlarmAndVibration();

          NotificationService().showHazardNotification(
            id: nodeId,
            title: alert.title,
            body: alert.body,
            isCritical: true,
          );

          notifyListeners();
        }
      } else if (!isHazardActive && _currentActiveAlert?.nodeId == nodeId) {
        // If hazard condition deactivated (e.g. Iron cooled down, door closed) -> clear alert immediately
        _lastRedAlertTime[nodeId] = null;
        _currentActiveAlert = null;
        notifyListeners();
      }
      return;
    }

    // Candidate differs from current confirmed zone
    if (_candidateZone[nodeId] == candidate) {
      _candidateCount[nodeId] = (_candidateCount[nodeId] ?? 0) + 1;
    } else {
      _candidateZone[nodeId] = candidate;
      _candidateCount[nodeId] = 1;
    }

    // Require small number of consecutive valid readings before switching
    if ((_candidateCount[nodeId] ?? 0) < confirmationSamples) {
      return;
    }

    // 5. Confirmed zone transition!
    final previousZone = currentZone;
    _confirmedZone[nodeId] = candidate;
    _candidateZone[nodeId] = null;
    _candidateCount[nodeId] = 0;
    final now = DateTime.now();

    // -------------------------------------------------------------
    // RED ZONE (Confirmed entry into Red Zone)
    // -------------------------------------------------------------
    if (candidate == ProximityZone.danger) {
      // REQUIREMENT 3: Only alert if hazard condition is fulfilled (Iron HOT or Door OPEN)
      if (isHazardActive) {
        final lastRedTime = _lastRedAlertTime[nodeId];
        final isFirstRedAlert = (_lastAlertedZone[nodeId] != ProximityZone.danger || lastRedTime == null);
        final is5SecondInterval = (lastRedTime != null && now.difference(lastRedTime).inMilliseconds >= 5000);

        if (isFirstRedAlert || is5SecondInterval) {
          _lastAlertedZone[nodeId] = ProximityZone.danger;
          _lastRedAlertTime[nodeId] = now;
          urgentNotificationCount++;

          final alert = SafetyAlertMessage(
            nodeId: nodeId,
            nodeName: nodeName,
            zone: ProximityZone.danger,
            rssi: rssi,
            distanceM: null, // Do not include exact distance
            isHazardActive: isHazardActive,
            hazardDescription: hazardDescription,
            title: '🚨 URGENT: Child Very Near $nodeName',
            body: 'URGENT: Your child is very near the ${nodeName.toLowerCase()}${hazardDescription.isNotEmpty ? " ($hazardDescription)" : ""}.',
            timestamp: now,
          );

          _currentActiveAlert = alert;
          _alertLog.insert(0, alert);
          if (_alertLog.length > 50) _alertLog.removeLast();

          // Trigger loud alarm and vibration
          _triggerMobileAlarmAndVibration();

          // Send urgent notification (immediate & repeated every 5s)
          NotificationService().showHazardNotification(
            id: nodeId,
            title: alert.title,
            body: alert.body,
            isCritical: true,
          );

          notifyListeners();
        }
      } else {
        // Normal condition / Room temp iron / Door closed -> NO alert message in Red zone
        _lastRedAlertTime[nodeId] = null;
        if (_currentActiveAlert?.nodeId == nodeId) {
          _currentActiveAlert = null;
          notifyListeners();
        }
      }
    }
    // -------------------------------------------------------------
    // YELLOW ZONE (Confirmed entry into Yellow Zone)
    // -------------------------------------------------------------
    else if (candidate == ProximityZone.warning) {
      _lastRedAlertTime[nodeId] = null;
      // REQUIREMENT 3: Only alert if hazard condition is fulfilled
      if (isHazardActive) {
        if (_lastAlertedZone[nodeId] != ProximityZone.warning) {
          _lastAlertedZone[nodeId] = ProximityZone.warning;
          normalNotificationCount++;

          final alert = SafetyAlertMessage(
            nodeId: nodeId,
            nodeName: nodeName,
            zone: ProximityZone.warning,
            rssi: rssi,
            distanceM: null, // Do not include exact distance
            isHazardActive: isHazardActive,
            hazardDescription: hazardDescription,
            title: '⚠️ Warning: Child Near $nodeName',
            body: 'Warning: Your child is near the ${nodeName.toLowerCase()}${hazardDescription.isNotEmpty ? " ($hazardDescription)" : ""}.',
            timestamp: now,
          );

          _currentActiveAlert = alert;
          _alertLog.insert(0, alert);
          if (_alertLog.length > 50) _alertLog.removeLast();

          // Normal notification ONLY — DO NOT trigger loud alarm
          NotificationService().showHazardNotification(
            id: nodeId,
            title: alert.title,
            body: alert.body,
            isCritical: false,
          );

          notifyListeners();
        }
      } else {
        // Normal condition / Room temp iron / Door closed -> NO alert message in Yellow zone
        if (_currentActiveAlert?.nodeId == nodeId) {
          _currentActiveAlert = null;
          notifyListeners();
        }
      }
    }
    // -------------------------------------------------------------
    // SAFE ZONE (Child clearly left the zone)
    // -------------------------------------------------------------
    else {
      _lastAlertedZone[nodeId] = ProximityZone.safe;
      _lastRedAlertTime[nodeId] = null;
      if (previousZone == ProximityZone.danger ||
          previousZone == ProximityZone.warning) {
        if (isHazardActive) {
          final alert = SafetyAlertMessage(
            nodeId: nodeId,
            nodeName: nodeName,
            zone: ProximityZone.safe,
            rssi: rssi,
            distanceM: null,
            isHazardActive: isHazardActive,
            hazardDescription: hazardDescription,
            title: '✅ Safe: Child Away from $nodeName',
            body: 'Your child has moved away from the ${nodeName.toLowerCase()}.',
            timestamp: now,
          );
          _alertLog.insert(0, alert);
          if (_alertLog.length > 50) _alertLog.removeLast();
        }
      }
      if (_currentActiveAlert?.nodeId == nodeId) {
        _currentActiveAlert = null;
      }
      notifyListeners();
    }
  }

  /// Mark node offline and send a single disconnection notification.
  /// Also clears any old active Red Zone state so disconnection cannot leave an alert active forever.
  void handleNodeOffline(int nodeId, String nodeName) {
    final wasOnline = _isOnline[nodeId] ?? false;
    _isOnline[nodeId] = false;

    // Send one phone notification when an Online node is confirmed Offline
    if (wasOnline && !(_hasNotifiedOffline[nodeId] ?? false)) {
      _hasNotifiedOffline[nodeId] = true;
      offlineNotificationCount++;

      NotificationService().showOfflineNotification(
        id: nodeId,
        nodeName: nodeName,
      );
    }

    // Ensure a confirmed disconnection resets all proximity states and pending confirmations
    _confirmedZone[nodeId] = ProximityZone.safe;
    _candidateZone[nodeId] = null;
    _candidateCount[nodeId] = 0;
    _lastAlertedZone[nodeId] = ProximityZone.safe;
    _lastRedAlertTime.remove(nodeId);

    if (_currentActiveAlert?.nodeId == nodeId) {
      _currentActiveAlert = null;
    }

    if (wasOnline) {
      notifyListeners();
    }
  }

  /// Mark node online when valid telemetry packets resume.
  void setNodeOnline(int nodeId, String nodeName) {
    _isOnline[nodeId] = true;
    _hasNotifiedOffline[nodeId] = false;
  }
}
