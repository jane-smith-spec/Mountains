/// Skyline lock — snaps the computed topo line to actual mountain edges.
///
/// ## The Problem
///
/// The horizon overlay is computed from DEM data and projected using
/// compass/accelerometer heading. But sensor errors (even after Kalman
/// filtering) mean the topo line drifts a few pixels from the real
/// mountain silhouette in the camera feed.
///
/// ## The Solution: Edge-Based Correction
///
/// We extract high-contrast horizontal edges from the camera frame
/// (these tend to be mountain ridgelines against the sky). Then we
/// compute a vertical offset that best aligns our projected topo
/// line with those edges.
///
/// This is a 1D correlation — we only correct vertical offset (pitch),
/// not horizontal (heading), because:
///   1. Heading from compass is more reliable than pitch from accelerometer
///   2. The horizon line is mostly horizontal, so vertical shift is most visible
///   3. A 1D search is fast enough for real-time (60 fps)
///
/// ## Algorithm
///
///   1. Take a horizontal strip of the camera image around the predicted
///      topo line position.
///   2. Compute vertical gradient (Sobel-y) — highlights horizontal edges.
///   3. Sum gradient magnitudes along each row → 1D "edge strength" signal.
///   4. Compute 1D cross-correlation between the edge signal and the
///      projected topo line's Y-values.
///   5. The shift with maximum correlation is the correction offset.
///   6. Clamp to a max correction (don't jump wildly on noise).
///   7. Apply exponential smoothing to avoid frame-to-frame jitter.
library;

import 'dart:math' as math;

import '../core/projection.dart';

/// Configuration for the skyline lock algorithm.
class SkylineLockConfig {
  const SkylineLockConfig({
    this.searchRangePx = 30,
    this.maxCorrectionPx = 15.0,
    this.smoothingFactor = 0.3,
    this.minEdgeStrength = 10.0,
    this.stripHeightPx = 60,
  });

  /// How many pixels above/below the predicted line to search.
  final int searchRangePx;

  /// Maximum pixel correction we'll apply in a single frame.
  final double maxCorrectionPx;

  /// Exponential smoothing: 0 = ignore new data, 1 = no smoothing.
  final double smoothingFactor;

  /// Minimum edge strength to consider a valid lock.
  /// Below this, the correction is zeroed (no edges found → don't correct).
  final double minEdgeStrength;

  /// Height of the image strip to analyze around the predicted line.
  final int stripHeightPx;
}

/// Result of a skyline lock computation.
class SkylineLockResult {
  const SkylineLockResult({
    required this.offsetPx,
    required this.confidence,
    required this.isLocked,
  });

  /// Vertical pixel offset to apply to the topo line.
  /// Positive = shift down, negative = shift up.
  final double offsetPx;

  /// How confident the lock is (0–1). Based on correlation strength.
  final double confidence;

  /// Whether the lock is active (enough edge strength was found).
  final bool isLocked;

  static const SkylineLockResult none = SkylineLockResult(
    offsetPx: 0,
    confidence: 0,
    isLocked: false,
  );
}

/// Computes vertical offset to snap the topo line to real mountain edges.
class SkylineLock {
  SkylineLock({this.config = const SkylineLockConfig()});

  final SkylineLockConfig config;

  double _smoothedOffset = 0.0;

  /// Current smoothed offset in pixels.
  double get currentOffsetPx => _smoothedOffset;

  /// Compute the correction offset from edge data and projected topo line.
  ///
  /// [edgeStrengthByRow] — vertical gradient magnitude summed per row,
  ///   for a strip of height [config.stripHeightPx] centered on the
  ///   predicted topo line. Index 0 = top of strip.
  ///
  /// [topoLineYValues] — Y pixel positions of the projected topo line,
  ///   one per column (or sampled). These are relative to the strip center.
  ///
  /// Returns a [SkylineLockResult] with the pixel correction to apply.
  SkylineLockResult computeOffset({
    required List<double> edgeStrengthByRow,
    required List<double> topoLineYValues,
  }) {
    if (edgeStrengthByRow.isEmpty || topoLineYValues.isEmpty) {
      return SkylineLockResult.none;
    }

    // Check if there are enough edges to be meaningful
    final maxEdge = edgeStrengthByRow.reduce(math.max);
    if (maxEdge < config.minEdgeStrength) {
      // No strong edges found — decay toward zero
      _smoothedOffset *= (1 - config.smoothingFactor);
      return SkylineLockResult(
        offsetPx: _smoothedOffset,
        confidence: 0,
        isLocked: false,
      );
    }

    // The topo line center in strip coordinates
    final stripCenter = config.stripHeightPx / 2.0;

    // Compute average Y offset of the topo line relative to strip center
    final avgTopoY = topoLineYValues.isEmpty
        ? 0.0
        : topoLineYValues.reduce((a, b) => a + b) / topoLineYValues.length;

    // 1D cross-correlation: slide the topo-line shape vertically
    // and find the offset where it best matches edge peaks
    double bestCorrelation = -1.0;
    int bestShift = 0;

    for (int shift = -config.searchRangePx;
        shift <= config.searchRangePx;
        shift++) {
      double correlation = 0;
      int count = 0;

      for (final topoY in topoLineYValues) {
        // Where this topo point would land in the strip with this shift
        final row = (stripCenter + (topoY - avgTopoY) + shift).round();
        if (row >= 0 && row < edgeStrengthByRow.length) {
          correlation += edgeStrengthByRow[row];
          count++;
        }
      }

      if (count > 0) {
        correlation /= count;
        if (correlation > bestCorrelation) {
          bestCorrelation = correlation;
          bestShift = shift;
        }
      }
    }

    // Clamp the correction
    final rawOffset = bestShift.toDouble();
    final clampedOffset = rawOffset.clamp(
      -config.maxCorrectionPx,
      config.maxCorrectionPx,
    );

    // Exponential smoothing
    _smoothedOffset = _smoothedOffset * (1 - config.smoothingFactor) +
        clampedOffset * config.smoothingFactor;

    // Confidence: normalize the correlation score
    final confidence = (bestCorrelation / maxEdge).clamp(0.0, 1.0);

    return SkylineLockResult(
      offsetPx: _smoothedOffset,
      confidence: confidence,
      isLocked: true,
    );
  }

  /// Apply the skyline lock offset to a list of projected screen points.
  ///
  /// Returns a new list with Y coordinates shifted by the current offset.
  List<ScreenPoint> applyToPoints(List<ScreenPoint> points) {
    if (_smoothedOffset.abs() < 0.5) return points;

    return points
        .map((p) => ScreenPoint(
              x: p.x,
              y: p.y + _smoothedOffset,
              isVisible: p.isVisible,
            ))
        .toList();
  }

  /// Reset the lock (e.g., when the camera view changes significantly).
  void reset() {
    _smoothedOffset = 0.0;
  }
}
