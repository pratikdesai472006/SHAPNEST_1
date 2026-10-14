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

class AlertService extends ChangeNotifier {
  final Map<int, ProximityZone> _lastZone = {};
  final Map<int, DateTime?> _lastAlertTime = {};

  SafetyAlertMessage? _currentActiveAlert;
  final List<SafetyAlertMessage> _alertLog = [];

  SafetyAlertMessage? get currentActiveAlert => _currentActiveAlert;
  List<SafetyAlertMessage> get alertLog => List.unmodifiable(_alertLog);

  /// Dismiss the current active alert banner
  void dismissActiveAlert() {
    _currentActiveAlert = null;
    notifyListeners();
  }

  /// Triggers mobile alarm sound and physical vibration
  void _triggerMobileAlarmAndVibration() {
    try {
      SystemSound.play(SystemSoundType.alert).catchError((_) {});
      HapticFeedback.heavyImpact().catchError((_) {});
      HapticFeedback.vibrate().catchError((_) {});
    } catch (_) {
      // Graceful fallback in environments without sound/vibrator hardware (e.g. tests)
    }
  }

  /// Evaluates signal strength and attached hazard condition from the child wristband.
  /// RULE:
  /// - Signal strength >= dangerRssiDbm (default -60 dBm) -> Child is Near (Red Zone)
  /// - Signal strength >= warningRssiDbm (default -75 dBm) -> Child Approaching (Yellow Zone)
  /// - Critical Alert (Mobile message notification + Mobile alarm + Vibration) is given ONLY IF:
  ///     Child is in Red Zone AND condition is fulfilled (Fan is ON, Iron is HOT, or Door is OPEN)!
  /// - Otherwise "nothing to do"!
  void processWristbandTelemetry({
    required int nodeId,
    required String nodeName,
    int? rssi,
    double? distanceM,
    bool isHazardActive = true,
    String hazardDescription = '',
    int dangerRssiDbm = -60,
    int warningRssiDbm = -74,
    double dangerDistanceM = 0.30,
    double warningDistanceM = 0.70,
    String unit = 'm',
  }) {
    if (rssi == null && distanceM == null) return;
    if (rssi == ShapnestProtocol.rssiOffline) return;

    final now = DateTime.now();

    // 1. Determine Proximity Zone using Signal Strength (RSSI in dBm) as primary metric
    ProximityZone currentZone;
    if (rssi != null) {
      if (rssi >= dangerRssiDbm) {
        currentZone = ProximityZone.danger; // Strong signal: child is near
      } else if (rssi >= warningRssiDbm) {
        currentZone = ProximityZone.warning; // Moderate signal
      } else {
        currentZone = ProximityZone.safe; // Weak signal: safe / far away
      }
    } else {
      // Fallback to distance boundary if RSSI unpopulated
      if (distanceM! <= dangerDistanceM) {
        currentZone = ProximityZone.danger;
      } else if (distanceM <= warningDistanceM) {
        currentZone = ProximityZone.warning;
      } else {
        currentZone = ProximityZone.safe;
      }
    }

    final prevZone = _lastZone[nodeId];
    final lastTime = _lastAlertTime[nodeId];

    final rssiStr = rssi != null ? '$rssi dBm' : '';
    final distStr = distanceM != null
        ? (unit == 'm' ? '${distanceM.toStringAsFixed(2)}m' : '${(distanceM * 100).toInt()}cm')
        : '';
    final metricStr = rssiStr.isNotEmpty ? rssiStr : distStr;

    // -------------------------------------------------------------
    // 1. RED DANGER ZONE (Strong Signal >= -60 dBm / Child Near)
    // -------------------------------------------------------------
    if (currentZone == ProximityZone.danger) {
      // CONDITION GATING: Only alarm/vibrate if the hazard is active (Fan ON, Iron HOT, Door OPEN)!
      if (isHazardActive) {
        final conditionText = hazardDescription.isNotEmpty ? hazardDescription : 'Hazard Active';

        if (prevZone != ProximityZone.danger) {
          // Immediate first mobile message notification + mobile alarm + vibration
          final alert = SafetyAlertMessage(
            nodeId: nodeId,
            nodeName: nodeName,
            zone: ProximityZone.danger,
            rssi: rssi,
            distanceM: distanceM,
            isHazardActive: true,
            hazardDescription: conditionText,
            title: '🚨 CRITICAL DANGER: Child Near $nodeName!',
            body: 'Strong signal ($metricStr) & $conditionText! Move child away immediately!',
            timestamp: now,
          );
          _triggerAlert(nodeId, alert, currentZone, now);
          _triggerMobileAlarmAndVibration();
        } else {
          // Already in Red Zone with active hazard -> repeat every 15 seconds
          if (lastTime == null || now.difference(lastTime) >= const Duration(seconds: 15)) {
            final alert = SafetyAlertMessage(
              nodeId: nodeId,
              nodeName: nodeName,
              zone: ProximityZone.danger,
              rssi: rssi,
              distanceM: distanceM,
              isHazardActive: true,
              hazardDescription: conditionText,
              title: '🚨 RED ZONE REPEAT ALARM (15s)',
              body: 'Child remains in hazard proximity to $nodeName ($metricStr, $conditionText)! Take immediate action!',
              timestamp: now,
            );
            _triggerAlert(nodeId, alert, currentZone, now);
            _triggerMobileAlarmAndVibration();
          }
        }
      } else {
        // Child is near, but condition is NOT fulfilled (e.g. Fan is OFF, Iron is Cool, Door is Closed)
        // "otherwise nothing to do" — do not trigger mobile alarm, do not vibrate!
        _lastZone[nodeId] = ProximityZone.safe;
      }
    }
    // -------------------------------------------------------------
    // 2. YELLOW WARNING ZONE (-60 dBm to -75 dBm)
    // -------------------------------------------------------------
    else if (currentZone == ProximityZone.warning) {
      if (isHazardActive) {
        final conditionText = hazardDescription.isNotEmpty ? hazardDescription : 'Hazard Active';

        if (prevZone != ProximityZone.warning) {
          final alert = SafetyAlertMessage(
            nodeId: nodeId,
            nodeName: nodeName,
            zone: ProximityZone.warning,
            rssi: rssi,
            distanceM: distanceM,
            isHazardActive: true,
            hazardDescription: conditionText,
            title: '⚠️ CAUTION: Child Approaching $nodeName',
            body: 'Child entered Warning Zone near $nodeName ($metricStr). $conditionText. Monitor closely.',
            timestamp: now,
          );
          _triggerAlert(nodeId, alert, currentZone, now);
        } else {
          if (lastTime == null || now.difference(lastTime) >= const Duration(minutes: 1)) {
            final alert = SafetyAlertMessage(
              nodeId: nodeId,
              nodeName: nodeName,
              zone: ProximityZone.warning,
              rssi: rssi,
              distanceM: distanceM,
              isHazardActive: true,
              hazardDescription: conditionText,
              title: '⚠️ YELLOW ZONE REMINDER (1 min)',
              body: 'Child is within Warning Caution Zone near $nodeName ($metricStr, $conditionText).',
              timestamp: now,
            );
            _triggerAlert(nodeId, alert, currentZone, now);
          }
        }
      } else {
        // Hazard inactive: nothing to do
        _lastZone[nodeId] = ProximityZone.safe;
      }
    }
    // -------------------------------------------------------------
    // 3. GREEN SAFE ZONE (< -75 dBm / Weak Signal / Far Away)
    // -------------------------------------------------------------
    else {
      if (prevZone == ProximityZone.danger || prevZone == ProximityZone.warning) {
        // Child recovered to safe distance
        final alert = SafetyAlertMessage(
          nodeId: nodeId,
          nodeName: nodeName,
          zone: ProximityZone.safe,
          rssi: rssi,
          distanceM: distanceM,
          isHazardActive: isHazardActive,
          hazardDescription: hazardDescription,
          title: '✅ RECOVERED TO SAFE ZONE',
          body: 'Child has safely moved away from $nodeName ($metricStr).',
          timestamp: now,
        );
        _triggerAlert(nodeId, alert, currentZone, now);
        _lastAlertTime[nodeId] = null;
      } else {
        _lastZone[nodeId] = ProximityZone.safe;
      }
    }
  }

  void _triggerAlert(int nodeId, SafetyAlertMessage alert, ProximityZone zone, DateTime now) {
    _lastZone[nodeId] = zone;
    _lastAlertTime[nodeId] = now;
    _currentActiveAlert = alert;
    _alertLog.insert(0, alert);
    if (_alertLog.length > 50) {
      _alertLog.removeLast();
    }

    // Trigger Native Device Notification (system notification banner, sound & lock screen)
    if (zone == ProximityZone.danger || zone == ProximityZone.warning) {
      NotificationService().showHazardNotification(
        id: nodeId,
        title: alert.title,
        body: alert.body,
        isCritical: zone == ProximityZone.danger,
      );
    }

    notifyListeners();
  }
}
