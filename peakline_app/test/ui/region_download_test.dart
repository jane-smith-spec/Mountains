import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/models/tile_index.dart';
import 'package:peakline_app/ui/screens/region_download_screen.dart';

void main() {
  group('RegionPreset', () {
    test('all presets have valid coordinates', () {
      for (final region in kRegionPresets) {
        expect(region.centerLat, inInclusiveRange(-90, 90),
            reason: '${region.name} lat out of range');
        expect(region.centerLon, inInclusiveRange(-180, 180),
            reason: '${region.name} lon out of range');
        expect(region.radiusKm, greaterThan(0),
            reason: '${region.name} radius must be positive');
      }
    });

    test('all presets have non-empty names and descriptions', () {
      for (final region in kRegionPresets) {
        expect(region.name, isNotEmpty);
        expect(region.description, isNotEmpty);
      }
    });

    test('Swiss Alps preset covers expected tiles', () {
      const swiss = RegionPreset(
        name: 'Swiss Alps',
        description: 'test',
        centerLat: 46.5,
        centerLon: 7.8,
        radiusKm: 100,
      );

      final tiles = TileIndex.tilesForRadius(
        swiss.centerLat,
        swiss.centerLon,
        swiss.radiusKm,
      );

      // 100km radius from center of Switzerland should cover
      // a good chunk of the Alps
      expect(tiles.length, greaterThan(4));
      expect(tiles.length, lessThan(30));

      // Should include the tile containing the center point
      expect(
        tiles,
        contains(const TileIndex(latDeg: 46, lonDeg: 7)),
      );
    });

    test('each preset generates a reasonable number of tiles', () {
      for (final region in kRegionPresets) {
        final tiles = TileIndex.tilesForRadius(
          region.centerLat,
          region.centerLon,
          region.radiusKm,
        );
        // Should need at least 1 tile and not more than ~50
        expect(tiles.length, greaterThan(0),
            reason: '${region.name} needs at least 1 tile');
        expect(tiles.length, lessThan(50),
            reason: '${region.name} needs too many tiles');
      }
    });
  });

  group('Region tile coverage', () {
    test('intersection correctly finds available tiles', () {
      final needed = {
        const TileIndex(latDeg: 46, lonDeg: 7),
        const TileIndex(latDeg: 46, lonDeg: 8),
        const TileIndex(latDeg: 47, lonDeg: 7),
        const TileIndex(latDeg: 47, lonDeg: 8),
      };
      final available = {
        const TileIndex(latDeg: 46, lonDeg: 7),
        const TileIndex(latDeg: 47, lonDeg: 8),
        const TileIndex(latDeg: 48, lonDeg: 9), // not needed
      };

      final downloaded = needed.intersection(available);
      final missing = needed.difference(available);

      expect(downloaded.length, 2);
      expect(missing.length, 2);
      expect(missing, contains(const TileIndex(latDeg: 46, lonDeg: 8)));
      expect(missing, contains(const TileIndex(latDeg: 47, lonDeg: 7)));
    });

    test('progress calculation', () {
      const total = 10;
      const downloaded = 7;
      final progress = downloaded / total;
      expect(progress, closeTo(0.7, 0.01));
    });
  });
}
