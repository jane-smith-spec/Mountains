import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/region_data.dart';
import 'package:peakline_app/models/tile_index.dart';

void main() {
  group('RegionBbox', () {
    test('tiles covers correct grid', () {
      const bbox = RegionBbox(
        minLat: 46.2,
        minLon: 7.3,
        maxLat: 47.8,
        maxLon: 8.9,
      );
      final tiles = bbox.tiles;

      // Should cover lat 46–47, lon 7–8 → 2×2 = 4 tiles
      expect(tiles.length, 4);
      expect(tiles, contains(const TileIndex(latDeg: 46, lonDeg: 7)));
      expect(tiles, contains(const TileIndex(latDeg: 46, lonDeg: 8)));
      expect(tiles, contains(const TileIndex(latDeg: 47, lonDeg: 7)));
      expect(tiles, contains(const TileIndex(latDeg: 47, lonDeg: 8)));
    });

    test('single-tile bbox', () {
      const bbox = RegionBbox(
        minLat: 46.2,
        minLon: 7.3,
        maxLat: 46.8,
        maxLon: 7.9,
      );
      expect(bbox.tiles.length, 1);
      expect(bbox.tiles.first, const TileIndex(latDeg: 46, lonDeg: 7));
    });

    test('estimated size is positive', () {
      const bbox = RegionBbox(
        minLat: 46.0,
        minLon: 7.0,
        maxLat: 47.0,
        maxLon: 8.0,
      );
      expect(bbox.estimatedSizeMB, greaterThan(0));
    });
  });

  group('Country catalog', () {
    test('all countries have valid codes', () {
      for (final country in kCountryCatalog) {
        expect(country.code.length, 2,
            reason: '${country.name} code should be 2 chars');
        expect(country.name, isNotEmpty);
        expect(country.emoji, isNotEmpty);
      }
    });

    test('all countries have at least one state', () {
      for (final country in kCountryCatalog) {
        expect(country.states, isNotEmpty,
            reason: '${country.name} needs at least one state');
      }
    });

    test('all states have valid bounding boxes', () {
      for (final country in kCountryCatalog) {
        for (final state in country.states) {
          expect(state.name, isNotEmpty);
          expect(state.bbox.minLat, lessThan(state.bbox.maxLat),
              reason:
                  '${country.name}/${state.name}: minLat must be < maxLat');
          expect(state.bbox.minLon, lessThan(state.bbox.maxLon),
              reason:
                  '${country.name}/${state.name}: minLon must be < maxLon');
          expect(state.bbox.minLat, inInclusiveRange(-90, 90));
          expect(state.bbox.maxLat, inInclusiveRange(-90, 90));
          expect(state.bbox.minLon, inInclusiveRange(-180, 180));
          expect(state.bbox.maxLon, inInclusiveRange(-180, 180));
        }
      }
    });

    test('country bbox is union of all state bboxes', () {
      for (final country in kCountryCatalog) {
        final cb = country.bbox;
        for (final state in country.states) {
          expect(cb.minLat, lessThanOrEqualTo(state.bbox.minLat),
              reason: '${country.name} bbox should contain ${state.name}');
          expect(cb.maxLat, greaterThanOrEqualTo(state.bbox.maxLat),
              reason: '${country.name} bbox should contain ${state.name}');
          expect(cb.minLon, lessThanOrEqualTo(state.bbox.minLon),
              reason: '${country.name} bbox should contain ${state.name}');
          expect(cb.maxLon, greaterThanOrEqualTo(state.bbox.maxLon),
              reason: '${country.name} bbox should contain ${state.name}');
        }
      }
    });

    test('each state generates a reasonable number of tiles', () {
      for (final country in kCountryCatalog) {
        for (final state in country.states) {
          final tiles = state.bbox.tiles;
          expect(tiles.length, greaterThan(0),
              reason: '${country.name}/${state.name} needs at least 1 tile');
          // States shouldn't need thousands of tiles
          expect(tiles.length, lessThan(2000),
              reason:
                  '${country.name}/${state.name} has ${tiles.length} tiles');
        }
      }
    });

    test('Switzerland Valais covers Matterhorn tile', () {
      final ch = kCountryCatalog.firstWhere((c) => c.code == 'CH');
      final valais = ch.states.firstWhere((s) => s.name == 'Valais');
      final tiles = valais.bbox.tiles;

      // Matterhorn is at ~45.97°N, 7.65°E → tile N45E007
      expect(tiles, contains(const TileIndex(latDeg: 45, lonDeg: 7)));
    });

    test('US Colorado covers 14er tiles', () {
      final us = kCountryCatalog.firstWhere((c) => c.code == 'US');
      final co = us.states.firstWhere((s) => s.name == 'Colorado');
      final tiles = co.bbox.tiles;

      // Mt. Elbert ~39.12°N, -106.45°W → tile N39W107
      expect(tiles, contains(const TileIndex(latDeg: 39, lonDeg: -107)));
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
