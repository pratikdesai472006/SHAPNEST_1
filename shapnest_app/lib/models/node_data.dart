import 'package:flutter/material.dart';
import '../services/distance_engine.dart';
import '../services/kalman_filter.dart';
import 'shapnest_protocol.dart';

class NodeData {
  final int id;
  final String name;
  final IconData icon;
  final Color primaryColor;
  final double dangerDistanceM; // Specific hazard boundary for this node

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

  // Calibration parameters
  int directCalibratedA; // Reference RSSI @ 1m for Phone Link (in dBm)
  int wbCalibratedA; // Reference RSSI @ 1m for Wristband Link (in dBm)
  int get calibratedA => directCalibratedA;
  set calibratedA(int val) => directCalibratedA = val;
  double pathLossExpN; // Environmental factor n
  bool isUserCalibrated;

  // Statistics
  int packetCount;
  double packetsPerSecond;

  NodeData({
    required this.id,
    required this.name,
    required this.icon,
    required this.primaryColor,
    required this.dangerDistanceM,
    int? directCalibratedA,
    int? wbCalibratedA,
    int? calibratedA,
    this.pathLossExpN = 2.2,
    this.isUserCalibrated = false,
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
        wbCalibratedA = wbCalibratedA ?? ShapnestProtocol.defaultWbRefRssi1m;

  /// Check whether the node is currently in the dangerous zone (< 30 cm)
  bool isDanger(double? distanceM) {
    if (distanceM == null) return false;
    return distanceM < 0.30;
  }

  /// Check whether the node is currently in the yellow warning zone (30 - 67 cm)
  bool isWarning(double? distanceM) {
    if (distanceM == null) return false;
    return distanceM >= 0.30 && distanceM <= 0.67;
  }

  /// Classify distance into standard SHAPNEST Safety Zones:
  /// - Below 30 cm: Dangerous Zone (Red)
  /// - 30 cm to 67 cm: Yellow Zone (Yellow/Warning)
  /// - Further than 67 cm: Safe Zone (Green)
  ProximityZone? getZone(double? distanceM) {
    if (distanceM == null) return null;
    if (distanceM < 0.30) {
      return ProximityZone.danger;
    } else if (distanceM <= 0.67) {
      return ProximityZone.warning;
    } else {
      return ProximityZone.safe;
    }
  }

  /// Create predefined default nodes
  static List<NodeData> createDefaultNodes() {
    return [
      NodeData(
        id: 1,
        name: 'Fan',
        icon: Icons.air_rounded,
        primaryColor: const Color(0xFF00E5FF), // Cyan
        dangerDistanceM: 0.60,
      ),
      NodeData(
        id: 2,
        name: 'Iron',
        icon: Icons.iron_outlined,
        primaryColor: const Color(0xFFFF5252), // Red alert
        dangerDistanceM: 0.80,
      ),
      NodeData(
        id: 3,
        name: 'Door',
        icon: Icons.door_front_door_outlined,
        primaryColor: const Color(0xFF76FF03), // Lime green
        dangerDistanceM: 0.50,
      ),
    ];
  }
}
