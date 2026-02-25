import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/models/peak.dart';

void main() {
  group('Peak', () {
    test('constructor stores values correctly', () {
      const peak = Peak(
        name: 'Matterhorn',
        latitudeDeg: 45.9764,
        longitudeDeg: 7.6586,
        elevationM: 4478,
        prominenceM: 1042,
        id: 12345,
      );
      expect(peak.name, 'Matterhorn');
      expect(peak.latitudeDeg, 45.9764);
      expect(peak.longitudeDeg, 7.6586);
      expect(peak.elevationM, 4478);
      expect(peak.prominenceM, 1042);
      expect(peak.id, 12345);
    });

    test('prominence and id are optional', () {
      const peak = Peak(
        name: 'Test Peak',
        latitudeDeg: 46.0,
        longitudeDeg: 7.0,
        elevationM: 3000,
      );
      expect(peak.prominenceM, isNull);
      expect(peak.id, isNull);
    });

    test('equality by value', () {
      const a = Peak(
        name: 'Eiger',
        latitudeDeg: 46.5776,
        longitudeDeg: 8.0053,
        elevationM: 3967,
      );
      const b = Peak(
        name: 'Eiger',
        latitudeDeg: 46.5776,
        longitudeDeg: 8.0053,
        elevationM: 3967,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when values differ', () {
      const a = Peak(
        name: 'Eiger',
        latitudeDeg: 46.5776,
        longitudeDeg: 8.0053,
        elevationM: 3967,
      );
      const b = Peak(
        name: 'Mönch',
        latitudeDeg: 46.5579,
        longitudeDeg: 7.9999,
        elevationM: 4107,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes name and elevation', () {
      const peak = Peak(
        name: 'Jungfrau',
        latitudeDeg: 46.5372,
        longitudeDeg: 7.9622,
        elevationM: 4158,
      );
      final str = peak.toString();
      expect(str, contains('Jungfrau'));
      expect(str, contains('4158'));
    });
  });
}
