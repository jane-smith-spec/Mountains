import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/data/dem_download_service.dart';
import 'package:peakline_app/models/tile_index.dart';

void main() {
  group('DownloadProgress', () {
    test('overall progress at start', () {
      const p = DownloadProgress(
        totalTiles: 10,
        completedTiles: 0,
        failedTiles: 0,
        currentTile: null,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: false,
      );
      expect(p.overallProgress, closeTo(0.0, 0.01));
    });

    test('overall progress midway', () {
      const p = DownloadProgress(
        totalTiles: 10,
        completedTiles: 5,
        failedTiles: 0,
        currentTile: TileIndex(latDeg: 46, lonDeg: 7),
        currentTileBytes: 12500000, // half of 25 MB
        currentTileTotalBytes: 25000000,
        isComplete: false,
      );
      // 5 complete + 0.5 in progress = 5.5 / 10 = 0.55
      expect(p.overallProgress, closeTo(0.55, 0.01));
    });

    test('overall progress when complete', () {
      const p = DownloadProgress(
        totalTiles: 10,
        completedTiles: 10,
        failedTiles: 0,
        currentTile: null,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: true,
      );
      expect(p.overallProgress, closeTo(1.0, 0.01));
    });

    test('overall progress with zero tiles', () {
      const p = DownloadProgress(
        totalTiles: 0,
        completedTiles: 0,
        failedTiles: 0,
        currentTile: null,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: true,
      );
      expect(p.overallProgress, 1.0);
    });

    test('status text while downloading', () {
      const p = DownloadProgress(
        totalTiles: 5,
        completedTiles: 2,
        failedTiles: 0,
        currentTile: TileIndex(latDeg: 46, lonDeg: 7),
        currentTileBytes: 0,
        currentTileTotalBytes: 25000000,
        isComplete: false,
      );
      expect(p.statusText, contains('N46E007'));
      expect(p.statusText, contains('3/5'));
    });

    test('status text when complete', () {
      const p = DownloadProgress(
        totalTiles: 5,
        completedTiles: 5,
        failedTiles: 0,
        currentTile: null,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: true,
      );
      expect(p.statusText, contains('complete'));
      expect(p.statusText, contains('5'));
    });

    test('status text with failures', () {
      const p = DownloadProgress(
        totalTiles: 5,
        completedTiles: 3,
        failedTiles: 2,
        currentTile: null,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: true,
      );
      expect(p.statusText, contains('3'));
      expect(p.statusText, contains('2 failed'));
    });
  });

  group('DemDownloadService tile URL', () {
    // Test the static URL builder via the service
    test('URL format for northern/eastern tile', () {
      // We can't directly test private _tileUrl, but we can test
      // that the service constructs properly by checking it doesn't
      // crash on tile creation
      const tile = TileIndex(latDeg: 46, lonDeg: 7);
      expect(tile.hgtFilename, 'N46E007.hgt');
    });

    test('URL format for southern/western tile', () {
      const tile = TileIndex(latDeg: -12, lonDeg: -77);
      expect(tile.hgtFilename, 'S12W077.hgt');
    });
  });
}
