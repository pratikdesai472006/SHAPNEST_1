import 'package:flutter/material.dart';
import '../services/distance_engine.dart';
import '../services/kalman_filter.dart';
import 'shapnest_protocol.dart';

class NodeData {
  final int id;
  String name;
  final IconData icon;
  final Color primaryColor;
  double dangerDistanceM; // Hazard boundary for Red zone (< dangerDistanceM)
  double warningDistanceM; // Warning boundary for Yellow zone (dangerDistanceM .. warningDistanceM)

  // Signal Strength (RSSI) Zone Thresholds (User configured: Red >= -60 dBm, Yellow >= -74 dBm)
  int dangerRssiDbm; // Danger Red Zone threshold (default -60 dBm)
  int warningRssiDbm; // Warning Yellow Zone threshold (default -74 dBm)

  // Direct Phone-to-Node Measurements
  double? directDistanceM;
  int? directRawRssi;
  int? directFilteredRssi;
  DateTime? directLastSeen;
  NodeState directState;
  FilterMotionState directMotionState;

  // Wristband-Reported Measurements (Child-to-Node)
  double? wbDistanceM;
  int? wbFilteredRssi;
  DateTime? wbLastSeen;
  NodeState wbState;

  // Attached Sensor / Hazard States
  bool isFanOn; // Node 1 (Fan): true = spinning/ON (hazard active), false = OFF (safe)
  int? ironTemperatureC; // Node 2 (Iron): Temperature in °C (>= 50°C is hot)
  DoorState doorState; // Node 3 (Door): open = hazard active, closed = secure

  // Dual Physical Calibration Parameters
  int directCalibratedA; // Reference RSSI @ 1m for direct phone BLE link
  int wbCalibratedA; // Reference RSSI @ 1m for child wristband link
  double pathLossExpN; // Environmental factor n (default 1.6 in free space)
  bool isUserCalibrated;

  int get calibratedA => wbCalibratedA;
  set calibratedA(int val) {
    wbCalibratedA = val;
    directCalibratedA = val;
  }

  // Statistics
  int packetCount;
  double packetsPerSecond;

  NodeData({
    required this.id,
    required this.name,
    required this.icon,
    required this.primaryColor,
    this.dangerDistanceM = 0.30,
    this.warningDistanceM = 0.70,
    this.dangerRssiDbm = -60,
    this.warningRssiDbm = -74,
    int? directCalibratedA,
    int? wbCalibratedA,
    int? calibratedA,
    this.pathLossExpN = 1.6,
    this.isUserCalibrated = false,
    this.isFanOn = true,
    this.doorState = DoorState.unknown,
    this.ironTemperatureC,
    this.directDistanceM,
    this.directRawRssi,
    this.directFilteredRssi,
    this.directLastSeen,
    this.directState = NodeState.offline,
    this.directMotionState = FilterMotionState.stationary,
    this.wbDistanceM,
    this.wbFilteredRssi,
    this.wbLastSeen,
    this.wbState = NodeState.offline,
    this.packetCount = 0,
    this.packetsPerSecond = 0.0,
  })  : directCalibratedA = calibratedA ?? directCalibratedA ?? ShapnestProtocol.defaultRefRssi1m,
        wbCalibratedA = calibratedA ?? wbCalibratedA ?? ShapnestProtocol.defaultWbRefRssi1m;

  /// Whether the iron is dangerously hot (>= 50°C)
  bool get isIronHot =>
      ironTemperatureC != null &&
      ironTemperatureC! >= ShapnestProtocol.ironHotThresholdC;

  /// Whether the iron is warm (40°C - 49°C)
  bool get isIronWarm =>
      ironTemperatureC != null &&
      ironTemperatureC! >= ShapnestProtocol.ironWarmThresholdC &&
      !isIronHot;

  /// Whether the physical hazard condition is currently fulfilled/active
  /// - Fan: Fan is ON / spinning
  /// - Iron: Iron is HOT (>= 50°C)
  /// - Door: Door / window is OPEN
  bool get isHazardConditionFulfilled {
    switch (id) {
      case 1:
        return isFanOn;
      case 2:
        return isIronHot;
      case 3:
        return doorState == DoorState.open;
      default:
        return false;
    }
  }

  /// Human-readable explanation of the current hazard condition
  String get hazardDescription {
    switch (id) {
      case 1:
        return isFanOn ? 'Fan is ON (Spinning Hazard)' : 'Fan is OFF';
      case 2:
        return isIronHot
            ? 'Iron is HOT (${ironTemperatureC ?? 50}°C Burn Hazard)'
            : (isIronWarm ? 'Iron is WARM (${ironTemperatureC ?? 40}°C)' : 'Iron is Cool');
      case 3:
        return doorState == DoorState.open ? 'Door/Window is OPEN' : 'Door is Closed';
      default:
        return 'Normal';
    }
  }

  /// Check whether the node signal strength is in the Red Danger Zone (>= dangerRssiDbm, default -60 dBm)
  bool isSignalDanger(int? rssi) {
    if (rssi == null || rssi == ShapnestProtocol.rssiOffline) return false;
    return rssi >= dangerRssiDbm;
  }

  /// Check whether the node signal strength is in the Yellow Warning Zone (dangerRssiDbm .. warningRssiDbm)
  bool isSignalWarning(int? rssi) {
    if (rssi == null || rssi == ShapnestProtocol.rssiOffline) return false;
    return rssi < dangerRssiDbm && rssi >= warningRssiDbm;
  }

  /// Classify signal strength into standard 3 Radar / Proximity Zones:
  /// - Red Zone: >= -60 dBm (Strong signal / Child is Near)
  /// - Yellow Zone: -60 dBm to -75 dBm (Moderate signal)
  /// - Green Zone: < -75 dBm (Weak signal / Far away)
  ProximityZone? getSignalZone(int? rssi) {
    if (rssi == null || rssi == ShapnestProtocol.rssiOffline) return null;
    if (rssi >= dangerRssiDbm) {
      return ProximityZone.danger; // Red Zone
    } else if (rssi >= warningRssiDbm) {
      return ProximityZone.warning; // Yellow Zone
    } else {
      return ProximityZone.safe; // Green Zone
    }
  }

  /// Exit thresholds with hysteresis margin (default 3 dBm)
  int get dangerExitRssiDbm => dangerRssiDbm - ShapnestProtocol.rssiHysteresisMarginDbm;
  int get warningExitRssiDbm => warningRssiDbm - ShapnestProtocol.rssiHysteresisMarginDbm;

  /// Returns understandable proximity label based on signal strength:
  /// - 'Very Near' (Red Zone >= dangerRssiDbm)
  /// - 'Near' (Yellow Zone dangerRssiDbm..warningRssiDbm)
  /// - 'Safe' (Green Zone < warningRssiDbm)
  /// - 'Offline' (null / no signal)
  String getProximityLabel(int? rssi) {
    if (rssi == null || rssi == ShapnestProtocol.rssiOffline) return 'Offline';
    if (rssi >= dangerRssiDbm) {
      return 'Very Near';
    } else if (rssi >= warningRssiDbm) {
      return 'Near';
    } else {
      return 'Safe';
    }
  }

  /// True when signal strength is in Red Zone (proximity alert)
  bool isCriticalHazardAlert(int? rssi) {
    return isSignalDanger(rssi);
  }

  /// Check whether the node is currently in the dangerous zone (< dangerDistanceM)
  bool isDanger(double? distanceM) {
    if (distanceM == null) return false;
    return distanceM < dangerDistanceM;
  }

  /// Check whether the node is currently in the yellow warning zone (dangerDistanceM .. warningDistanceM)
  bool isWarning(double? distanceM) {
    if (distanceM == null) return false;
    return distanceM >= dangerDistanceM && distanceM <= warningDistanceM;
  }

  /// Classify distance into standard SHAPNEST Safety Zones
  ProximityZone? getZone(double? distanceM) {
    if (distanceM == null) return null;
    if (distanceM <= 0.30) {
      return ProximityZone.criticalDanger;
    } else if (distanceM <= dangerDistanceM || distanceM <= 1.00) {
      return ProximityZone.danger;
    } else if (distanceM <= warningDistanceM || distanceM <= 2.00) {
      return ProximityZone.warning;
    } else {
      return ProximityZone.safe;
    }
  }

  /// Create predefined default nodes with distinct free-space n = 1.6 values and signal zones
  static List<NodeData> createDefaultNodes() {
    return [
      NodeData(
        id: 1,
        name: 'Fan',
        icon: Icons.air_rounded,
        primaryColor: const Color(0xFF00E5FF), // Cyan
        dangerDistanceM: 0.60,
        dangerRssiDbm: -60,
        warningRssiDbm: -74,
        pathLossExpN: 1.6, // Free space n = 1.6 for Node 1 Fan
        isFanOn: true,
      ),
      NodeData(
        id: 2,
        name: 'Iron',
        icon: Icons.iron_outlined,
        primaryColor: const Color(0xFFFF5252), // Red alert
        dangerDistanceM: 0.80,
        dangerRssiDbm: -60,
        warningRssiDbm: -74,
        pathLossExpN: 1.6, // Free space n = 1.6 for Node 2 Iron
      ),
      NodeData(
        id: 3,
        name: 'Door',
        icon: Icons.door_front_door_outlined,
        primaryColor: const Color(0xFF76FF03), // Lime green
        dangerDistanceM: 0.50,
        dangerRssiDbm: -60,
        warningRssiDbm: -74,
        pathLossExpN: 1.6, // Free space n = 1.6 for Node 3 Door
        doorState: DoorState.unknown,
      ),
    ];
  }
}
