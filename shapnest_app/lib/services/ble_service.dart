import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/node_data.dart';
import '../models/shapnest_protocol.dart';
import 'distance_engine.dart';
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

  // Active tracking display mode
  TrackingSource trackingSource = TrackingSource.directPhone;

  // Wristband state
  bool isWristbandOnline = false;
  int wristbandSequence = 0;
  DateTime? lastWristbandSeen;

  // Scanner status
  bool isScanning = false;
  bool isBluetoothAvailable = false;
  String statusMessage = 'Ready';

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

    // Start periodic watchdog timer for staleness & offline detection (1 Hz)
    _stalenessTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
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

    // Load saved calibration parameters into node models
    for (final node in nodes) {
      node.calibratedA = distanceEngine.getCalibratedA(node.id);
      node.pathLossExpN = distanceEngine.globalPathLossN;
    }
  }

  /// Request all required runtime permissions on Android
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      _addLog('# [WARN] Some Bluetooth/Location permissions were denied.');
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
    _addLog('# [LOG] Switched tracking source to: ${source == TrackingSource.directPhone ? "Direct Phone" : "Child Wristband"}');
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
          node.wbDistanceM = block.distanceM;
          node.wbFilteredRssi = block.filteredRssi;
          node.wbLastSeen = now;
        }

        if (wasOffline || parsed.sequence % 4 == 0) {
          final d1 = nodes[0].wbDistanceM != null ? '${nodes[0].wbDistanceM!.toStringAsFixed(2)}m' : (nodes[0].wbState == NodeState.offline ? 'OFF' : '——');
          final d2 = nodes[1].wbDistanceM != null ? '${nodes[1].wbDistanceM!.toStringAsFixed(2)}m' : (nodes[1].wbState == NodeState.offline ? 'OFF' : '——');
          final d3 = nodes[2].wbDistanceM != null ? '${nodes[2].wbDistanceM!.toStringAsFixed(2)}m' : (nodes[2].wbState == NodeState.offline ? 'OFF' : '——');
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
          _addLog('# [WARN] Child Wristband LOST (> 3500ms silence).');
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
        } else if (age > ShapnestProtocol.nodeActiveTimeout) {
          node.directState = NodeState.stale;
        }
      }

      if (node.wbLastSeen != null) {
        final age = now.difference(node.wbLastSeen!);
        if (age > ShapnestProtocol.nodeOfflineTimeout) {
          node.wbState = NodeState.offline;
          node.wbDistanceM = null;
        } else if (age > ShapnestProtocol.nodeActiveTimeout) {
          node.wbState = NodeState.stale;
        }
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

    // Save into distance engine & node data
    await distanceEngine.saveCalibration(nodeId, calibratedA);
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].calibratedA = calibratedA;
      nodes[nodeIndex].isUserCalibrated = true;
    }

    _addLog('# [CALIBRATION] Node $nodeId Calibrated! New 1m RSSI (A): $calibratedA dBm.');
    notifyListeners();
  }

  Future<void> resetNodeCalibration(int nodeId) async {
    await distanceEngine.resetCalibration(nodeId);
    final nodeIndex = nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex != -1) {
      nodes[nodeIndex].calibratedA = ShapnestProtocol.defaultRefRssi1m;
      nodes[nodeIndex].isUserCalibrated = false;
    }
    _addLog('# [CALIBRATION] Node $nodeId calibration reset to default (-59 dBm).');
    notifyListeners();
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
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
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
