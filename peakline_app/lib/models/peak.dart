/// Peak data model — a named mountain summit.
///
/// Represents a peak from our database (sourced from OpenStreetMap and
/// GeoNames). Each peak has a geographic position and metadata that
/// we display on the AR overlay as a flag/label.
library;

/// A mountain peak with its geographic data and metadata.
class Peak {
  const Peak({
    required this.name,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.elevationM,
    this.prominenceM,
    this.id,
  });

  /// Human-readable name (e.g., "Matterhorn", "Mont Blanc").
  final String name;

  /// Latitude in degrees (positive = North).
  final double latitudeDeg;

  /// Longitude in degrees (positive = East).
  final double longitudeDeg;

  /// Summit elevation in meters above sea level.
  final double elevationM;

  /// Topographic prominence in meters (how much the peak "stands out").
  /// Null if unknown. Higher prominence = more significant peak.
  final double? prominenceM;

  /// Database ID (e.g., OSM node ID). Null for synthetic test data.
  final int? id;

  @override
  String toString() =>
      'Peak("$name", ${latitudeDeg.toStringAsFixed(4)}°N, '
      '${longitudeDeg.toStringAsFixed(4)}°E, ${elevationM.toStringAsFixed(0)}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peak &&
          name == other.name &&
          latitudeDeg == other.latitudeDeg &&
          longitudeDeg == other.longitudeDeg &&
          elevationM == other.elevationM;

  @override
  int get hashCode => Object.hash(name, latitudeDeg, longitudeDeg, elevationM);
}
