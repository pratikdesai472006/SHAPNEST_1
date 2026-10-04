/// 1D Adaptive Kalman Filter optimized for 2.4 GHz BLE RSSI signal conditioning.
/// Replaces jumpy raw RSSI with a smooth, mathematically optimal true-state estimate.
class RssiKalmanFilter {
  double _x = 0.0; // Estimated state (Filtered RSSI)
  double _p = 1.0; // Estimation error covariance
  double _q = 0.08; // Process noise covariance (movement dynamics)
  double _r = 3.0; // Measurement noise covariance (multipath noise)

  bool _isInitialized = false;
  int _consecutiveOutliers = 0;

  RssiKalmanFilter({
    double processNoise = 0.08,
    double measurementNoise = 3.0,
  })  : _q = processNoise,
        _r = measurementNoise;

  bool get isInitialized => _isInitialized;
  double get currentRssi => _x;

  /// Update the filter with a fresh raw RSSI measurement
  double filter(double rawRssi) {
    if (!_isInitialized) {
      _x = rawRssi;
      _p = 1.0;
      _isInitialized = true;
      return _x;
    }

    // 1. Time Update (Predict)
    // x_pred = x_prev
    // p_pred = p_prev + Q
    final pPred = _p + _q;

    // 2. Adaptive Measurement Noise (Outlier Dampening)
    // In indoor environments, multipath reflection causes instantaneous +/- 10 dBm nulls.
    final innovation = (rawRssi - _x).abs();
    double adaptiveR = _r;

    if (innovation > 7.0) {
      _consecutiveOutliers++;
      if (_consecutiveOutliers < 3) {
        // Single impulse spike: heavily damp by elevating measurement noise
        adaptiveR = _r * 4.0;
      } else {
        // Sustained change: user actually moved! Accelerate tracking
        adaptiveR = _r * 0.5;
      }
    } else {
      _consecutiveOutliers = 0;
    }

    // 3. Measurement Update (Correct)
    // Kalman Gain: K = p_pred / (p_pred + R)
    final k = pPred / (pPred + adaptiveR);

    // Update state estimate: x = x_pred + K * (z - x_pred)
    _x = _x + k * (rawRssi - _x);

    // Update error covariance: P = (1 - K) * p_pred
    _p = (1.0 - k) * pPred;

    return _x;
  }

  void reset() {
    _isInitialized = false;
    _x = 0.0;
    _p = 1.0;
    _consecutiveOutliers = 0;
  }

  void setParameters({double? processNoise, double? measurementNoise}) {
    if (processNoise != null) _q = processNoise;
    if (measurementNoise != null) _r = measurementNoise;
  }
}
