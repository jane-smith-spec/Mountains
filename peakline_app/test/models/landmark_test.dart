import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/models/landmark.dart';

void main() {
  group('LandmarkCategory', () {
    test('all categories have labels', () {
      for (final cat in LandmarkCategory.values) {
        expect(cat.label, isNotEmpty);
      }
    });
  });

  group('Landmark', () {
    test('constructor stores values correctly', () {
      const landmark = Landmark(
        name: 'Hörnli Hut',
        latitudeDeg: 45.9826,
        longitudeDeg: 7.6617,
        elevationM: 3260,
        category: LandmarkCategory.hut,
        id: 999,
      );
      expect(landmark.name, 'Hörnli Hut');
      expect(landmark.latitudeDeg, 45.9826);
      expect(landmark.elevationM, 3260);
      expect(landmark.category, LandmarkCategory.hut);
      expect(landmark.id, 999);
    });

    test('id is optional', () {
      const landmark = Landmark(
        name: 'Lake Oeschinen',
        latitudeDeg: 46.4978,
        longitudeDeg: 7.7264,
        elevationM: 1578,
        category: LandmarkCategory.lake,
      );
      expect(landmark.id, isNull);
    });

    test('equality by value', () {
      const a = Landmark(
        name: 'Grimsel Pass',
        latitudeDeg: 46.5721,
        longitudeDeg: 8.3380,
        elevationM: 2165,
        category: LandmarkCategory.pass,
      );
      const b = Landmark(
        name: 'Grimsel Pass',
        latitudeDeg: 46.5721,
        longitudeDeg: 8.3380,
        elevationM: 2165,
        category: LandmarkCategory.pass,
      );
      expect(a, equals(b));
    });

    test('different categories are not equal', () {
      const a = Landmark(
        name: 'Test',
        latitudeDeg: 46.0,
        longitudeDeg: 7.0,
        elevationM: 2000,
        category: LandmarkCategory.hut,
      );
      const b = Landmark(
        name: 'Test',
        latitudeDeg: 46.0,
        longitudeDeg: 7.0,
        elevationM: 2000,
        category: LandmarkCategory.lake,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes name and category', () {
      const landmark = Landmark(
        name: 'Aletsch Glacier',
        latitudeDeg: 46.4,
        longitudeDeg: 8.1,
        elevationM: 3000,
        category: LandmarkCategory.glacier,
      );
      final str = landmark.toString();
      expect(str, contains('Aletsch Glacier'));
      expect(str, contains('Glacier'));
    });
  });
}
