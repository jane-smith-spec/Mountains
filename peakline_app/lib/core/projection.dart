/// Screen projection — converts world coordinates to screen pixels.
///
/// This is the key piece that makes the AR overlay work. It answers:
/// "Given that a mountain peak is at compass bearing X and elevation
/// angle Y, where on the phone screen should I draw it?"
///
/// The math is a simple pinhole camera model:
///   1. Compute the angular offset of the point relative to where
///      the camera is pointing (heading and pitch).
///   2. Map that angular offset to a pixel position, using the
///      camera's field of view and the screen dimensions.
///
/// Points outside the camera's field of view return null (don't draw).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/sensor_data.dart';
import 'constants.dart';

/// The result of projecting a world point to screen coordinates.
///
/// Includes the pixel position and whether the point is actually
/// within the visible camera frame.
class ScreenPoint {
  const ScreenPoint({
    required this.x,
    required this.y,
    required this.isVisible,
  });

  /// X pixel coordinate (0 = left edge of screen).
  final double x;

  /// Y pixel coordinate (0 = top edge of screen).
  final double y;

  /// Whether this point falls within the camera's field of view.
  /// If false, x and y are still computed (for off-screen indicators)
  /// but the point shouldn't be drawn as an overlay.
  final bool isVisible;

  /// Convert to a Flutter Offset for use with Canvas drawing.
  Offset toOffset() => Offset(x, y);

  @override
  String toString() =>
      'ScreenPoint(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      'visible=$isVisible)';
}

/// Parameters describing the camera's current view.
///
/// This captures everything we need to project world coordinates
/// to screen pixels: where the camera is pointing, how wide its
/// view is, and how big the screen is.
class CameraViewParams {
  const CameraViewParams({
    required this.headingDeg,
    required this.pitchDeg,
    required this.screenWidth,
    required this.screenHeight,
    this.horizontalFovDeg = defaultHorizontalFovDeg,
    this.verticalFovDeg = defaultVerticalFovDeg,
  });

  /// Create from the current device orientation and screen size.
  factory CameraViewParams.fromOrientation({
    required DeviceOrientation orientation,
    required double screenWidth,
    required double screenHeight,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double? verticalFovDeg,
  }) {
    // If vertical FOV not specified, derive from horizontal FOV
    // assuming the screen aspect ratio matches the camera aspect ratio.
    final vFov = verticalFovDeg ??
        2.0 *
            math.atan(
              math.tan(horizontalFovDeg * deg2Rad / 2.0) *
                  (screenHeight / screenWidth),
            ) *
            rad2Deg;

    return CameraViewParams(
      headingDeg: orientation.headingDeg,
      pitchDeg: orientation.pitchDeg,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      horizontalFovDeg: horizontalFovDeg,
      verticalFovDeg: vFov,
    );
  }

  /// Compass direction the camera is pointing (0-360°).
  final double headingDeg;

  /// Vertical tilt of the camera. 0° = horizontal, positive = up.
  final double pitchDeg;

  /// Screen width in pixels.
  final double screenWidth;

  /// Screen height in pixels.
  final double screenHeight;

  /// Horizontal field of view in degrees.
  final double horizontalFovDeg;

  /// Vertical field of view in degrees.
  final double verticalFovDeg;
}

/// Project a world point (azimuth + elevation angle) to screen pixels.
///
/// This is the core projection function. It takes:
///   - [azimuthDeg]: The compass bearing of the point (0=N, 90=E, etc.)
///   - [elevationAngleDeg]: How far above horizontal the point appears
///   - [camera]: The current camera view parameters
///
/// Returns a [ScreenPoint] with the pixel position.
///
/// The math:
///   1. Find how far left/right of camera center the point is (in degrees)
///   2. Find how far up/down from camera center the point is (in degrees)
///   3. Map those angular offsets to pixel positions using the FOV
///
/// ```
/// Screen layout:
///   (0,0) ───────────────── (width,0)
///     │                         │
///     │     ·  (center)         │
///     │                         │
///   (0,height) ─────────── (width,height)
/// ```
ScreenPoint projectToScreen({
  required double azimuthDeg,
  required double elevationAngleDeg,
  required CameraViewParams camera,
}) {
  // Step 1: Angular offset from camera center (horizontal).
  // We need to handle the 0°/360° wraparound: if the camera points
  // at 350° and the target is at 10°, the offset should be +20°,
  // not -340°.
  double relativeAzimuth = azimuthDeg - camera.headingDeg;
  // Normalize to [-180, 180]
  while (relativeAzimuth > 180.0) {
    relativeAzimuth -= 360.0;
  }
  while (relativeAzimuth < -180.0) {
    relativeAzimuth += 360.0;
  }

  // Step 2: Angular offset from camera center (vertical).
  final relativeElevation = elevationAngleDeg - camera.pitchDeg;

  // Step 3: Map angular offsets to pixel positions.
  //
  // Half the FOV maps to half the screen width/height.
  // A point at +halfFOV should be at the right/top edge.
  // A point at -halfFOV should be at the left/bottom edge.
  final halfFovH = camera.horizontalFovDeg / 2.0;
  final halfFovV = camera.verticalFovDeg / 2.0;
  final halfW = camera.screenWidth / 2.0;
  final halfH = camera.screenHeight / 2.0;

  // X: positive relative azimuth → right side of screen
  final x = halfW + (relativeAzimuth / halfFovH) * halfW;

  // Y: positive elevation → UP in the real world, but UP is LOWER y
  // on screen (screen y increases downward). So we subtract.
  final y = halfH - (relativeElevation / halfFovV) * halfH;

  // Is the point within the visible camera frame?
  final isVisible = relativeAzimuth.abs() <= halfFovH &&
      relativeElevation.abs() <= halfFovV;

  return ScreenPoint(x: x, y: y, isVisible: isVisible);
}

/// Project a list of horizon profile points to screen coordinates.
///
/// Takes a list of (azimuth, elevation) pairs and returns a list of
/// [ScreenPoint]s. This is used to project an entire horizon profile
/// at once for drawing the topo line.
///
/// Only returns points that are within or near the camera's field of
/// view (with a small margin for smooth line drawing at the edges).
List<ScreenPoint> projectHorizonProfile({
  required List<({double azimuthDeg, double elevationAngleDeg})> points,
  required CameraViewParams camera,
  double marginDeg = 5.0,
}) {
  final result = <ScreenPoint>[];
  final halfFovH = camera.horizontalFovDeg / 2.0 + marginDeg;

  for (final point in points) {
    // Quick check: skip points far outside the horizontal FOV
    double relAz = point.azimuthDeg - camera.headingDeg;
    while (relAz > 180.0) {
      relAz -= 360.0;
    }
    while (relAz < -180.0) {
      relAz += 360.0;
    }

    if (relAz.abs() > halfFovH) continue;

    result.add(projectToScreen(
      azimuthDeg: point.azimuthDeg,
      elevationAngleDeg: point.elevationAngleDeg,
      camera: camera,
    ));
  }

  return result;
}
