/// Performance optimization utilities.
///
/// This module provides:
///   1. **Frame budget tracker** — monitors how long each frame takes and
///      warns when we're exceeding the 16ms budget (60 fps target).
///   2. **Adaptive quality** — automatically reduces drawing detail when
///      frames are too slow (fewer horizon points, simpler painting).
///   3. **Projection cache** — avoids re-projecting horizon points when
///      the heading/pitch hasn't changed enough to matter.
///
/// ## Why This Matters
///
/// The AR overlay runs every frame (60 fps). Each frame must:
///   1. Read sensors (~0.5ms)
///   2. Project horizon points to screen (~1-3ms for 3600 points)
///   3. Paint the horizon line (~1ms)
///   4. Paint peak labels (~0.5ms per visible peak)
///   5. Composite with camera preview (~2ms)
///
/// Total budget: 16ms. If we exceed it, frames drop and the overlay
/// feels laggy. The adaptive quality system keeps us in budget.
library;

import 'dart:collection';

import '../core/projection.dart';

/// Tracks frame timing and recommends quality adjustments.
class FrameBudgetTracker {
  FrameBudgetTracker({
    this.targetFrameTimeMs = 16.0,
    this.historySize = 30,
    this.downgradeThresholdMs = 14.0,
    this.upgradeThresholdMs = 10.0,
  });

  /// Target frame time in milliseconds (16ms = 60fps).
  final double targetFrameTimeMs;

  /// Number of frame times to keep in the rolling window.
  final int historySize;

  /// If average frame time exceeds this, suggest lower quality.
  final double downgradeThresholdMs;

  /// If average frame time is below this, suggest higher quality.
  final double upgradeThresholdMs;

  final Queue<double> _frameTimes = Queue();

  /// Record a frame's total render time.
  void recordFrame(double frameTimeMs) {
    _frameTimes.addLast(frameTimeMs);
    while (_frameTimes.length > historySize) {
      _frameTimes.removeFirst();
    }
  }

  /// Average frame time over the recent window.
  double get averageFrameTimeMs {
    if (_frameTimes.isEmpty) return 0;
    return _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
  }

  /// Whether we're dropping frames (average exceeds target).
  bool get isDroppingFrames => averageFrameTimeMs > targetFrameTimeMs;

  /// Recommended quality adjustment.
  QualityAction get recommendation {
    if (_frameTimes.length < historySize ~/ 2) return QualityAction.hold;
    final avg = averageFrameTimeMs;
    if (avg > downgradeThresholdMs) return QualityAction.decrease;
    if (avg < upgradeThresholdMs) return QualityAction.increase;
    return QualityAction.hold;
  }

  /// Reset frame history.
  void reset() => _frameTimes.clear();
}

/// What the adaptive quality system recommends.
enum QualityAction { increase, hold, decrease }

/// Quality level that controls drawing detail.
enum QualityLevel {
  low(
    label: 'Low',
    horizonPointSkip: 4,
    maxVisiblePeaks: 5,
    enableFill: false,
    enableGrid: false,
  ),
  medium(
    label: 'Medium',
    horizonPointSkip: 2,
    maxVisiblePeaks: 15,
    enableFill: true,
    enableGrid: false,
  ),
  high(
    label: 'High',
    horizonPointSkip: 1,
    maxVisiblePeaks: 30,
    enableFill: true,
    enableGrid: true,
  );

  const QualityLevel({
    required this.label,
    required this.horizonPointSkip,
    required this.maxVisiblePeaks,
    required this.enableFill,
    required this.enableGrid,
  });

  final String label;

  /// Skip every N-th horizon point when drawing (1 = draw all).
  final int horizonPointSkip;

  /// Maximum number of peak labels to draw simultaneously.
  final int maxVisiblePeaks;

  /// Whether to draw the terrain fill below the horizon line.
  final bool enableFill;

  /// Whether to draw the bearing/elevation grid.
  final bool enableGrid;

  /// Get the next lower quality level.
  QualityLevel get lower {
    final idx = QualityLevel.values.indexOf(this);
    if (idx == 0) return this;
    return QualityLevel.values[idx - 1];
  }

  /// Get the next higher quality level.
  QualityLevel get higher {
    final idx = QualityLevel.values.indexOf(this);
    if (idx == QualityLevel.values.length - 1) return this;
    return QualityLevel.values[idx + 1];
  }
}

/// Manages adaptive quality based on frame timing.
class AdaptiveQuality {
  AdaptiveQuality({QualityLevel initial = QualityLevel.high})
      : _currentLevel = initial;

  final FrameBudgetTracker _tracker = FrameBudgetTracker();
  QualityLevel _currentLevel;

  // Cooldown to avoid rapid oscillation between levels
  int _framesSinceLastChange = 0;
  static const _changeCooldownFrames = 60; // ~1 second at 60fps

  /// The current quality level.
  QualityLevel get level => _currentLevel;

  /// Record a frame time and potentially adjust quality.
  void recordFrame(double frameTimeMs) {
    _tracker.recordFrame(frameTimeMs);
    _framesSinceLastChange++;

    if (_framesSinceLastChange < _changeCooldownFrames) return;

    final action = _tracker.recommendation;
    if (action == QualityAction.decrease && _currentLevel != QualityLevel.low) {
      _currentLevel = _currentLevel.lower;
      _framesSinceLastChange = 0;
    } else if (action == QualityAction.increase &&
        _currentLevel != QualityLevel.high) {
      _currentLevel = _currentLevel.higher;
      _framesSinceLastChange = 0;
    }
  }

  /// Whether we're currently dropping frames.
  bool get isDroppingFrames => _tracker.isDroppingFrames;

  /// Average frame time in ms.
  double get averageFrameTimeMs => _tracker.averageFrameTimeMs;

  /// Force a specific quality level.
  void setLevel(QualityLevel level) {
    _currentLevel = level;
    _framesSinceLastChange = 0;
  }

  void reset() {
    _tracker.reset();
    _currentLevel = QualityLevel.high;
    _framesSinceLastChange = 0;
  }
}

/// Caches projected screen points and reuses them when heading/pitch
/// hasn't changed enough to matter.
///
/// The projection (azimuth/elevation → screen pixels) is pure math
/// and runs every frame. But if the phone moved < 0.1° since the last
/// frame, the output is essentially the same. Caching avoids redoing
/// the math for 3600 points every 16ms.
class ProjectionCache {
  ProjectionCache({
    this.headingToleranceDeg = 0.05,
    this.pitchToleranceDeg = 0.05,
  });

  final double headingToleranceDeg;
  final double pitchToleranceDeg;

  double? _lastHeadingDeg;
  double? _lastPitchDeg;
  List<ScreenPoint>? _cachedPoints;

  /// Get cached points if heading/pitch hasn't changed enough.
  /// Returns null if the cache is stale (caller should recompute).
  List<ScreenPoint>? getCachedPoints({
    required double headingDeg,
    required double pitchDeg,
  }) {
    if (_cachedPoints == null) return null;

    final dHeading = (headingDeg - (_lastHeadingDeg ?? 0)).abs();
    final dPitch = (pitchDeg - (_lastPitchDeg ?? 0)).abs();

    // Handle 0°/360° wrap for heading
    final wrappedDHeading = dHeading > 180 ? 360 - dHeading : dHeading;

    if (wrappedDHeading <= headingToleranceDeg &&
        dPitch <= pitchToleranceDeg) {
      return _cachedPoints;
    }

    return null;
  }

  /// Store new projected points.
  void update({
    required double headingDeg,
    required double pitchDeg,
    required List<ScreenPoint> points,
  }) {
    _lastHeadingDeg = headingDeg;
    _lastPitchDeg = pitchDeg;
    _cachedPoints = points;
  }

  /// Clear the cache.
  void invalidate() {
    _cachedPoints = null;
    _lastHeadingDeg = null;
    _lastPitchDeg = null;
  }
}
