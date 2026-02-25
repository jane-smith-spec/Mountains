import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/ui/widgets/ruler_tool.dart';

void main() {
  group('unprojectFromScreen', () {
    test('screen center maps to camera heading and pitch', () {
      final result = unprojectFromScreen(
        screenPoint: const Offset(200, 400),
        cameraHeadingDeg: 90.0,
        cameraPitchDeg: 5.0,
        screenWidth: 400,
        screenHeight: 800,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(result.bearingDeg, closeTo(90.0, 0.01));
      expect(result.elevationDeg, closeTo(5.0, 0.01));
    });

    test('right edge maps to heading + halfFov', () {
      final result = unprojectFromScreen(
        screenPoint: const Offset(400, 400), // Right edge
        cameraHeadingDeg: 90.0,
        cameraPitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 800,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(result.bearingDeg, closeTo(120.0, 0.01)); // 90 + 30
    });

    test('left edge maps to heading - halfFov', () {
      final result = unprojectFromScreen(
        screenPoint: const Offset(0, 400), // Left edge
        cameraHeadingDeg: 90.0,
        cameraPitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 800,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(result.bearingDeg, closeTo(60.0, 0.01)); // 90 - 30
    });

    test('top edge maps to pitch + halfVFov', () {
      final result = unprojectFromScreen(
        screenPoint: const Offset(200, 0), // Top edge
        cameraHeadingDeg: 90.0,
        cameraPitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 800,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(result.elevationDeg, closeTo(17.8, 0.01)); // 0 + 35.6/2
    });

    test('handles north wrap-around (heading near 0)', () {
      final result = unprojectFromScreen(
        screenPoint: const Offset(0, 400), // Left edge
        cameraHeadingDeg: 10.0,
        cameraPitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 800,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      // 10 - 30 = -20 → 340°
      expect(result.bearingDeg, closeTo(340.0, 0.01));
    });

    test('bearing is always in [0, 360)', () {
      for (final heading in [0.0, 90.0, 180.0, 270.0, 350.0]) {
        final result = unprojectFromScreen(
          screenPoint: const Offset(0, 400),
          cameraHeadingDeg: heading,
          cameraPitchDeg: 0.0,
          screenWidth: 400,
          screenHeight: 800,
        );

        expect(result.bearingDeg, greaterThanOrEqualTo(0));
        expect(result.bearingDeg, lessThan(360));
      }
    });
  });

  group('estimateDistance', () {
    test('returns distance from two known horizon distances', () {
      final dist = estimateDistance(
        bearing1Deg: 90.0,
        elevation1Deg: 1.0,
        bearing2Deg: 100.0,
        elevation2Deg: 1.0,
        observerAltitudeM: 2000,
        horizonDistance1M: 5000,
        horizonDistance2M: 8000,
      );

      expect(dist, isNotNull);
      expect(dist!, greaterThan(0));
    });

    test('distance between same point is ~0', () {
      final dist = estimateDistance(
        bearing1Deg: 90.0,
        elevation1Deg: 1.0,
        bearing2Deg: 90.0,
        elevation2Deg: 1.0,
        observerAltitudeM: 2000,
        horizonDistance1M: 5000,
        horizonDistance2M: 5000,
      );

      expect(dist, closeTo(0, 1)); // Nearly zero
    });

    test('returns null when no distance estimates possible', () {
      final dist = estimateDistance(
        bearing1Deg: 90.0,
        elevation1Deg: 0.0, // Exactly horizontal
        bearing2Deg: 100.0,
        elevation2Deg: 0.0,
        observerAltitudeM: 2000,
      );

      expect(dist, isNull);
    });

    test('returns distance estimate from elevation angles', () {
      final dist = estimateDistance(
        bearing1Deg: 90.0,
        elevation1Deg: 2.0,
        bearing2Deg: 100.0,
        elevation2Deg: 3.0,
        observerAltitudeM: 2000,
      );

      expect(dist, isNotNull);
      expect(dist!, greaterThan(0));
    });
  });

  group('RulerMeasurement', () {
    test('angular separation is computed correctly', () {
      const measurement = RulerMeasurement(
        startScreen: Offset.zero,
        endScreen: Offset(100, 0),
        startBearingDeg: 90.0,
        endBearingDeg: 100.0,
        startElevationDeg: 0.0,
        endElevationDeg: 0.0,
      );

      // Pure horizontal: 10° separation
      expect(measurement.angularSeparationDeg, closeTo(10.0, 0.1));
    });

    test('angular separation with both horizontal and vertical', () {
      const measurement = RulerMeasurement(
        startScreen: Offset.zero,
        endScreen: Offset(100, 100),
        startBearingDeg: 90.0,
        endBearingDeg: 93.0,
        startElevationDeg: 0.0,
        endElevationDeg: 4.0,
      );

      // sqrt(3² + 4²) = 5
      expect(measurement.angularSeparationDeg, closeTo(5.0, 0.1));
    });
  });

  group('RulerState', () {
    test('initial state has no measurement', () {
      const state = RulerState();
      expect(state.hasMeasurement, false);
      expect(state.waitingForSecondTap, false);
      expect(state.isActive, false);
    });

    test('after first tap, waiting for second', () {
      const state = RulerState(
        firstTap: Offset(100, 200),
        isActive: true,
      );
      expect(state.waitingForSecondTap, true);
    });

    test('clear keeps active state', () {
      const state = RulerState(
        firstTap: Offset(100, 200),
        secondTap: Offset(300, 400),
        isActive: true,
      );

      final cleared = state.clear();
      expect(cleared.firstTap, isNull);
      expect(cleared.secondTap, isNull);
      expect(cleared.isActive, true);
    });
  });
}
