import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/services/kalman_filter.dart';

void main() {
  group('KalmanFilter1D', () {
    test('first measurement returns the input value', () {
      final kf = KalmanFilter1D(processNoise: 0.1, measurementNoise: 2.0);
      expect(kf.isInitialized, false);

      final result = kf.filter(42.0);
      expect(result, 42.0);
      expect(kf.isInitialized, true);
      expect(kf.estimate, 42.0);
    });

    test('constant input converges to that value', () {
      final kf = KalmanFilter1D(processNoise: 0.1, measurementNoise: 2.0);

      // Feed 20 identical measurements at 30ms intervals
      double result = 0;
      for (int i = 0; i < 20; i++) {
        result = kf.filter(100.0, dt: 0.033);
      }

      // Should converge close to 100
      expect(result, closeTo(100.0, 0.5));
    });

    test('tracks a linear ramp', () {
      final kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 1.0);

      // Feed measurements that increase linearly: 0, 5, 10, 15, ...
      double result = 0;
      for (int i = 0; i <= 20; i++) {
        result = kf.filter(i * 5.0, dt: 0.033);
      }

      // After tracking a ramp to 100, the Kalman filter should be close
      // (it learns the rate of change)
      expect(result, closeTo(100.0, 10.0));
    });

    test('smooths noisy data around a constant', () {
      final kf = KalmanFilter1D(processNoise: 0.1, measurementNoise: 4.0);

      // Simulate noisy measurements around 50.0
      final noisyValues = [
        52.0, 48.0, 53.0, 47.0, 51.0, 49.0, 54.0, 46.0, 50.0, 52.0,
        48.0, 51.0, 49.0, 50.0, 53.0, 47.0, 50.0, 51.0, 49.0, 50.0,
      ];

      final outputs = <double>[];
      for (final v in noisyValues) {
        outputs.add(kf.filter(v, dt: 0.033));
      }

      // The filtered output should be smoother (less variance) than input
      final inputVariance = _variance(noisyValues);
      final outputVariance = _variance(outputs);

      expect(outputVariance, lessThan(inputVariance));

      // The final filtered value should be near 50
      expect(outputs.last, closeTo(50.0, 3.0));
    });

    test('responds to step change', () {
      final kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 1.0);

      // Settle at 0
      for (int i = 0; i < 10; i++) {
        kf.filter(0.0, dt: 0.033);
      }

      // Step change to 100
      double result = 0;
      for (int i = 0; i < 30; i++) {
        result = kf.filter(100.0, dt: 0.033);
      }

      // Should track to near 100
      expect(result, closeTo(100.0, 5.0));
    });

    test('reset clears state', () {
      final kf = KalmanFilter1D(processNoise: 0.1, measurementNoise: 2.0);

      kf.filter(50.0);
      expect(kf.isInitialized, true);

      kf.reset();
      expect(kf.isInitialized, false);
      expect(kf.estimate, isNull);

      // After reset, next value should be returned directly
      final result = kf.filter(75.0);
      expect(result, 75.0);
    });

    test('works without dt (update-only mode)', () {
      final kf = KalmanFilter1D(processNoise: 0.1, measurementNoise: 2.0);

      // Filter without dt — skips the prediction step
      kf.filter(10.0);
      final result = kf.filter(12.0);

      // Should still produce a reasonable value
      expect(result, greaterThanOrEqualTo(10.0));
      expect(result, lessThanOrEqualTo(12.0));
    });

    test('estimated rate tracks velocity', () {
      final kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 1.0);

      // Move at 30 units/second (1 unit per 33ms frame)
      for (int i = 0; i < 30; i++) {
        kf.filter(i * 1.0, dt: 0.033);
      }

      // The estimated rate should be positive (moving upward)
      expect(kf.estimatedRate, greaterThan(0));
    });
  });

  group('HeadingKalmanFilter', () {
    test('tracks heading near north (0/360 wrap)', () {
      final hkf = HeadingKalmanFilter(
        processNoise: 0.5,
        measurementNoise: 1.0,
      );

      // Feed headings that oscillate near north
      final headings = [
        358.0, 2.0, 359.0, 1.0, 0.0, 357.0, 3.0, 360.0, 358.0, 1.0,
        0.0, 359.0, 2.0, 1.0, 0.0, 358.0, 3.0, 0.0, 1.0, 359.0,
      ];

      double result = 0;
      for (final h in headings) {
        result = hkf.filter(h, dt: 0.033);
      }

      // Should be near 0/360 (north), NOT near 180 (south)
      final nearNorth = result < 10 || result > 350;
      expect(nearNorth, true,
          reason: 'Expected near north (0/360) but got $result');
    });

    test('tracks heading smoothly through east', () {
      final hkf = HeadingKalmanFilter(
        processNoise: 0.5,
        measurementNoise: 1.0,
      );

      // Sweep from 70° to 110° (through east)
      double result = 0;
      for (int i = 70; i <= 110; i++) {
        result = hkf.filter(i.toDouble(), dt: 0.033);
      }

      // Should end near 110°
      expect(result, closeTo(110.0, 10.0));
    });

    test('result is always in [0, 360)', () {
      final hkf = HeadingKalmanFilter();

      // Feed various headings
      for (final h in [0.0, 90.0, 180.0, 270.0, 359.0, 1.0, 350.0, 10.0]) {
        final result = hkf.filter(h, dt: 0.033);
        expect(result, greaterThanOrEqualTo(0));
        expect(result, lessThan(360));
      }
    });

    test('reset clears state', () {
      final hkf = HeadingKalmanFilter();

      hkf.filter(90.0);
      hkf.filter(95.0, dt: 0.033);
      hkf.reset();

      // After reset, should initialize fresh from next measurement
      final result = hkf.filter(270.0);
      // Should be near 270 since the filter was reset
      expect(result, closeTo(270.0, 5.0));
    });
  });

  group('SmoothingLevel', () {
    test('has three preset levels', () {
      expect(SmoothingLevel.values.length, 3);
    });

    test('low has smallest process noise (most smoothing)', () {
      expect(SmoothingLevel.low.processNoise,
          lessThan(SmoothingLevel.medium.processNoise));
    });

    test('high has largest process noise (most responsive)', () {
      expect(SmoothingLevel.high.processNoise,
          greaterThan(SmoothingLevel.medium.processNoise));
    });

    test('low has largest measurement noise (trusts prediction more)', () {
      expect(SmoothingLevel.low.measurementNoise,
          greaterThan(SmoothingLevel.medium.measurementNoise));
    });

    test('each level has a label', () {
      for (final level in SmoothingLevel.values) {
        expect(level.label, isNotEmpty);
      }
    });
  });
}

/// Compute variance of a list of doubles.
double _variance(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  final squaredDiffs = values.map((v) => (v - mean) * (v - mean));
  return squaredDiffs.reduce((a, b) => a + b) / values.length;
}
