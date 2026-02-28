import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/ffi/native_bridge.dart';
import 'package:peakline_app/services/skyline_matcher.dart';

void main() {
  late SkylineMatcher matcher;

  setUp(() {
    matcher = SkylineMatcher();
  });

  group('SkylineMatcher.match', () {
    test('returns zero confidence for empty inputs', () {
      final result = matcher.match(
        photoSkyline: [],
        horizonProfile: [],
        photoFovDeg: 60.0,
      );
      expect(result.confidence, 0.0);
    });

    test('finds correct heading with synthetic data', () {
      // Create a 360° profile with a distinctive peak at 180° (south)
      final profile = <HorizonPoint>[];
      for (double az = 0; az < 360; az += 0.5) {
        // Gaussian bump centered at 180°
        final diff = (az - 180.0).abs();
        final wrapped = diff > 180 ? 360 - diff : diff;
        final elevation = 3.0 * math.exp(-(wrapped * wrapped) / 200.0);
        profile.add(HorizonPoint(
          azimuthDeg: az,
          elevationAngleDeg: elevation,
          distanceM: 50000,
          terrainHeightM: 2000,
        ));
      }

      // Create a photo skyline that matches the 60° window centered at 180°
      // (i.e., from 150° to 210°)
      const fov = 60.0;
      const numPoints = 100;
      final photoSkyline = <double>[];
      for (int i = 0; i < numPoints; i++) {
        final az = 150.0 + i * fov / (numPoints - 1);
        final diff = (az - 180.0).abs();
        final elevation = 3.0 * math.exp(-(diff * diff) / 200.0);
        photoSkyline.add(elevation);
      }

      final result = matcher.match(
        photoSkyline: photoSkyline,
        horizonProfile: profile,
        photoFovDeg: fov,
        stepDeg: 1.0,
      );

      // Should find heading near 180°
      expect(result.headingDeg, closeTo(180.0, 2.0));
      // Should be highly confident (NCC close to 1.0)
      expect(result.confidence, greaterThan(0.9));
    });

    test('finds correct heading at 0/360 wraparound', () {
      // Create profile with a peak at 0° (north) — tests wraparound
      final profile = <HorizonPoint>[];
      for (double az = 0; az < 360; az += 0.5) {
        double diff = az;
        if (diff > 180) diff = 360 - diff;
        final elevation = 2.0 * math.exp(-(diff * diff) / 100.0);
        profile.add(HorizonPoint(
          azimuthDeg: az,
          elevationAngleDeg: elevation,
          distanceM: 50000,
          terrainHeightM: 2000,
        ));
      }

      // Photo skyline matching the window around 0° (330° to 30°)
      const fov = 60.0;
      const numPoints = 100;
      final photoSkyline = <double>[];
      for (int i = 0; i < numPoints; i++) {
        double az = 330.0 + i * fov / (numPoints - 1);
        if (az >= 360) az -= 360;
        double diff = az;
        if (diff > 180) diff = 360 - diff;
        final elevation = 2.0 * math.exp(-(diff * diff) / 100.0);
        photoSkyline.add(elevation);
      }

      final result = matcher.match(
        photoSkyline: photoSkyline,
        horizonProfile: profile,
        photoFovDeg: fov,
        stepDeg: 1.0,
      );

      // Should find heading near 0° (could be 0 or 360)
      final normalizedHeading = result.headingDeg % 360;
      final distFrom0 = normalizedHeading > 180
          ? 360 - normalizedHeading
          : normalizedHeading;
      expect(distFrom0, lessThan(3.0));
      expect(result.confidence, greaterThan(0.8));
    });

    test('allScores covers full 360°', () {
      final profile = List.generate(
        720,
        (i) => HorizonPoint(
          azimuthDeg: i * 0.5,
          elevationAngleDeg: 1.0,
          distanceM: 50000,
          terrainHeightM: 2000,
        ),
      );

      final photoSkyline = List.filled(50, 1.0);

      final result = matcher.match(
        photoSkyline: photoSkyline,
        horizonProfile: profile,
        photoFovDeg: 60.0,
        stepDeg: 1.0,
      );

      // Should have tested ~360 headings
      expect(result.allScores.length, closeTo(360, 5));
    });

    test('low confidence for flat profile', () {
      // Flat horizon — no distinctive features to match
      final profile = List.generate(
        720,
        (i) => HorizonPoint(
          azimuthDeg: i * 0.5,
          elevationAngleDeg: 1.0,
          distanceM: 50000,
          terrainHeightM: 2000,
        ),
      );

      // Photo with some variation
      final photoSkyline = List.generate(
        100,
        (i) => 1.0 + 0.5 * math.sin(i * 0.1),
      );

      final result = matcher.match(
        photoSkyline: photoSkyline,
        horizonProfile: profile,
        photoFovDeg: 60.0,
        stepDeg: 1.0,
      );

      // Flat profile can't match a varied skyline well
      expect(result.confidence, lessThan(0.5));
    });
  });
}
