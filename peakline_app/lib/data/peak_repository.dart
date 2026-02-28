/// Peak repository — loads and queries the peak/landmark database.
///
/// The app ships with a bundled SQLite database of mountain peaks
/// (from OpenStreetMap) and landmarks. This repository provides
/// efficient spatial queries: "give me all peaks within X km of
/// this position."
///
/// The database schema:
///   peaks(id, name, lat, lon, elevation_m, prominence_m)
///   landmarks(id, name, lat, lon, elevation_m, category)
///
/// Spatial queries use a bounding-box pre-filter (fast integer
/// comparison on lat/lon) followed by an exact haversine distance
/// check on the candidates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/landmark.dart';
import '../models/peak.dart';

/// Repository for querying the peak and landmark database.
class PeakRepository {
  PeakRepository({this.dbPath});

  /// Path to the SQLite database file. If null, uses the default
  /// bundled database path.
  final String? dbPath;

  Database? _db;

  /// Open the database connection.
  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    final path = dbPath ?? p.join(await getDatabasesPath(), 'peaks.db');
    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  /// Initialize the database from a bundled asset.
  ///
  /// This should be called on first app launch to copy the bundled
  /// peak database from assets to the writable database directory.
  /// If the database already exists, this is a no-op.
  Future<void> ensureInitialized() async {
    final path = dbPath ?? p.join(await getDatabasesPath(), 'peaks.db');
    if (await databaseExists(path)) return;

    // The database will be created by the data preparation tools.
    // For now, create an empty database with the correct schema.
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS peaks (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            elevation_m REAL NOT NULL,
            prominence_m REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS landmarks (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            elevation_m REAL NOT NULL,
            category TEXT NOT NULL
          )
        ''');
        // Indexes for spatial bounding-box queries
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_peaks_lat ON peaks(lat)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_peaks_lon ON peaks(lon)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_landmarks_lat ON landmarks(lat)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_landmarks_lon ON landmarks(lon)');
      },
    );
    await db.close();
  }

  /// Find all peaks within a radius of a given position.
  ///
  /// Uses a bounding-box pre-filter for speed, then returns all
  /// candidates within the box. The caller (peak_visibility_service)
  /// does the precise distance filtering.
  ///
  /// [radiusKm] defaults to 100 km (our maximum ray-cast distance).
  Future<List<Peak>> peaksInRange({
    required double latDeg,
    required double lonDeg,
    double radiusKm = 100.0,
  }) async {
    final db = await _getDb();

    // Bounding box: 1° latitude ≈ 111 km
    final latMargin = radiusKm / 111.0;
    // Longitude degrees vary with latitude
    final lonMargin = radiusKm / (111.0 * _cosApprox(latDeg));

    final rows = await db.query(
      'peaks',
      where: 'lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
      whereArgs: [
        latDeg - latMargin,
        latDeg + latMargin,
        lonDeg - lonMargin,
        lonDeg + lonMargin,
      ],
    );

    return rows.map(_rowToPeak).toList();
  }

  /// Find all landmarks within a radius of a given position.
  Future<List<Landmark>> landmarksInRange({
    required double latDeg,
    required double lonDeg,
    double radiusKm = 100.0,
  }) async {
    final db = await _getDb();

    final latMargin = radiusKm / 111.0;
    final lonMargin = radiusKm / (111.0 * _cosApprox(latDeg));

    final rows = await db.query(
      'landmarks',
      where: 'lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
      whereArgs: [
        latDeg - latMargin,
        latDeg + latMargin,
        lonDeg - lonMargin,
        lonDeg + lonMargin,
      ],
    );

    return rows.map(_rowToLandmark).toList();
  }

  /// Get the total number of peaks in the database.
  Future<int> peakCount() async {
    final db = await _getDb();
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM peaks');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get the total number of landmarks in the database.
  Future<int> landmarkCount() async {
    final db = await _getDb();
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM landmarks');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Close the database connection.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // -----------------------------------------------------------------------
  //  Row mappers
  // -----------------------------------------------------------------------

  Peak _rowToPeak(Map<String, dynamic> row) {
    return Peak(
      id: row['id'] as int?,
      name: row['name'] as String,
      latitudeDeg: (row['lat'] as num).toDouble(),
      longitudeDeg: (row['lon'] as num).toDouble(),
      elevationM: (row['elevation_m'] as num).toDouble(),
      prominenceM: row['prominence_m'] != null
          ? (row['prominence_m'] as num).toDouble()
          : null,
    );
  }

  Landmark _rowToLandmark(Map<String, dynamic> row) {
    return Landmark(
      id: row['id'] as int?,
      name: row['name'] as String,
      latitudeDeg: (row['lat'] as num).toDouble(),
      longitudeDeg: (row['lon'] as num).toDouble(),
      elevationM: (row['elevation_m'] as num).toDouble(),
      category: _parseCategory(row['category'] as String),
    );
  }

  LandmarkCategory _parseCategory(String value) {
    return LandmarkCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => LandmarkCategory.other,
    );
  }

  /// Approximate cosine (avoids dart:math import for just this).
  static double _cosApprox(double degrees) {
    const pi = 3.14159265358979;
    final rad = degrees * pi / 180.0;
    final x2 = rad * rad;
    return 1.0 - x2 / 2.0 + x2 * x2 / 24.0;
  }
}

// -----------------------------------------------------------------------
//  Riverpod provider
// -----------------------------------------------------------------------

final peakRepositoryProvider = Provider<PeakRepository>((ref) {
  final repo = PeakRepository();
  ref.onDispose(() => repo.close());
  return repo;
});
