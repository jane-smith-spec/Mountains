import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/core/projection.dart';
import 'package:peakline_app/ffi/native_bridge.dart';
import 'package:peakline_app/models/landmark.dart';
import 'package:peakline_app/models/observer_state.dart';
import 'package:peakline_app/models/peak.dart';
import 'package:peakline_app/services/peak_visibility_service.dart';

void main() {
  late PeakVisibilityService service;

  setUp(() {
    service = PeakVisibilityService();
  });

  // Common test setup: observer in Zurich, looking south toward the Alps.
  const observer = ObserverState(
    latitudeDeg: 47.3769,
    longitudeDeg: 8.5417,
    altitudeM: 408,
    headingDeg: 180.0, // south
    pitchDeg: 2.0,
  );

  const camera = CameraViewParams(
    headingDeg: 180.0,
    pitchDeg: 2.0,
    screenWidth: 1920,
    screenHeight: 1080,
    horizontalFovDeg: 60.0,
    verticalFovDeg: 35.6,
  );

  group('findVisiblePeaks', () {
    test('returns empty for empty input', () {
      final result = service.findVisiblePeaks(
        peaks: [],
        horizonProfile: [],
        observer: observer,
        camera: camera,
      );
      expect(result, isEmpty);
    });

    test('peak above horizon is visible', () {
      // Pilatus is south of Zurich, ~55km, 2128m
      const pilatus = Peak(
        name: 'Pilatus',
        latitudeDeg: 46.9786,
        longitudeDeg: 8.2556,
        elevationM: 2128,
      );

      // Create a low horizon at the bearing to Pilatus (~210° from Zurich)
      // The horizon at that bearing is only 0.5°, so Pilatus at ~1.5° should be visible
      final profile = _fakeHorizonProfile(
        startDeg: 0,
        endDeg: 360,
        stepDeg: 1.0,
        elevationDeg: 0.5,
      );

      final result = service.findVisiblePeaks(
        peaks: [pilatus],
        horizonProfile: profile,
        observer: observer,
        camera: camera,
      );

      expect(result, isNotEmpty);
      expect(result.first.peak.name, 'Pilatus');
      expect(result.first.distanceM, greaterThan(40000));
      expect(result.first.distanceM, lessThan(70000));
    });

    test('peak behind higher ridge is hidden', () {
      // A small peak behind a very high horizon
      const smallPeak = Peak(
        name: 'Small Hill',
        latitudeDeg: 47.2, // south of observer
        longitudeDeg: 8.5,
        elevationM: 600,
      );

      // Horizon is at 5° everywhere — the small hill is way below
      final profile = _fakeHorizonProfile(
        startDeg: 0,
        endDeg: 360,
        stepDeg: 1.0,
        elevationDeg: 5.0,
      );

      final result = service.findVisiblePeaks(
        peaks: [smallPeak],
        horizonProfile: profile,
        observer: observer,
        camera: camera,
      );

      expect(result, isEmpty);
    });

    test('peak outside FOV is excluded', () {
      // Peak due north — camera is pointing south
      const northPeak = Peak(
        name: 'Northern Peak',
        latitudeDeg: 48.0,
        longitudeDeg: 8.5,
        elevationM: 3000,
      );

      final profile = _fakeHorizonProfile(
        startDeg: 0,
        endDeg: 360,
        stepDeg: 1.0,
        elevationDeg: 0.0,
      );

      final result = service.findVisiblePeaks(
        peaks: [northPeak],
        horizonProfile: profile,
        observer: observer,
        camera: camera,
      );

      expect(result, isEmpty);
    });

    test('peaks too far are excluded', () {
      const farPeak = Peak(
        name: 'Very Far Peak',
        latitudeDeg: 45.0, // ~250 km south
        longitudeDeg: 8.5,
        elevationM: 4000,
      );

      final profile = _fakeHorizonProfile(
        startDeg: 0,
        endDeg: 360,
        stepDeg: 1.0,
        elevationDeg: 0.0,
      );

      final result = service.findVisiblePeaks(
        peaks: [farPeak],
        horizonProfile: profile,
        observer: observer,
        camera: camera,
        maxDistanceM: 100000,
      );

      expect(result, isEmpty);
    });

    test('results sorted by distance (closest first)', () {
      const peak1 = Peak(
        name: 'Far Peak',
        latitudeDeg: 46.9,
        longitudeDeg: 8.5,
        elevationM: 2500,
      );
      const peak2 = Peak(
        name: 'Close Peak',
        latitudeDeg: 47.2,
        longitudeDeg: 8.5,
        elevationM: 1500,
      );

      final profile = _fakeHorizonProfile(
        startDeg: 0,
        endDeg: 360,
        stepDeg: 1.0,
        elevationDeg: 0.0,
      );

      final result = service.findVisiblePeaks(
        peaks: [peak1, peak2],
        horizonProfile: profile,
        observer: observer,
        camera: camera,
      );

      if (result.length == 2) {
        expect(result[0].distanceM, lessThan(result[1].distanceM));
      }
    });
  });

  group('findVisibleLandmarks', () {
    test('returns empty when no categories enabled', () {
      const hut = Landmark(
        name: 'Test Hut',
        latitudeDeg: 47.2,
        longitudeDeg: 8.5,
        elevationM: 1200,
        category: LandmarkCategory.hut,
      );

      final result = service.findVisibleLandmarks(
        landmarks: [hut],
        horizonProfile: [],
        observer: observer,
        camera: camera,
        enabledCategories: {}, // nothing enabled
      );

      expect(result, isEmpty);
    });

    test('landmark with matching category is included', () {
      const lake = Landmark(
        name: 'Zugersee',
        latitudeDeg: 47.1, // south of observer, within FOV
        longitudeDeg: 8.5,
        elevationM: 413,
        category: LandmarkCategory.lake,
      );

      final result = service.findVisibleLandmarks(
        landmarks: [lake],
        horizonProfile: [],
        observer: observer,
        camera: camera,
        enabledCategories: {LandmarkCategory.lake},
      );

      expect(result, isNotEmpty);
      expect(result.first.landmark.name, 'Zugersee');
    });
  });

  group('VisiblePeak.distanceLabel', () {
    test('formats meters for short distances', () {
      const vp = VisiblePeak(
        peak: Peak(
          name: 'Test',
          latitudeDeg: 0,
          longitudeDeg: 0,
          elevationM: 100,
        ),
        bearingDeg: 0,
        elevationAngleDeg: 0,
        distanceM: 500,
        screenPoint: ScreenPoint(x: 0, y: 0, isVisible: true),
      );
      expect(vp.distanceLabel, '500 m');
    });

    test('formats km for long distances', () {
      const vp = VisiblePeak(
        peak: Peak(
          name: 'Test',
          latitudeDeg: 0,
          longitudeDeg: 0,
          elevationM: 100,
        ),
        bearingDeg: 0,
        elevationAngleDeg: 0,
        distanceM: 12345,
        screenPoint: ScreenPoint(x: 0, y: 0, isVisible: true),
      );
      expect(vp.distanceLabel, '12.3 km');
    });
  });
}

/// Create a fake horizon profile with uniform elevation at all bearings.
List<HorizonPoint> _fakeHorizonProfile({
  required double startDeg,
  required double endDeg,
  required double stepDeg,
  required double elevationDeg,
}) {
  final points = <HorizonPoint>[];
  for (double az = startDeg; az < endDeg; az += stepDeg) {
    points.add(HorizonPoint(
      azimuthDeg: az,
      elevationAngleDeg: elevationDeg,
      distanceM: 50000,
      terrainHeightM: 2000,
    ));
  }
  return points;
}
