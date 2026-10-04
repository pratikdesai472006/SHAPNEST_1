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
  double _p = 1.0; // Estimation error covariance

  // Stationary Tuning Parameters
  static const double _qStationary = 0.005; // Minimal process noise when still
  static const double _rStationary = 14.0;  // High measurement noise resistance

  // Moving Tuning Parameters
  static const double _qMoving = 0.35;      // Higher process noise during movement
  static const double _rMoving = 1.50;      // Low measurement noise to follow motion

  // Fast Attack (Approaching Danger) Parameters
  static const double _qFastAttack = 0.80;  // Extreme process noise
  static const double _rFastAttack = 0.60;  // Minimal measurement resistance

  // Thresholds (dBm)
  static const double _stationaryDeltaThresh = 2.0; // Typical Rayleigh indoor noise
  static const double _movementDeltaThresh   = 3.0; // Meaningful step change
  static const double _fastAttackDeltaThresh = 4.0; // Rapid approach (+dBm = closer)

  bool _isInitialized = false;
  FilterMotionState _motionState = FilterMotionState.stationary;
  int _consecutiveStationarySamples = 0;
  final List<double> _recentDeltas = [];

  RssiKalmanFilter();

  bool get isInitialized => _isInitialized;
  double get currentRssi => _x;
  FilterMotionState get motionState => _motionState;

  /// Update the filter with a fresh raw RSSI measurement
  double filter(double rawRssi) {
    if (!_isInitialized) {
      _x = rawRssi;
      _p = 1.0;
      _isInitialized = true;
      _motionState = FilterMotionState.stationary;
      _consecutiveStationarySamples = 5;
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

    // Fast Attack: Signal is strengthening rapidly (device approaching danger)
    if (delta >= _fastAttackDeltaThresh || (delta > 2.5 && isConsistentDirection && delta > 0)) {
      _motionState = FilterMotionState.fastAttack;
      _consecutiveStationarySamples = 0;
    }
    // Normal Movement: Meaningful deviation or consistent directional drift
    else if (absDelta >= _movementDeltaThresh || isConsistentDirection) {
      _motionState = FilterMotionState.moving;
      _consecutiveStationarySamples = 0;
    }
    // Stationary: Delta is within typical stationary RF noise envelope (<= 2.0 dBm)
    else if (absDelta <= _stationaryDeltaThresh) {
      _consecutiveStationarySamples++;
      if (_consecutiveStationarySamples >= 3) {
        _motionState = FilterMotionState.stationary;
      }
    }

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
    _p = 1.0;
    _motionState = FilterMotionState.stationary;
    _consecutiveStationarySamples = 0;
    _recentDeltas.clear();
  }

  /// Override filter state directly (e.g. for testing or instant reset)
  void setState(double rssi) {
    _x = rssi;
    _p = 1.0;
    _isInitialized = true;
    _motionState = FilterMotionState.stationary;
    _consecutiveStationarySamples = 5;
    _recentDeltas.clear();
  }
}
