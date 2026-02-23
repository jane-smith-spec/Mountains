/**
 * curvature.c — Earth curvature and atmospheric refraction corrections.
 */

#include "curvature.h"
#include <math.h>

double peakline_curvature_drop(double distance_m) {
    /*
     * drop = d^2 / (2 * R * k)
     *
     * R = 6,371,000 m (mean Earth radius)
     * k = 1.13 (standard atmospheric refraction coefficient)
     *
     * The denominator (2 * R * k) is a constant: 14,398,460 m
     */
    return (distance_m * distance_m) / (2.0 * EARTH_RADIUS_M * REFRACTION_K);
}

double peakline_elevation_angle(
    double observer_alt_m,
    double target_alt_m,
    double distance_m
) {
    if (distance_m <= 0.0) {
        return 0.0;
    }

    double drop = peakline_curvature_drop(distance_m);
    double effective_height_diff = target_alt_m - drop - observer_alt_m;

    /* atan2 gives the angle in radians; convert to degrees */
    double angle_rad = atan2(effective_height_diff, distance_m);
    return angle_rad * (180.0 / M_PI);
}
