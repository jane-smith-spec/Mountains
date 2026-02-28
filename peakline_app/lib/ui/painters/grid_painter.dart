/// Grid painter — draws bearing and elevation reference lines on the AR view.
///
/// This optional overlay helps users orient themselves by showing:
///   - **Vertical lines** at regular compass bearings (every 30° or 10°)
///     with labels like "N", "NE", "E", "90°", etc.
///   - **Horizontal lines** at regular elevation angles (every 5° or 1°)
///     with labels like "+5°", "0°", "-5°".
///   - A prominent **horizon line** at 0° elevation.
///
/// The grid scrolls as the phone turns — bearings that enter the camera's
/// field of view slide in from the edges.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/sensor_data.dart';

/// Draws a bearing/elevation reference grid on the camera preview.
class GridPainter extends CustomPainter {
  GridPainter({
    required this.headingDeg,
    required this.pitchDeg,
    required this.hFovDeg,
    required this.vFovDeg,
    this.bearingIntervalDeg = 30.0,
    this.elevationIntervalDeg = 5.0,
    this.showCardinals = true,
    this.gridColor = Colors.white38,
    this.labelColor = Colors.white70,
    this.horizonColor = Colors.white54,
  });

  /// Current compass heading of the camera center (0-360).
  final double headingDeg;

  /// Current pitch of the camera center.
  final double pitchDeg;

  /// Horizontal field of view in degrees.
  final double hFovDeg;

  /// Vertical field of view in degrees.
  final double vFovDeg;

  /// Degrees between vertical bearing lines.
  final double bearingIntervalDeg;

  /// Degrees between horizontal elevation lines.
  final double elevationIntervalDeg;

  /// Whether to show cardinal direction labels (N, E, S, W).
  final bool showCardinals;

  /// Color of the grid lines.
  final Color gridColor;

  /// Color of the bearing/elevation labels.
  final Color labelColor;

  /// Color of the 0° horizon line.
  final Color horizonColor;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBearingLines(canvas, size);
    _drawElevationLines(canvas, size);
  }

  /// Draw vertical lines at regular bearing intervals.
  void _drawBearingLines(Canvas canvas, Size size) {
    final halfFov = hFovDeg / 2.0;
    final minBearing = headingDeg - halfFov - bearingIntervalDeg;
    final maxBearing = headingDeg + halfFov + bearingIntervalDeg;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final cardinalPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Find the first bearing line that falls within the view
    final startBearing = (minBearing / bearingIntervalDeg).floor() *
        bearingIntervalDeg;

    for (double bearing = startBearing;
        bearing <= maxBearing;
        bearing += bearingIntervalDeg) {
      // Normalize bearing to 0-360
      double normBearing = bearing % 360;
      if (normBearing < 0) normBearing += 360;

      // Compute screen x position
      double relBearing = bearing - headingDeg;
      // Handle wrap-around
      while (relBearing > 180) {
        relBearing -= 360;
      }
      while (relBearing < -180) {
        relBearing += 360;
      }

      if (relBearing.abs() > halfFov) continue;

      final x = ((relBearing / halfFov) + 1.0) * 0.5 * size.width;

      // Determine if this is a cardinal direction
      final isCardinal = _isCardinalBearing(normBearing);
      final paint = isCardinal ? cardinalPaint : gridPaint;

      // Draw the vertical line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );

      // Draw the bearing label
      final label = showCardinals && isCardinal
          ? _cardinalLabel(normBearing)
          : '${normBearing.toStringAsFixed(0)}°';

      _drawLabel(
        canvas,
        label,
        Offset(x, size.height - 24),
        isCardinal ? 12.0 : 10.0,
        isCardinal,
      );
    }
  }

  /// Draw horizontal lines at regular elevation angles.
  void _drawElevationLines(Canvas canvas, Size size) {
    final halfVFov = vFovDeg / 2.0;
    final minElev = pitchDeg - halfVFov - elevationIntervalDeg;
    final maxElev = pitchDeg + halfVFov + elevationIntervalDeg;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final horizonPaint = Paint()
      ..color = horizonColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final startElev = (minElev / elevationIntervalDeg).floor() *
        elevationIntervalDeg;

    for (double elev = startElev;
        elev <= maxElev;
        elev += elevationIntervalDeg) {
      final relElev = elev - pitchDeg;
      if (relElev.abs() > halfVFov) continue;

      // Screen y: positive elevation = higher on screen
      final y = (1.0 - ((relElev / halfVFov) + 1.0) * 0.5) * size.height;

      final isHorizon = elev.abs() < 0.01;
      final paint = isHorizon ? horizonPaint : gridPaint;

      // Draw the horizontal line
      if (isHorizon) {
        // Dashed horizon line
        _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), paint);
      } else {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }

      // Draw the elevation label
      final label = isHorizon
          ? 'HORIZON'
          : '${elev >= 0 ? "+" : ""}${elev.toStringAsFixed(0)}°';

      _drawLabel(
        canvas,
        label,
        Offset(8, y - 14),
        isHorizon ? 11.0 : 10.0,
        isHorizon,
      );
    }
  }

  /// Draw a text label at the given position.
  void _drawLabel(
    Canvas canvas,
    String text,
    Offset position,
    double fontSize,
    bool bold,
  ) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: labelColor,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ))
      ..addText(text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 80));

    canvas.drawParagraph(paragraph, position);
  }

  /// Draw a dashed line between two points.
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 4.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final totalLength = (dx * dx + dy * dy);
    if (totalLength == 0) return;

    final length = totalLength > 0 ? totalLength : 1.0;
    final unitDx = dx / length;
    final unitDy = dy / length;

    double currentLength = 0;
    while (currentLength < length) {
      final segEnd = (currentLength + dashLength).clamp(0, length);
      canvas.drawLine(
        Offset(
          start.dx + unitDx * currentLength,
          start.dy + unitDy * currentLength,
        ),
        Offset(
          start.dx + unitDx * segEnd,
          start.dy + unitDy * segEnd,
        ),
        paint,
      );
      currentLength += dashLength + gapLength;
    }
  }

  /// Check if a bearing is a cardinal or intercardinal direction.
  bool _isCardinalBearing(double bearing) {
    const cardinals = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0];
    for (final c in cardinals) {
      if ((bearing - c).abs() < 0.5) return true;
    }
    return false;
  }

  /// Get the label for a cardinal bearing.
  String _cardinalLabel(double bearing) {
    final rounded = (bearing % 360).round();
    switch (rounded) {
      case 0:
      case 360:
        return 'N';
      case 45:
        return 'NE';
      case 90:
        return 'E';
      case 135:
        return 'SE';
      case 180:
        return 'S';
      case 225:
        return 'SW';
      case 270:
        return 'W';
      case 315:
        return 'NW';
      default:
        return '${rounded}°';
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) {
    return headingDeg != oldDelegate.headingDeg ||
        pitchDeg != oldDelegate.pitchDeg ||
        hFovDeg != oldDelegate.hFovDeg ||
        vFovDeg != oldDelegate.vFovDeg;
  }
}
