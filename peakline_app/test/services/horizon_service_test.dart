import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/core/projection.dart';
import 'package:peakline_app/models/observer_state.dart';
import 'package:peakline_app/services/horizon_service.dart';

void main() {
  group('HorizonState', () {
    test('empty state has no profile', () {
      expect(HorizonState.empty.hasProfile, isFalse);
      expect(HorizonState.empty.profilePoints, isEmpty);
      expect(HorizonState.empty.screenPoints, isEmpty);
      expect(HorizonState.empty.observer, isNull);
      expect(HorizonState.empty.isComputing, isFalse);
      expect(HorizonState.empty.error, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      final state = HorizonState(
        profilePoints: [],
        screenPoints: [],
        observer: const ObserverState(
          latitudeDeg: 46.5,
          longitudeDeg: 7.5,
          altitudeM: 1500,
          headingDeg: 180.0,
          pitchDeg: 5.0,
        ),
        isComputing: false,
        error: null,
      );

      final updated = state.copyWith(isComputing: true);
      expect(updated.isComputing, isTrue);
      expect(updated.observer, equals(state.observer));
    });
  });

  group('HorizonService', () {
    test('creates without native bridge (test mode)', () {
      final service = HorizonService();
      // Should not throw
      expect(service, isNotNull);
    });

    test('projectToScreen returns empty with no profile', () {
      final service = HorizonService();
      final points = service.projectToScreen(
        camera: const CameraViewParams(
          headingDeg: 180.0,
          pitchDeg: 0.0,
          screenWidth: 1920,
          screenHeight: 1080,
        ),
      );
      expect(points, isEmpty);
    });

    test('computeProfile returns empty without bridge', () async {
      final service = HorizonService();
      final points = await service.computeProfile(
        observer: const ObserverState(
          latitudeDeg: 46.5,
          longitudeDeg: 7.5,
          altitudeM: 1500,
          headingDeg: 180.0,
          pitchDeg: 5.0,
        ),
        demPath: '/some/path.hgt',
      );
      expect(points, isEmpty);
    });

    test('dispose is safe to call multiple times', () {
      final service = HorizonService();
      service.dispose();
      service.dispose(); // should not throw
    });
  });
}
