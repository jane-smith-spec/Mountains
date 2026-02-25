/// Landmark data model — named points of interest that aren't peaks.
///
/// Landmarks include mountain huts, alpine lakes, passes, glaciers,
/// towns, etc. They use the same projection math as peaks but are
/// displayed with different icons and can be toggled by category.
library;

/// Categories of landmarks. Each can be toggled on/off independently.
enum LandmarkCategory {
  hut('Hut'),
  lake('Lake'),
  pass('Pass'),
  glacier('Glacier'),
  town('Town'),
  other('Other');

  const LandmarkCategory(this.label);

  /// Human-readable label for the UI toggle.
  final String label;
}

/// A named point of interest in the mountains.
class Landmark {
  const Landmark({
    required this.name,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.elevationM,
    required this.category,
    this.id,
  });

  /// Human-readable name (e.g., "Hörnli Hut", "Lake Oeschinen").
  final String name;

  /// Latitude in degrees (positive = North).
  final double latitudeDeg;

  /// Longitude in degrees (positive = East).
  final double longitudeDeg;

  /// Elevation in meters above sea level.
  final double elevationM;

  /// What kind of landmark this is.
  final LandmarkCategory category;

  /// Database ID. Null for synthetic test data.
  final int? id;

  @override
  String toString() =>
      'Landmark("$name", ${category.label}, '
      '${latitudeDeg.toStringAsFixed(4)}°N, '
      '${longitudeDeg.toStringAsFixed(4)}°E, '
      '${elevationM.toStringAsFixed(0)}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Landmark &&
          name == other.name &&
          latitudeDeg == other.latitudeDeg &&
          longitudeDeg == other.longitudeDeg &&
          category == other.category;

  @override
  int get hashCode => Object.hash(name, latitudeDeg, longitudeDeg, category);
}
