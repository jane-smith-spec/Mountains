/// Elevation readout — shows the observer's current altitude.
///
/// A small widget that displays the GPS altitude in meters,
/// positioned at the bottom-left of the live view.
library;

import 'package:flutter/material.dart';

/// Compact elevation readout for the live AR view.
class ElevationReadout extends StatelessWidget {
  const ElevationReadout({
    super.key,
    required this.altitudeM,
    this.accuracyM,
  });

  /// Altitude in meters above sea level.
  final double altitudeM;

  /// GPS accuracy in meters (shown as ± if provided).
  final double? accuracyM;

  @override
  Widget build(BuildContext context) {
    final accuracyStr = accuracyM != null
        ? ' ±${accuracyM!.toStringAsFixed(0)}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.height,
            color: Colors.white70,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${altitudeM.toStringAsFixed(0)} m$accuracyStr',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
