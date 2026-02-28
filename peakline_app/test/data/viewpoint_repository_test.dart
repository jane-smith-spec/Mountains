import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/viewpoint_repository.dart';

void main() {
  group('Viewpoint', () {
    test('can be constructed with required fields', () {
      const viewpoint = Viewpoint(
        name: 'Eiger View',
        latitudeDeg: 46.5763,
        longitudeDeg: 7.9904,
        altitudeM: 2168,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );

      expect(viewpoint.name, 'Eiger View');
      expect(viewpoint.latitudeDeg, 46.5763);
      expect(viewpoint.longitudeDeg, 7.9904);
      expect(viewpoint.altitudeM, 2168);
      expect(viewpoint.headingDeg, 180.0);
      expect(viewpoint.pitchDeg, 5.0);
      expect(viewpoint.id, isNull);
      expect(viewpoint.notes, isNull);
    });

    test('toMap includes all fields', () {
      final viewpoint = Viewpoint(
        id: 1,
        name: 'Test Point',
        latitudeDeg: 46.0,
        longitudeDeg: 8.0,
        altitudeM: 1000,
        headingDeg: 90.0,
        pitchDeg: 0.0,
        notes: 'Great view of the alps',
        createdAt: DateTime(2025, 6, 15, 10, 30),
      );

      final map = viewpoint.toMap();

      expect(map['id'], 1);
      expect(map['name'], 'Test Point');
      expect(map['latitude_deg'], 46.0);
      expect(map['longitude_deg'], 8.0);
      expect(map['altitude_m'], 1000);
      expect(map['heading_deg'], 90.0);
      expect(map['pitch_deg'], 0.0);
      expect(map['notes'], 'Great view of the alps');
      expect(map['created_at'], contains('2025'));
    });

    test('toMap excludes null id', () {
      const viewpoint = Viewpoint(
        name: 'No ID',
        latitudeDeg: 46.0,
        longitudeDeg: 8.0,
        altitudeM: 1000,
        headingDeg: 0.0,
        pitchDeg: 0.0,
      );

      final map = viewpoint.toMap();
      expect(map.containsKey('id'), false);
    });

    test('fromMap round-trips correctly', () {
      final original = Viewpoint(
        id: 42,
        name: 'Matterhorn Viewpoint',
        latitudeDeg: 45.9763,
        longitudeDeg: 7.6586,
        altitudeM: 3883,
        headingDeg: 210.0,
        pitchDeg: 15.0,
        notes: 'Sunset spot',
        createdAt: DateTime(2025, 8, 1),
      );

      final map = original.toMap();
      final restored = Viewpoint.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.latitudeDeg, original.latitudeDeg);
      expect(restored.longitudeDeg, original.longitudeDeg);
      expect(restored.altitudeM, original.altitudeM);
      expect(restored.headingDeg, original.headingDeg);
      expect(restored.pitchDeg, original.pitchDeg);
      expect(restored.notes, original.notes);
    });

    test('copyWith updates specified fields', () {
      const viewpoint = Viewpoint(
        name: 'Original',
        latitudeDeg: 46.0,
        longitudeDeg: 8.0,
        altitudeM: 1000,
        headingDeg: 0.0,
        pitchDeg: 0.0,
      );

      final updated = viewpoint.copyWith(
        name: 'Updated',
        headingDeg: 180.0,
        notes: 'Added notes',
      );

      expect(updated.name, 'Updated');
      expect(updated.headingDeg, 180.0);
      expect(updated.notes, 'Added notes');
      expect(updated.latitudeDeg, 46.0); // Unchanged
      expect(updated.longitudeDeg, 8.0); // Unchanged
    });

    test('roughDistanceFrom computes squared distance', () {
      const viewpoint = Viewpoint(
        name: 'A',
        latitudeDeg: 46.0,
        longitudeDeg: 8.0,
        altitudeM: 1000,
        headingDeg: 0.0,
        pitchDeg: 0.0,
      );

      // Same point → distance 0
      expect(viewpoint.roughDistanceFrom(46.0, 8.0), 0);

      // Different point → positive
      expect(viewpoint.roughDistanceFrom(47.0, 9.0), greaterThan(0));
    });

    test('equality by id and name', () {
      const a = Viewpoint(
        id: 1,
        name: 'A',
        latitudeDeg: 46.0,
        longitudeDeg: 8.0,
        altitudeM: 1000,
        headingDeg: 0.0,
        pitchDeg: 0.0,
      );
      const b = Viewpoint(
        id: 1,
        name: 'A',
        latitudeDeg: 47.0, // Different position
        longitudeDeg: 9.0,
        altitudeM: 2000,
        headingDeg: 90.0,
        pitchDeg: 10.0,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes key info', () {
      const viewpoint = Viewpoint(
        name: 'Eiger',
        latitudeDeg: 46.5763,
        longitudeDeg: 7.9904,
        altitudeM: 2168,
        headingDeg: 180.0,
        pitchDeg: 5.0,
      );

      final str = viewpoint.toString();
      expect(str, contains('Eiger'));
      expect(str, contains('46.5763'));
      expect(str, contains('180'));
    });
  });

  group('ViewpointRepository', () {
    test('can be constructed without a database', () {
      final repo = ViewpointRepository();
      expect(repo.db, isNull);
    });

    // Note: actual database operations (insert, getAll, delete, etc.)
    // require sqflite which needs platform channels. These are tested
    // via integration tests on real devices.
  });
}
