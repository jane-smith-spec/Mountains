import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/photo_repository.dart';

void main() {
  group('PhotoMetadata', () {
    test('hasGps requires both lat and lon', () {
      const noGps = PhotoMetadata();
      expect(noGps.hasGps, isFalse);

      const latOnly = PhotoMetadata(latitudeDeg: 46.0);
      expect(latOnly.hasGps, isFalse);

      const both = PhotoMetadata(latitudeDeg: 46.0, longitudeDeg: 7.0);
      expect(both.hasGps, isTrue);
    });

    test('hasHeading checks headingDeg', () {
      const noHeading = PhotoMetadata();
      expect(noHeading.hasHeading, isFalse);

      const withHeading = PhotoMetadata(headingDeg: 180.0);
      expect(withHeading.hasHeading, isTrue);
    });

    test('estimatedHorizontalFovDeg computes from focal length', () {
      // A typical phone with 4.25mm focal length should give ~60-80° FOV
      const meta = PhotoMetadata(focalLengthMm: 4.25);
      final fov = meta.estimatedHorizontalFovDeg;
      expect(fov, isNotNull);
      expect(fov!, greaterThan(50));
      expect(fov, lessThan(90));
    });

    test('estimatedHorizontalFovDeg is null without focal length', () {
      const meta = PhotoMetadata();
      expect(meta.estimatedHorizontalFovDeg, isNull);
    });

    test('estimatedHorizontalFovDeg handles zero focal length', () {
      const meta = PhotoMetadata(focalLengthMm: 0);
      expect(meta.estimatedHorizontalFovDeg, isNull);
    });

    test('longer focal length gives narrower FOV', () {
      const wide = PhotoMetadata(focalLengthMm: 2.5);
      const tele = PhotoMetadata(focalLengthMm: 10.0);

      expect(wide.estimatedHorizontalFovDeg, isNotNull);
      expect(tele.estimatedHorizontalFovDeg, isNotNull);
      expect(
        wide.estimatedHorizontalFovDeg!,
        greaterThan(tele.estimatedHorizontalFovDeg!),
      );
    });

    test('toString includes available fields', () {
      const meta = PhotoMetadata(
        latitudeDeg: 46.5,
        longitudeDeg: 7.5,
        headingDeg: 180.0,
        focalLengthMm: 4.25,
      );
      final str = meta.toString();
      expect(str, contains('46.5'));
      expect(str, contains('7.5'));
      expect(str, contains('180'));
      expect(str, contains('4.25'));
    });
  });

  group('ImportedPhoto', () {
    test('stores file path and metadata', () {
      const photo = ImportedPhoto(
        filePath: '/tmp/test.jpg',
        metadata: PhotoMetadata(latitudeDeg: 46.0, longitudeDeg: 7.0),
      );
      expect(photo.filePath, '/tmp/test.jpg');
      expect(photo.metadata.hasGps, isTrue);
    });
  });
}
