/// Viewpoint repository — persists bookmarked observation spots.
///
/// Users can save their current location + heading as a "viewpoint" to
/// revisit later. Each viewpoint stores:
///   - GPS coordinates and altitude
///   - Compass heading and pitch (camera orientation)
///   - User-given name and optional notes
///   - Timestamp
///
/// Viewpoints are stored in the SQLite database alongside DEM tiles
/// and peak data.
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// A saved observation viewpoint.
class Viewpoint {
  const Viewpoint({
    this.id,
    required this.name,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.altitudeM,
    required this.headingDeg,
    required this.pitchDeg,
    this.notes,
    this.createdAt,
  });

  final int? id;
  final String name;
  final double latitudeDeg;
  final double longitudeDeg;
  final double altitudeM;
  final double headingDeg;
  final double pitchDeg;
  final String? notes;
  final DateTime? createdAt;

  /// Distance from a given point in meters (rough Euclidean on degrees).
  double roughDistanceFrom(double lat, double lon) {
    final dLat = (latitudeDeg - lat) * 111000;
    final dLon = (longitudeDeg - lon) * 111000;
    return (dLat * dLat + dLon * dLon);
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'latitude_deg': latitudeDeg,
      'longitude_deg': longitudeDeg,
      'altitude_m': altitudeM,
      'heading_deg': headingDeg,
      'pitch_deg': pitchDeg,
      'notes': notes,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Viewpoint.fromMap(Map<String, dynamic> map) {
    return Viewpoint(
      id: map['id'] as int?,
      name: map['name'] as String,
      latitudeDeg: (map['latitude_deg'] as num).toDouble(),
      longitudeDeg: (map['longitude_deg'] as num).toDouble(),
      altitudeM: (map['altitude_m'] as num).toDouble(),
      headingDeg: (map['heading_deg'] as num).toDouble(),
      pitchDeg: (map['pitch_deg'] as num).toDouble(),
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Viewpoint copyWith({
    int? id,
    String? name,
    double? latitudeDeg,
    double? longitudeDeg,
    double? altitudeM,
    double? headingDeg,
    double? pitchDeg,
    String? notes,
    DateTime? createdAt,
  }) {
    return Viewpoint(
      id: id ?? this.id,
      name: name ?? this.name,
      latitudeDeg: latitudeDeg ?? this.latitudeDeg,
      longitudeDeg: longitudeDeg ?? this.longitudeDeg,
      altitudeM: altitudeM ?? this.altitudeM,
      headingDeg: headingDeg ?? this.headingDeg,
      pitchDeg: pitchDeg ?? this.pitchDeg,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'Viewpoint("$name", '
      '${latitudeDeg.toStringAsFixed(4)}°N, '
      '${longitudeDeg.toStringAsFixed(4)}°E, '
      '${altitudeM.toStringAsFixed(0)}m, '
      'heading=${headingDeg.toStringAsFixed(0)}°)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Viewpoint && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// SQLite-backed repository for bookmarked viewpoints.
class ViewpointRepository {
  ViewpointRepository({this.db});

  Database? db;

  static const _tableName = 'viewpoints';

  /// Open (or create) the viewpoints database.
  Future<void> open() async {
    if (db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'peakline_viewpoints.db');

    db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            latitude_deg REAL NOT NULL,
            longitude_deg REAL NOT NULL,
            altitude_m REAL NOT NULL,
            heading_deg REAL NOT NULL,
            pitch_deg REAL NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Insert a new viewpoint. Returns the database ID.
  Future<int> insert(Viewpoint viewpoint) async {
    await open();
    return db!.insert(_tableName, viewpoint.toMap());
  }

  /// Get all saved viewpoints, newest first.
  Future<List<Viewpoint>> getAll() async {
    await open();
    final rows = await db!.query(
      _tableName,
      orderBy: 'created_at DESC',
    );
    return rows.map(Viewpoint.fromMap).toList();
  }

  /// Get a single viewpoint by ID.
  Future<Viewpoint?> getById(int id) async {
    await open();
    final rows = await db!.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Viewpoint.fromMap(rows.first);
  }

  /// Update an existing viewpoint (by ID).
  Future<int> update(Viewpoint viewpoint) async {
    await open();
    return db!.update(
      _tableName,
      viewpoint.toMap(),
      where: 'id = ?',
      whereArgs: [viewpoint.id],
    );
  }

  /// Delete a viewpoint by ID.
  Future<int> delete(int id) async {
    await open();
    return db!.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get viewpoints near a given location, sorted by distance.
  Future<List<Viewpoint>> getNearby({
    required double latitudeDeg,
    required double longitudeDeg,
    double radiusDeg = 0.5,
  }) async {
    await open();
    final rows = await db!.query(
      _tableName,
      where: 'latitude_deg BETWEEN ? AND ? '
          'AND longitude_deg BETWEEN ? AND ?',
      whereArgs: [
        latitudeDeg - radiusDeg,
        latitudeDeg + radiusDeg,
        longitudeDeg - radiusDeg,
        longitudeDeg + radiusDeg,
      ],
      orderBy: 'created_at DESC',
    );
    final viewpoints = rows.map(Viewpoint.fromMap).toList();
    // Sort by actual distance
    viewpoints.sort((a, b) {
      final distA = a.roughDistanceFrom(latitudeDeg, longitudeDeg);
      final distB = b.roughDistanceFrom(latitudeDeg, longitudeDeg);
      return distA.compareTo(distB);
    });
    return viewpoints;
  }

  /// Total number of saved viewpoints.
  Future<int> count() async {
    await open();
    final result = await db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_tableName',
    );
    return result.first['cnt'] as int;
  }

  /// Close the database.
  Future<void> close() async {
    await db?.close();
    db = null;
  }
}
