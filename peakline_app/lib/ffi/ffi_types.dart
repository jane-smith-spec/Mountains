/// FFI type definitions matching the C structs in peakline.h
///
/// These classes tell Dart how to read memory that the C library writes.
/// Each field's type and position must exactly match the C struct layout,
/// or the values will be garbage.
///
/// Think of this like a translation dictionary: C speaks in raw memory
/// bytes, Dart speaks in objects. These classes are the translator.
library;

import 'dart:ffi';

/// A single point in a horizon profile.
///
/// Matches the C struct:
/// ```c
/// typedef struct {
///     float azimuth_deg;         // Compass direction (0=North, 90=East)
///     float elevation_angle_deg; // Angle above horizontal
///     float distance_m;          // Distance to the horizon point
///     float terrain_height_m;    // Ground elevation at that point
/// } PeaklineHorizonPoint;
/// ```
///
/// Example: azimuth=45°, elevation=3.2°, distance=12000m, height=2847m
/// means "Looking northeast, the ridgeline is 3.2° above horizontal,
/// 12km away, at a mountain that's 2847m above sea level."
final class PeaklineHorizonPoint extends Struct {
  @Float()
  external double azimuthDeg;

  @Float()
  external double elevationAngleDeg;

  @Float()
  external double distanceM;

  @Float()
  external double terrainHeightM;
}

/// Result of a horizon profile computation.
///
/// Matches the C struct:
/// ```c
/// typedef struct {
///     PeaklineHorizonPoint *points; // Array of horizon points
///     int32_t count;                // Number of points
///     int32_t status;               // 0 = success, nonzero = error
/// } PeaklineHorizonResult;
/// ```
///
/// The `points` field is a pointer to a C array. To access the Dart
/// values, we read from this pointer using array indexing.
///
/// IMPORTANT: After you're done with the result, you MUST call
/// peakline_free_profile() to release the C-allocated memory.
/// Dart's garbage collector doesn't know about C memory.
final class PeaklineHorizonResult extends Struct {
  external Pointer<PeaklineHorizonPoint> points;

  @Int32()
  external int count;

  @Int32()
  external int status;
}
