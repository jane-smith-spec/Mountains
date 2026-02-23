/**
 * curvature.h — Earth curvature and atmospheric refraction corrections.
 *
 * When you look at a mountain 50km away, the Earth's curvature means
 * the ground at that distance is actually ~196 meters lower than a flat
 * plane would suggest. But atmospheric refraction bends light slightly
 * downward, making distant objects appear ~13% higher than pure geometry
 * predicts. We must account for both effects.
 *
 * Without these corrections, distant peaks would appear in the wrong
 * position on the overlay (too low).
 */

#ifndef PEAKLINE_CURVATURE_H
#define PEAKLINE_CURVATURE_H

/** Mean radius of the Earth in meters. */
#define EARTH_RADIUS_M 6371000.0

/**
 * Standard atmospheric refraction coefficient.
 * k = 1.13 means light curves enough to see ~13% "over" the geometric horizon.
 * This is the standard surveying value for normal atmospheric conditions.
 */
#define REFRACTION_K 1.13

/**
 * Compute the effective height drop due to Earth curvature and atmospheric
 * refraction at a given distance.
 *
 * At distance d from the observer, a point on the ground is this many meters
 * lower than it would be on a flat plane:
 *
 *   drop = d^2 / (2 * R * k)
 *
 * where R = Earth radius, k = refraction coefficient.
 *
 * Parameters:
 *   distance_m - Distance from observer in meters
 *
 * Returns: Height drop in meters (always positive).
 *
 * Examples:
 *   At  10km: ~  7.0m drop
 *   At  50km: ~174.5m drop
 *   At 100km: ~698.0m drop
 */
double peakline_curvature_drop(double distance_m);

/**
 * Compute the elevation angle from an observer to a target point,
 * accounting for Earth curvature and atmospheric refraction.
 *
 * Parameters:
 *   observer_alt_m - Observer's altitude in meters above sea level
 *   target_alt_m   - Target's altitude in meters above sea level
 *   distance_m     - Horizontal distance between observer and target in meters
 *
 * Returns: Elevation angle in degrees.
 *          Positive = target is above horizontal.
 *          Negative = target is below horizontal.
 */
double peakline_elevation_angle(
    double observer_alt_m,
    double target_alt_m,
    double distance_m
);

#endif /* PEAKLINE_CURVATURE_H */
