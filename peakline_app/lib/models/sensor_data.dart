/// Data models for sensor readings.
///
/// These are simple Dart classes that hold the values from the phone's
/// sensors. They're separate from the sensor-reading code so they can be
/// used anywhere in the app (UI, services, tests) without importing
/// platform-specific sensor packages.
library;

/// The device's current orientation in 3D space.
///
/// Think of holding your phone upright in front of you like a camera:
///   - [headingDeg]: Which compass direction the phone points at.
///     0° = North, 90° = East, 180° = South, 270° = West.
///   - [pitchDeg]: How much the phone is tilted up or down.
///     0° = looking straight at the horizon.
///     +90° = pointing at the sky. -90° = pointing at the ground.
///   - [rollDeg]: How much the phone is rotated sideways.
///     0° = perfectly upright. +90° = tilted right.
class DeviceOrientation {
  const DeviceOrientation({
    required this.headingDeg,
    required this.pitchDeg,
    required this.rollDeg,
  });

  /// Compass heading in degrees (0-360). 0 = North, 90 = East.
  final double headingDeg;

  /// Pitch in degrees. 0 = horizontal, positive = tilted up.
  final double pitchDeg;

  /// Roll in degrees. 0 = upright, positive = tilted right.
  final double rollDeg;

  @override
  String toString() =>
      'DeviceOrientation(heading=${headingDeg.toStringAsFixed(1)}°, '
      'pitch=${pitchDeg.toStringAsFixed(1)}°, '
      'roll=${rollDeg.toStringAsFixed(1)}°)';
}

/// The device's current GPS location.
///
/// This is what the app uses to know WHERE you are, so it can look up
/// the right elevation data and compute the horizon for your position.
class DeviceLocation {
  const DeviceLocation({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.altitudeM,
    required this.accuracyM,
  });

  /// Latitude in degrees. Positive = North, negative = South.
  final double latitudeDeg;

  /// Longitude in degrees. Positive = East, negative = West.
  final double longitudeDeg;

  /// Altitude in meters above sea level.
  /// May be 0 if the device doesn't have altitude data.
  final double altitudeM;

  /// Horizontal accuracy in meters. Lower = more precise.
  /// GPS typically gives 3-10m accuracy outdoors.
  final double accuracyM;

  @override
  String toString() =>
      'DeviceLocation(${latitudeDeg.toStringAsFixed(5)}°N, '
      '${longitudeDeg.toStringAsFixed(5)}°E, '
      '${altitudeM.toStringAsFixed(0)}m, '
      '±${accuracyM.toStringAsFixed(0)}m)';
}

// -----------------------------------------------------------------------
//  Math helpers for angle operations
// -----------------------------------------------------------------------

/// Normalize an angle to the range [0, 360).
double normalizeAngle(double deg) {
  double result = deg % 360.0;
  if (result < 0) result += 360.0;
  return result;
}

/// Compute the shortest angular difference between two headings.
/// Result is in the range [-180, 180].
///
/// For example:
///   angleDifference(350, 10) = 20  (10° is 20° clockwise from 350°)
///   angleDifference(10, 350) = -20 (350° is 20° counter-clockwise from 10°)
double angleDifference(double fromDeg, double toDeg) {
  double diff = toDeg - fromDeg;
  while (diff > 180.0) {
    diff -= 360.0;
  }
  while (diff < -180.0) {
    diff += 360.0;
  }
  return diff;
}
