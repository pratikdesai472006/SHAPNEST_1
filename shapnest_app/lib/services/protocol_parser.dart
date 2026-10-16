import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/shapnest_protocol.dart';

class ParsedNodeBeacon {
  final int nodeId;
  final int calibratedRssi1m;
  final double pathLossExpN;
  final int sequence;
  final int sensorState;

  ParsedNodeBeacon({
    required this.nodeId,
    required this.calibratedRssi1m,
    required this.pathLossExpN,
    required this.sequence,
    this.sensorState = 0,
  });
}

class ParsedWristbandNodeBlock {
  final int nodeId;
  final NodeState state;
  final double? distanceM;
  final int filteredRssi;

  ParsedWristbandNodeBlock({
    required this.nodeId,
    required this.state,
    required this.distanceM,
    required this.filteredRssi,
  });
}

class ParsedWristbandTelemetry {
  final int wristbandId;
  final int sequence;
  final List<ParsedWristbandNodeBlock> nodes;

  ParsedWristbandTelemetry({
    required this.wristbandId,
    required this.sequence,
    required this.nodes,
  });
}

class ProtocolParser {
  /// Attempt to parse a ScanResult as either a SHAPNEST Anchor Node Beacon or Wristband Telemetry
  static Object? parseScanResult(ScanResult result) {
    final adv = result.advertisementData;
    final mfrDataMap = adv.manufacturerData;
    final devName = adv.advName.isNotEmpty ? adv.advName : result.device.platformName;
    final isShapnestDevice = devName.contains('SHAPNEST') || devName.contains('WB1');

    // Check all manufacturer data entries
    for (final entry in mfrDataMap.entries) {
      final key = entry.key; // 16-bit company ID or parsed ID
      final rawBytes = entry.value;

      // Case 1: Key itself is 0x534E ('SN') or 0x4E53 ('NS')
      if (key == ShapnestProtocol.protocolId || key == ShapnestProtocol.protocolIdLe) {
        final parsed = _parsePayloadBytes(rawBytes, devName);
        if (parsed != null) return parsed;
      }

      // Case 2: Full payload included company ID as first 2 bytes
      if (rawBytes.length >= 2) {
        final compId = rawBytes[0] | (rawBytes[1] << 8);
        final compIdAlt = (rawBytes[0] << 8) | rawBytes[1];
        if (compId == ShapnestProtocol.protocolId || compIdAlt == ShapnestProtocol.protocolId) {
          final parsed = _parsePayloadBytes(rawBytes.sublist(2), devName);
          if (parsed != null) return parsed;
        }
      }

      // Case 3: Only parse without company ID IF the device name explicitly identifies as SHAPNEST
      if (isShapnestDevice) {
        final directParsed = _parsePayloadBytes(rawBytes, devName);
        if (directParsed != null) return directParsed;
      }
    }

    // Fallback: check device name pattern (e.g. "SHAPNEST_N1", "SHAPNEST_N2", "SHAPNEST_N3")
    if (devName.startsWith('SHAPNEST_N')) {
      final idChar = devName.replaceAll('SHAPNEST_N', '').trim();
      final id = int.tryParse(idChar);
      if (id != null && id >= ShapnestProtocol.nodeIdMin && id <= ShapnestProtocol.nodeIdMax) {
        return ParsedNodeBeacon(
          nodeId: id,
          calibratedRssi1m: ShapnestProtocol.defaultRefRssi1m,
          pathLossExpN: 2.2,
          sequence: 0,
        );
      }
    }

    return null;
  }

  static Object? _parsePayloadBytes(List<int> bytes, String devName) {
    if (bytes.isEmpty) return null;

    // Auto-strip 2-byte company ID if present in payload (0x534E or 0x4E53)
    if (bytes.length >= 7 &&
        ((bytes[0] == 0x4E && bytes[1] == 0x53) || (bytes[0] == 0x53 && bytes[1] == 0x4E))) {
      bytes = bytes.sublist(2);
    }

    final frameType = bytes[0];

    // Frame Type 0x01: Node Beacon (Length: 5 bytes after company ID)
    // [0] frame_type (0x01)
    // [1] node_id (1..3)
    // [2] calibrated_rssi_1m (int8)
    // [3] path_loss_exp_x10 (uint8)
    // [4] sequence (uint8)
    if (frameType == ShapnestProtocol.frameTypeNodeBeacon && bytes.length >= 5) {
      final nodeId = bytes[1];
      if (nodeId < ShapnestProtocol.nodeIdMin || nodeId > ShapnestProtocol.nodeIdMax) {
        return null;
      }
      final rawCalA = ByteData.view(Uint8List.fromList([bytes[2]]).buffer).getInt8(0);
      final expX10 = bytes[3];
      final seq = bytes[4];
      final sensorState = bytes.length >= 6 ? bytes[5] : 0;

      return ParsedNodeBeacon(
        nodeId: nodeId,
        calibratedRssi1m: rawCalA,
        pathLossExpN: expX10 > 0 ? (expX10 / 10.0) : 2.2,
        sequence: seq,
        sensorState: sensorState,
      );
    }

    // Frame Type 0x02: Wristband Telemetry (Length: 16 bytes after company ID)
    // [0] frame_type (0x02)
    // [1] wristband_id (1)
    // [2] sequence (uint8)
    // [3] node_count (3)
    // Followed by node blocks (4 bytes each):
    //   id_and_state (1 byte)
    //   distance_cm (2 bytes uint16 little endian)
    //   filtered_rssi (1 byte int8)
    if (frameType == ShapnestProtocol.frameTypeWristbandTel && bytes.length >= 4) {
      final wbId = bytes[1];
      if (wbId != ShapnestProtocol.targetWristbandId) return null;

      final seq = bytes[2];
      final nodeCount = bytes[3];
      if (nodeCount < 1 || nodeCount > ShapnestProtocol.maxNodes) return null;
      if (bytes.length < 4 + (nodeCount * 4)) return null;

      final List<ParsedWristbandNodeBlock> parsedBlocks = [];
      int offset = 4;

      for (int i = 0; i < nodeCount && (offset + 4) <= bytes.length; i++) {
        final idAndState = bytes[offset];
        final nodeId = ShapnestProtocol.unpackId(idAndState);
        final state = ShapnestProtocol.unpackState(idAndState);

        final distCm = bytes[offset + 1] | (bytes[offset + 2] << 8);
        final filteredRssi = ByteData.view(Uint8List.fromList([bytes[offset + 3]]).buffer).getInt8(0);

        double? distanceM;
        if (distCm != ShapnestProtocol.distanceOfflineCm &&
            distCm > 0 &&
            distCm <= 1500 &&
            state != NodeState.offline) {
          distanceM = (distCm / 100.0).clamp(
            ShapnestProtocol.distanceMinM,
            ShapnestProtocol.distanceMaxM,
          );
        }

        parsedBlocks.add(ParsedWristbandNodeBlock(
          nodeId: nodeId,
          state: state,
          distanceM: distanceM,
          filteredRssi: filteredRssi,
        ));

        offset += 4;
      }

      return ParsedWristbandTelemetry(
        wristbandId: wbId,
        sequence: seq,
        nodes: parsedBlocks,
      );
    }

    return null;
  }
}
