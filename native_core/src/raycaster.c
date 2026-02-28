/**
 * raycaster.c — Horizon profile computation via ray-casting.
 *
 * This is the "engine" of PeakLine. It answers the question:
 * "If I'm standing HERE, what does the horizon look like in every direction?"
 *
 * The algorithm is conceptually simple:
 *   1. Pick a compass direction (e.g., 45° = northeast).
 *   2. Start marching outward in that direction, step by step.
 *   3. At each step, look up "how high is the ground here?" from the DEM.
 *   4. Compute the angle you'd look up (or down) to see that point,
 *      accounting for Earth curvature.
 *   5. If this angle is higher than anything seen so far on this ray,
 *      it becomes the new "horizon" — closer ridges hide what's behind them.
 *   6. Repeat for every compass direction in the camera's field of view.
 *
 * Variable step size: We take small steps near the observer (where detail
 * matters) and larger steps far away (where you can't see small bumps).
 */

#include "raycaster.h"
#include "curvature.h"
#include "interpolation.h"
#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/** Convert degrees to radians. */
static double deg_to_rad(double deg) {
    return deg * (M_PI / 180.0);
}

/** Convert radians to degrees. */
static double rad_to_deg(double rad) {
    return rad * (180.0 / M_PI);
}

/*
 * --------------------------------------------------------------------------
 *  Geodesic destination point
 * --------------------------------------------------------------------------
 * Given a starting point (lat, lon), a compass bearing, and a distance,
 * compute where you'd end up on a sphere.
 *
 * This is a standard formula from spherical trigonometry. It's the same
 * math used by GPS devices and mapping software.
 *
 * Formula (from movable-type.co.uk/scripts/latlong.html):
 *   lat2 = asin(sin(lat1) * cos(d/R) + cos(lat1) * sin(d/R) * cos(bearing))
 *   lon2 = lon1 + atan2(sin(bearing) * sin(d/R) * cos(lat1),
 *                        cos(d/R) - sin(lat1) * sin(lat2))
 *
 * where R = Earth's radius, d = distance.
 */
void peakline_destination_point(
    double lat_deg, double lon_deg,
    double bearing_deg, double distance_m,
    double *out_lat, double *out_lon
) {
    double lat1 = deg_to_rad(lat_deg);
    double lon1 = deg_to_rad(lon_deg);
    double brng = deg_to_rad(bearing_deg);
    double d_over_R = distance_m / EARTH_RADIUS_M;

    double sin_lat1 = sin(lat1);
    double cos_lat1 = cos(lat1);
    double sin_dR = sin(d_over_R);
    double cos_dR = cos(d_over_R);

    double lat2 = asin(sin_lat1 * cos_dR + cos_lat1 * sin_dR * cos(brng));
    double lon2 = lon1 + atan2(sin(brng) * sin_dR * cos_lat1,
                                cos_dR - sin_lat1 * sin(lat2));

    *out_lat = rad_to_deg(lat2);
    *out_lon = rad_to_deg(lon2);
}

/**
 * Choose the step size based on distance from the observer.
 *
 * Near:  < 5km  →  50m steps  (captures small ridges and nearby features)
 * Mid:   5–30km → 200m steps  (good balance of speed and detail)
 * Far:   > 30km → 500m steps  (distant mountains are large, don't need fine steps)
 *
 * This saves a lot of computation: without variable steps, we'd need
 * 500m/50m = 10x more samples for distant terrain with no visible benefit.
 */
static double step_size_for_distance(double distance_m) {
    if (distance_m < 5000.0) {
        return 50.0;
    } else if (distance_m < 30000.0) {
        return 200.0;
    } else {
        return 500.0;
    }
}

float peakline_cast_ray(
    double observer_lat, double observer_lon, double observer_alt_m,
    double azimuth_deg, double max_distance_m,
    const PeaklineDemTile *tile,
    float *out_distance_m, float *out_terrain_h_m
) {
    float max_angle = -90.0f;  /* Start at "looking straight down" — anything beats this */
    float best_distance = 0.0f;
    float best_terrain_h = 0.0f;

    /* Start at 100m out (skip very close ground, which would just be your feet) */
    double distance = 100.0;

    while (distance <= max_distance_m) {
        /* Where on Earth is the point at this distance in this direction? */
        double target_lat, target_lon;
        peakline_destination_point(observer_lat, observer_lon,
                                   azimuth_deg, distance,
                                   &target_lat, &target_lon);

        /* Look up terrain height from the DEM */
        float terrain_h = peakline_dem_get_elevation(tile, target_lat, target_lon);

        /* Skip void (no data) points — could be ocean, missing data, etc. */
        if (terrain_h > (float)DEM_VOID_VALUE + 1.0f && terrain_h > -9998.0f) {
            /*
             * Compute the elevation angle from us to this terrain point.
             * The curvature module handles Earth curvature + atmospheric refraction.
             */
            double angle = peakline_elevation_angle(
                observer_alt_m, (double)terrain_h, distance
            );

            if ((float)angle > max_angle) {
                max_angle = (float)angle;
                best_distance = (float)distance;
                best_terrain_h = terrain_h;
            }
        }

        /* Move to the next step (variable size based on distance) */
        distance += step_size_for_distance(distance);
    }

    if (out_distance_m)  *out_distance_m = best_distance;
    if (out_terrain_h_m) *out_terrain_h_m = best_terrain_h;

    return max_angle;
}

int peakline_compute_horizon_from_tile(
    double observer_lat, double observer_lon, double observer_alt_m,
    double azimuth_start, double azimuth_end, double angular_step,
    double max_distance_m,
    const PeaklineDemTile *tile,
    PeaklineHorizonResult *result
) {
    if (!tile || !tile->data || !result) {
        return -1;
    }
    if (angular_step <= 0.0 || azimuth_start >= azimuth_end) {
        return -2;
    }

    /* How many rays do we need to cast? */
    int num_points = (int)((azimuth_end - azimuth_start) / angular_step) + 1;
    if (num_points <= 0) {
        return -3;
    }

    /* Allocate the result array */
    PeaklineHorizonPoint *points = (PeaklineHorizonPoint *)malloc(
        (size_t)num_points * sizeof(PeaklineHorizonPoint)
    );
    if (!points) {
        return -4;  /* Out of memory */
    }

    /* Cast a ray for each azimuth direction */
    int i = 0;
    for (double az = azimuth_start; az <= azimuth_end && i < num_points; az += angular_step, i++) {
        float dist, terrain_h;
        float angle = peakline_cast_ray(
            observer_lat, observer_lon, observer_alt_m,
            az, max_distance_m, tile,
            &dist, &terrain_h
        );

        points[i].azimuth_deg = (float)az;
        points[i].elevation_angle_deg = angle;
        points[i].distance_m = dist;
        points[i].terrain_height_m = terrain_h;
    }

    result->points = points;
    result->count = i;  /* Actual number of points computed */
    result->status = 0;

    return 0;
}
