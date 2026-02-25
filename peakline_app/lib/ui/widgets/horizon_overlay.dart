/// Horizon overlay widget — the topo line drawn over the camera view.
///
/// This widget watches the horizon service and sensor providers, then
/// uses [HorizonPainter] to draw the projected horizon line on top of
/// the camera preview. It re-projects the profile on every sensor
/// update (heading/pitch change) for smooth tracking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/projection.dart';
import '../../models/sensor_data.dart';
import '../../services/horizon_service.dart';
import '../../services/sensor_service.dart';
import '../painters/horizon_painter.dart';

/// Overlays the horizon topo line on the camera preview.
///
/// This is a [ConsumerWidget] that:
///   1. Watches the device orientation (heading, pitch) for projection
///   2. Gets the cached horizon profile from the service
///   3. Re-projects the profile to screen coordinates each frame
///   4. Passes the points to [HorizonPainter] for drawing
class HorizonOverlay extends ConsumerWidget {
  const HorizonOverlay({
    super.key,
    this.lineColor = const Color(0xFFFF6B35),
    this.lineWidth = 2.5,
    this.showFill = true,
  });

  /// Color of the horizon line.
  final Color lineColor;

  /// Width of the horizon line in logical pixels.
  final double lineWidth;

  /// Whether to show the terrain fill below the line.
  final bool showFill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orientation = ref.watch(deviceOrientationProvider);
    final horizonService = ref.watch(horizonServiceProvider);

    return orientation.when(
      data: (o) => LayoutBuilder(
        builder: (context, constraints) {
          final camera = CameraViewParams.fromOrientation(
            orientation: o,
            screenWidth: constraints.maxWidth,
            screenHeight: constraints.maxHeight,
          );

          final screenPoints = horizonService.projectToScreen(camera: camera);

          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: HorizonPainter(
              points: screenPoints,
              lineColor: lineColor,
              lineWidth: lineWidth,
              showFill: showFill,
            ),
          );
        },
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
