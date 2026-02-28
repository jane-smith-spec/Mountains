/// Observer state — combines position and orientation into a single snapshot.
///
/// This is the "where am I and which way am I looking?" package that gets
/// passed to the horizon computation. It bundles GPS location with device
/// orientation so services don't need to juggle two separate streams.
library;

import 'sensor_data.dart';

/// A snapshot of the observer's position and orientation.
///
/// Immutable value object — create a new one each time the sensors update.
class ObserverState {
  const ObserverState({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.altitudeM,
    required this.headingDeg,
    required this.pitchDeg,
  });

  /// Create from separate location and orientation objects.
  factory ObserverState.from({
    required DeviceLocation location,
    required DeviceOrientation orientation,
  }) {
    return ObserverState(
      latitudeDeg: location.latitudeDeg,
      longitudeDeg: location.longitudeDeg,
      altitudeM: location.altitudeM,
      headingDeg: orientation.headingDeg,
      pitchDeg: orientation.pitchDeg,
    );
  }

  /// Latitude in degrees (positive = North).
  final double latitudeDeg;

  /// Longitude in degrees (positive = East).
  final double longitudeDeg;

  /// Altitude in meters above sea level.
  final double altitudeM;

  /// Compass heading in degrees (0 = North, 90 = East).
  final double headingDeg;

  /// Camera pitch in degrees (0 = horizontal, positive = up).
  final double pitchDeg;

  @override
  String toString() =>
      'ObserverState(${latitudeDeg.toStringAsFixed(4)}°N, '
      '${longitudeDeg.toStringAsFixed(4)}°E, '
      '${altitudeM.toStringAsFixed(0)}m, '
      'heading=${headingDeg.toStringAsFixed(1)}°, '
      'pitch=${pitchDeg.toStringAsFixed(1)}°)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObserverState &&
          latitudeDeg == other.latitudeDeg &&
          longitudeDeg == other.longitudeDeg &&
          altitudeM == other.altitudeM &&
          headingDeg == other.headingDeg &&
          pitchDeg == other.pitchDeg;

  @override
  int get hashCode => Object.hash(
        latitudeDeg,
        longitudeDeg,
        altitudeM,
        headingDeg,
        pitchDeg,
      );
}
