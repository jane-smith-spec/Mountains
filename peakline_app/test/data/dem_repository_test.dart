import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/dem_repository.dart';
import 'package:peakline_app/models/tile_index.dart';

void main() {
  late Directory tempDir;
  late DemRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dem_test_');
    repo = DemRepository(basePath: tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('DemRepository', () {
    test('hasTile returns false for missing tile', () async {
      const tile = TileIndex(latDeg: 46, lonDeg: 7);
      expect(await repo.hasTile(tile), isFalse);
    });

    test('hasTile returns true for existing tile', () async {
      const tile = TileIndex(latDeg: 46, lonDeg: 7);
      // Create a fake tile file
      await File('${tempDir.path}/${tile.hgtFilename}').create();
      expect(await repo.hasTile(tile), isTrue);
    });

    test('availableTiles lists existing files', () async {
      await File('${tempDir.path}/N46E007.hgt').create();
      await File('${tempDir.path}/N47E008.hgt').create();
      await File('${tempDir.path}/not_a_tile.txt').create();

      final tiles = await repo.availableTiles();
      expect(tiles.length, 2);
      expect(tiles, contains(const TileIndex(latDeg: 46, lonDeg: 7)));
      expect(tiles, contains(const TileIndex(latDeg: 47, lonDeg: 8)));
    });

    test('tilesForPosition separates available and missing', () async {
      // Create one tile that would be needed for Zurich area
      await File('${tempDir.path}/N46E008.hgt').create();

      final result = await repo.tilesForPosition(47.0, 8.5, radiusKm: 50.0);
      // Should have at least one available and some missing
      expect(result.available, isNotEmpty);
      // The specific tiles depend on the radius calculation
    });

    test('tilePathForCoordinate returns path for existing tile', () async {
      await File('${tempDir.path}/N46E007.hgt').create();
      final path = await repo.tilePathForCoordinate(46.5, 7.5);
      expect(path, isNotNull);
      expect(path, endsWith('N46E007.hgt'));
    });

    test('tilePathForCoordinate returns null for missing tile', () async {
      final path = await repo.tilePathForCoordinate(46.5, 7.5);
      expect(path, isNull);
    });

    test('deleteTile removes the file', () async {
      const tile = TileIndex(latDeg: 46, lonDeg: 7);
      final file = File('${tempDir.path}/${tile.hgtFilename}');
      await file.create();
      expect(await file.exists(), isTrue);

      await repo.deleteTile(tile);
      expect(await file.exists(), isFalse);
    });

    test('deleteTile is safe for non-existent tile', () async {
      const tile = TileIndex(latDeg: 99, lonDeg: 99);
      // Should not throw
      await repo.deleteTile(tile);
    });

    test('diskUsageBytes counts file sizes', () async {
      // Create a file with some content
      final file = File('${tempDir.path}/N46E007.hgt');
      await file.writeAsBytes(List.filled(1024, 0));

      final usage = await repo.diskUsageBytes();
      expect(usage, 1024);
    });

    test('diskUsageLabel formats correctly', () async {
      // 2 MB file
      final file = File('${tempDir.path}/N46E007.hgt');
      await file.writeAsBytes(List.filled(2 * 1024 * 1024, 0));

      final label = await repo.diskUsageLabel();
      expect(label, '2.0 MB');
    });
  });
}
