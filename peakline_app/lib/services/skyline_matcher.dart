/// Skyline matcher — determines camera heading from a mountain photo.
///
/// When a photo has GPS but no compass heading, this service figures
/// out which direction the camera was pointing by matching the shape
/// of the mountains in the photo against the computed 360° horizon
/// profile.
///
/// Algorithm (Normalized Cross-Correlation):
///   1. Extract the skyline from the photo (sky/terrain boundary)
///   2. Compute the full 360° horizon profile from the GPS position
///   3. Slide the photo skyline along the 360° profile
///   4. At each position, compute a similarity score (NCC)
///   5. The position with the highest score = camera heading
///
/// NCC is used because it's insensitive to differences in brightness
/// and contrast between the photo and the computed profile. A mountain
/// silhouette in a sunset photo matches just as well as one at noon.
library;

import 'dart:math' as math;

import '../ffi/native_bridge.dart';

/// Result of a skyline matching attempt.
class MatchResult {
  const MatchResult({
    required this.headingDeg,
    required this.confidence,
    required this.allScores,
  });

  /// Best-match heading in degrees (0 = North, 90 = East, etc.).
  final double headingDeg;

  /// Confidence score (0.0–1.0). Higher = better match.
  /// Typically: >0.8 = very confident, 0.5–0.8 = reasonable,
  /// <0.5 = uncertain (user should manually adjust).
  final double confidence;

  /// NCC scores at each tested heading (for debugging/visualization).
  final List<({double headingDeg, double score})> allScores;

  @override
  String toString() =>
      'MatchResult(heading=${headingDeg.toStringAsFixed(1)}°, '
      'confidence=${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Service that matches photo skylines against horizon profiles.
class SkylineMatcher {
  /// Match a photo skyline against a 360° horizon profile.
  ///
  /// [photoSkyline] — the sky/terrain boundary extracted from the photo,
  ///   as a list of elevation angles from left to right edge.
  /// [horizonProfile] — the full 360° profile from the C core.
  /// [photoFovDeg] — the horizontal field of view of the photo.
  /// [stepDeg] — angular step for sliding (smaller = more precise but slower).
  ///
  /// Returns a [MatchResult] with the best heading and confidence.
  MatchResult match({
    required List<double> photoSkyline,
    required List<HorizonPoint> horizonProfile,
    required double photoFovDeg,
    double stepDeg = 0.5,
  }) {
    if (photoSkyline.isEmpty || horizonProfile.isEmpty) {
      return const MatchResult(
        headingDeg: 0,
        confidence: 0,
        allScores: [],
      );
    }

    // Build a lookup: azimuth → elevation angle from the profile
    final profileMap = _buildProfileLookup(horizonProfile);

    final scores = <({double headingDeg, double score})>[];
    double bestScore = -2.0;
    double bestHeading = 0.0;

    // Slide the photo skyline across all possible headings
    for (double heading = 0; heading < 360; heading += stepDeg) {
      // Extract the profile slice that corresponds to this heading + FOV
      final profileSlice = _extractSlice(
        profileMap,
        heading,
        photoFovDeg,
        photoSkyline.length,
      );

      // Compute NCC between the photo skyline and this profile slice
      final score = _ncc(photoSkyline, profileSlice);
      scores.add((headingDeg: heading, score: score));

      if (score > bestScore) {
        bestScore = score;
        bestHeading = heading;
      }
    }

    // Refine the best heading with sub-step precision
    final refinedHeading = _refine(
      profileMap,
      photoSkyline,
      photoFovDeg,
      bestHeading,
      stepDeg,
    );

    return MatchResult(
      headingDeg: refinedHeading,
      confidence: bestScore.clamp(0.0, 1.0),
      allScores: scores,
    );
  }

  /// Build a sorted lookup array from the horizon profile.
  List<({double azimuthDeg, double elevationDeg})> _buildProfileLookup(
    List<HorizonPoint> profile,
  ) {
    final sorted = List<HorizonPoint>.from(profile)
      ..sort((a, b) => a.azimuthDeg.compareTo(b.azimuthDeg));
    return sorted
        .map((p) => (
              azimuthDeg: p.azimuthDeg,
              elevationDeg: p.elevationAngleDeg,
            ))
        .toList();
  }

  /// Extract a slice of the profile centered at [heading] with width [fovDeg].
  /// Resampled to [numPoints] evenly-spaced samples.
  List<double> _extractSlice(
    List<({double azimuthDeg, double elevationDeg})> profile,
    double heading,
    double fovDeg,
    int numPoints,
  ) {
    final result = List<double>.filled(numPoints, 0.0);
    final startAz = heading - fovDeg / 2.0;
    final step = fovDeg / (numPoints - 1);

    for (int i = 0; i < numPoints; i++) {
      double az = startAz + i * step;
      // Normalize to [0, 360)
      while (az < 0) az += 360.0;
      while (az >= 360) az -= 360.0;
      result[i] = _interpolateProfile(profile, az);
    }
    return result;
  }

  /// Interpolate the profile elevation at an arbitrary azimuth.
  double _interpolateProfile(
    List<({double azimuthDeg, double elevationDeg})> profile,
    double azimuth,
  ) {
    if (profile.isEmpty) return 0.0;

    // Binary search for the bracket
    int lo = 0;
    int hi = profile.length - 1;

    // Handle wraparound: if azimuth is less than the first point
    if (azimuth < profile.first.azimuthDeg ||
        azimuth > profile.last.azimuthDeg) {
      // Interpolate between last and first (wraparound)
      final a = profile.last;
      final b = profile.first;
      double span = (360.0 - a.azimuthDeg) + b.azimuthDeg;
      if (span == 0) return a.elevationDeg;
      double offset = azimuth > a.azimuthDeg
          ? azimuth - a.azimuthDeg
          : (360.0 - a.azimuthDeg) + azimuth;
      final t = offset / span;
      return a.elevationDeg + t * (b.elevationDeg - a.elevationDeg);
    }

    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (profile[mid].azimuthDeg <= azimuth) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final a = profile[lo];
    final b = profile[hi];
    final span = b.azimuthDeg - a.azimuthDeg;
    if (span == 0) return a.elevationDeg;
    final t = (azimuth - a.azimuthDeg) / span;
    return a.elevationDeg + t * (b.elevationDeg - a.elevationDeg);
  }

  /// Normalized Cross-Correlation between two equal-length signals.
  ///
  /// Returns a value in [-1, 1]:
  ///   +1 = perfect positive correlation (identical shape)
  ///    0 = no correlation
  ///   -1 = perfect negative correlation (inverted shape)
  double _ncc(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    final n = a.length;

    // Compute means
    double meanA = 0, meanB = 0;
    for (int i = 0; i < n; i++) {
      meanA += a[i];
      meanB += b[i];
    }
    meanA /= n;
    meanB /= n;

    // Compute NCC
    double sumAB = 0, sumA2 = 0, sumB2 = 0;
    for (int i = 0; i < n; i++) {
      final da = a[i] - meanA;
      final db = b[i] - meanB;
      sumAB += da * db;
      sumA2 += da * da;
      sumB2 += db * db;
    }

    final denom = math.sqrt(sumA2 * sumB2);
    if (denom == 0) return 0.0;
    return sumAB / denom;
  }

  /// Refine the heading estimate with finer steps around the best match.
  double _refine(
    List<({double azimuthDeg, double elevationDeg})> profile,
    List<double> photoSkyline,
    double fovDeg,
    double roughHeading,
    double roughStep,
  ) {
    double bestScore = -2.0;
    double bestHeading = roughHeading;
    final fineStep = roughStep / 10.0;

    for (double h = roughHeading - roughStep;
        h <= roughHeading + roughStep;
        h += fineStep) {
      double heading = h;
      while (heading < 0) heading += 360.0;
      while (heading >= 360) heading -= 360.0;

      final slice = _extractSlice(profile, heading, fovDeg, photoSkyline.length);
      final score = _ncc(photoSkyline, slice);

      if (score > bestScore) {
        bestScore = score;
        bestHeading = heading;
      }
    }

    return bestHeading;
  }
}
