/// SHAPNEST Protocol Constants and Packet Definitions
/// 100% compliant with firmware/common/shapnest_protocol.h
library;

enum NodeState {
  active,
  stale,
  offline;

  String get displayName {
    switch (this) {
      case NodeState.active:
        return 'ACTIVE';
      case NodeState.stale:
        return 'STALE';
      case NodeState.offline:
        return 'OFFLINE';
    }
  }
}

class ShapnestProtocol {
  static const int protocolId = 0x534E; // 'SN'
  static const int protocolIdLe = 0x4E53; // 'NS'
  static const int protocolVersion = 1;

  static const int frameTypeNodeBeacon = 0x01;
  static const int frameTypeWristbandTel = 0x02;

  static const int targetWristbandId = 1;
  static const int maxNodes = 3;
  static const int nodeIdMin = 1;
  static const int nodeIdMax = 3;

  // Defaults
  static const int defaultTxPowerDbm = 9;
  static const int defaultRefRssi1m = -59;
  static const int defaultPathLossExpX10 = 22; // n = 2.2

  // Distance bounds
  static const double distanceMinM = 0.15;
  static const double distanceMaxM = 8.00;
  static const int distanceOfflineCm = 0xFFFF;

  // Staleness timeouts
  static const Duration nodeActiveTimeout = Duration(milliseconds: 1400);
  static const Duration nodeOfflineTimeout = Duration(milliseconds: 3500);
  static const Duration wristbandOfflineTimeout = Duration(milliseconds: 3500);

  static NodeState unpackState(int packedByte) {
    final raw = (packedByte >> 4) & 0x03;
    switch (raw) {
      case 0:
        return NodeState.active;
      case 1:
        return NodeState.stale;
      case 2:
      default:
        return NodeState.offline;
    }
  }

  static int unpackId(int packedByte) {
    return packedByte & 0x0F;
  }
}
