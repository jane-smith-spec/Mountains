/// Sensor service — reads compass heading and device tilt from phone sensors.
///
/// Your phone has several motion sensors:
///   - **Magnetometer**: Detects the Earth's magnetic field → compass heading.
///   - **Accelerometer**: Detects gravity and movement → which way is "down".
///   - **Gyroscope**: Detects rotation speed → smooth short-term orientation.
///
/// This service combines them to answer: "Which direction is the phone
/// pointing, and how much is it tilted up/down?"
///
/// The readings are streamed as [DeviceOrientation] objects via Riverpod,
/// so the UI automatically rebuilds whenever the sensors update.
///
/// ## Filtering
///
/// Raw compass readings jitter by 5-10° between consecutive samples.
/// This service supports two filtering modes:
///   - **Low-pass filter**: Simple exponential smoothing (the original).
///   - **Kalman filter**: Adaptive smoothing that tracks rate of change,
///     giving smooth output when still and fast response when turning.
///
/// The active filter is controlled by the [SmoothingLevel] from settings.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/sensor_data.dart';
import 'kalman_filter.dart';

// -----------------------------------------------------------------------
//  Low-pass filter for smoothing noisy sensor data (legacy/fallback)
// -----------------------------------------------------------------------

/// A simple exponential smoothing filter.
///
/// Raw sensor readings are noisy — they jump around by several degrees
/// from one reading to the next. This filter blends each new reading
/// with the previous smoothed value:
///
///   smoothed = alpha * newValue + (1 - alpha) * previousSmoothed
///
/// alpha close to 1.0 = responsive but noisy (follows raw data closely)
/// alpha close to 0.0 = smooth but laggy (slow to respond to changes)
///
/// We use 0.15 as a good balance for compass/orientation data.
class _LowPassFilter {
  _LowPassFilter(this.alpha);

  final double alpha;
  double? _value;

  double filter(double newValue) {
    final prev = _value;
    if (prev == null) {
      _value = newValue;
      return newValue;
    }
    final smoothed = alpha * newValue + (1.0 - alpha) * prev;
    _value = smoothed;
    return smoothed;
  }

  void reset() => _value = null;
}

/// Specialized filter for compass heading that handles the 0°/360° wrap.
///
/// Normal smoothing breaks near north: averaging 350° and 10° gives 180°
/// (south!) instead of 0° (north). We fix this by converting to
/// sin/cos components, smoothing those, then converting back.
class _HeadingFilter {
  _HeadingFilter(double alpha)
      : _sinFilter = _LowPassFilter(alpha),
        _cosFilter = _LowPassFilter(alpha);

  final _LowPassFilter _sinFilter;
  final _LowPassFilter _cosFilter;

  double filter(double headingDeg) {
    final rad = headingDeg * (math.pi / 180.0);
    final smoothSin = _sinFilter.filter(math.sin(rad));
    final smoothCos = _cosFilter.filter(math.cos(rad));
    final smoothRad = math.atan2(smoothSin, smoothCos);
    return normalizeAngle(smoothRad * (180.0 / math.pi));
  }

  void reset() {
    _sinFilter.reset();
    _cosFilter.reset();
  }
}

// -----------------------------------------------------------------------
//  Sensor Service
// -----------------------------------------------------------------------

/// Service that fuses magnetometer and accelerometer into orientation.
///
/// The key insight: the magnetometer gives us compass heading, and the
/// accelerometer gives us pitch and roll (by detecting which way gravity
/// pulls). Together they tell us the phone's full 3D orientation.
///
/// Supports both legacy low-pass filtering and adaptive Kalman filtering.
/// Switch between them with [setSmoothingLevel].
class SensorService {
  SensorService({SmoothingLevel? smoothingLevel}) {
    // Initialize with legacy low-pass filters as baseline
    _headingFilter = _HeadingFilter(0.15);
    _pitchFilter = _LowPassFilter(0.15);
    _rollFilter = _LowPassFilter(0.15);

    // Set up Kalman filters if a smoothing level is provided
    if (smoothingLevel != null) {
      _useKalman = true;
      _applyKalmanSettings(smoothingLevel);
    }
  }

  // -- Legacy low-pass filters --
  late final _HeadingFilter _headingFilter;
  late final _LowPassFilter _pitchFilter;
  late final _LowPassFilter _rollFilter;

  // -- Kalman filters (used when enabled via settings) --
  bool _useKalman = false;
  HeadingKalmanFilter? _headingKalman;
  KalmanFilter1D? _pitchKalman;
  KalmanFilter1D? _rollKalman;

  // Timestamp for computing dt between measurements
  DateTime? _lastSampleTime;

  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Latest raw readings from each sensor
  MagnetometerEvent? _lastMag;
  AccelerometerEvent? _lastAccel;

  // Stream controller that emits fused orientation
  final _orientationController = StreamController<DeviceOrientation>.broadcast();

  /// Whether the Kalman filter is currently active.
  bool get useKalmanFilter => _useKalman;

  /// Stream of device orientation updates.
  ///
  /// Emits roughly 30-60 times per second (depends on device).
  /// Each event contains the smoothed heading, pitch, and roll.
  Stream<DeviceOrientation> get orientationStream =>
      _orientationController.stream;

  /// Update the smoothing level (switches filter parameters).
  ///
  /// This can be called while the sensor is running — the filters
  /// will be recreated with the new noise parameters. There will be
  /// a brief transient as the new filter initializes.
  void setSmoothingLevel(SmoothingLevel level) {
    _useKalman = true;
    _applyKalmanSettings(level);
  }

  /// Switch back to the legacy low-pass filter.
  void useLegacyFilter() {
    _useKalman = false;
    _headingFilter.reset();
    _pitchFilter.reset();
    _rollFilter.reset();
    _lastSampleTime = null;
  }

  void _applyKalmanSettings(SmoothingLevel level) {
    _headingKalman = HeadingKalmanFilter(
      processNoise: level.processNoise,
      measurementNoise: level.measurementNoise,
    );
    _pitchKalman = KalmanFilter1D(
      processNoise: level.processNoise * 0.5, // Pitch is less noisy
      measurementNoise: level.measurementNoise * 0.5,
    );
    _rollKalman = KalmanFilter1D(
      processNoise: level.processNoise * 0.5,
      measurementNoise: level.measurementNoise * 0.5,
    );
    _lastSampleTime = null;
  }

  /// Start listening to sensors.
  ///
  /// Call this when the camera/AR view opens. Don't forget to call
  /// [stop] when leaving the screen to save battery.
  void start() {
    // Listen to magnetometer (compass)
    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _lastMag = event;
      _computeOrientation();
    });

    // Listen to accelerometer (gravity → pitch/roll)
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _lastAccel = event;
      _computeOrientation();
    });
  }

  /// Stop listening to sensors (saves battery).
  void stop() {
    _magSub?.cancel();
    _accelSub?.cancel();
    _magSub = null;
    _accelSub = null;
  }

  /// Clean up resources.
  void dispose() {
    stop();
    _orientationController.close();
  }

  /// Compute orientation from the latest sensor readings.
  ///
  /// This is called every time either sensor updates. It combines
  /// magnetometer + accelerometer to get a full 3D orientation.
  void _computeOrientation() {
    final mag = _lastMag;
    final accel = _lastAccel;
    if (mag == null || accel == null) return;

    // --- Pitch and Roll from accelerometer ---
    // The accelerometer measures gravity. When the phone is flat,
    // all gravity is on the Z axis. When tilted, gravity shifts
    // to X (roll) and Y (pitch).
    //
    // pitch = how much the phone is tilted forward/backward
    // roll = how much the phone is tilted left/right
    final ax = accel.x;
    final ay = accel.y;
    final az = accel.z;

    // atan2 gives us the angle of tilt
    final pitchRad = math.atan2(-ay, math.sqrt(ax * ax + az * az));
    final rollRad = math.atan2(ax, az);

    final pitchDeg = pitchRad * (180.0 / math.pi);
    final rollDeg = rollRad * (180.0 / math.pi);

    // --- Compass heading from magnetometer ---
    // The magnetometer gives the magnetic field strength on each axis.
    // We need to "tilt-compensate" it using the pitch and roll we just
    // computed, otherwise the heading drifts when you tilt the phone.
    final mx = mag.x;
    final my = mag.y;
    final mz = mag.z;

    // Tilt compensation: rotate the magnetic vector to horizontal plane
    final cosPitch = math.cos(pitchRad);
    final sinPitch = math.sin(pitchRad);
    final cosRoll = math.cos(rollRad);
    final sinRoll = math.sin(rollRad);

    final xH = mx * cosRoll + my * sinRoll * sinPitch + mz * sinRoll * cosPitch;
    final yH = my * cosPitch - mz * sinPitch;

    var headingDeg = math.atan2(-yH, xH) * (180.0 / math.pi);
    headingDeg = normalizeAngle(headingDeg);

    // Apply smoothing filters (Kalman or legacy low-pass)
    final double smoothHeading;
    final double smoothPitch;
    final double smoothRoll;

    if (_useKalman &&
        _headingKalman != null &&
        _pitchKalman != null &&
        _rollKalman != null) {
      // Compute dt for Kalman prediction step
      final now = DateTime.now();
      final double? dt;
      if (_lastSampleTime != null) {
        dt = now.difference(_lastSampleTime!).inMicroseconds / 1e6;
      } else {
        dt = null;
      }
      _lastSampleTime = now;

      smoothHeading = _headingKalman!.filter(headingDeg, dt: dt);
      smoothPitch = _pitchKalman!.filter(pitchDeg, dt: dt);
      smoothRoll = _rollKalman!.filter(rollDeg, dt: dt);
    } else {
      smoothHeading = _headingFilter.filter(headingDeg);
      smoothPitch = _pitchFilter.filter(pitchDeg);
      smoothRoll = _rollFilter.filter(rollDeg);
    }

    _orientationController.add(DeviceOrientation(
      headingDeg: smoothHeading,
      pitchDeg: smoothPitch,
      rollDeg: smoothRoll,
    ));
  }
}

// -----------------------------------------------------------------------
//  Riverpod providers
// -----------------------------------------------------------------------

/// Provider that creates and manages the SensorService lifecycle.
///
/// Use `ref.watch(sensorServiceProvider)` to get the service instance.
/// The service is automatically disposed when no longer needed.
final sensorServiceProvider = Provider<SensorService>((ref) {
  final service = SensorService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for live device orientation.
///
/// Use `ref.watch(deviceOrientationProvider)` in widgets to get the
/// latest orientation. The widget automatically rebuilds on each update.
///
/// Example:
/// ```dart
/// final orientation = ref.watch(deviceOrientationProvider);
/// orientation.when(
///   data: (o) => Text('Heading: ${o.headingDeg.toStringAsFixed(0)}°'),
///   loading: () => Text('Starting sensors...'),
///   error: (e, s) => Text('Sensor error: $e'),
/// );
/// ```
final deviceOrientationProvider = StreamProvider<DeviceOrientation>((ref) {
  final service = ref.watch(sensorServiceProvider);
  service.start();
  ref.onDispose(() => service.stop());
  return service.orientationStream;
});
