import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/photo_repository.dart';

const double coordinateTolerance = 0.000001;

void main() {
  group('PhotoRepository.parseCoordinate', () {
    test('parses DMS coordinate with positive hemisphere', () {
      final double? value = PhotoRepository.parseCoordinate(
        rawCoordinate: '46, 30, 0',
        directionRef: 'N',
      );

      expect(value, closeTo(46.5, coordinateTolerance));
    });

    test('parses fractional DMS coordinate and applies hemisphere sign', () {
      final double? value = PhotoRepository.parseCoordinate(
        rawCoordinate: '46/1, 30/1, 0/1',
        directionRef: 'W',
      );

      expect(value, closeTo(-46.5, coordinateTolerance));
    });
  });
}
