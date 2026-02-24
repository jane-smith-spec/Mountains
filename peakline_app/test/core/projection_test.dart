import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/core/projection.dart';
import 'package:peakline_app/models/sensor_data.dart';

void main() {
  // Standard test camera: pointing north, horizontal, 60° × 35.6° FOV
  // on a 1000 × 600 pixel screen.
  final camera = CameraViewParams(
    headingDeg: 0.0,
    pitchDeg: 0.0,
    screenWidth: 1000.0,
    screenHeight: 600.0,
    horizontalFovDeg: 60.0,
    verticalFovDeg: 36.0,
  );

  group('projectToScreen', () {
    test('point at camera center maps to screen center', () {
      // Looking north (0°), point due north at horizon (0° elevation)
      final p = projectToScreen(
        azimuthDeg: 0.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(p.x, closeTo(500.0, 0.01));
      expect(p.y, closeTo(300.0, 0.01));
      expect(p.isVisible, isTrue);
    });

    test('point at right edge of FOV maps to right edge of screen', () {
      // 30° right of center (half of 60° FOV)
      final p = projectToScreen(
        azimuthDeg: 30.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(p.x, closeTo(1000.0, 0.01));
      expect(p.y, closeTo(300.0, 0.01));
      expect(p.isVisible, isTrue);
    });

    test('point at left edge of FOV maps to left edge of screen', () {
      // 30° left of center → azimuth 330° (since camera faces 0°/north)
      final p = projectToScreen(
        azimuthDeg: 330.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(p.x, closeTo(0.0, 0.01));
      expect(p.y, closeTo(300.0, 0.01));
      expect(p.isVisible, isTrue);
    });

    test('point above center maps to upper half of screen', () {
      // 18° above horizon (half of 36° vertical FOV)
      final p = projectToScreen(
        azimuthDeg: 0.0,
        elevationAngleDeg: 18.0,
        camera: camera,
      );

      expect(p.x, closeTo(500.0, 0.01));
      expect(p.y, closeTo(0.0, 0.01)); // top of screen
      expect(p.isVisible, isTrue);
    });

    test('point below center maps to lower half of screen', () {
      final p = projectToScreen(
        azimuthDeg: 0.0,
        elevationAngleDeg: -18.0,
        camera: camera,
      );

      expect(p.x, closeTo(500.0, 0.01));
      expect(p.y, closeTo(600.0, 0.01)); // bottom of screen
      expect(p.isVisible, isTrue);
    });

    test('point outside FOV is marked not visible', () {
      // 45° to the right → outside 60° FOV
      final p = projectToScreen(
        azimuthDeg: 45.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(p.isVisible, isFalse);
      // x/y are still computed (for potential off-screen indicators)
      expect(p.x, greaterThan(1000.0));
    });

    test('handles 0°/360° wraparound: camera at 350°, target at 10°', () {
      final cam = CameraViewParams(
        headingDeg: 350.0,
        pitchDeg: 0.0,
        screenWidth: 1000.0,
        screenHeight: 600.0,
        horizontalFovDeg: 60.0,
        verticalFovDeg: 36.0,
      );

      final p = projectToScreen(
        azimuthDeg: 10.0,
        elevationAngleDeg: 0.0,
        camera: cam,
      );

      // 10° is 20° to the RIGHT of 350°
      // 20° / 30° (half FOV) = 0.667 → screen x = 500 + 0.667 * 500 = 833
      expect(p.x, closeTo(833.3, 1.0));
      expect(p.isVisible, isTrue);
    });

    test('camera pitched up shifts horizon down on screen', () {
      final cam = CameraViewParams(
        headingDeg: 0.0,
        pitchDeg: 10.0, // looking 10° up
        screenWidth: 1000.0,
        screenHeight: 600.0,
        horizontalFovDeg: 60.0,
        verticalFovDeg: 36.0,
      );

      // A point at the horizon (0° elevation) should appear in the
      // lower portion of the screen when camera is pitched up
      final p = projectToScreen(
        azimuthDeg: 0.0,
        elevationAngleDeg: 0.0,
        camera: cam,
      );

      expect(p.y, greaterThan(300.0)); // below screen center
      expect(p.isVisible, isTrue);
    });
  });

  group('CameraViewParams.fromOrientation', () {
    test('derives vertical FOV from horizontal FOV and screen aspect', () {
      final params = CameraViewParams.fromOrientation(
        orientation: const DeviceOrientation(
          headingDeg: 90.0,
          pitchDeg: 5.0,
          rollDeg: 0.0,
        ),
        screenWidth: 1920.0,
        screenHeight: 1080.0,
        horizontalFovDeg: 60.0,
      );

      expect(params.headingDeg, equals(90.0));
      expect(params.pitchDeg, equals(5.0));
      // For 16:9 at 60° hFOV, vFOV ≈ 35.6°
      expect(params.verticalFovDeg, closeTo(35.6, 0.5));
    });
  });

  group('projectHorizonProfile', () {
    test('filters out points outside FOV', () {
      // Create points at every 10° around the compass
      final points = List.generate(36, (i) => (
            azimuthDeg: i * 10.0,
            elevationAngleDeg: 1.0,
          ));

      final projected = projectHorizonProfile(
        points: points,
        camera: camera,
        marginDeg: 5.0,
      );

      // Camera faces north (0°) with 60° FOV + 5° margin = 35° each side
      // So azimuths 0°, 10°, 20°, 30° and 330°, 340°, 350° should be included
      // That's 7 points
      expect(projected.length, equals(7));
    });

    test('empty input returns empty output', () {
      final projected = projectHorizonProfile(
        points: [],
        camera: camera,
      );
      expect(projected, isEmpty);
    });
  });
}
