import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/core/coordinate_utils.dart';

void main() {
  group('haversineDistanceM', () {
    test('same point returns zero', () {
      final d = haversineDistanceM(47.0, 8.0, 47.0, 8.0);
      expect(d, closeTo(0.0, 0.01));
    });

    test('known distance: Zurich to Bern ~95 km', () {
      // Zurich (47.3769°N, 8.5417°E) to Bern (46.9480°N, 7.4474°E)
      final d = haversineDistanceM(47.3769, 8.5417, 46.9480, 7.4474);
      // Actual distance is ~95.3 km
      expect(d, closeTo(95300, 1000)); // within 1 km
    });

    test('antipodal points ~20,000 km', () {
      // North Pole to South Pole
      final d = haversineDistanceM(90.0, 0.0, -90.0, 0.0);
      // Half the Earth's circumference ≈ 20,015 km
      expect(d, closeTo(20015000, 50000));
    });

    test('short distance: 1 degree latitude ~111 km', () {
      final d = haversineDistanceM(46.0, 8.0, 47.0, 8.0);
      expect(d, closeTo(111195, 500));
    });
  });

  group('bearingDeg', () {
    test('due north returns 0', () {
      final b = bearingDeg(46.0, 8.0, 47.0, 8.0);
      expect(b, closeTo(0.0, 0.1));
    });

    test('due south returns 180', () {
      final b = bearingDeg(47.0, 8.0, 46.0, 8.0);
      expect(b, closeTo(180.0, 0.1));
    });

    test('due east returns ~90', () {
      // At the equator, moving east is exactly 90°
      final b = bearingDeg(0.0, 0.0, 0.0, 1.0);
      expect(b, closeTo(90.0, 0.1));
    });

    test('due west returns ~270', () {
      final b = bearingDeg(0.0, 1.0, 0.0, 0.0);
      expect(b, closeTo(270.0, 0.1));
    });

    test('result is in range [0, 360)', () {
      final b = bearingDeg(47.3769, 8.5417, 46.9480, 7.4474);
      expect(b, greaterThanOrEqualTo(0.0));
      expect(b, lessThan(360.0));
    });
  });

  group('destinationPoint', () {
    test('zero distance returns same point', () {
      final p = destinationPoint(47.0, 8.0, 0.0, 0.0);
      expect(p.latDeg, closeTo(47.0, 0.001));
      expect(p.lonDeg, closeTo(8.0, 0.001));
    });

    test('1 degree north from equator', () {
      // ~111.2 km north from the equator should give ~1° latitude
      final p = destinationPoint(0.0, 0.0, 0.0, 111195.0);
      expect(p.latDeg, closeTo(1.0, 0.01));
      expect(p.lonDeg, closeTo(0.0, 0.01));
    });

    test('round trip: destination then bearing back', () {
      // Go 50 km northeast from Zurich
      final dest = destinationPoint(47.3769, 8.5417, 45.0, 50000.0);
      // Bearing back should be roughly 225° (southwest)
      final back = bearingDeg(dest.latDeg, dest.lonDeg, 47.3769, 8.5417);
      expect(back, closeTo(225.0, 2.0)); // within 2°
    });
  });

  group('elevationAngleDeg', () {
    test('same altitude at distance returns negative (Earth curves away)', () {
      final angle = elevationAngleDeg(
        observerAltM: 1000,
        targetAltM: 1000,
        distanceM: 50000, // 50 km
      );
      // At 50 km, Earth curvature drops the target below horizontal
      expect(angle, lessThan(0.0));
    });

    test('much higher target at close range is positive', () {
      final angle = elevationAngleDeg(
        observerAltM: 500,
        targetAltM: 4000,
        distanceM: 10000, // 10 km
      );
      // 3500m higher at 10 km → about 19.3°
      expect(angle, closeTo(19.3, 0.5));
    });

    test('zero distance returns zero', () {
      final angle = elevationAngleDeg(
        observerAltM: 1000,
        targetAltM: 5000,
        distanceM: 0,
      );
      expect(angle, equals(0.0));
    });

    test('target below observer is negative', () {
      final angle = elevationAngleDeg(
        observerAltM: 3000,
        targetAltM: 1000,
        distanceM: 5000,
      );
      expect(angle, lessThan(0.0));
    });
  });
}
