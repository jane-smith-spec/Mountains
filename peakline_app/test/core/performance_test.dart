import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/core/performance.dart';
import 'package:peakline_app/core/projection.dart';

void main() {
  group('FrameBudgetTracker', () {
    test('average is zero initially', () {
      final tracker = FrameBudgetTracker();
      expect(tracker.averageFrameTimeMs, 0);
      expect(tracker.isDroppingFrames, false);
    });

    test('records frame times and computes average', () {
      final tracker = FrameBudgetTracker();

      tracker.recordFrame(10.0);
      tracker.recordFrame(20.0);
      expect(tracker.averageFrameTimeMs, 15.0);
    });

    test('detects dropped frames when average exceeds target', () {
      final tracker = FrameBudgetTracker(targetFrameTimeMs: 16.0);

      for (int i = 0; i < 10; i++) {
        tracker.recordFrame(20.0); // 20ms per frame = too slow
      }

      expect(tracker.isDroppingFrames, true);
    });

    test('does not report dropped frames when under budget', () {
      final tracker = FrameBudgetTracker(targetFrameTimeMs: 16.0);

      for (int i = 0; i < 10; i++) {
        tracker.recordFrame(8.0); // 8ms per frame = plenty fast
      }

      expect(tracker.isDroppingFrames, false);
    });

    test('rolling window only keeps recent frames', () {
      final tracker = FrameBudgetTracker(historySize: 5);

      // Record 5 fast frames
      for (int i = 0; i < 5; i++) {
        tracker.recordFrame(5.0);
      }
      expect(tracker.averageFrameTimeMs, 5.0);

      // Record 5 slow frames — old fast ones should be evicted
      for (int i = 0; i < 5; i++) {
        tracker.recordFrame(20.0);
      }
      expect(tracker.averageFrameTimeMs, 20.0);
    });

    test('recommends hold when not enough data', () {
      final tracker = FrameBudgetTracker(historySize: 30);
      tracker.recordFrame(10.0);
      expect(tracker.recommendation, QualityAction.hold);
    });

    test('recommends decrease when too slow', () {
      final tracker = FrameBudgetTracker(
        historySize: 10,
        downgradeThresholdMs: 14.0,
      );

      for (int i = 0; i < 10; i++) {
        tracker.recordFrame(15.0);
      }

      expect(tracker.recommendation, QualityAction.decrease);
    });

    test('recommends increase when very fast', () {
      final tracker = FrameBudgetTracker(
        historySize: 10,
        upgradeThresholdMs: 10.0,
      );

      for (int i = 0; i < 10; i++) {
        tracker.recordFrame(5.0);
      }

      expect(tracker.recommendation, QualityAction.increase);
    });

    test('reset clears history', () {
      final tracker = FrameBudgetTracker();
      tracker.recordFrame(10.0);
      tracker.reset();
      expect(tracker.averageFrameTimeMs, 0);
    });
  });

  group('QualityLevel', () {
    test('low has most aggressive settings', () {
      expect(QualityLevel.low.horizonPointSkip, 4);
      expect(QualityLevel.low.maxVisiblePeaks, 5);
      expect(QualityLevel.low.enableFill, false);
      expect(QualityLevel.low.enableGrid, false);
    });

    test('high has full detail', () {
      expect(QualityLevel.high.horizonPointSkip, 1);
      expect(QualityLevel.high.maxVisiblePeaks, 30);
      expect(QualityLevel.high.enableFill, true);
      expect(QualityLevel.high.enableGrid, true);
    });

    test('lower from low stays at low', () {
      expect(QualityLevel.low.lower, QualityLevel.low);
    });

    test('higher from high stays at high', () {
      expect(QualityLevel.high.higher, QualityLevel.high);
    });

    test('lower from high goes to medium', () {
      expect(QualityLevel.high.lower, QualityLevel.medium);
    });

    test('higher from low goes to medium', () {
      expect(QualityLevel.low.higher, QualityLevel.medium);
    });
  });

  group('AdaptiveQuality', () {
    test('starts at high quality', () {
      final adaptive = AdaptiveQuality();
      expect(adaptive.level, QualityLevel.high);
    });

    test('can start at a specific level', () {
      final adaptive = AdaptiveQuality(initial: QualityLevel.low);
      expect(adaptive.level, QualityLevel.low);
    });

    test('does not change quality too quickly (cooldown)', () {
      final adaptive = AdaptiveQuality();

      // Record a few slow frames (not enough to trigger change)
      for (int i = 0; i < 10; i++) {
        adaptive.recordFrame(20.0);
      }

      // Quality should still be high (cooldown not elapsed)
      expect(adaptive.level, QualityLevel.high);
    });

    test('decreases quality after enough slow frames', () {
      final adaptive = AdaptiveQuality();

      // Record many slow frames to exceed cooldown
      for (int i = 0; i < 100; i++) {
        adaptive.recordFrame(18.0);
      }

      // Should have decreased at least once
      expect(adaptive.level, isNot(QualityLevel.high));
    });

    test('setLevel forces a specific level', () {
      final adaptive = AdaptiveQuality();
      adaptive.setLevel(QualityLevel.low);
      expect(adaptive.level, QualityLevel.low);
    });

    test('reset returns to high quality', () {
      final adaptive = AdaptiveQuality();
      adaptive.setLevel(QualityLevel.low);
      adaptive.reset();
      expect(adaptive.level, QualityLevel.high);
    });
  });

  group('ProjectionCache', () {
    test('returns null when empty', () {
      final cache = ProjectionCache();
      expect(
        cache.getCachedPoints(headingDeg: 90.0, pitchDeg: 0.0),
        isNull,
      );
    });

    test('returns cached points when heading/pitch unchanged', () {
      final cache = ProjectionCache();
      final points = [const ScreenPoint(x: 100, y: 200, isVisible: true)];

      cache.update(headingDeg: 90.0, pitchDeg: 0.0, points: points);

      final cached = cache.getCachedPoints(headingDeg: 90.0, pitchDeg: 0.0);
      expect(cached, isNotNull);
      expect(cached!.length, 1);
      expect(cached[0].x, 100);
    });

    test('returns cached points when within tolerance', () {
      final cache = ProjectionCache(
        headingToleranceDeg: 0.1,
        pitchToleranceDeg: 0.1,
      );
      final points = [const ScreenPoint(x: 100, y: 200, isVisible: true)];

      cache.update(headingDeg: 90.0, pitchDeg: 0.0, points: points);

      // Within tolerance
      final cached = cache.getCachedPoints(
        headingDeg: 90.05,
        pitchDeg: 0.03,
      );
      expect(cached, isNotNull);
    });

    test('returns null when heading changes beyond tolerance', () {
      final cache = ProjectionCache(headingToleranceDeg: 0.1);
      final points = [const ScreenPoint(x: 100, y: 200, isVisible: true)];

      cache.update(headingDeg: 90.0, pitchDeg: 0.0, points: points);

      final cached = cache.getCachedPoints(headingDeg: 91.0, pitchDeg: 0.0);
      expect(cached, isNull);
    });

    test('handles north wrap-around', () {
      final cache = ProjectionCache(headingToleranceDeg: 1.0);
      final points = [const ScreenPoint(x: 100, y: 200, isVisible: true)];

      cache.update(headingDeg: 359.5, pitchDeg: 0.0, points: points);

      // 0.5° is within 1° tolerance despite numeric difference of 359
      final cached = cache.getCachedPoints(headingDeg: 0.5, pitchDeg: 0.0);
      expect(cached, isNotNull);
    });

    test('invalidate clears cache', () {
      final cache = ProjectionCache();
      final points = [const ScreenPoint(x: 100, y: 200, isVisible: true)];

      cache.update(headingDeg: 90.0, pitchDeg: 0.0, points: points);
      cache.invalidate();

      expect(
        cache.getCachedPoints(headingDeg: 90.0, pitchDeg: 0.0),
        isNull,
      );
    });
  });
}
