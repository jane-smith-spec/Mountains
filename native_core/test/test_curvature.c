/**
 * test_curvature.c — Tests for Earth curvature and elevation angle functions.
 *
 * We test against known values that you can verify by hand:
 *   - At 50km distance, curvature drop should be ~174.5m
 *   - At 100km, ~698.0m
 *   - These are based on the formula: drop = d^2 / (2 * R * k)
 *     where R = 6,371,000m and k = 1.13
 */

#include "curvature.h"
#include <math.h>
#include <stdio.h>

/** Helper: check if two doubles are close enough (within tolerance). */
static int approx_equal(double a, double b, double tolerance) {
    return fabs(a - b) <= tolerance;
}

int test_curvature_drop_at_known_distances(void) {
    /*
     * Expected values (drop = d^2 / (2 * 6371000 * 1.13)):
     *   10km  →  6.95m
     *   50km  → 173.8m
     *  100km  → 695.1m
     */
    double drop_10km = peakline_curvature_drop(10000.0);
    double drop_50km = peakline_curvature_drop(50000.0);
    double drop_100km = peakline_curvature_drop(100000.0);

    if (!approx_equal(drop_10km, 6.95, 0.5)) {
        printf("    Expected ~6.95m at 10km, got %.2f\n", drop_10km);
        return 1;
    }
    if (!approx_equal(drop_50km, 173.8, 1.0)) {
        printf("    Expected ~173.8m at 50km, got %.2f\n", drop_50km);
        return 1;
    }
    if (!approx_equal(drop_100km, 695.1, 2.0)) {
        printf("    Expected ~695.1m at 100km, got %.2f\n", drop_100km);
        return 1;
    }
    return 0;
}

int test_curvature_drop_at_zero(void) {
    double drop = peakline_curvature_drop(0.0);
    if (!approx_equal(drop, 0.0, 0.001)) {
        printf("    Expected 0.0 at 0km, got %.6f\n", drop);
        return 1;
    }
    return 0;
}

int test_elevation_angle_same_altitude(void) {
    /*
     * Observer and target at the same altitude, 10km apart.
     * Due to curvature, the target appears BELOW horizontal.
     * Expected angle: slightly negative (about -0.04 degrees).
     */
    double angle = peakline_elevation_angle(1000.0, 1000.0, 10000.0);
    if (angle >= 0.0) {
        printf("    Expected negative angle for same-altitude at 10km, got %.4f\n", angle);
        return 1;
    }
    if (!approx_equal(angle, -0.04, 0.02)) {
        printf("    Expected ~-0.04 degrees, got %.4f\n", angle);
        return 1;
    }
    return 0;
}

int test_elevation_angle_higher_target(void) {
    /*
     * Observer at 500m, target mountain at 4000m, 20km away.
     * Height diff = 3500m, curvature drop at 20km = ~27.8m
     * Effective diff = 3500 - 27.8 = 3472.2m
     * Angle = atan2(3472.2, 20000) = ~9.85 degrees
     */
    double angle = peakline_elevation_angle(500.0, 4000.0, 20000.0);
    if (!approx_equal(angle, 9.85, 0.2)) {
        printf("    Expected ~9.85 degrees, got %.4f\n", angle);
        return 1;
    }
    return 0;
}

int test_elevation_angle_with_curvature(void) {
    /*
     * At 100km, curvature drop is ~695m.
     * Observer at 1000m, target at 1500m, 100km away.
     * Effective diff = 1500 - 695 - 1000 = -195m
     * So the target should appear BELOW horizontal.
     */
    double angle = peakline_elevation_angle(1000.0, 1500.0, 100000.0);
    if (angle >= 0.0) {
        printf("    Expected negative angle (curvature wins), got %.4f\n", angle);
        return 1;
    }
    return 0;
}
