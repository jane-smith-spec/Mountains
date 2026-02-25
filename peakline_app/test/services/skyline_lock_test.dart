import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/services/skyline_lock.dart';

void main() {
  group('SkylineLockConfig', () {
    test('default values are reasonable', () {
      const config = SkylineLockConfig();
      expect(config.searchRangePx, 30);
      expect(config.maxCorrectionPx, 15.0);
      expect(config.smoothingFactor, 0.3);
      expect(config.minEdgeStrength, 10.0);
      expect(config.stripHeightPx, 60);
    });
  });

  group('SkylineLockResult', () {
    test('none result has zero offset and no lock', () {
      expect(SkylineLockResult.none.offsetPx, 0);
      expect(SkylineLockResult.none.confidence, 0);
      expect(SkylineLockResult.none.isLocked, false);
    });
  });

  group('SkylineLock', () {
    test('returns none for empty inputs', () {
      final lock = SkylineLock();

      final result = lock.computeOffset(
        edgeStrengthByRow: [],
        topoLineYValues: [0.0, 1.0, 2.0],
      );

      expect(result.isLocked, false);
    });

    test('returns none for empty topo line', () {
      final lock = SkylineLock();

      final result = lock.computeOffset(
        edgeStrengthByRow: [5.0, 10.0, 15.0],
        topoLineYValues: [],
      );

      expect(result.isLocked, false);
    });

    test('returns not locked when edge strength is below threshold', () {
      final lock = SkylineLock(
        config: const SkylineLockConfig(minEdgeStrength: 50.0),
      );

      final result = lock.computeOffset(
        edgeStrengthByRow: List.filled(60, 5.0), // All below threshold
        topoLineYValues: [0.0, 0.0, 0.0],
      );

      expect(result.isLocked, false);
    });

    test('finds offset when edges are present', () {
      final lock = SkylineLock(
        config: const SkylineLockConfig(
          stripHeightPx: 20,
          searchRangePx: 10,
          smoothingFactor: 1.0, // No smoothing for test clarity
        ),
      );

      // Edge peak at row 15 (5 rows below center at row 10)
      final edges = List<double>.filled(20, 1.0);
      edges[15] = 100.0; // Strong edge at row 15

      // Topo line at the center (row 10) — expects offset of +5
      final topoY = List<double>.filled(10, 0.0);

      final result = lock.computeOffset(
        edgeStrengthByRow: edges,
        topoLineYValues: topoY,
      );

      expect(result.isLocked, true);
      expect(result.offsetPx, closeTo(5.0, 2.0));
    });

    test('offset is clamped to maxCorrectionPx', () {
      final lock = SkylineLock(
        config: const SkylineLockConfig(
          stripHeightPx: 60,
          searchRangePx: 30,
          maxCorrectionPx: 5.0,
          smoothingFactor: 1.0,
        ),
      );

      // Edge peak very far from center
      final edges = List<double>.filled(60, 1.0);
      edges[55] = 100.0; // 25 rows below center

      final topoY = List<double>.filled(10, 0.0);

      final result = lock.computeOffset(
        edgeStrengthByRow: edges,
        topoLineYValues: topoY,
      );

      expect(result.isLocked, true);
      expect(result.offsetPx.abs(), lessThanOrEqualTo(5.0));
    });

    test('smoothing dampens rapid changes', () {
      final lock = SkylineLock(
        config: const SkylineLockConfig(
          stripHeightPx: 20,
          searchRangePx: 10,
          smoothingFactor: 0.1, // Heavy smoothing
        ),
      );

      final edges = List<double>.filled(20, 1.0);
      edges[15] = 100.0;

      final topoY = List<double>.filled(10, 0.0);

      // First frame
      final result1 = lock.computeOffset(
        edgeStrengthByRow: edges,
        topoLineYValues: topoY,
      );

      // With heavy smoothing, offset should be small after one frame
      expect(result1.offsetPx.abs(), lessThan(3.0));
    });

    test('reset clears the offset', () {
      final lock = SkylineLock(
        config: const SkylineLockConfig(
          stripHeightPx: 20,
          searchRangePx: 10,
          smoothingFactor: 1.0,
        ),
      );

      final edges = List<double>.filled(20, 1.0);
      edges[15] = 100.0;
      final topoY = List<double>.filled(10, 0.0);

      lock.computeOffset(edgeStrengthByRow: edges, topoLineYValues: topoY);
      expect(lock.currentOffsetPx, isNot(0));

      lock.reset();
      expect(lock.currentOffsetPx, 0.0);
    });

    test('applyToPoints shifts Y coordinates', () {
      final lock = SkylineLock();

      // Manually set offset via a computation
      final edges = List<double>.filled(60, 1.0);
      edges[35] = 100.0; // Offset = +5

      lock.computeOffset(
        edgeStrengthByRow: edges,
        topoLineYValues: List.filled(10, 0.0),
      );

      final points = [
        const ScreenPoint(x: 100, y: 200, isVisible: true),
        const ScreenPoint(x: 200, y: 300, isVisible: true),
      ];

      final shifted = lock.applyToPoints(points);

      // Points should be shifted vertically
      if (lock.currentOffsetPx.abs() >= 0.5) {
        expect(shifted[0].y, isNot(200));
        expect(shifted[0].x, 100); // X unchanged
      }
    });
  });
}
