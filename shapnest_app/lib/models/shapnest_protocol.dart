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

enum DoorState {
  closed,
  open,
  unknown;

  String get displayName {
    switch (this) {
      case DoorState.closed:
        return 'CLOSED';
      case DoorState.open:
        return 'OPEN';
      case DoorState.unknown:
        return 'UNKNOWN';
    }
  }
}

class ShapnestProtocol {
  static const int protocolId = 0x534E; // 'SN'
  static const int protocolIdLe = 0x4E53; // 'NS'
  static const int protocolVersion = 1;

  static const int frameTypeNodeBeacon = 0x01;
  static const int frameTypeWristbandTel = 0x02;

  // Door Sensor States
  static const int doorClosed = 0x00;
  static const int doorOpen = 0x01;

  // Iron Temperature Thresholds
  static const int ironHotThresholdC = 50; // >= 50°C is considered HOT / Hazard
  static const int ironWarmThresholdC = 40; // >= 40°C is considered Warm
  static const int ironDefaultAmbientC = 28; // Default ambient room temperature (28°C)


  static const int targetWristbandId = 1;
  static const int maxNodes = 3;
  static const int nodeIdMin = 1;
  static const int nodeIdMax = 3;

  // RSSI Proximity Zones & Hysteresis Thresholds (Configurable defaults)
  static const int defaultRedZoneEntryRssiDbm = -60;   // Very Near / Red Zone entry threshold
  static const int defaultRedZoneExitRssiDbm = -63;    // Exit Red Zone (3 dB hysteresis)
  static const int defaultYellowZoneEntryRssiDbm = -74; // Near / Yellow Zone entry threshold
  static const int defaultYellowZoneExitRssiDbm = -77;  // Exit Yellow Zone (3 dB hysteresis)
  static const int rssiHysteresisMarginDbm = 3;        // 3 dB hysteresis to prevent boundary flutter
  static const int defaultZoneConfirmationSamples = 2;  // Consecutive samples required for confirmed zone transition

  static const int defaultTxPowerDbm = 9;
  static const int defaultRefRssi1m = -77;
  static const int defaultWbRefRssi1m = -77; // Calibrated -77 dBm @ 1m in free space
  static const int defaultPathLossExpX10 = 16; // n = 1.6 in free space

  // Distance bounds
  static const double distanceMinM = 0.15;
  static const double distanceMaxM = 8.00;
  static const int distanceOfflineCm = 0xFFFF;
  static const int rssiOffline = -128;

  // Staleness timeouts (Optimized for faster reading and offline detection)
  static const Duration nodeActiveTimeout = Duration(milliseconds: 1000);
  static const Duration nodeOfflineTimeout = Duration(milliseconds: 2500);
  static const Duration wristbandOfflineTimeout = Duration(milliseconds: 2000);

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
