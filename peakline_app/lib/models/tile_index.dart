/// Tile index — identifies which DEM elevation tile to load.
///
/// DEM data is stored as 1°×1° tiles. Each tile covers one degree of
/// latitude and one degree of longitude. The tile is identified by
/// its southwest corner: N46E007 covers lat 46–47°N, lon 7–8°E.
///
/// The naming convention follows the SRTM/Copernicus standard:
///   N46E007.hgt — North 46°, East 7°
///   S12W077.hgt — South 12°, West 77°
library;

/// Identifies a single 1°×1° DEM tile by its southwest corner.
class TileIndex {
  const TileIndex({
    required this.latDeg,
    required this.lonDeg,
  });

  /// Create from a geographic coordinate (picks the tile containing that point).
  factory TileIndex.fromCoordinate(double latitudeDeg, double longitudeDeg) {
    return TileIndex(
      latDeg: latitudeDeg.floor(),
      lonDeg: longitudeDeg.floor(),
    );
  }

  /// Southwest corner latitude (integer degrees).
  final int latDeg;

  /// Southwest corner longitude (integer degrees).
  final int lonDeg;

  /// Standard .hgt filename for this tile (e.g., "N46E007.hgt").
  String get hgtFilename {
    final latPrefix = latDeg >= 0 ? 'N' : 'S';
    final lonPrefix = lonDeg >= 0 ? 'E' : 'W';
    final latStr = latDeg.abs().toString().padLeft(2, '0');
    final lonStr = lonDeg.abs().toString().padLeft(3, '0');
    return '$latPrefix$latStr$lonPrefix$lonStr.hgt';
  }

  /// Get all tiles needed to cover a circular area around a center point.
  ///
  /// [centerLat] and [centerLon] are in degrees.
  /// [radiusKm] is the radius in kilometers.
  ///
  /// Returns a set of tile indices covering the bounding box of the circle.
  static Set<TileIndex> tilesForRadius(
    double centerLat,
    double centerLon,
    double radiusKm,
  ) {
    // Rough conversion: 1° latitude ≈ 111 km
    final latSpan = radiusKm / 111.0;
    // 1° longitude varies with latitude
    final lonSpan = radiusKm / (111.0 * _cosApprox(centerLat));

    final minLat = (centerLat - latSpan).floor();
    final maxLat = (centerLat + latSpan).floor();
    final minLon = (centerLon - lonSpan).floor();
    final maxLon = (centerLon + lonSpan).floor();

    final tiles = <TileIndex>{};
    for (int lat = minLat; lat <= maxLat; lat++) {
      for (int lon = minLon; lon <= maxLon; lon++) {
        tiles.add(TileIndex(latDeg: lat, lonDeg: lon));
      }
    }
    return tiles;
  }

  /// Approximate cosine for latitude (good enough for tile math).
  static double _cosApprox(double degrees) {
    // Avoid importing dart:math for just this
    const pi = 3.14159265358979;
    final rad = degrees * pi / 180.0;
    // Taylor series: cos(x) ≈ 1 - x²/2 + x⁴/24
    final x2 = rad * rad;
    return 1.0 - x2 / 2.0 + x2 * x2 / 24.0;
  }

  @override
  String toString() => 'TileIndex($hgtFilename)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileIndex &&
          latDeg == other.latDeg &&
          lonDeg == other.lonDeg;

  @override
  int get hashCode => Object.hash(latDeg, lonDeg);
}
