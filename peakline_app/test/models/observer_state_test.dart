import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/models/observer_state.dart';
import 'package:peakline_app/models/sensor_data.dart';

void main() {
  group('ObserverState', () {
    test('constructor stores values correctly', () {
      const state = ObserverState(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        altitudeM: 1500,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );
      expect(state.latitudeDeg, 46.5);
      expect(state.longitudeDeg, 7.5);
      expect(state.altitudeM, 1500);
      expect(state.headingDeg, 180.0);
      expect(state.pitchDeg, 5.0);
    });

    test('factory from location + orientation', () {
      const location = DeviceLocation(
        latitudeDeg: 47.3769,
        longitudeDeg: 8.5417,
        altitudeM: 408,
        accuracyM: 5,
      );
      const orientation = DeviceOrientation(
        headingDeg: 225.0,
        pitchDeg: 3.0,
        rollDeg: 1.0,
      );

      final state = ObserverState.from(
        location: location,
        orientation: orientation,
      );

      expect(state.latitudeDeg, 47.3769);
      expect(state.longitudeDeg, 8.5417);
      expect(state.altitudeM, 408);
      expect(state.headingDeg, 225.0);
      expect(state.pitchDeg, 3.0);
    });

    test('equality by value', () {
      const a = ObserverState(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        altitudeM: 1500,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );
      const b = ObserverState(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        altitudeM: 1500,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when values differ', () {
      const a = ObserverState(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        altitudeM: 1500,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );
      const b = ObserverState(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        altitudeM: 1500,
        headingDeg: 90.0, // different heading
        pitchDeg: 5.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes key fields', () {
      const state = ObserverState(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        altitudeM: 1500,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );
      final str = state.toString();
      expect(str, contains('46.5'));
      expect(str, contains('7.5'));
      expect(str, contains('1500'));
    });
  });
}
