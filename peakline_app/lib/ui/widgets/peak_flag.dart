/// Peak flag widget — a label that appears over a peak in the AR view.
///
/// Shows the peak name, elevation, and distance in a compact flag
/// that points down toward the peak's screen position. The flag is
/// designed to be readable against both sky and terrain backgrounds.
library;

import 'package:flutter/material.dart';

import '../../services/peak_visibility_service.dart';

/// Displays a peak label at its projected screen position.
///
/// Layout:
/// ```
///  ┌─────────────────┐
///  │ Matterhorn       │
///  │ 4478 m · 12.3 km │
///  └────────┬────────┘
///           │  (points at peak)
/// ```
class PeakFlag extends StatelessWidget {
  const PeakFlag({
    super.key,
    required this.visiblePeak,
    this.color = const Color(0xFFFF6B35),
  });

  final VisiblePeak visiblePeak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Offset so the flag sits ABOVE the peak position
      left: visiblePeak.screenPoint.x - 60,
      top: visiblePeak.screenPoint.y - 65,
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flag body
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color, width: 1.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Peak name
                  Text(
                    visiblePeak.peak.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 1),
                  // Elevation and distance
                  Text(
                    '${visiblePeak.peak.elevationM.toStringAsFixed(0)} m · '
                    '${visiblePeak.distanceLabel}',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.9),
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // Stem pointing down to the peak
            CustomPaint(
              size: const Size(12, 8),
              painter: _StemPainter(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the small triangle stem below the flag.
class _StemPainter extends CustomPainter {
  _StemPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2 - 5, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 5, 0)
      ..close();

    canvas.drawPath(path, paint);

    // Border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final borderPath = Path()
      ..moveTo(size.width / 2 - 5, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 5, 0);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(_StemPainter oldDelegate) => color != oldDelegate.color;
}
