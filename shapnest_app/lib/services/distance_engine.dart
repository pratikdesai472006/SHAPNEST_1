import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shapnest_protocol.dart';
import 'kalman_filter.dart';

/// Standard SHAPNEST Proximity Safety Classification
enum ProximityZone {
  danger,  // < 30 cm (Dangerous Zone - Red)
  warning, // 30 cm - 67 cm (Yellow Zone)
  safe;    // > 67 cm (Safe Zone - Green)

  String get displayName {
    switch (this) {
      case ProximityZone.danger:
        return 'DANGEROUS ZONE';
      case ProximityZone.warning:
        return 'YELLOW ZONE';
      case ProximityZone.safe:
        return 'SAFE ZONE';
    }
  }

  Color get color {
    switch (this) {
      case ProximityZone.danger:
        return const Color(0xFFFF1744); // Neon Red (< 30cm)
      case ProximityZone.warning:
        return const Color(0xFFFFEA00); // Yellow (30cm - 67cm)
      case ProximityZone.safe:
        return const Color(0xFF00E676); // Mint Green (> 67cm)
    }
  }
}

class DistanceEngine {
  // Per-node Dual-Regime Kalman filters
  final Map<int, RssiKalmanFilter> _kalmanFilters = {};

  // Per-node rolling sample buffers for median impulse rejection
  // Kept tight (3 samples ~ 200-300ms) to eliminate latency while suppressing impulse spikes
  final Map<int, List<int>> _sampleBuffers = {};
  static const int _sampleBufferSize = 3;

  // Displayed distance memory for Hysteresis Dead-Band
  final Map<int, double> _displayedDistances = {};

  // Velocity limiting
  final Map<int, double> _lastCalculatedDistances = {};
  final Map<int, DateTime> _lastCalculationTimes = {};
  static const double _maxRetreatSpeedMps = 3.5; // Walking away
  static const double _maxApproachSpeedMps = 4.5; // Fast step toward hazard

  // Per-node calibrated 1m reference RSSI (A) for Direct Phone Link
  final Map<int, int> _calibratedA = {};

  // Per-node calibrated 1m reference RSSI (A) for Child Wristband Link
  final Map<int, int> _wbCalibratedA = {};

  // Environmental path loss exponent (n)
  double globalPathLossN = 2.2;

  DistanceEngine() {
    for (int i = ShapnestProtocol.nodeIdMin; i <= ShapnestProtocol.nodeIdMax; i++) {
      _kalmanFilters[i] = RssiKalmanFilter();
      _sampleBuffers[i] = [];
      _calibratedA[i] = ShapnestProtocol.defaultRefRssi1m;
      _wbCalibratedA[i] = ShapnestProtocol.defaultWbRefRssi1m;
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
      final savedWbA = prefs.getInt('shapnest_cal_wb_a_node_$i');
      if (savedWbA != null) {
        _wbCalibratedA[i] = savedWbA;
      }
    }
  }

  /// Save calibration for a specific node (Phone)
  Future<void> saveCalibration(int nodeId, int referenceRssi1m) async {
    _calibratedA[nodeId] = referenceRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_cal_a_node_$nodeId', referenceRssi1m);
  }

  /// Save calibration for a specific node (Wristband)
  Future<void> saveWbCalibration(int nodeId, int referenceRssi1m) async {
    _wbCalibratedA[nodeId] = referenceRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_cal_wb_a_node_$nodeId', referenceRssi1m);
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

  /// Reset wristband calibration back to hardware defaults
  Future<void> resetWbCalibration(int nodeId) async {
    _wbCalibratedA[nodeId] = ShapnestProtocol.defaultWbRefRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shapnest_cal_wb_a_node_$nodeId');
  }

  int getCalibratedA(int nodeId) {
    return _calibratedA[nodeId] ?? ShapnestProtocol.defaultRefRssi1m;
  }

  int getWbCalibratedA(int nodeId) {
    return _wbCalibratedA[nodeId] ?? ShapnestProtocol.defaultWbRefRssi1m;
  }

  RssiKalmanFilter? getFilter(int nodeId) => _kalmanFilters[nodeId];

  /// Compute distance from raw incoming BLE RSSI using the adaptive pipeline:
  /// 1. Compact 3-sample median impulse gate (100-200ms latency, eliminates single-packet nulls)
  /// 2. Dual-Regime 1D Adaptive Kalman Filter (Stationary strong smoothing vs Fast Attack rapid snap)
  /// 3. Calibrated Log-Distance Path Loss Model
  /// 4. Asymmetric Velocity Limiting (fast approach permitted)
  /// 5. Small-Jitter Hysteresis Dead-Band (eliminates visual numeric wobble when still)
  DistanceResult processRssi({
    required int nodeId,
    required int rawRssi,
    int? customA,
    double? customN,
  }) {
    // Physical sanity gate
    if (rawRssi < -100 || rawRssi > -15) {
      final lastDist = _displayedDistances[nodeId] ?? 1.0;
      return DistanceResult(
        distanceMeters: lastDist,
        filteredRssi: rawRssi,
        rawRssi: rawRssi,
        motionState: FilterMotionState.stationary,
        isClamped: false,
      );
    }

    final kalman = _kalmanFilters.putIfAbsent(nodeId, () => RssiKalmanFilter());

    // 1. Maintain compact sliding window buffer for impulse rejection
    final buffer = _sampleBuffers.putIfAbsent(nodeId, () => []);

    // Fast-Attack Priority: If signal jumps significantly stronger (approaching hazard),
    // immediately clear stale far samples so the median filter never delays life-safety proximity detection!
    if (kalman.isInitialized && (rawRssi - kalman.currentRssi) >= 3.5) {
      buffer.clear();
    }

    buffer.add(rawRssi);
    if (buffer.length > _sampleBufferSize) {
      buffer.removeAt(0);
    }

    // 2. Compute median from compact window
    final sorted = List<int>.from(buffer)..sort();
    final medianRssi = sorted[sorted.length ~/ 2].toDouble();

    // 3. Adaptive Dual-Regime Kalman Filter update
    final filteredRssiDouble = kalman.filter(medianRssi);
    final filteredRssiInt = filteredRssiDouble.round();
    final motionState = kalman.motionState;

    // 4. Log-Distance Path Loss Model (Continuous Dual-Zone Transition)
    final refA = (customA ?? _calibratedA[nodeId] ?? ShapnestProtocol.defaultRefRssi1m).toDouble();
    final expN = customN ?? globalPathLossN;

    // Near-field (<1m, RSSI > refA) uses lower attenuation (n ~ 1.8) since direct LOS dominates;
    // Far-field (>=1m, RSSI <= refA) uses indoor clutter exponent (n ~ 2.2 - 2.4).
    final effectiveN = filteredRssiDouble > refA
        ? (expN * 0.85).clamp(1.6, 2.0)
        : expN;

    final exponent = (refA - filteredRssiDouble) / (10.0 * effectiveN);
    double calculatedDistance = pow(10.0, exponent).toDouble();

    // 5. Asymmetric Velocity Limiting
    final now = DateTime.now();
    final lastTime = _lastCalculationTimes[nodeId];
    final lastDist = _lastCalculatedDistances[nodeId];

    if (lastTime != null && lastDist != null && motionState != FilterMotionState.fastAttack) {
      final dtSec = now.difference(lastTime).inMilliseconds / 1000.0;
      if (dtSec > 0.05 && dtSec < 2.0) {
        final isApproaching = calculatedDistance < lastDist;
        final maxSpeed = isApproaching ? _maxApproachSpeedMps : _maxRetreatSpeedMps;
        final maxDelta = maxSpeed * dtSec;
        final delta = calculatedDistance - lastDist;
        if (delta.abs() > maxDelta) {
          calculatedDistance = lastDist + (delta.sign * maxDelta);
        }
      }
    }

    _lastCalculationTimes[nodeId] = now;
    _lastCalculatedDistances[nodeId] = calculatedDistance;

    // 6. Operational Boundary Clamping [0.15m .. 8.00m]
    bool isClamped = false;
    if (calculatedDistance < ShapnestProtocol.distanceMinM) {
      calculatedDistance = ShapnestProtocol.distanceMinM;
      isClamped = true;
    } else if (calculatedDistance > ShapnestProtocol.distanceMaxM) {
      calculatedDistance = ShapnestProtocol.distanceMaxM;
      isClamped = true;
    }

    // 7. Small-Jitter Hysteresis Dead-Band
    // Prevents microscopic numeric display flickering when the target is physically stationary,
    // while allowing real movements to propagate instantly.
    double displayedDist = _displayedDistances[nodeId] ?? calculatedDistance;

    if (motionState == FilterMotionState.stationary) {
      // Dynamic dead-band scales with distance zone
      double deadband;
      if (displayedDist <= 0.30) {
        deadband = 0.02; // 2 cm in critical danger (high precision)
      } else if (displayedDist <= 1.00) {
        deadband = 0.03; // 3 cm in danger zone
      } else if (displayedDist <= 2.00) {
        deadband = 0.05; // 5 cm in warning zone
      } else {
        deadband = min(0.10, 0.04 * displayedDist); // 6-10 cm in safe zone
      }

      if ((calculatedDistance - displayedDist).abs() >= deadband) {
        displayedDist = calculatedDistance;
      }
    } else {
      // In moving or fastAttack mode, update immediately without dead-band suppression
      displayedDist = calculatedDistance;
    }

    _displayedDistances[nodeId] = displayedDist;

    return DistanceResult(
      distanceMeters: displayedDist,
      filteredRssi: filteredRssiInt,
      rawRssi: rawRssi,
      motionState: motionState,
      isClamped: isClamped,
    );
  }

  void resetFilter(int nodeId) {
    _kalmanFilters[nodeId]?.reset();
    _sampleBuffers[nodeId]?.clear();
    _displayedDistances.remove(nodeId);
    _lastCalculatedDistances.remove(nodeId);
    _lastCalculationTimes.remove(nodeId);
  }
}

class DistanceResult {
  final double distanceMeters;
  final int filteredRssi;
  final int rawRssi;
  final FilterMotionState motionState;
  final bool isClamped;

  DistanceResult({
    required this.distanceMeters,
    required this.filteredRssi,
    required this.rawRssi,
    required this.motionState,
    required this.isClamped,
  });

  int get distanceCm => (distanceMeters * 100).round();

  /// Proximity Safety Zone Classification
  /// - Below 30 cm: Dangerous Zone (Red)
  /// - 30 cm to 67 cm: Yellow Zone (Yellow/Warning)
  /// - Further than 67 cm: Safe Zone (Green)
  ProximityZone get zone {
    if (distanceMeters < 0.30) {
      return ProximityZone.danger;
    } else if (distanceMeters <= 0.67) {
      return ProximityZone.warning;
    } else {
      return ProximityZone.safe;
    }
  }
}
