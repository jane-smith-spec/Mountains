/// Ruler tool — measure distance and elevation between two screen points.
///
/// The user taps two points on the AR view. The ruler:
///   1. Un-projects the screen points back to world bearings/elevations
///   2. Uses the horizon profile to estimate real-world distance
///   3. Draws a measurement line with distance/elevation labels
///
/// ## How Un-Projection Works
///
/// We reverse the projection math from [projectToScreen]:
///   - Screen X → relative azimuth → absolute bearing
///   - Screen Y → relative elevation → absolute elevation angle
///
/// Then, using the horizon profile, we find the terrain distance
/// at that bearing (the first DEM surface hit along that ray).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/coordinate_utils.dart';

/// A measurement between two points on the AR view.
class RulerMeasurement {
  const RulerMeasurement({
    required this.startScreen,
    required this.endScreen,
    required this.startBearingDeg,
    required this.endBearingDeg,
    required this.startElevationDeg,
    required this.endElevationDeg,
    this.distanceM,
    this.elevationDiffM,
  });

  /// Screen coordinates of the two endpoints.
  final Offset startScreen;
  final Offset endScreen;

  /// World bearing (azimuth) of each endpoint.
  final double startBearingDeg;
  final double endBearingDeg;

  /// World elevation angle of each endpoint.
  final double startElevationDeg;
  final double endElevationDeg;

  /// Estimated ground distance between the two points (meters).
  /// Null if we couldn't estimate (no horizon profile data).
  final double? distanceM;

  /// Estimated elevation difference (meters).
  /// Null if we couldn't estimate.
  final double? elevationDiffM;

  /// Angular separation between the two points (degrees).
  double get angularSeparationDeg {
    // Haversine-like formula for angular distance on a sphere
    final dAz = (endBearingDeg - startBearingDeg) * deg2Rad;
    final dEl = (endElevationDeg - startElevationDeg) * deg2Rad;
    return math.sqrt(dAz * dAz + dEl * dEl) * rad2Deg;
  }
}

/// Un-projects a screen point back to world bearing and elevation angle.
///
/// This reverses [projectToScreen]:
///   x → relativeAzimuth → absoluteBearing
///   y → relativeElevation → absoluteElevation
({double bearingDeg, double elevationDeg}) unprojectFromScreen({
  required Offset screenPoint,
  required double cameraHeadingDeg,
  required double cameraPitchDeg,
  required double screenWidth,
  required double screenHeight,
  double hFovDeg = defaultHorizontalFovDeg,
  double vFovDeg = defaultVerticalFovDeg,
}) {
  final halfW = screenWidth / 2.0;
  final halfH = screenHeight / 2.0;
  final halfFovH = hFovDeg / 2.0;
  final halfFovV = vFovDeg / 2.0;

  // Reverse the x → azimuth mapping
  // x = halfW + (relAz / halfFovH) * halfW
  // relAz = (x - halfW) / halfW * halfFovH
  final relativeAzimuth = (screenPoint.dx - halfW) / halfW * halfFovH;
  var bearing = cameraHeadingDeg + relativeAzimuth;
  while (bearing < 0) {
    bearing += 360.0;
  }
  while (bearing >= 360) {
    bearing -= 360.0;
  }

  // Reverse the y → elevation mapping
  // y = halfH - (relEl / halfFovV) * halfH
  // relEl = (halfH - y) / halfH * halfFovV
  final relativeElevation = (halfH - screenPoint.dy) / halfH * halfFovV;
  final elevation = cameraPitchDeg + relativeElevation;

  return (bearingDeg: bearing, elevationDeg: elevation);
}

/// Estimate the ground distance between two bearing/elevation pairs.
///
/// Uses simple trigonometry:
///   - If both points hit the horizon at known distances, the ground
///     distance is the difference.
///   - If horizon distance is unknown, estimate from elevation angles
///     using Earth geometry.
double? estimateDistance({
  required double bearing1Deg,
  required double elevation1Deg,
  required double bearing2Deg,
  required double elevation2Deg,
  required double observerAltitudeM,
  double? horizonDistance1M,
  double? horizonDistance2M,
}) {
  if (horizonDistance1M != null && horizonDistance2M != null) {
    // Both points hit the horizon at known distances
    // Use law of cosines to compute ground distance
    final angleBetween = (bearing2Deg - bearing1Deg).abs() * deg2Rad;
    final d1 = horizonDistance1M;
    final d2 = horizonDistance2M;
    return math.sqrt(d1 * d1 + d2 * d2 - 2 * d1 * d2 * math.cos(angleBetween));
  }

  // Fallback: estimate from elevation angles
  // Distance ≈ altitude / tan(elevation) for distant objects
  double? dist1, dist2;
  if (elevation1Deg.abs() > 0.1) {
    dist1 = observerAltitudeM / math.tan(elevation1Deg.abs() * deg2Rad);
  }
  if (elevation2Deg.abs() > 0.1) {
    dist2 = observerAltitudeM / math.tan(elevation2Deg.abs() * deg2Rad);
  }

  if (dist1 != null && dist2 != null) {
    final angleBetween = (bearing2Deg - bearing1Deg).abs() * deg2Rad;
    return math.sqrt(
        dist1 * dist1 + dist2 * dist2 - 2 * dist1 * dist2 * math.cos(angleBetween));
  }

  return null;
}

// -----------------------------------------------------------------------
//  Ruler state management
// -----------------------------------------------------------------------

/// Manages the ruler tool state: tap points, measurements, display.
class RulerState {
  const RulerState({
    this.firstTap,
    this.secondTap,
    this.measurement,
    this.isActive = false,
  });

  /// First tap point (screen coordinates).
  final Offset? firstTap;

  /// Second tap point (screen coordinates).
  final Offset? secondTap;

  /// Computed measurement (available after both taps).
  final RulerMeasurement? measurement;

  /// Whether the ruler tool is active (accepting taps).
  final bool isActive;

  /// Whether we have a complete measurement.
  bool get hasMeasurement => measurement != null;

  /// Whether we're waiting for the second tap.
  bool get waitingForSecondTap => firstTap != null && secondTap == null;

  RulerState copyWith({
    Offset? firstTap,
    Offset? secondTap,
    RulerMeasurement? measurement,
    bool? isActive,
  }) {
    return RulerState(
      firstTap: firstTap ?? this.firstTap,
      secondTap: secondTap ?? this.secondTap,
      measurement: measurement ?? this.measurement,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Reset to initial state (clear measurement, keep active).
  RulerState clear() => RulerState(isActive: isActive);
}

// -----------------------------------------------------------------------
//  Ruler painter
// -----------------------------------------------------------------------

/// Draws the ruler measurement line and labels on the AR overlay.
class RulerPainter extends CustomPainter {
  RulerPainter({
    required this.measurement,
    this.lineColor = Colors.yellowAccent,
    this.lineWidth = 2.0,
    this.formatDistance,
    this.formatElevation,
  });

  final RulerMeasurement measurement;
  final Color lineColor;
  final double lineWidth;

  /// Optional formatting functions (from AppSettings).
  final String Function(double meters)? formatDistance;
  final String Function(double meters)? formatElevation;

  @override
  void paint(Canvas canvas, Size size) {
    final start = measurement.startScreen;
    final end = measurement.endScreen;

    // Draw the measurement line
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, linePaint);

    // Draw endpoint dots
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(start, 5, dotPaint);
    canvas.drawCircle(end, 5, dotPaint);

    // Draw measurement label at the midpoint
    final mid = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );

    final label = _buildLabel();
    _drawLabelWithBackground(canvas, label, mid);
  }

  String _buildLabel() {
    final parts = <String>[];

    // Distance
    final dist = measurement.distanceM;
    if (dist != null) {
      final formatted = formatDistance != null
          ? formatDistance!(dist)
          : _defaultFormatDistance(dist);
      parts.add(formatted);
    }

    // Elevation difference
    final elevDiff = measurement.elevationDiffM;
    if (elevDiff != null) {
      final sign = elevDiff >= 0 ? '+' : '';
      final formatted = formatElevation != null
          ? '$sign${formatElevation!(elevDiff.abs())}'
          : '$sign${_defaultFormatElevation(elevDiff)}';
      parts.add(formatted);
    }

    // Angular separation (always available)
    parts.add('${measurement.angularSeparationDeg.toStringAsFixed(1)}°');

    return parts.join('  ');
  }

  String _defaultFormatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _defaultFormatElevation(double meters) {
    return '${meters.toStringAsFixed(0)}m';
  }

  void _drawLabelWithBackground(Canvas canvas, String text, Offset position) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 4,
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    // Background pill
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(position.dx, position.dy - 16),
        width: textPainter.width + 16,
        height: textPainter.height + 8,
      ),
      const Radius.circular(10),
    );

    canvas.drawRRect(
      bgRect,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - 16 - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(RulerPainter oldDelegate) =>
      measurement != oldDelegate.measurement;
}
