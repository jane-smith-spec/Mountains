/// Tile manager — multi-resolution DEM tile selection.
///
/// The key insight: you don't need 30m resolution for mountains 80km
/// away. The tile manager picks the right resolution based on distance:
///
///   Distance       Resolution   Points per tile   File size
///   0–10 km        30m (1")     3601×3601         ~25 MB
///   10–40 km       90m (3")     1201×1201         ~2.8 MB
///   40–100 km      250m (9")    401×401           ~313 KB
///
/// This saves ~10x storage compared to using full resolution everywhere,
/// while keeping close terrain sharp and detailed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tile_index.dart';
import 'dem_repository.dart';

/// Resolution tiers for DEM data.
enum TileResolution {
  /// Full resolution: 1 arc-second (~30m). For nearby terrain (0–10 km).
  full(label: '30m', arcseconds: 1, maxDistanceKm: 10.0),

  /// Medium resolution: 3 arc-seconds (~90m). For mid-range (10–40 km).
  medium(label: '90m', arcseconds: 3, maxDistanceKm: 40.0),

  /// Low resolution: 9 arc-seconds (~250m). For distant terrain (40–100 km).
  low(label: '250m', arcseconds: 9, maxDistanceKm: 100.0);

  const TileResolution({
    required this.label,
    required this.arcseconds,
    required this.maxDistanceKm,
  });

  /// Human-readable label (e.g., "30m").
  final String label;

  /// Resolution in arc-seconds.
  final int arcseconds;

  /// Maximum distance in km where this resolution is used.
  final double maxDistanceKm;

  /// Number of grid points per degree at this resolution.
  int get gridSize => (3600 ~/ arcseconds) + 1;

  /// Approximate file size per tile in bytes.
  int get approxFileSizeBytes => gridSize * gridSize * 2; // Int16 = 2 bytes
}

/// A tile with its assigned resolution.
class ResolvedTile {
  const ResolvedTile({
    required this.index,
    required this.resolution,
    required this.distanceKm,
    this.filePath,
  });

  /// Which 1°×1° tile this is.
  final TileIndex index;

  /// The resolution tier assigned to this tile.
  final TileResolution resolution;

  /// Distance from the observer to the tile center (km).
  final double distanceKm;

  /// File path if the tile is available locally, null if it needs download.
  final String? filePath;

  /// Whether this tile is available for computation.
  bool get isAvailable => filePath != null;
}

/// Manages multi-resolution tile selection and availability.
class TileManager {
  TileManager({required this.demRepository});

  final DemRepository demRepository;

  /// Select the optimal resolution for a given distance.
  static TileResolution resolutionForDistance(double distanceKm) {
    if (distanceKm <= TileResolution.full.maxDistanceKm) {
      return TileResolution.full;
    }
    if (distanceKm <= TileResolution.medium.maxDistanceKm) {
      return TileResolution.medium;
    }
    return TileResolution.low;
  }

  /// Get all tiles needed for a position, with resolution assigned.
  ///
  /// Returns tiles sorted by distance (closest first), each tagged
  /// with its resolution tier and availability status.
  Future<List<ResolvedTile>> resolveTiles({
    required double observerLat,
    required double observerLon,
    double maxRadiusKm = 100.0,
  }) async {
    final needed = TileIndex.tilesForRadius(
      observerLat,
      observerLon,
      maxRadiusKm,
    );

    final result = <ResolvedTile>[];

    for (final tile in needed) {
      // Distance from observer to tile center
      final tileCenterLat = tile.latDeg + 0.5;
      final tileCenterLon = tile.lonDeg + 0.5;
      final distanceKm = _approxDistanceKm(
        observerLat,
        observerLon,
        tileCenterLat,
        tileCenterLon,
      );

      // Assign resolution based on distance
      final resolution = resolutionForDistance(distanceKm);

      // Check if tile is available locally
      // For now, we use full-resolution files for all tiers.
      // Multi-resolution tile conversion will be done by the
      // prepare_dem_tiles.py tool in a future step.
      final hasIt = await demRepository.hasTile(tile);
      final path = hasIt ? await demRepository.tileFilePath(tile) : null;

      result.add(ResolvedTile(
        index: tile,
        resolution: resolution,
        distanceKm: distanceKm,
        filePath: path,
      ));
    }

    // Sort by distance (closest tiles first — they matter most)
    result.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result;
  }

  /// Get only the available tiles for computation.
  Future<List<ResolvedTile>> availableTiles({
    required double observerLat,
    required double observerLon,
    double maxRadiusKm = 100.0,
  }) async {
    final all = await resolveTiles(
      observerLat: observerLat,
      observerLon: observerLon,
      maxRadiusKm: maxRadiusKm,
    );
    return all.where((t) => t.isAvailable).toList();
  }

  /// Calculate storage requirements for a given position.
  ///
  /// Returns the total estimated download size in bytes for all
  /// missing tiles.
  Future<int> estimatedDownloadBytes({
    required double observerLat,
    required double observerLon,
    double maxRadiusKm = 100.0,
  }) async {
    final tiles = await resolveTiles(
      observerLat: observerLat,
      observerLon: observerLon,
      maxRadiusKm: maxRadiusKm,
    );

    int totalBytes = 0;
    for (final tile in tiles) {
      if (!tile.isAvailable) {
        totalBytes += tile.resolution.approxFileSizeBytes;
      }
    }
    return totalBytes;
  }

  /// Approximate distance between two points in km.
  /// Uses equirectangular approximation (fast, accurate enough for
  /// tile selection at these scales).
  static double _approxDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const kmPerDeg = 111.0;
    final dLat = (lat2 - lat1) * kmPerDeg;
    // Approximate cos(lat) for longitude scaling
    const pi = 3.14159265358979;
    final avgLat = (lat1 + lat2) / 2.0;
    final cosLat = 1.0 - (avgLat * pi / 180.0) * (avgLat * pi / 180.0) / 2.0;
    final dLon = (lon2 - lon1) * kmPerDeg * cosLat;

    // Euclidean distance in km
    final d2 = dLat * dLat + dLon * dLon;
    // Newton's method for sqrt (avoid dart:math for this utility)
    if (d2 <= 0) return 0;
    double x = d2;
    for (int i = 0; i < 5; i++) {
      x = (x + d2 / x) / 2.0;
    }
    return x;
  }
}

// -----------------------------------------------------------------------
//  Riverpod provider
// -----------------------------------------------------------------------

final tileManagerProvider = Provider<TileManager>((ref) {
  final demRepo = ref.watch(demRepositoryProvider);
  return TileManager(demRepository: demRepo);
});
