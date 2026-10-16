import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shapnest_protocol.dart';
import 'kalman_filter.dart';

/// Standard SHAPNEST Proximity Safety Classification
enum ProximityZone {
  criticalDanger, // 0 - 30 cm
  danger,         // 30 - 100 cm
  warning,        // 100 - 200 cm
  safe;           // > 200 cm

  String get displayName {
    switch (this) {
      case ProximityZone.criticalDanger:
        return 'CRITICAL DANGER';
      case ProximityZone.danger:
        return 'DANGER';
      case ProximityZone.warning:
        return 'WARNING';
      case ProximityZone.safe:
        return 'SAFE';
    }
  }

  Color get color {
    switch (this) {
      case ProximityZone.criticalDanger:
        return const Color(0xFFFF1744); // Neon Red
      case ProximityZone.danger:
        return const Color(0xFFFF9100); // Amber/Orange
      case ProximityZone.warning:
        return const Color(0xFFFFEA00); // Yellow
      case ProximityZone.safe:
        return const Color(0xFF00E676); // Mint Green
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
  final Map<int, double> _smoothDistances = {};
  final Map<int, int> _deadbandBreachCounts = {};

  // Velocity limiting (unclamped for rapid physical relocation)
  final Map<int, double> _lastCalculatedDistances = {};
  final Map<int, DateTime> _lastCalculationTimes = {};
  static const double _maxRetreatSpeedMps = 8.0; // Rapid physical separation
  static const double _maxApproachSpeedMps = 8.0; // Rapid physical approach

  // Per-node calibrated 1m reference RSSI (A) for Phone link
  final Map<int, int> _calibratedA = {};

  // Per-node calibrated 1m reference RSSI (A) for Child Wristband Link
  final Map<int, int> _wbCalibratedA = {};

  // Environmental path loss exponent (n) per node (default 1.6 in free space)
  final Map<int, double> _nodePathLossN = {};
  double globalPathLossN = 1.6;

  /// Default free-space path loss exponent (n)
  static double getDefaultFreeSpaceN(int nodeId) {
    return 1.6; // User requested default n = 1.6
  }

  DistanceEngine() {
    for (int i = ShapnestProtocol.nodeIdMin; i <= ShapnestProtocol.nodeIdMax; i++) {
      _kalmanFilters[i] = RssiKalmanFilter();
      _sampleBuffers[i] = [];
      _calibratedA[i] = ShapnestProtocol.defaultRefRssi1m;
      _wbCalibratedA[i] = ShapnestProtocol.defaultWbRefRssi1m;
      _nodePathLossN[i] = getDefaultFreeSpaceN(i);
    }
  }

  /// Initialize and load saved calibration parameters from local storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    globalPathLossN = prefs.getDouble('shapnest_path_loss_n') ?? 1.6;

    // Calibration migration: ensure -77 dBm calibration is applied
    final calMigration = prefs.getString('shapnest_cal_profile_v1');
    final needsProfileReset = calMigration != 'cal_77dbm_v1';

    for (int i = ShapnestProtocol.nodeIdMin; i <= ShapnestProtocol.nodeIdMax; i++) {
      if (needsProfileReset) {
        _calibratedA[i] = ShapnestProtocol.defaultRefRssi1m; // -77 dBm
        _wbCalibratedA[i] = ShapnestProtocol.defaultWbRefRssi1m; // -77 dBm
        await prefs.setInt('shapnest_cal_a_node_$i', ShapnestProtocol.defaultRefRssi1m);
        await prefs.setInt('shapnest_cal_wb_a_node_$i', ShapnestProtocol.defaultWbRefRssi1m);
      } else {
        final savedA = prefs.getInt('shapnest_cal_a_node_$i');
        if (savedA != null && savedA >= -95 && savedA <= -30) {
          _calibratedA[i] = savedA;
        } else {
          _calibratedA[i] = ShapnestProtocol.defaultRefRssi1m;
          await prefs.setInt('shapnest_cal_a_node_$i', ShapnestProtocol.defaultRefRssi1m);
        }
        final savedWbA = prefs.getInt('shapnest_cal_wb_a_node_$i');
        if (savedWbA != null && savedWbA >= -95 && savedWbA <= -30) {
          _wbCalibratedA[i] = savedWbA;
        } else {
          _wbCalibratedA[i] = ShapnestProtocol.defaultWbRefRssi1m;
          await prefs.setInt('shapnest_cal_wb_a_node_$i', ShapnestProtocol.defaultWbRefRssi1m);
        }
      }
      final savedN = prefs.getDouble('shapnest_path_loss_n_node_$i');
      if (savedN != null) {
        _nodePathLossN[i] = savedN;
      }
    }
    if (needsProfileReset) {
      await prefs.setString('shapnest_cal_profile_v1', 'cal_77dbm_v1');
    }
  }

  /// Save calibration for a specific node (Phone link)
  Future<void> saveCalibration(int nodeId, int referenceRssi1m) async {
    _calibratedA[nodeId] = referenceRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_cal_a_node_$nodeId', referenceRssi1m);
  }

  /// Save calibration for Child Wristband link
  Future<void> saveWbCalibration(int nodeId, int referenceRssi1m) async {
    _wbCalibratedA[nodeId] = referenceRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shapnest_cal_wb_a_node_$nodeId', referenceRssi1m);
  }

  /// Save per-node path loss exponent
  Future<void> saveNodePathLossN(int nodeId, double n) async {
    _nodePathLossN[nodeId] = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shapnest_path_loss_n_node_$nodeId', n);
  }

  /// Save global path loss exponent
  Future<void> savePathLossN(double n) async {
    globalPathLossN = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shapnest_path_loss_n', n);
  }

  double getNodePathLossN(int nodeId) {
    return _nodePathLossN[nodeId] ?? globalPathLossN;
  }

  /// Reset calibration back to hardware defaults
  Future<void> resetCalibration(int nodeId) async {
    _calibratedA[nodeId] = ShapnestProtocol.defaultRefRssi1m;
    _wbCalibratedA[nodeId] = ShapnestProtocol.defaultWbRefRssi1m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shapnest_cal_a_node_$nodeId');
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
    bool isWristband = false,
  }) {
    final filterKey = isWristband ? (nodeId + 100) : nodeId;

    // Physical sanity gate
    if (rawRssi < -100 || rawRssi > -15) {
      final lastDist = _displayedDistances[filterKey] ?? 1.0;
      return DistanceResult(
        distanceMeters: lastDist,
        filteredRssi: rawRssi,
        rawRssi: rawRssi,
        motionState: FilterMotionState.stationary,
        isClamped: false,
      );
    }

    final kalman = _kalmanFilters.putIfAbsent(filterKey, () => RssiKalmanFilter());

    // 1. Maintain compact sliding window buffer for impulse rejection
    final buffer = _sampleBuffers.putIfAbsent(filterKey, () => []);

    // Fast-Attack / Step Change: Flush on meaningful step change (>= 3.8 dBm) so physical motion flushes stale samples
    if (kalman.isInitialized && (rawRssi - kalman.currentRssi).abs() >= 3.8) {
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

    // 4. Log-Distance Path Loss Model
    // d = 10 ^ ((A - RSSI) / (10 * n))
    final fallbackA = isWristband
        ? (_wbCalibratedA[nodeId] ?? ShapnestProtocol.defaultWbRefRssi1m)
        : (_calibratedA[nodeId] ?? ShapnestProtocol.defaultRefRssi1m);
    final refA = (customA ?? fallbackA).toDouble();
    final expN = customN ?? globalPathLossN;

    final exponent = (refA - filteredRssiDouble) / (10.0 * expN);
    double calculatedDistance = pow(10.0, exponent).toDouble();

    // 5. Asymmetric Velocity Limiting
    final now = DateTime.now();
    final lastTime = _lastCalculationTimes[filterKey];
    final lastDist = _lastCalculatedDistances[filterKey];

    if (lastTime != null && lastDist != null && motionState == FilterMotionState.stationary) {
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

    _lastCalculationTimes[filterKey] = now;
    _lastCalculatedDistances[filterKey] = calculatedDistance;

    // 6. Operational Boundary Clamping [0.15m .. 8.00m]
    bool isClamped = false;
    if (calculatedDistance < ShapnestProtocol.distanceMinM) {
      calculatedDistance = ShapnestProtocol.distanceMinM;
      isClamped = true;
    } else if (calculatedDistance > ShapnestProtocol.distanceMaxM) {
      calculatedDistance = ShapnestProtocol.distanceMaxM;
      isClamped = true;
    }

    // 7. Ultra-Stable Hysteresis Dead-Band with Persistence & Smooth Motion Tracking
    double lockedDist = _displayedDistances[filterKey] ?? calculatedDistance;
    double smoothDist = _smoothDistances[filterKey] ?? lockedDist;
    int breachCount = _deadbandBreachCounts[filterKey] ?? 0;

    // Dynamic dead-band scales with distance zone
    double deadband;
    if (lockedDist <= 0.50) {
      deadband = 0.04; // 4 cm in critical danger
    } else if (lockedDist <= 1.20) {
      deadband = 0.08; // 8 cm in danger zone
    } else if (lockedDist <= 2.50) {
      deadband = 0.16; // 16 cm in warning zone
    } else {
      deadband = min(0.35, 0.08 * lockedDist); // up to 35 cm in safe zone
    }

    final diffFromLocked = (calculatedDistance - lockedDist).abs();

    if (motionState == FilterMotionState.stationary) {
      if (diffFromLocked >= deadband) {
        breachCount++;
        if (breachCount >= 2 || diffFromLocked >= 1.8 * deadband) {
          lockedDist = calculatedDistance;
          breachCount = 0;
        }
      } else {
        breachCount = 0;
      }
      smoothDist = lockedDist;
    } else {
      // In moving or fastAttack mode, smoothly glide to new position
      breachCount = 0;
      final alpha = (motionState == FilterMotionState.fastAttack) ? 0.80 : 0.60;
      smoothDist = alpha * calculatedDistance + (1.0 - alpha) * smoothDist;
      lockedDist = smoothDist;
    }

    _displayedDistances[filterKey] = lockedDist;
    _smoothDistances[filterKey] = smoothDist;
    _deadbandBreachCounts[filterKey] = breachCount;

    return DistanceResult(
      distanceMeters: smoothDist,
      filteredRssi: filteredRssiInt,
      rawRssi: rawRssi,
      motionState: motionState,
      isClamped: isClamped,
    );
  }

  // Displayed wristband distance memory & state
  final Map<int, double> _displayedWbDistances = {};
  final Map<int, double> _smoothWbDistances = {};
  final Map<int, int> _wbBreachCounts = {};

  /// Stabilize wristband-reported distance with tight 3cm anti-flicker deadband.
  /// The wristband on-chip firmware ALREADY applies the calibrated Dual-Regime Kalman filter,
  /// so the mobile app must not add a heavy secondary deadband that suppresses real movement!
  double filterWristbandDistance({
    required int nodeId,
    required double incomingDistanceM,
  }) {
    final locked = _displayedWbDistances[nodeId];
    if (locked == null) {
      _displayedWbDistances[nodeId] = incomingDistanceM;
      _smoothWbDistances[nodeId] = incomingDistanceM;
      _wbBreachCounts[nodeId] = 0;
      return incomingDistanceM;
    }

    final diff = (incomingDistanceM - locked).abs();

    // Microscopic jitter of <= 3 cm is absorbed to prevent stationary display numeric flicker.
    // Genuine physical movement (> 3 cm) updates instantly without secondary lag!
    if (diff <= 0.03) {
      return locked;
    }

    _displayedWbDistances[nodeId] = incomingDistanceM;
    _smoothWbDistances[nodeId] = incomingDistanceM;
    _wbBreachCounts[nodeId] = 0;
    return incomingDistanceM;
  }

  void clearWbDistance(int nodeId) {
    _displayedWbDistances.remove(nodeId);
    _smoothWbDistances.remove(nodeId);
    _wbBreachCounts.remove(nodeId);

    final wbKey = nodeId + 100;
    _kalmanFilters[wbKey]?.reset();
    _sampleBuffers[wbKey]?.clear();
    _displayedDistances.remove(wbKey);
    _smoothDistances.remove(wbKey);
    _deadbandBreachCounts.remove(wbKey);
    _lastCalculatedDistances.remove(wbKey);
    _lastCalculationTimes.remove(wbKey);
  }

  void resetFilter(int nodeId) {
    _kalmanFilters[nodeId]?.reset();
    _sampleBuffers[nodeId]?.clear();
    _displayedDistances.remove(nodeId);
    _smoothDistances.remove(nodeId);
    _deadbandBreachCounts.remove(nodeId);
    _displayedWbDistances.remove(nodeId);
    _smoothWbDistances.remove(nodeId);
    _wbBreachCounts.remove(nodeId);
    _lastCalculatedDistances.remove(nodeId);
    _lastCalculationTimes.remove(nodeId);

    final wbKey = nodeId + 100;
    _kalmanFilters[wbKey]?.reset();
    _sampleBuffers[wbKey]?.clear();
    _displayedDistances.remove(wbKey);
    _smoothDistances.remove(wbKey);
    _deadbandBreachCounts.remove(wbKey);
    _lastCalculatedDistances.remove(wbKey);
    _lastCalculationTimes.remove(wbKey);
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
  ProximityZone get zone {
    if (distanceMeters <= 0.30) {
      return ProximityZone.criticalDanger;
    } else if (distanceMeters <= 1.00) {
      return ProximityZone.danger;
    } else if (distanceMeters <= 2.00) {
      return ProximityZone.warning;
    } else {
      return ProximityZone.safe;
    }
  }
}
