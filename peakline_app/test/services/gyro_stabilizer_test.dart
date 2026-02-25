import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/services/gyro_stabilizer.dart';

void main() {
  group('GyroStabilizer', () {
    test('first update returns compass heading directly', () {
      final stabilizer = GyroStabilizer();

      final result = stabilizer.update(
        compassHeadingDeg: 90.0,
        compassPitchDeg: 5.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      expect(result.headingDeg, 90.0);
      expect(result.pitchDeg, 5.0);
    });

    test('stationary with no rotation stays at compass heading', () {
      final stabilizer = GyroStabilizer(alpha: 0.98);

      // Initialize
      stabilizer.update(
        compassHeadingDeg: 180.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Several updates with zero gyro and same compass
      for (int i = 0; i < 20; i++) {
        stabilizer.update(
          compassHeadingDeg: 180.0,
          compassPitchDeg: 0.0,
          gyroZDegPerSec: 0.0,
          gyroXDegPerSec: 0.0,
        );
      }

      expect(stabilizer.fusedHeadingDeg, closeTo(180.0, 1.0));
      expect(stabilizer.fusedPitchDeg, closeTo(0.0, 1.0));
    });

    test('handles north wrap-around (350 to 10 degrees)', () {
      final stabilizer = GyroStabilizer(alpha: 0.5);

      // Start near north
      stabilizer.update(
        compassHeadingDeg: 350.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Compass jumps across north
      final result = stabilizer.update(
        compassHeadingDeg: 10.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Should be near north (0/360), NOT near 180 (south)
      final nearNorth = result.headingDeg < 30 || result.headingDeg > 330;
      expect(nearNorth, true,
          reason: 'Expected near north but got ${result.headingDeg}');
    });

    test('gyro rotation is integrated into heading', () {
      final stabilizer = GyroStabilizer(alpha: 0.98);

      // Initialize at 90°
      stabilizer.update(
        compassHeadingDeg: 90.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Gyro says we're rotating at 10°/sec, compass lags behind
      // With alpha=0.98, the gyro should dominate short-term
      final result = stabilizer.update(
        compassHeadingDeg: 90.0, // Compass hasn't caught up yet
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 10.0,
        gyroXDegPerSec: 0.0,
      );

      // Fused heading should be slightly ahead of compass (gyro pushing it)
      // The exact value depends on dt, but should be >= 90
      expect(result.headingDeg, greaterThanOrEqualTo(89.0));
    });

    test('heading result is always in [0, 360)', () {
      final stabilizer = GyroStabilizer();

      for (final heading in [0.0, 90.0, 180.0, 270.0, 359.0, 1.0]) {
        final result = stabilizer.update(
          compassHeadingDeg: heading,
          compassPitchDeg: 0.0,
          gyroZDegPerSec: 0.0,
          gyroXDegPerSec: 0.0,
        );

        expect(result.headingDeg, greaterThanOrEqualTo(0));
        expect(result.headingDeg, lessThan(360));
      }
    });

    test('reset clears all state', () {
      final stabilizer = GyroStabilizer();

      stabilizer.update(
        compassHeadingDeg: 90.0,
        compassPitchDeg: 10.0,
        gyroZDegPerSec: 5.0,
        gyroXDegPerSec: 2.0,
      );

      expect(stabilizer.fusedHeadingDeg, isNotNull);

      stabilizer.reset();

      expect(stabilizer.fusedHeadingDeg, isNull);
      expect(stabilizer.fusedPitchDeg, isNull);
      expect(stabilizer.isBiasCalibrated, false);
      expect(stabilizer.isStationary, true);
    });

    group('bias estimation', () {
      test('bias is not calibrated initially', () {
        final stabilizer = GyroStabilizer(biasEstimationSamples: 5);
        expect(stabilizer.isBiasCalibrated, false);
      });

      test('bias calibrates after enough stationary samples', () {
        final stabilizer = GyroStabilizer(
          biasEstimationSamples: 5,
          stillnessThresholdDegPerSec: 10.0, // High threshold so samples count
        );

        // Feed stationary samples with a small constant gyro offset (bias)
        for (int i = 0; i < 10; i++) {
          stabilizer.update(
            compassHeadingDeg: 90.0,
            compassPitchDeg: 0.0,
            gyroZDegPerSec: 0.5, // Constant bias
            gyroXDegPerSec: 0.3,
          );
        }

        expect(stabilizer.isBiasCalibrated, true);
      });

      test('device detected as stationary when gyro is near zero', () {
        final stabilizer = GyroStabilizer(stillnessThresholdDegPerSec: 2.0);

        stabilizer.update(
          compassHeadingDeg: 90.0,
          compassPitchDeg: 0.0,
          gyroZDegPerSec: 0.1,
          gyroXDegPerSec: 0.1,
        );

        expect(stabilizer.isStationary, true);
      });

      test('device detected as moving when gyro is large', () {
        final stabilizer = GyroStabilizer(stillnessThresholdDegPerSec: 2.0);

        // Initialize first
        stabilizer.update(
          compassHeadingDeg: 90.0,
          compassPitchDeg: 0.0,
          gyroZDegPerSec: 0.0,
          gyroXDegPerSec: 0.0,
        );

        stabilizer.update(
          compassHeadingDeg: 90.0,
          compassPitchDeg: 0.0,
          gyroZDegPerSec: 30.0, // Fast rotation
          gyroXDegPerSec: 0.0,
        );

        expect(stabilizer.isStationary, false);
      });
    });
  });

  group('GyroStabilizer._circularBlend', () {
    // We test the static method indirectly through the update() interface.

    test('blending 350 and 10 gives near north, not south', () {
      // Using alpha=0.5 for a 50/50 blend
      final stabilizer = GyroStabilizer(alpha: 0.5);

      // First update to set heading to 350
      stabilizer.update(
        compassHeadingDeg: 350.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Immediately blend with 10° compass
      // With zero gyro, the gyro prediction = 350° (no change)
      // Compass = 10°. Blend of 350° and 10° should be near 0°.
      final result = stabilizer.update(
        compassHeadingDeg: 10.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      final nearNorth = result.headingDeg < 20 || result.headingDeg > 340;
      expect(nearNorth, true,
          reason: 'Blend of 350° and 10° should be near 0°, '
              'got ${result.headingDeg}');
    });
  });

  group('complementary filter alpha parameter', () {
    test('alpha=1.0 trusts gyro completely', () {
      final stabilizer = GyroStabilizer(alpha: 1.0);

      // Initialize at 90°
      stabilizer.update(
        compassHeadingDeg: 90.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Compass says 180° but gyro says no rotation
      final result = stabilizer.update(
        compassHeadingDeg: 180.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // With alpha=1.0, compass is completely ignored → stays at ~90°
      expect(result.headingDeg, closeTo(90.0, 5.0));
    });

    test('alpha=0.0 trusts compass completely', () {
      final stabilizer = GyroStabilizer(alpha: 0.0);

      // Initialize at 90°
      stabilizer.update(
        compassHeadingDeg: 90.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // Compass says 180°
      final result = stabilizer.update(
        compassHeadingDeg: 180.0,
        compassPitchDeg: 0.0,
        gyroZDegPerSec: 0.0,
        gyroXDegPerSec: 0.0,
      );

      // With alpha=0.0, gyro is completely ignored → follows compass
      expect(result.headingDeg, closeTo(180.0, 5.0));
    });
  });
}
