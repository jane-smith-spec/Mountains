/// Kalman filter — smooth, adaptive sensor filtering.
///
/// The existing low-pass filter in [SensorService] uses fixed exponential
/// smoothing. It works, but has a fundamental trade-off: either it's
/// smooth (laggy when you turn fast) or responsive (jittery when still).
///
/// A Kalman filter solves this by tracking *uncertainty*:
///   - When measurements agree with the prediction → high confidence,
///     small corrections, smooth output.
///   - When measurements suddenly change (you turn quickly) → the filter
///     recognizes the prediction is wrong and catches up fast.
///
/// This gives us the best of both worlds: smooth when still, responsive
/// when moving.
///
/// ## How a 1D Kalman Filter Works (Plain English)
///
/// 1. **Predict**: "Based on how fast I was turning, I expect to be
///    at heading X next." Uncertainty grows a bit (things could change).
///
/// 2. **Update**: "The compass says heading Y." Compare with prediction.
///    The *Kalman gain* decides how much to trust the measurement vs
///    the prediction. If we're uncertain about our prediction, we trust
///    the measurement more. If the measurement is noisy, we trust the
///    prediction more.
///
/// 3. **Output**: The corrected estimate — smoother than raw data,
///    but more responsive than a fixed low-pass filter.
library;

import 'dart:math' as math;

/// A 1D Kalman filter for scalar values (heading, pitch, roll).
///
/// State vector: [value, rate_of_change]
/// This tracks both the current value AND how fast it's changing,
/// which allows the filter to anticipate motion.
class KalmanFilter1D {
  /// Create a Kalman filter.
  ///
  /// - [processNoise]: How much we expect the true value to randomly
  ///   change between measurements. Higher = more responsive, less smooth.
  ///   Good starting point: 0.1 for compass, 0.05 for pitch.
  ///
  /// - [measurementNoise]: How noisy the sensor readings are.
  ///   Higher = smoother output, slower response.
  ///   Good starting point: 2.0 for compass, 1.0 for pitch.
  KalmanFilter1D({
    required this.processNoise,
    required this.measurementNoise,
  });

  /// Process noise variance (Q). Controls responsiveness.
  final double processNoise;

  /// Measurement noise variance (R). Controls smoothness.
  final double measurementNoise;

  // State estimate
  double? _x; // Estimated value
  double _dx = 0.0; // Estimated rate of change

  // Error covariance matrix (2x2, stored as 4 values)
  double _p00 = 1000.0; // Variance of value
  double _p01 = 0.0; // Covariance
  double _p10 = 0.0; // Covariance
  double _p11 = 1000.0; // Variance of rate

  bool _initialized = false;

  /// Whether the filter has received at least one measurement.
  bool get isInitialized => _initialized;

  /// The current filtered estimate, or null if not yet initialized.
  double? get estimate => _x;

  /// The current estimated rate of change.
  double get estimatedRate => _dx;

  /// Process a new measurement and return the filtered estimate.
  ///
  /// [measurement] is the raw sensor reading.
  /// [dt] is the time since the last measurement, in seconds.
  ///   If null, only the update step is performed (no prediction).
  double filter(double measurement, {double? dt}) {
    if (!_initialized) {
      // First measurement: initialize state directly
      _x = measurement;
      _dx = 0.0;
      _p00 = measurementNoise;
      _p01 = 0.0;
      _p10 = 0.0;
      _p11 = 1.0;
      _initialized = true;
      return measurement;
    }

    // --- PREDICT step ---
    if (dt != null && dt > 0) {
      // Predict new state: x = x + dx * dt
      _x = _x! + _dx * dt;

      // Predict new covariance: P = F*P*F' + Q
      // where F = [[1, dt], [0, 1]]
      final newP00 = _p00 + dt * (_p10 + _p01) + dt * dt * _p11 + processNoise;
      final newP01 = _p01 + dt * _p11;
      final newP10 = _p10 + dt * _p11;
      final newP11 = _p11 + processNoise * 0.1; // Rate changes more slowly

      _p00 = newP00;
      _p01 = newP01;
      _p10 = newP10;
      _p11 = newP11;
    }

    // --- UPDATE step ---
    // Innovation (difference between measurement and prediction)
    final innovation = measurement - _x!;

    // Innovation covariance: S = H*P*H' + R
    // where H = [1, 0]
    final s = _p00 + measurementNoise;

    // Kalman gain: K = P*H' / S
    final k0 = _p00 / s; // Gain for value
    final k1 = _p10 / s; // Gain for rate

    // Correct state estimate
    _x = _x! + k0 * innovation;
    _dx = _dx + k1 * innovation;

    // Correct error covariance: P = (I - K*H) * P
    final newP00 = (1.0 - k0) * _p00;
    final newP01 = (1.0 - k0) * _p01;
    final newP10 = _p10 - k1 * _p00;
    final newP11 = _p11 - k1 * _p01;

    _p00 = newP00;
    _p01 = newP01;
    _p10 = newP10;
    _p11 = newP11;

    return _x!;
  }

  /// Reset the filter to uninitialized state.
  void reset() {
    _x = null;
    _dx = 0.0;
    _p00 = 1000.0;
    _p01 = 0.0;
    _p10 = 0.0;
    _p11 = 1000.0;
    _initialized = false;
  }
}

/// Kalman filter specialized for compass heading (handles 0/360 wrap).
///
/// Compass headings wrap: 359° and 1° are only 2° apart, not 358° apart.
/// This filter works internally in sin/cos space to avoid discontinuities,
/// then converts back to degrees for the output.
class HeadingKalmanFilter {
  HeadingKalmanFilter({
    double processNoise = 0.1,
    double measurementNoise = 2.0,
  })  : _sinFilter = KalmanFilter1D(
          processNoise: processNoise,
          measurementNoise: measurementNoise,
        ),
        _cosFilter = KalmanFilter1D(
          processNoise: processNoise,
          measurementNoise: measurementNoise,
        );

  final KalmanFilter1D _sinFilter;
  final KalmanFilter1D _cosFilter;

  /// Filter a heading measurement (in degrees) and return smoothed heading.
  double filter(double headingDeg, {double? dt}) {
    final rad = headingDeg * (math.pi / 180.0);
    final smoothSin = _sinFilter.filter(math.sin(rad), dt: dt);
    final smoothCos = _cosFilter.filter(math.cos(rad), dt: dt);
    final smoothRad = math.atan2(smoothSin, smoothCos);
    return _normalizeAngle(smoothRad * (180.0 / math.pi));
  }

  /// Reset both component filters.
  void reset() {
    _sinFilter.reset();
    _cosFilter.reset();
  }

  static double _normalizeAngle(double deg) {
    double result = deg % 360.0;
    if (result < 0) result += 360.0;
    return result;
  }
}

/// Smoothing level presets for the Kalman filter.
///
/// These map to different process/measurement noise combinations:
///   - [low]: More smoothing, less responsive (good when stationary)
///   - [medium]: Balanced (default, good for casual use)
///   - [high]: Less smoothing, more responsive (good for fast panning)
enum SmoothingLevel {
  low(
    label: 'Low (smoother)',
    processNoise: 0.02,
    measurementNoise: 4.0,
  ),
  medium(
    label: 'Medium',
    processNoise: 0.1,
    measurementNoise: 2.0,
  ),
  high(
    label: 'High (responsive)',
    processNoise: 0.5,
    measurementNoise: 1.0,
  );

  const SmoothingLevel({
    required this.label,
    required this.processNoise,
    required this.measurementNoise,
  });

  final String label;
  final double processNoise;
  final double measurementNoise;
}
