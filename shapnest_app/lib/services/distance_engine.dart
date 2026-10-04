import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shapnest_protocol.dart';
import 'kalman_filter.dart';

class DistanceEngine {
  // Per-node Kalman filters
  final Map<int, RssiKalmanFilter> _kalmanFilters = {};

  // Per-node rolling sample buffers for median/IQR pre-filtering
  final Map<int, List<int>> _sampleBuffers = {};
  static const int _sampleBufferSize = 8;

  // Velocity limiting
  final Map<int, double> _lastCalculatedDistances = {};
  final Map<int, DateTime> _lastCalculationTimes = {};
  static const double _maxPhysicalSpeedMps = 2.0; // 2 meters per second

  // Per-node calibrated 1m reference RSSI (A)
  final Map<int, int> _calibratedA = {};

  // Environmental path loss exponent (n)
  double globalPathLossN = 2.2;

  DistanceEngine() {
    for (int i = ShapnestProtocol.nodeIdMin; i <= ShapnestProtocol.nodeIdMax; i++) {
      _kalmanFilters[i] = RssiKalmanFilter();
      _sampleBuffers[i] = [];
      _calibratedA[i] = ShapnestProtocol.defaultRefRssi1m;
    }
  }

  /// Initialize and load saved calibration parameters from local storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    globalPathLossN = prefs.getDouble('shapnest_path_loss_n') ?? 2.2;

    for (int i = ShapnestProtocol.nodeIdMin; i <= ShapnestProtocol.nodeIdMax; i++) {
      final savedA = prefs.getInt('shapnest_cal_a_node_$i');
      if (savedA != null) {
        _calibratedA[i] = savedA;
      }
    }
  }

  /// Save calibration for a specific node
  Future<void> saveCalibration(int nodeId, int referenceRssi1m) async {
    _calibratedA[nodeId] = referenceRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_cal_a_node_$nodeId', referenceRssi1m);
  }

  /// Save global path loss exponent
  Future<void> savePathLossN(double n) async {
    globalPathLossN = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shapnest_path_loss_n', n);
  }

  /// Reset calibration back to hardware defaults
  Future<void> resetCalibration(int nodeId) async {
    _calibratedA[nodeId] = ShapnestProtocol.defaultRefRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shapnest_cal_a_node_$nodeId');
  }

  int getCalibratedA(int nodeId) {
    return _calibratedA[nodeId] ?? ShapnestProtocol.defaultRefRssi1m;
  }

  /// Compute distance from raw incoming BLE RSSI using the full filtering pipeline:
  /// 1. Outlier Rejection & Trimmed Median Pre-Filter
  /// 2. 1D Adaptive Kalman Filter
  /// 3. Calibrated Log-Distance Path Loss Model
  /// 4. Velocity Slew-Rate Limiting
  /// 5. Operational Boundary Clamping [0.15m .. 8.00m]
  DistanceResult processRssi({
    required int nodeId,
    required int rawRssi,
    int? customA,
    double? customN,
  }) {
    // Physical sanity gate
    if (rawRssi < -100 || rawRssi > -15) {
      final lastDist = _lastCalculatedDistances[nodeId] ?? 1.0;
      return DistanceResult(
        distanceMeters: lastDist,
        filteredRssi: rawRssi,
        rawRssi: rawRssi,
        isClamped: false,
      );
    }

    // 1. Maintain sliding window buffer
    final buffer = _sampleBuffers.putIfAbsent(nodeId, () => []);
    buffer.add(rawRssi);
    if (buffer.length > _sampleBufferSize) {
      buffer.removeAt(0);
    }

    // 2. Pre-filter: compute median from window
    final sorted = List<int>.from(buffer)..sort();
    final medianRssi = sorted[sorted.length ~/ 2].toDouble();

    // 3. Kalman Filter update
    final kalman = _kalmanFilters.putIfAbsent(nodeId, () => RssiKalmanFilter());
    final filteredRssiDouble = kalman.filter(medianRssi);
    final filteredRssiInt = filteredRssiDouble.round();

    // 4. Log-Distance Path Loss Model
    // d = 10 ^ ((A - RSSI) / (10 * n))
    final refA = (customA ?? _calibratedA[nodeId] ?? ShapnestProtocol.defaultRefRssi1m).toDouble();
    final expN = customN ?? globalPathLossN;

    final exponent = (refA - filteredRssiDouble) / (10.0 * expN);
    double calculatedDistance = pow(10.0, exponent).toDouble();

    // 5. Velocity Slew-Rate Limiting (prevent unphysical teleporting)
    final now = DateTime.now();
    final lastTime = _lastCalculationTimes[nodeId];
    final lastDist = _lastCalculatedDistances[nodeId];

    if (lastTime != null && lastDist != null) {
      final dtSec = now.difference(lastTime).inMilliseconds / 1000.0;
      if (dtSec > 0.05 && dtSec < 2.0) {
        final maxDelta = _maxPhysicalSpeedMps * dtSec;
        final delta = calculatedDistance - lastDist;
        if (delta.abs() > maxDelta) {
          calculatedDistance = lastDist + (delta.sign * maxDelta);
        }
      }
    }

    _lastCalculationTimes[nodeId] = now;

    // 6. Operational Boundary Clamping
    bool isClamped = false;
    if (calculatedDistance < ShapnestProtocol.distanceMinM) {
      calculatedDistance = ShapnestProtocol.distanceMinM;
      isClamped = true;
    } else if (calculatedDistance > ShapnestProtocol.distanceMaxM) {
      calculatedDistance = ShapnestProtocol.distanceMaxM;
      isClamped = true;
    }

    _lastCalculatedDistances[nodeId] = calculatedDistance;

    return DistanceResult(
      distanceMeters: calculatedDistance,
      filteredRssi: filteredRssiInt,
      rawRssi: rawRssi,
      isClamped: isClamped,
    );
  }

  void resetFilter(int nodeId) {
    _kalmanFilters[nodeId]?.reset();
    _sampleBuffers[nodeId]?.clear();
    _lastCalculatedDistances.remove(nodeId);
    _lastCalculationTimes.remove(nodeId);
  }
}

class DistanceResult {
  final double distanceMeters;
  final int filteredRssi;
  final int rawRssi;
  final bool isClamped;

  DistanceResult({
    required this.distanceMeters,
    required this.filteredRssi,
    required this.rawRssi,
    required this.isClamped,
  });

  int get distanceCm => (distanceMeters * 100).round();
}
