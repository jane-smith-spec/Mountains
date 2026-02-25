/// Horizon painter — draws the topographic horizon line on the camera view.
///
/// This CustomPainter takes a list of screen-projected horizon points
/// and draws them as a smooth polyline over the camera preview. The
/// line represents the mountain ridgeline — what you'd trace if you
/// drew along the top of every mountain in your field of view.
///
/// The painter also fills the area below the line with a semi-transparent
/// gradient to make the terrain stand out against the sky.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/projection.dart';

/// Draws the horizon profile as a polyline on a Canvas.
///
/// Used inside a [CustomPaint] widget, which is layered on top of the
/// camera preview in the live view screen.
class HorizonPainter extends CustomPainter {
  HorizonPainter({
    required this.points,
    this.lineColor = const Color(0xFFFF6B35),
    this.lineWidth = 2.5,
    this.fillOpacity = 0.15,
    this.showFill = true,
  });

  /// Screen-projected horizon points to draw.
  final List<ScreenPoint> points;

  /// Color of the horizon line.
  final Color lineColor;

  /// Width of the horizon line in logical pixels.
  final double lineWidth;

  /// Opacity of the terrain fill below the line (0.0–1.0).
  final double fillOpacity;

  /// Whether to draw the semi-transparent fill below the line.
  final bool showFill;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Sort points by x coordinate for a clean left-to-right polyline.
    final sorted = List<ScreenPoint>.from(points)
      ..sort((a, b) => a.x.compareTo(b.x));

    // Build the horizon line path
    final linePath = Path();
    linePath.moveTo(sorted.first.x, sorted.first.y);

    for (int i = 1; i < sorted.length; i++) {
      // Skip points that are too far apart horizontally — they'd create
      // visual artifacts when the profile wraps around or has gaps.
      final dx = (sorted[i].x - sorted[i - 1].x).abs();
      if (dx > size.width * 0.3) {
        linePath.moveTo(sorted[i].x, sorted[i].y);
      } else {
        linePath.lineTo(sorted[i].x, sorted[i].y);
      }
    }

    // Draw the fill below the line (terrain area)
    if (showFill && fillOpacity > 0) {
      final fillPath = Path.from(linePath);
      // Close the path along the bottom of the screen
      fillPath.lineTo(sorted.last.x, size.height);
      fillPath.lineTo(sorted.first.x, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.3),
          Offset(0, size.height),
          [
            lineColor.withValues(alpha: fillOpacity),
            lineColor.withValues(alpha: 0.0),
          ],
        );

      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw the horizon line itself
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(linePath, linePaint);

    // Draw a subtle glow behind the line for better visibility
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth * 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..isAntiAlias = true;

    canvas.drawPath(linePath, glowPaint);
  }

  @override
  bool shouldRepaint(HorizonPainter oldDelegate) {
    // Repaint when the points change (camera moved) or style changed.
    // Comparing list references is fast — the projection code creates
    // a new list each time.
    return points != oldDelegate.points ||
        lineColor != oldDelegate.lineColor ||
        lineWidth != oldDelegate.lineWidth;
  }
}
