import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/models/tile_index.dart';

void main() {
  group('TileIndex', () {
    test('hgtFilename for northern/eastern tile', () {
      const tile = TileIndex(latDeg: 46, lonDeg: 7);
      expect(tile.hgtFilename, 'N46E007.hgt');
    });

    test('hgtFilename for southern/western tile', () {
      const tile = TileIndex(latDeg: -12, lonDeg: -77);
      expect(tile.hgtFilename, 'S12W077.hgt');
    });

    test('hgtFilename pads latitude to 2 digits', () {
      const tile = TileIndex(latDeg: 5, lonDeg: 100);
      expect(tile.hgtFilename, 'N05E100.hgt');
    });

    test('hgtFilename pads longitude to 3 digits', () {
      const tile = TileIndex(latDeg: 46, lonDeg: 8);
      expect(tile.hgtFilename, 'N46E008.hgt');
    });

    test('fromCoordinate floors to southwest corner', () {
      final tile = TileIndex.fromCoordinate(46.578, 7.998);
      expect(tile.latDeg, 46);
      expect(tile.lonDeg, 7);
    });

    test('fromCoordinate handles negative coordinates', () {
      final tile = TileIndex.fromCoordinate(-33.85, -70.65);
      expect(tile.latDeg, -34);
      expect(tile.lonDeg, -71);
    });

    test('fromCoordinate on exact integer boundary', () {
      final tile = TileIndex.fromCoordinate(47.0, 8.0);
      expect(tile.latDeg, 47);
      expect(tile.lonDeg, 8);
    });

    test('equality by value', () {
      const a = TileIndex(latDeg: 46, lonDeg: 7);
      const b = TileIndex(latDeg: 46, lonDeg: 7);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different tiles', () {
      const a = TileIndex(latDeg: 46, lonDeg: 7);
      const b = TileIndex(latDeg: 46, lonDeg: 8);
      expect(a, isNot(equals(b)));
    });
  });

  group('TileIndex.tilesForRadius', () {
    test('single tile for very small radius', () {
      final tiles = TileIndex.tilesForRadius(46.5, 7.5, 1.0);
      // 1 km radius at lat 46.5 — should be just 1 tile
      expect(tiles, contains(const TileIndex(latDeg: 46, lonDeg: 7)));
    });

    test('multiple tiles for larger radius', () {
      // 60 km radius from center of Switzerland — should span several tiles
      final tiles = TileIndex.tilesForRadius(46.8, 8.2, 60.0);
      expect(tiles.length, greaterThan(1));
      // Should include the center tile
      expect(tiles, contains(const TileIndex(latDeg: 46, lonDeg: 8)));
    });

    test('100 km radius covers a reasonable number of tiles', () {
      final tiles = TileIndex.tilesForRadius(46.5, 7.5, 100.0);
      // ~100 km ≈ ~1° lat, ~1.5° lon at this latitude
      // Should be roughly 3×4 = 12 tiles, give or take
      expect(tiles.length, greaterThanOrEqualTo(4));
      expect(tiles.length, lessThanOrEqualTo(25));
    });
  });
}
