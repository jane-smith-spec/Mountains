/// DEM repository — manages elevation tile files on the device.
///
/// This repository handles:
///   - Finding where DEM tiles are stored on the device
///   - Checking which tiles are available locally
///   - Providing tile file paths to the FFI bridge for computation
///   - Managing tile storage (download, delete, disk usage)
///
/// DEM tiles are stored as raw .hgt files in the app's documents
/// directory under `dem_tiles/`. Each file is a 1°×1° grid of
/// Int16 elevation values (SRTM/Copernicus format).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tile_index.dart';

/// Repository for DEM elevation tile data.
class DemRepository {
  DemRepository({String? basePath}) : _basePath = basePath;

  String? _basePath;

  /// Get the base directory for DEM tile storage.
  ///
  /// Creates the directory if it doesn't exist.
  Future<String> get tilePath async {
    if (_basePath != null) return _basePath!;

    final appDir = await getApplicationDocumentsDirectory();
    final demDir = Directory(p.join(appDir.path, 'dem_tiles'));
    if (!await demDir.exists()) {
      await demDir.create(recursive: true);
    }
    _basePath = demDir.path;
    return _basePath!;
  }

  /// Get the full file path for a specific DEM tile.
  Future<String> tileFilePath(TileIndex tile) async {
    final base = await tilePath;
    return p.join(base, tile.hgtFilename);
  }

  /// Check if a specific tile is available locally.
  Future<bool> hasTile(TileIndex tile) async {
    final path = await tileFilePath(tile);
    return File(path).exists();
  }

  /// Get all tiles that are available locally.
  Future<Set<TileIndex>> availableTiles() async {
    final base = await tilePath;
    final dir = Directory(base);

    if (!await dir.exists()) return {};

    final tiles = <TileIndex>{};
    await for (final entity in dir.list()) {
      if (entity is File) {
        final tile = _parseTileFilename(p.basename(entity.path));
        if (tile != null) tiles.add(tile);
      }
    }
    return tiles;
  }

  /// Get the tiles needed for a given observer position and radius.
  ///
  /// Returns a record with available and missing tiles.
  Future<({Set<TileIndex> available, Set<TileIndex> missing})>
      tilesForPosition(
    double latDeg,
    double lonDeg, {
    double radiusKm = 100.0,
  }) async {
    final needed = TileIndex.tilesForRadius(latDeg, lonDeg, radiusKm);
    final available = <TileIndex>{};
    final missing = <TileIndex>{};

    for (final tile in needed) {
      if (await hasTile(tile)) {
        available.add(tile);
      } else {
        missing.add(tile);
      }
    }

    return (available: available, missing: missing);
  }

  /// Get the file path for the tile containing a specific coordinate,
  /// or null if the tile isn't available locally.
  Future<String?> tilePathForCoordinate(
    double latDeg,
    double lonDeg,
  ) async {
    final tile = TileIndex.fromCoordinate(latDeg, lonDeg);
    if (await hasTile(tile)) {
      return tileFilePath(tile);
    }
    return null;
  }

  /// Delete a specific tile from local storage.
  Future<void> deleteTile(TileIndex tile) async {
    final path = await tileFilePath(tile);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Get total disk usage of all stored tiles in bytes.
  Future<int> diskUsageBytes() async {
    final base = await tilePath;
    final dir = Directory(base);

    if (!await dir.exists()) return 0;

    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Format disk usage as a human-readable string.
  Future<String> diskUsageLabel() async {
    final bytes = await diskUsageBytes();
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Parse a tile filename back to a TileIndex.
  /// Returns null if the filename doesn't match the expected pattern.
  TileIndex? _parseTileFilename(String filename) {
    // Expected format: N46E007.hgt or S12W077.hgt
    final regex = RegExp(r'^([NS])(\d{2})([EW])(\d{3})\.hgt$');
    final match = regex.firstMatch(filename);
    if (match == null) return null;

    int lat = int.parse(match.group(2)!);
    int lon = int.parse(match.group(4)!);

    if (match.group(1) == 'S') lat = -lat;
    if (match.group(3) == 'W') lon = -lon;

    return TileIndex(latDeg: lat, lonDeg: lon);
  }
}

// -----------------------------------------------------------------------
//  Riverpod provider
// -----------------------------------------------------------------------

final demRepositoryProvider = Provider<DemRepository>((ref) {
  return DemRepository();
});
