/// Coordinate utilities — lat/lon math for distance and bearing.
///
/// These functions answer two basic geographic questions:
///   1. "How far is it from point A to point B?" → [haversineDistanceM]
///   2. "What compass direction is point B from point A?" → [bearingDeg]
///
/// Both use the **haversine formula**, which treats the Earth as a sphere.
/// This is accurate to ~0.3% (good enough for our purposes — we're drawing
/// lines on a phone screen, not landing spacecraft).
///
/// There's also [destinationPoint], which goes the other direction:
///   "If I walk 5 km due northeast, where do I end up?"
library;

import 'dart:math' as math;

import 'constants.dart';

/// Compute the great-circle distance between two points on Earth.
///
/// Uses the haversine formula, which is numerically stable for all
/// distances (unlike the simpler law-of-cosines formula, which fails
/// for very short distances due to floating-point rounding).
///
/// Returns distance in meters.
///
/// Example:
///   // Zurich to Bern ≈ 95 km
///   haversineDistanceM(47.3769, 8.5417, 46.9480, 7.4474) → ~95300
double haversineDistanceM(
  double lat1Deg,
  double lon1Deg,
  double lat2Deg,
  double lon2Deg,
) {
  final lat1 = lat1Deg * deg2Rad;
  final lat2 = lat2Deg * deg2Rad;
  final dLat = (lat2Deg - lat1Deg) * deg2Rad;
  final dLon = (lon2Deg - lon1Deg) * deg2Rad;

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) *
      math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadiusM * c;
}

/// Compute the initial bearing (forward azimuth) from point 1 to point 2.
///
/// Returns a compass bearing in degrees [0, 360).
///   0° = North, 90° = East, 180° = South, 270° = West.
///
/// Note: This is the *initial* bearing. On a sphere, the bearing changes
/// as you travel along a great circle. For distances under ~100 km (our
/// use case), the change is negligible.
///
/// Example:
///   // Zurich to Bern → roughly 250° (west-southwest)
///   bearingDeg(47.3769, 8.5417, 46.9480, 7.4474) → ~248
double bearingDeg(
  double lat1Deg,
  double lon1Deg,
  double lat2Deg,
  double lon2Deg,
) {
  final lat1 = lat1Deg * deg2Rad;
  final lat2 = lat2Deg * deg2Rad;
  final dLon = (lon2Deg - lon1Deg) * deg2Rad;

  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

  final bearing = math.atan2(y, x) * rad2Deg;
  return (bearing + 360.0) % 360.0;
}

/// Compute the destination point given a start point, bearing, and distance.
///
/// "If I start at (lat, lon) and walk [distanceM] meters in direction
/// [bearingDeg], where do I end up?"
///
/// Returns (latitude, longitude) in degrees.
///
/// This is used by the ray-caster: starting from the observer, march
/// outward in a given compass direction, and find the lat/lon at each
/// distance step so we can look up the terrain elevation there.
({double latDeg, double lonDeg}) destinationPoint(
  double lat1Deg,
  double lon1Deg,
  double bearingDegrees,
  double distanceM,
) {
  final lat1 = lat1Deg * deg2Rad;
  final lon1 = lon1Deg * deg2Rad;
  final brng = bearingDegrees * deg2Rad;
  final angularDist = distanceM / earthRadiusM;

  final sinLat1 = math.sin(lat1);
  final cosLat1 = math.cos(lat1);
  final sinDist = math.sin(angularDist);
  final cosDist = math.cos(angularDist);

  final lat2 = math.asin(
    sinLat1 * cosDist + cosLat1 * sinDist * math.cos(brng),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(brng) * sinDist * cosLat1,
        cosDist - sinLat1 * math.sin(lat2),
      );

  return (
    latDeg: lat2 * rad2Deg,
    lonDeg: lon2 * rad2Deg,
  );
}

/// Compute the elevation angle from an observer to a target point.
///
/// Given the observer's altitude, the target's altitude, the horizontal
/// distance between them, and Earth curvature, compute the angle above
/// (or below) horizontal that the observer must look to see the target.
///
/// Positive = looking up, negative = looking down.
///
/// This accounts for Earth curvature and atmospheric refraction:
/// distant ground "drops away" due to curvature, but refraction bends
/// light downward, partially compensating (making things appear ~13%
/// higher than pure geometry).
double elevationAngleDeg({
  required double observerAltM,
  required double targetAltM,
  required double distanceM,
}) {
  if (distanceM <= 0) return 0.0;

  // Earth curvature drop, corrected for atmospheric refraction.
  // drop = d² / (2 × R_eff)
  final curvatureDrop =
      (distanceM * distanceM) / (2.0 * effectiveEarthRadiusM);

  // Effective height difference: how high the target appears
  // relative to the observer, accounting for curvature.
  final effectiveHeightDiff = (targetAltM - curvatureDrop) - observerAltM;

  // Elevation angle = atan(height_diff / distance)
  return math.atan2(effectiveHeightDiff, distanceM) * rad2Deg;
}
