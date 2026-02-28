/// Gyro stabilizer — fuses gyroscope with compass for smooth heading.
///
/// ## The Problem
///
/// The magnetometer (compass) gives us absolute heading, but it's noisy —
/// readings jump 5-10° between samples. The Kalman filter (Step 12) helps
/// a lot, but for a truly smooth AR overlay we need something better.
///
/// ## The Solution: Complementary Filter
///
/// The gyroscope measures angular velocity (how fast you're rotating).
/// It's *very* smooth, but it drifts over time (accumulates error).
///
/// We combine the two using a complementary filter:
///
///   heading = α × (heading + gyro × dt) + (1 - α) × compass
///
/// - **Short term** (α ≈ 0.98): Trust the gyro → smooth, no jitter
/// - **Long term** (1-α ≈ 0.02): Correct toward compass → no drift
///
/// The result: an overlay that feels rock-solid when you hold the phone
/// still, yet accurately tracks when you turn.
///
/// ## Gyro Bias Estimation
///
/// Even when stationary, gyroscopes report small non-zero values (bias).
/// We estimate this bias when the device is still and subtract it from
/// future readings. This prevents slow drift when standing still.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/sensor_data.dart';

/// Fuses gyroscope angular velocity with magnetometer-derived heading
/// using a complementary filter for smooth, jitter-free AR overlay.
class GyroStabilizer {
  GyroStabilizer({
    this.alpha = 0.98,
    this.biasEstimationSamples = 50,
    this.stillnessThresholdDegPerSec = 1.0,
  });

  /// Complementary filter weight for gyro (0-1).
  /// Higher = smoother, slower to correct compass drift.
  /// Lower = noisier but follows compass more closely.
  final double alpha;

  /// Number of stationary samples to collect for bias estimation.
  final int biasEstimationSamples;

  /// Below this rotation rate, the device is considered still (for bias).
  final double stillnessThresholdDegPerSec;

  // -- Internal state --
  double? _fusedHeadingDeg;
  double? _fusedPitchDeg;
  DateTime? _lastTimestamp;

  // Gyro bias estimation (offsets when stationary)
  double _gyroBiasZ = 0.0; // Yaw (heading) bias
  double _gyroBiasX = 0.0; // Pitch bias
  final List<double> _biasZSamples = [];
  final List<double> _biasXSamples = [];
  bool _biasCalibrated = false;

  // Motion detection
  bool _isStationary = true;

  /// Whether the gyro bias has been calibrated.
  bool get isBiasCalibrated => _biasCalibrated;

  /// Whether the device appears to be stationary.
  bool get isStationary => _isStationary;

  /// The current fused heading, or null if not yet initialized.
  double? get fusedHeadingDeg => _fusedHeadingDeg;

  /// The current fused pitch, or null if not yet initialized.
  double? get fusedPitchDeg => _fusedPitchDeg;

  /// Process a new set of sensor readings and return the stabilized orientation.
  ///
  /// [compassHeadingDeg] — raw magnetometer-derived heading (0-360).
  /// [compassPitchDeg] — raw accelerometer-derived pitch.
  /// [gyroZDegPerSec] — gyro angular velocity around Z axis (yaw/heading).
  /// [gyroXDegPerSec] — gyro angular velocity around X axis (pitch).
  ///
  /// Returns the fused (heading, pitch) as a record.
  ({double headingDeg, double pitchDeg}) update({
    required double compassHeadingDeg,
    required double compassPitchDeg,
    required double gyroZDegPerSec,
    required double gyroXDegPerSec,
  }) {
    final now = DateTime.now();

    // Compute dt (time since last sample, in seconds)
    final double dt;
    if (_lastTimestamp != null) {
      dt = now.difference(_lastTimestamp!).inMicroseconds / 1e6;
    } else {
      dt = 0.0;
    }
    _lastTimestamp = now;

    // --- Bias estimation ---
    _updateBiasEstimation(gyroZDegPerSec, gyroXDegPerSec);

    // Subtract estimated bias from gyro readings
    final correctedGyroZ = gyroZDegPerSec - _gyroBiasZ;
    final correctedGyroX = gyroXDegPerSec - _gyroBiasX;

    // --- Motion detection ---
    final rotationRate = math.sqrt(
      correctedGyroZ * correctedGyroZ + correctedGyroX * correctedGyroX,
    );
    _isStationary = rotationRate < stillnessThresholdDegPerSec;

    // --- Complementary filter ---
    if (_fusedHeadingDeg == null || dt > 1.0) {
      // First sample or time gap too large — initialize from compass
      _fusedHeadingDeg = compassHeadingDeg;
      _fusedPitchDeg = compassPitchDeg;
    } else if (dt <= 0) {
      // Same-instant call (no time elapsed) — blend without gyro integration.
      // We can't integrate gyro with dt=0, so just nudge toward compass.
      _fusedHeadingDeg = _circularBlend(
        _fusedHeadingDeg!,
        compassHeadingDeg,
        alpha,
      );
      _fusedPitchDeg = alpha * _fusedPitchDeg! + (1 - alpha) * compassPitchDeg;
    } else {
      // Normal case: integrate gyro angular velocity, then blend with compass
      final gyroHeading = _fusedHeadingDeg! + correctedGyroZ * dt;
      final gyroPitch = _fusedPitchDeg! + correctedGyroX * dt;

      // Heading: blend gyro (smooth) with compass (stable)
      // Handle 0°/360° wrap using sin/cos decomposition
      _fusedHeadingDeg = _circularBlend(
        gyroHeading,
        compassHeadingDeg,
        alpha,
      );

      // Pitch: simpler linear blend (no wrap-around issues)
      _fusedPitchDeg = alpha * gyroPitch + (1 - alpha) * compassPitchDeg;
    }

    return (
      headingDeg: _fusedHeadingDeg!,
      pitchDeg: _fusedPitchDeg!,
    );
  }

  /// Reset the stabilizer to uninitialized state.
  void reset() {
    _fusedHeadingDeg = null;
    _fusedPitchDeg = null;
    _lastTimestamp = null;
    _gyroBiasZ = 0.0;
    _gyroBiasX = 0.0;
    _biasZSamples.clear();
    _biasXSamples.clear();
    _biasCalibrated = false;
    _isStationary = true;
  }

  /// Collect bias samples when stationary and compute average bias.
  void _updateBiasEstimation(double gyroZ, double gyroX) {
    // Only collect samples when nearly still
    final rate = math.sqrt(gyroZ * gyroZ + gyroX * gyroX);
    if (rate > stillnessThresholdDegPerSec * 2) {
      // Device is moving — don't collect bias samples
      return;
    }

    _biasZSamples.add(gyroZ);
    _biasXSamples.add(gyroX);

    // Keep only the most recent samples
    if (_biasZSamples.length > biasEstimationSamples) {
      _biasZSamples.removeAt(0);
      _biasXSamples.removeAt(0);
    }

    // Once we have enough samples, compute bias
    if (_biasZSamples.length >= biasEstimationSamples) {
      _gyroBiasZ = _mean(_biasZSamples);
      _gyroBiasX = _mean(_biasXSamples);
      _biasCalibrated = true;
    }
  }

  /// Circular (angular) blend that handles the 0°/360° wrap correctly.
  ///
  /// Blends [a] (gyro prediction) with [b] (compass reading) using
  /// weight [w] for [a]. Uses sin/cos decomposition to avoid the
  /// 350°/10° averaging problem.
  static double _circularBlend(double a, double b, double w) {
    final aRad = a * (math.pi / 180.0);
    final bRad = b * (math.pi / 180.0);

    final sinBlend = w * math.sin(aRad) + (1 - w) * math.sin(bRad);
    final cosBlend = w * math.cos(aRad) + (1 - w) * math.cos(bRad);

    var result = math.atan2(sinBlend, cosBlend) * (180.0 / math.pi);
    if (result < 0) result += 360.0;
    return result;
  }

  static double _mean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }
}

// -----------------------------------------------------------------------
//  Stabilized sensor service (gyro + compass fusion)
// -----------------------------------------------------------------------

/// Enhanced sensor service that adds gyroscope fusion on top of the
/// base [SensorService] magnetometer/accelerometer readings.
///
/// This creates a separate stream of stabilized orientations that are
/// smoother than raw compass readings. The live view can choose between
/// the standard sensor stream and this stabilized stream.
class StabilizedSensorService {
  StabilizedSensorService({
    double alpha = 0.98,
  }) : _stabilizer = GyroStabilizer(alpha: alpha);

  final GyroStabilizer _stabilizer;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Latest raw readings
  MagnetometerEvent? _lastMag;
  AccelerometerEvent? _lastAccel;
  GyroscopeEvent? _lastGyro;

  final _controller = StreamController<DeviceOrientation>.broadcast();

  /// Stream of gyro-stabilized orientation updates.
  Stream<DeviceOrientation> get stabilizedStream => _controller.stream;

  /// Whether the gyro bias has been calibrated.
  bool get isBiasCalibrated => _stabilizer.isBiasCalibrated;

  /// Start listening to all three sensor streams.
  void start() {
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _lastGyro = event;
      _computeStabilized();
    });

    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _lastMag = event;
    });

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _lastAccel = event;
    });
  }

  /// Stop all sensor listeners.
  void stop() {
    _gyroSub?.cancel();
    _magSub?.cancel();
    _accelSub?.cancel();
    _gyroSub = null;
    _magSub = null;
    _accelSub = null;
  }

  /// Clean up resources.
  void dispose() {
    stop();
    _controller.close();
    _stabilizer.reset();
  }

  void _computeStabilized() {
    final mag = _lastMag;
    final accel = _lastAccel;
    final gyro = _lastGyro;
    if (mag == null || accel == null || gyro == null) return;

    // Compute raw compass heading and pitch from mag + accel
    final ax = accel.x;
    final ay = accel.y;
    final az = accel.z;

    final pitchRad = math.atan2(-ay, math.sqrt(ax * ax + az * az));
    final rollRad = math.atan2(ax, az);
    final pitchDeg = pitchRad * (180.0 / math.pi);
    final rollDeg = rollRad * (180.0 / math.pi);

    final mx = mag.x;
    final my = mag.y;
    final mz = mag.z;
    final cosPitch = math.cos(pitchRad);
    final sinPitch = math.sin(pitchRad);
    final cosRoll = math.cos(rollRad);
    final sinRoll = math.sin(rollRad);
    final xH = mx * cosRoll + my * sinRoll * sinPitch + mz * sinRoll * cosPitch;
    final yH = my * cosPitch - mz * sinPitch;
    var compassHeading = math.atan2(-yH, xH) * (180.0 / math.pi);
    if (compassHeading < 0) compassHeading += 360.0;

    // Gyro angular velocities (rad/s → deg/s)
    // gyro.z = rotation around vertical axis (yaw/heading change)
    // gyro.x = rotation around horizontal axis (pitch change)
    final gyroZDegPerSec = gyro.z * (180.0 / math.pi);
    final gyroXDegPerSec = gyro.x * (180.0 / math.pi);

    // Fuse via complementary filter
    final fused = _stabilizer.update(
      compassHeadingDeg: compassHeading,
      compassPitchDeg: pitchDeg,
      gyroZDegPerSec: gyroZDegPerSec,
      gyroXDegPerSec: gyroXDegPerSec,
    );

    _controller.add(DeviceOrientation(
      headingDeg: fused.headingDeg,
      pitchDeg: fused.pitchDeg,
      rollDeg: rollDeg,
    ));
  }
}

// -----------------------------------------------------------------------
//  Riverpod providers
// -----------------------------------------------------------------------

/// Provider for the stabilized sensor service.
final stabilizedSensorProvider = Provider<StabilizedSensorService>((ref) {
  final service = StabilizedSensorService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for gyro-stabilized orientation.
///
/// Use this instead of [deviceOrientationProvider] for smoother AR overlay.
final stabilizedOrientationProvider =
    StreamProvider<DeviceOrientation>((ref) {
  final service = ref.watch(stabilizedSensorProvider);
  service.start();
  ref.onDispose(() => service.stop());
  return service.stabilizedStream;
});
