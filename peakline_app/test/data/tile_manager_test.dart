import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/dem_repository.dart';
import 'package:peakline_app/data/tile_manager.dart';

void main() {
  group('TileResolution', () {
    test('full resolution has correct grid size', () {
      expect(TileResolution.full.gridSize, 3601);
    });

    test('medium resolution has correct grid size', () {
      expect(TileResolution.medium.gridSize, 1201);
    });

    test('low resolution has correct grid size', () {
      expect(TileResolution.low.gridSize, 401);
    });

    test('file size estimates are reasonable', () {
      // Full: 3601×3601×2 ≈ 25.9 MB
      expect(TileResolution.full.approxFileSizeBytes, greaterThan(20000000));
      expect(TileResolution.full.approxFileSizeBytes, lessThan(30000000));

      // Medium: 1201×1201×2 ≈ 2.9 MB
      expect(TileResolution.medium.approxFileSizeBytes, greaterThan(2000000));
      expect(TileResolution.medium.approxFileSizeBytes, lessThan(4000000));

      // Low: 401×401×2 ≈ 322 KB
      expect(TileResolution.low.approxFileSizeBytes, greaterThan(200000));
      expect(TileResolution.low.approxFileSizeBytes, lessThan(500000));
    });
  });

  group('TileManager.resolutionForDistance', () {
    test('close range gets full resolution', () {
      expect(
        TileManager.resolutionForDistance(5.0),
        TileResolution.full,
      );
    });

    test('boundary at 10 km gets full resolution', () {
      expect(
        TileManager.resolutionForDistance(10.0),
        TileResolution.full,
      );
    });

    test('mid range gets medium resolution', () {
      expect(
        TileManager.resolutionForDistance(25.0),
        TileResolution.medium,
      );
    });

    test('boundary at 40 km gets medium resolution', () {
      expect(
        TileManager.resolutionForDistance(40.0),
        TileResolution.medium,
      );
    });

    test('far range gets low resolution', () {
      expect(
        TileManager.resolutionForDistance(80.0),
        TileResolution.low,
      );
    });

    test('very far gets low resolution', () {
      expect(
        TileManager.resolutionForDistance(100.0),
        TileResolution.low,
      );
    });
  });

  group('TileManager.resolveTiles', () {
    late Directory tempDir;
    late DemRepository demRepo;
    late TileManager tileManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tile_mgr_test_');
      demRepo = DemRepository(basePath: tempDir.path);
      tileManager = TileManager(demRepository: demRepo);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns tiles sorted by distance', () async {
      final tiles = await tileManager.resolveTiles(
        observerLat: 46.8,
        observerLon: 8.2,
        maxRadiusKm: 50.0,
      );

      expect(tiles, isNotEmpty);
      // Verify sorted by distance
      for (int i = 1; i < tiles.length; i++) {
        expect(tiles[i].distanceKm, greaterThanOrEqualTo(tiles[i - 1].distanceKm));
      }
    });

    test('closest tiles get higher resolution', () async {
      final tiles = await tileManager.resolveTiles(
        observerLat: 46.8,
        observerLon: 8.2,
        maxRadiusKm: 100.0,
      );

      if (tiles.length >= 2) {
        // The closest tile should have the best (or equal) resolution
        expect(
          tiles.first.resolution.arcseconds,
          lessThanOrEqualTo(tiles.last.resolution.arcseconds),
        );
      }
    });

    test('available tiles have file paths', () async {
      // Create a tile file
      await File('${tempDir.path}/N46E008.hgt').create();

      final tiles = await tileManager.resolveTiles(
        observerLat: 46.5,
        observerLon: 8.5,
        maxRadiusKm: 50.0,
      );

      final n46e008 = tiles.where(
        (t) => t.index.latDeg == 46 && t.index.lonDeg == 8,
      );
      if (n46e008.isNotEmpty) {
        expect(n46e008.first.isAvailable, isTrue);
        expect(n46e008.first.filePath, isNotNull);
      }
    });

    test('missing tiles have null file paths', () async {
      final tiles = await tileManager.resolveTiles(
        observerLat: 46.5,
        observerLon: 8.5,
        maxRadiusKm: 50.0,
      );

      // With an empty temp dir, all tiles should be missing
      for (final tile in tiles) {
        expect(tile.isAvailable, isFalse);
        expect(tile.filePath, isNull);
      }
    });

    test('availableTiles filters out missing ones', () async {
      final available = await tileManager.availableTiles(
        observerLat: 46.5,
        observerLon: 8.5,
        maxRadiusKm: 50.0,
      );

      // Empty temp dir → no available tiles
      expect(available, isEmpty);
    });
  });
}
