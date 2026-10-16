import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/node_data.dart';
import '../models/shapnest_protocol.dart';
import 'alert_service.dart';
import 'distance_engine.dart';
import 'notification_service.dart';
import 'protocol_parser.dart';

enum TrackingSource {
  directPhone, // Phone is the receiver (measures phone <-> nodes)
  wristband, // Phone displays child wristband telemetry (wristband <-> nodes)
}

class CalibrationState {
  final int nodeId;
  final int targetSamples;
  final List<int> collectedRssi = [];
  bool isCompleted = false;
  int? finalCalibratedA;

  CalibrationState({required this.nodeId, this.targetSamples = 30});

  double get progress => collectedRssi.length / targetSamples;
}

class BleService extends ChangeNotifier {
  final DistanceEngine distanceEngine;

  // Nodes list (Node 1: Fan, Node 2: Iron, Node 3: Door)
  late List<NodeData> nodes;

  // Active tracking display mode (Defaults to Child Wristband for instant tracking)
  TrackingSource trackingSource = TrackingSource.wristband;

  // Wristband state
  bool isWristbandOnline = false;
  int wristbandSequence = 0;
  DateTime? lastWristbandSeen;

  // Scanner status
  bool isScanning = false;
  bool isBluetoothAvailable = false;
  String statusMessage = 'Ready';

  // Safety Alert Messaging Engine (Yellow: 1 min, Red: 15s)
  final AlertService alertService = AlertService();

  // Simulation mode
  bool isSimulating = false;
  Timer? _simulationTimer;
  double _simAngle = 0.0;

  // Diagnostic log stream
  final List<String> diagnosticLogs = [];
  static const int maxLogs = 100;

  // Calibration Wizard state
  CalibrationState? activeCalibration;

  // Subscriptions & Timers
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _stalenessTimer;
  Timer? _packetRateTimer;

  // Statistics
  final Map<int, int> _windowPacketCounters = {};

  BleService({required this.distanceEngine}) {
    nodes = NodeData.createDefaultNodes();
    _initBluetooth();
  }

  void _addLog(String log) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    diagnosticLogs.insert(0, '[$timestamp] $log');
    if (diagnosticLogs.length > maxLogs) {
      diagnosticLogs.removeLast();
    }
    notifyListeners();
  }

  Future<void> _initBluetooth() async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (supported) {
        _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
          isBluetoothAvailable = (state == BluetoothAdapterState.on);
          if (!isBluetoothAvailable) {
            statusMessage = 'Bluetooth is OFF';
          } else {
            statusMessage = 'Bluetooth Ready';
            // Auto-start continuous scanning immediately once Bluetooth is ready
            if (!isScanning && !isSimulating) {
              startScan();
            }
          }
          notifyListeners();
        }, onError: (e) {
          statusMessage = 'Bluetooth error: $e';
        });
      } else {
        statusMessage = 'BLE not supported on device';
      }
    } catch (e) {
      statusMessage = 'Bluetooth unavailable';
      isBluetoothAvailable = false;
    }

    // Start periodic watchdog timer for staleness & offline detection (10 Hz faster response)
    _stalenessTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _checkStaleness();
    });

    // Packet rate counter calculation (every 1 second)
    _packetRateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      for (final node in nodes) {
        final count = _windowPacketCounters[node.id] ?? 0;
        node.packetsPerSecond = count.toDouble();
        _windowPacketCounters[node.id] = 0;
      }
      notifyListeners();
    });

    // Load saved calibration and zone parameters into per-node models
    final prefs = await SharedPreferences.getInstance();
    for (final node in nodes) {
      node.directCalibratedA = distanceEngine.getCalibratedA(node.id);
      node.wbCalibratedA = distanceEngine.getWbCalibratedA(node.id);
      node.pathLossExpN = distanceEngine.getNodePathLossN(node.id);

      final savedDanger = prefs.getDouble('shapnest_danger_node_${node.id}');
      if (savedDanger != null) {
        node.dangerDistanceM = savedDanger;
      }
      final savedWarn = prefs.getDouble('shapnest_warn_node_${node.id}');
      if (savedWarn != null) {
        node.warningDistanceM = savedWarn;
      }

      final savedDangerRssi = prefs.getInt('shapnest_danger_rssi_node_${node.id}');
      if (savedDangerRssi != null) {
        node.dangerRssiDbm = savedDangerRssi;
      }
      final savedWarnRssi = prefs.getInt('shapnest_warn_rssi_node_${node.id}');
      if (savedWarnRssi != null) {
        node.warningRssiDbm = savedWarnRssi;
      }

      // Load user customized node names
      final savedName = prefs.getString('shapnest_node_name_${node.id}');
      if (savedName != null && savedName.trim().isNotEmpty) {
        node.name = savedName.trim();
      }
    }
  }

  /// Rename a node as per user customization and persist in local storage
  Future<void> renameNode(int nodeId, String newName) async {
    final index = nodes.indexWhere((n) => n.id == nodeId);
    if (index != -1 && newName.trim().isNotEmpty) {
      nodes[index].name = newName.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shapnest_node_name_$nodeId', newName.trim());
      _addLog('# [CONFIG] Node $nodeId renamed to "${newName.trim()}".');
      notifyListeners();
    }
  }

  /// Request all required runtime permissions on Android/iOS (Bluetooth, Location, System Notifications)
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();

    await NotificationService().requestPermissions();

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      _addLog('# [WARN] Some Bluetooth/Location/Notification permissions were denied.');
    }
    return allGranted;
  }

  /// Start BLE scanning
  Future<void> startScan() async {
    if (isSimulating) {
      stopSimulation();
    }

    final permissionsOk = await requestPermissions();
    if (!permissionsOk) {
      statusMessage = 'Permissions required';
      notifyListeners();
      return;
    }

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(_handleScanResults);

      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );

      isScanning = true;
      statusMessage = 'Scanning BLE spectrum...';
      _addLog('# [LOG] Direct BLE Scanner ACTIVE (Low Latency Mode).');
      notifyListeners();
    } catch (e) {
      statusMessage = 'Scan error: $e';
      _addLog('# [ERROR] Failed to start BLE scan: $e');
      notifyListeners();
    }
  }

  /// Stop BLE scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      isScanning = false;
      statusMessage = 'Scan stopped';
      _addLog('# [LOG] BLE Scanner stopped.');
      notifyListeners();
    } catch (e) {
      _addLog('# [ERROR] Stop scan error: $e');
    }
  }

  void toggleScan() {
    if (isScanning) {
      stopScan();
    } else {
      startScan();
    }
  }

  void setTrackingSource(TrackingSource source) {
    trackingSource = source;
    _addLog('# [LOG] Tracking mode switched: ${source == TrackingSource.directPhone ? "Phone Direct Bluetooth" : "Child Wristband"}.');
    notifyListeners();
  }

  /// Process incoming BLE advertisements
  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final parsed = ProtocolParser.parseScanResult(result);
      if (parsed == null) continue;

      final rawRssi = result.rssi;
      final now = DateTime.now();

      // Case 1: Direct Anchor Node Beacon (SHAPNEST_N1..N3)
      if (parsed is ParsedNodeBeacon) {
        final nodeId = parsed.nodeId;
        final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
        if (nodeIndex == -1) continue;

        final node = nodes[nodeIndex];
        node.packetCount++;
        _windowPacketCounters[nodeId] = (_windowPacketCounters[nodeId] ?? 0) + 1;
        node.directRawRssi = rawRssi;
        node.directLastSeen = now;
        node.directState = NodeState.active;
        alertService.setNodeOnline(nodeId, node.name);

        // Adopt over-the-air broadcasted calibration unless user calibrated manually on phone
        // Ignore legacy -59 dBm firmware constant so calibrated -80 dBm remains intact
        if (!node.isUserCalibrated && parsed.calibratedRssi1m != -59) {
          node.calibratedA = parsed.calibratedRssi1m;
          node.pathLossExpN = parsed.pathLossExpN;
        }

        // Update Door Reed Switch State if Node 3
        if (nodeId == 3) {
          final newDoorState = (parsed.sensorState == ShapnestProtocol.doorOpen)
              ? DoorState.open
              : DoorState.closed;
          if (node.doorState != newDoorState) {
            node.doorState = newDoorState;
            _addLog('# [DOOR EVENT] Node 3 Door changed -> ${newDoorState == DoorState.open ? "OPEN [ALERT]" : "CLOSED [SECURE]"}');
          }
        }

        // Update Iron Temperature if Node 2 (ignore zero from unpopulated fallback beacons)
        if (nodeId == 2 && parsed.sensorState > 0) {
          final tempC = parsed.sensorState;
          if (node.ironTemperatureC != tempC) {
            node.ironTemperatureC = tempC;
            final isHot = tempC >= ShapnestProtocol.ironHotThresholdC;
            _addLog('# [IRON EVENT] Node 2 Iron Temp -> $tempC°C ${isHot ? "[HOT ALERT]" : "[SAFE]"}');
          }
        }

        // Feed to Distance Engine
        final distRes = distanceEngine.processRssi(
          nodeId: nodeId,
          rawRssi: rawRssi,
          customA: node.calibratedA,
          customN: node.pathLossExpN,
        );

        node.directDistanceM = distRes.distanceMeters;
        node.directFilteredRssi = distRes.filteredRssi;
        node.directMotionState = distRes.motionState;

        // Check if Calibration Wizard is actively recording this node
        if (activeCalibration != null && activeCalibration!.nodeId == nodeId && !activeCalibration!.isCompleted) {
          activeCalibration!.collectedRssi.add(rawRssi);
          if (activeCalibration!.collectedRssi.length >= activeCalibration!.targetSamples) {
            _finishCalibration();
          }
        }
      }

      // Case 2: Child Wristband Uplink Telemetry (SHAPNEST_WB1)
      else if (parsed is ParsedWristbandTelemetry) {
        final wasOffline = !isWristbandOnline;
        isWristbandOnline = true;
        wristbandSequence = parsed.sequence;
        lastWristbandSeen = now;

        for (final block in parsed.nodes) {
          final nodeIndex = nodes.indexWhere((n) => n.id == block.nodeId);
          if (nodeIndex == -1) continue;

          final node = nodes[nodeIndex];
          node.wbState = block.state;
          node.wbFilteredRssi = block.filteredRssi;
          node.wbLastSeen = now;

          if (block.state == NodeState.offline) {
            node.wbDistanceM = null;
            distanceEngine.clearWbDistance(block.nodeId);
          } else {
            // Consistent distance processing using phone's calibrated Dual-Regime Kalman Distance Engine
            if (block.filteredRssi != ShapnestProtocol.rssiOffline &&
                block.filteredRssi >= -105 &&
                block.filteredRssi <= -15) {
              final distRes = distanceEngine.processRssi(
                nodeId: block.nodeId,
                rawRssi: block.filteredRssi,
                customA: node.wbCalibratedA,
                customN: node.pathLossExpN,
                isWristband: true,
              );
              node.wbDistanceM = distRes.distanceMeters;
            } else if (block.distanceM != null) {
              node.wbDistanceM = distanceEngine.filterWristbandDistance(
                nodeId: block.nodeId,
                incomingDistanceM: block.distanceM!,
              );
            }
          }

          // Safety Alert Engine: evaluates signal strength (Red >= -60 dBm) & active hazard condition
          alertService.processWristbandTelemetry(
            nodeId: node.id,
            nodeName: node.name,
            rssi: node.wbFilteredRssi,
            isHazardActive: node.isHazardConditionFulfilled,
            hazardDescription: node.hazardDescription,
            distanceM: node.wbDistanceM,
            dangerRssiDbm: node.dangerRssiDbm,
            warningRssiDbm: node.warningRssiDbm,
            dangerDistanceM: node.dangerDistanceM,
            warningDistanceM: node.warningDistanceM,
          );

          // Collect wristband calibration samples when Calibration Wizard is running
          if (activeCalibration != null &&
              activeCalibration!.nodeId == block.nodeId &&
              !activeCalibration!.isCompleted &&
              block.filteredRssi != ShapnestProtocol.rssiOffline &&
              block.filteredRssi >= -105 &&
              block.filteredRssi <= -15) {
            activeCalibration!.collectedRssi.add(block.filteredRssi);
            if (activeCalibration!.collectedRssi.length >= activeCalibration!.targetSamples) {
              _finishCalibration();
            }
          }
        }

        if (wasOffline || parsed.sequence % 4 == 0) {
          final d1 = nodes[0].wbFilteredRssi != null ? '${nodes[0].wbFilteredRssi}dBm (${nodes[0].getProximityLabel(nodes[0].wbFilteredRssi)})' : (nodes[0].wbState == NodeState.offline ? 'OFF' : '——');
          final d2 = nodes[1].wbFilteredRssi != null ? '${nodes[1].wbFilteredRssi}dBm (${nodes[1].getProximityLabel(nodes[1].wbFilteredRssi)})' : (nodes[1].wbState == NodeState.offline ? 'OFF' : '——');
          final d3 = nodes[2].wbFilteredRssi != null ? '${nodes[2].wbFilteredRssi}dBm (${nodes[2].getProximityLabel(nodes[2].wbFilteredRssi)})' : (nodes[2].wbState == NodeState.offline ? 'OFF' : '——');
          _addLog('# [WRISTBAND] WB#${parsed.wristbandId} (Seq #${parsed.sequence}) ⟷ Fan: $d1 | Iron: $d2 | Door: $d3');
        }
      }
    }
    notifyListeners();
  }

  /// Check timeouts to transition nodes between ACTIVE -> STALE -> OFFLINE
  void _checkStaleness() {
    final now = DateTime.now();

    // Check Wristband staleness
    if (lastWristbandSeen != null) {
      final wbAge = now.difference(lastWristbandSeen!);
      if (wbAge > ShapnestProtocol.wristbandOfflineTimeout) {
        if (isWristbandOnline) {
          isWristbandOnline = false;
          for (final node in nodes) {
            node.wbState = NodeState.offline;
            node.wbDistanceM = null;
            node.wbFilteredRssi = null;
            distanceEngine.clearWbDistance(node.id);
            alertService.handleNodeOffline(node.id, node.name);
          }
          _addLog('# [WARN] Child Wristband LOST (> ${ShapnestProtocol.wristbandOfflineTimeout.inMilliseconds}ms silence).');
        }
      }
    }

    // Check Direct & Wristband Node staleness
    for (final node in nodes) {
      if (node.directLastSeen != null) {
        final age = now.difference(node.directLastSeen!);
        if (age > ShapnestProtocol.nodeOfflineTimeout) {
          node.directState = NodeState.offline;
          node.directDistanceM = null;
          node.directFilteredRssi = null;
          node.directRawRssi = null;
        } else if (age > ShapnestProtocol.nodeActiveTimeout) {
          node.directState = NodeState.stale;
        }
      }

      if (node.wbLastSeen != null) {
        final age = now.difference(node.wbLastSeen!);
        if (age > ShapnestProtocol.nodeOfflineTimeout) {
          node.wbState = NodeState.offline;
          node.wbDistanceM = null;
          node.wbFilteredRssi = null;
          distanceEngine.clearWbDistance(node.id);
        } else if (age > ShapnestProtocol.nodeActiveTimeout) {
          node.wbState = NodeState.stale;
        }
      }

      // Check offline transition for active tracking source
      final isNodeOffline = (trackingSource == TrackingSource.wristband)
          ? (node.wbState == NodeState.offline)
          : (node.directState == NodeState.offline);

      if (isNodeOffline) {
        alertService.handleNodeOffline(node.id, node.name);
      }

      // Reset sensor state only when both direct link and wristband telemetry are offline
      if (node.directState == NodeState.offline && node.wbState == NodeState.offline) {
        if (node.id == 2) node.ironTemperatureC = null;
        if (node.id == 3) node.doorState = DoorState.unknown;
      }
    }
    notifyListeners();
  }

  // ==========================================================================
  // CALIBRATION WIZARD
  // ==========================================================================
  void startCalibration(int nodeId) {
    activeCalibration = CalibrationState(nodeId: nodeId, targetSamples: 35);
    _addLog('# [CALIBRATION] Started 1-meter calibration wizard for Node $nodeId. Keep phone exactly 1m away.');
    notifyListeners();
  }

  void cancelCalibration() {
    activeCalibration = null;
    notifyListeners();
  }

  Future<void> _finishCalibration() async {
    if (activeCalibration == null) return;

    final samples = List<int>.from(activeCalibration!.collectedRssi)..sort();
    if (samples.isEmpty) return;

    // 20% trimmed mean to reject multipath anomalies during calibration
    final trimCount = (samples.length * 0.2).round();
    final validSamples = samples.sublist(trimCount, samples.length - trimCount);

    double sum = 0;
    for (final s in validSamples) {
      sum += s;
    }
    final calibratedA = (sum / validSamples.length).round();

    final nodeId = activeCalibration!.nodeId;
    activeCalibration!.finalCalibratedA = calibratedA;
    activeCalibration!.isCompleted = true;

    // Save into distance engine & node data for both wristband and direct links
    await distanceEngine.saveWbCalibration(nodeId, calibratedA);
    await distanceEngine.saveCalibration(nodeId, calibratedA);
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].wbCalibratedA = calibratedA;
      nodes[nodeIndex].directCalibratedA = calibratedA;
      nodes[nodeIndex].isUserCalibrated = true;
    }

    _addLog('# [CALIBRATION] Node $nodeId Wristband Calibrated! New 1m RSSI (A): $calibratedA dBm.');
    notifyListeners();
  }

  /// Nudge reference RSSI by +1 or -1 dBm for instantaneous real-world fine-tuning
  Future<void> nudgeCalibration(int nodeId, int deltaDbm) async {
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    final node = nodes[nodeIndex];
    final newA = (node.wbCalibratedA + deltaDbm).clamp(-95, -30);
    node.wbCalibratedA = newA;
    node.directCalibratedA = newA;
    node.isUserCalibrated = true;
    await distanceEngine.saveWbCalibration(nodeId, newA);
    await distanceEngine.saveCalibration(nodeId, newA);
    _addLog('# [CALIBRATION] Node $nodeId 1m A nudged to: $newA dBm');
    notifyListeners();
  }

  Future<void> resetNodeCalibration(int nodeId) async {
    await distanceEngine.resetCalibration(nodeId);
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].calibratedA = ShapnestProtocol.defaultRefRssi1m;
      nodes[nodeIndex].wbCalibratedA = ShapnestProtocol.defaultWbRefRssi1m;
      nodes[nodeIndex].isUserCalibrated = false;
    }
    _addLog('# [CALIBRATION] Node $nodeId calibration reset to default (-77 dBm).');
    notifyListeners();
  }

  Future<void> setNodePathLossN(int nodeId, double n) async {
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].pathLossExpN = n;
    }
    await distanceEngine.saveNodePathLossN(nodeId, n);
    _addLog('# [CALIBRATION] Node $nodeId exponent (n) set to: ${n.toStringAsFixed(1)}');
    notifyListeners();
  }

  Future<void> setNodeDangerDistance(int nodeId, double distM) async {
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].dangerDistanceM = distM;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shapnest_danger_node_$nodeId', distM);
    _addLog('# [SAFETY] Node $nodeId Danger Zone set to < ${distM.toStringAsFixed(2)}m');
    notifyListeners();
  }

  Future<void> setNodeWarningDistance(int nodeId, double distM) async {
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].warningDistanceM = distM;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shapnest_warn_node_$nodeId', distM);
    _addLog('# [SAFETY] Node $nodeId Warning Zone set to < ${distM.toStringAsFixed(2)}m');
    notifyListeners();
  }

  Future<void> setNodeDangerRssi(int nodeId, int rssiDbm) async {
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].dangerRssiDbm = rssiDbm;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_danger_rssi_node_$nodeId', rssiDbm);
    _addLog('# [SAFETY] Node $nodeId Red Danger RSSI threshold set to >= $rssiDbm dBm');
    notifyListeners();
  }

  Future<void> setNodeWarningRssi(int nodeId, int rssiDbm) async {
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].warningRssiDbm = rssiDbm;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_warn_rssi_node_$nodeId', rssiDbm);
    _addLog('# [SAFETY] Node $nodeId Yellow Warning RSSI threshold set to >= $rssiDbm dBm');
    notifyListeners();
  }

  void toggleFanState() {
    final fanIndex = nodes.indexWhere((n) => n.id == 1);
    if (fanIndex != -1) {
      nodes[fanIndex].isFanOn = !nodes[fanIndex].isFanOn;
      _addLog('# [FAN EVENT] Node 1 Fan toggled -> ${nodes[fanIndex].isFanOn ? "ON (Spinning Hazard)" : "OFF (Safe)"}');
      notifyListeners();
    }
  }

  Future<void> setGlobalPathLossN(double n) async {
    await distanceEngine.savePathLossN(n);
    for (final node in nodes) {
      node.pathLossExpN = n;
    }
    _addLog('# [CALIBRATION] Environmental exponent (n) set to: ${n.toStringAsFixed(1)}');
    notifyListeners();
  }

  // ==========================================================================
  // SIMULATION / DEMO MODE (For Testing without physical hardware)
  // ==========================================================================
  void toggleSimulation() {
    if (isSimulating) {
      stopSimulation();
    } else {
      startSimulation();
    }
  }

  void startSimulation() {
    if (isScanning) {
      stopScan();
    }

    isSimulating = true;
    statusMessage = 'DEMO SIMULATION ACTIVE';
    _addLog('# [SIMULATION] Demo Simulation mode STARTED with synthetic walking path.');

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _simAngle += 0.05;
      final now = DateTime.now();

      // Synthetic dynamic distances for each node
      final d1 = 1.20 + 0.80 * sin(_simAngle); // Fan: 0.4m to 2.0m
      final d2 = 2.50 + 1.20 * cos(_simAngle * 0.7); // Iron: 1.3m to 3.7m
      final d3 = 3.80 + 1.50 * sin(_simAngle * 0.5); // Door: 2.3m to 5.3m

      final distances = [d1, d2, d3];

      for (int i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final dist = distances[i];
        node.directDistanceM = dist;
        node.directFilteredRssi = -59 - (10 * 2.2 * log(dist) / ln10).round();
        node.directRawRssi = node.directFilteredRssi! + (Random().nextInt(5) - 2);
        node.directState = NodeState.active;
        node.directLastSeen = now;

        node.wbDistanceM = dist + 0.05 * sin(_simAngle * 2);
        node.wbFilteredRssi = node.directFilteredRssi;
        node.wbState = NodeState.active;
        node.wbLastSeen = now;

        // Dynamic simulated sensor states
        if (node.id == 1) {
          node.isFanOn = (sin(_simAngle * 0.8) > -0.2); // Dynamic fan spinning
        } else if (node.id == 2) {
          // Dynamic realistic iron temp oscillation (30°C to 65°C)
          node.ironTemperatureC = 45 + (18 * sin(_simAngle)).round();
        } else if (node.id == 3) {
          node.doorState = (sin(_simAngle) > 0) ? DoorState.open : DoorState.closed;
        }

        // Process alert engine in simulation
        alertService.processWristbandTelemetry(
          nodeId: node.id,
          nodeName: node.name,
          rssi: node.wbFilteredRssi,
          isHazardActive: node.isHazardConditionFulfilled,
          hazardDescription: node.hazardDescription,
          distanceM: node.wbDistanceM,
          dangerRssiDbm: node.dangerRssiDbm,
          warningRssiDbm: node.warningRssiDbm,
          dangerDistanceM: node.dangerDistanceM,
          warningDistanceM: node.warningDistanceM,
        );
      }

      isWristbandOnline = true;
      wristbandSequence++;
      lastWristbandSeen = now;

      notifyListeners();
    });

    notifyListeners();
  }

  void stopSimulation() {
    isSimulating = false;
    _simulationTimer?.cancel();
    statusMessage = 'Simulation stopped';
    _addLog('# [SIMULATION] Simulation mode STOPPED.');

    for (final node in nodes) {
      node.directState = NodeState.offline;
      node.directDistanceM = null;
      node.wbState = NodeState.offline;
      node.wbDistanceM = null;
      if (node.id == 2) node.ironTemperatureC = null;
      if (node.id == 3) node.doorState = DoorState.unknown;
      distanceEngine.clearWbDistance(node.id);
    }
    isWristbandOnline = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _stalenessTimer?.cancel();
    _packetRateTimer?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }
}
