/// Movement regime of the target node or receiver.
enum FilterMotionState {
  stationary,
  moving,
  fastAttack, // Rapidly approaching (into danger proximity)
}

/// Dual-Regime 1D Adaptive Kalman Filter optimized for 2.4 GHz BLE RSSI.
/// 
/// Solves the fundamental trade-off:
/// - In STILL/STATIONARY state: Aggressively suppresses multipath RF flutter (K ~ 0.02 - 0.04).
/// - In MOTION state: Lowers measurement resistance, tracking movement instantaneously (K ~ 0.50).
/// - In FAST-ATTACK state (approaching danger): Instantly snaps to closer distance (K ~ 0.80).
class RssiKalmanFilter {
  double _x = 0.0; // Estimated state (Filtered RSSI)
  double _p = 4.0; // Estimation error covariance

  // Stationary Tuning Parameters: suppresses multipath RF flutter without infinite lag (K ~ 0.02)
  static const double _qStationary = 0.005;
  static const double _rStationary = 14.0;

  // Moving Tuning Parameters: responsive tracking of physical motion (K ~ 0.45)
  static const double _qMoving = 0.50;
  static const double _rMoving = 1.00;

  // Fast Attack: Rapid approach into danger or initial acquisition (K ~ 0.85)
  static const double _qFastAttack = 1.40;
  static const double _rFastAttack = 0.30;

  // Thresholds (dBm)
  static const double _stationaryDeltaThresh = 2.2; // Typical indoor noise envelope (<= 2.2 dBm)
  static const double _movementDeltaThresh   = 3.0; // Sustained physical movement
  static const double _fastAttackDeltaThresh = 5.0; // Rapid approach into danger zone

  bool _isInitialized = false;
  int _warmupSamples = 5;
  FilterMotionState _motionState = FilterMotionState.stationary;
  int _consecutiveStationarySamples = 0;
  int _consecutiveMovingSamples = 0;
  double _lastDelta = 0.0;
  final List<double> _recentDeltas = [];

  RssiKalmanFilter();

  bool get isInitialized => _isInitialized;
  double get currentRssi => _x;
  FilterMotionState get motionState => _motionState;

  /// Update the filter with a fresh raw RSSI measurement
  double filter(double rawRssi) {
    if (!_isInitialized) {
      _x = rawRssi;
      _p = 4.0;
      _isInitialized = true;
      _warmupSamples = 5;
      _motionState = FilterMotionState.fastAttack;
      _consecutiveStationarySamples = 0;
      _consecutiveMovingSamples = 2;
      _lastDelta = 0.0;
      return _x;
    }

    final double delta = rawRssi - _x;
    final double absDelta = delta.abs();

    // 1. Maintain sliding delta history (last 3 samples) for trend analysis
    _recentDeltas.add(delta);
    if (_recentDeltas.length > 3) {
      _recentDeltas.removeAt(0);
    }

    // 2. Trend & Motion Classification
    final bool isConsistentDirection = _recentDeltas.length >= 2 &&
        (_recentDeltas.every((d) => d > 1.5) ||
        _recentDeltas.every((d) => d < -1.5));

    // Rapid warm-up phase (first 5 samples after node detection)
    if (_warmupSamples > 0) {
      _warmupSamples--;
      _motionState = FilterMotionState.fastAttack;
      _consecutiveStationarySamples = 0;
      _consecutiveMovingSamples = 2;
    }
    // Fast Attack: Rapid approach towards beacon (getting closer to danger) or massive step (>= 8.0)
    else if ((delta >= _fastAttackDeltaThresh && (_x < -64.0 || rawRssi > -60.0)) || absDelta >= 8.0) {
      _motionState = FilterMotionState.fastAttack;
      _consecutiveStationarySamples = 0;
      _consecutiveMovingSamples = 3;
    }
    // Normal Movement: Meaningful deviation with consistent direction or substantial step
    else if (absDelta >= _movementDeltaThresh) {
      final bool sameDirection = (delta * _lastDelta > 0.0);
      if (sameDirection || isConsistentDirection || absDelta >= 5.0) {
        _consecutiveMovingSamples++;
        if (_consecutiveMovingSamples >= 2 || absDelta >= 6.0) {
          _motionState = FilterMotionState.moving;
          _consecutiveStationarySamples = 0;
        }
      }
    }
    // Stationary: Delta is within typical stationary RF noise envelope (<= 2.2 dBm)
    else if (absDelta <= _stationaryDeltaThresh) {
      _consecutiveStationarySamples++;
      if (_consecutiveStationarySamples >= 2) {
        _motionState = FilterMotionState.stationary;
        _consecutiveMovingSamples = 0;
      }
    }

    _lastDelta = delta;

    // 3. Select Covariances Based on Adaptive Motion State
    double q;
    double r;

    switch (_motionState) {
      case FilterMotionState.fastAttack:
        q = _qFastAttack;
        r = _rFastAttack;
        break;
      case FilterMotionState.moving:
        q = _qMoving;
        r = _rMoving;
        break;
      case FilterMotionState.stationary:
        q = _qStationary;
        r = _rStationary;
        break;
    }

    // 4. Time Update (Predict)
    final pPred = _p + q;

    // 5. Measurement Update (Correct)
    final k = pPred / (pPred + r);
    _x = _x + k * (rawRssi - _x);
    _p = (1.0 - k) * pPred;

    return _x;
  }

  void reset() {
    _isInitialized = false;
    _x = 0.0;
    _p = 4.0;
    _warmupSamples = 5;
    _motionState = FilterMotionState.fastAttack;
    _consecutiveStationarySamples = 0;
    _consecutiveMovingSamples = 0;
    _lastDelta = 0.0;
    _recentDeltas.clear();
  }

  /// Override filter state directly (e.g. for testing or instant reset)
  void setState(double rssi) {
    _x = rssi;
    _p = 1.0;
    _isInitialized = true;
    _motionState = FilterMotionState.stationary;
    _consecutiveStationarySamples = 5;
    _consecutiveMovingSamples = 0;
    _lastDelta = 0.0;
    _recentDeltas.clear();
  }
}
