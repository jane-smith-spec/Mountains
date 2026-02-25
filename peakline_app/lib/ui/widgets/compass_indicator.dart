/// Compass indicator — shows the current heading as a rotating compass.
///
/// Positioned at the top center of the live view, this widget shows
/// a compact compass rose that rotates with the device heading,
/// plus a numeric readout and cardinal direction label.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compact compass indicator for the live AR view.
class CompassIndicator extends StatelessWidget {
  const CompassIndicator({
    super.key,
    required this.headingDeg,
  });

  /// Current compass heading in degrees (0 = North).
  final double headingDeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rotating compass needle
          Transform.rotate(
            angle: -headingDeg * math.pi / 180.0,
            child: const Icon(
              Icons.navigation,
              color: Color(0xFFFF6B35),
              size: 18,
            ),
          ),
          const SizedBox(width: 6),
          // Heading and cardinal direction
          Text(
            '${headingDeg.toStringAsFixed(0)}° ${_cardinalLabel(headingDeg)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _cardinalLabel(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading < 67.5) return 'NE';
    if (heading < 112.5) return 'E';
    if (heading < 157.5) return 'SE';
    if (heading < 202.5) return 'S';
    if (heading < 247.5) return 'SW';
    if (heading < 292.5) return 'W';
    return 'NW';
  }
}
