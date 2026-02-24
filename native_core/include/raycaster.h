/**
 * raycaster.h — Horizon profile computation via ray-casting.
 *
 * This is the core algorithm of PeakLine. Here's how it works:
 *
 * Imagine standing on a hilltop and slowly turning your head from left to
 * right. At each direction, you note the highest point on the horizon.
 * That's exactly what this code does mathematically:
 *
 * 1. For each compass direction (azimuth) in the field of view:
 * 2.   Cast a "ray" outward — march from 100m to 100km in steps
 * 3.   At each step, look up the terrain height from the DEM data
 * 4.   Compute "what angle would I look up/down to see this point?"
 *      (accounting for Earth curvature — distant ground curves away)
 * 5.   Keep track of the MAXIMUM angle seen — that's the ridgeline
 *      (because a closer ridge blocks what's behind it)
 * 6. The result is a series of (direction, angle) pairs = the horizon shape
 *
 * The variable step size is an important optimization:
 *   - Near the observer (< 5km): fine steps, because small features matter
 *   - Mid-range (5–30km): medium steps
 *   - Far away (> 30km): coarse steps, because you can't see small features anyway
 */

#ifndef PEAKLINE_RAYCASTER_H
#define PEAKLINE_RAYCASTER_H

#include "peakline.h"
#include "dem_io.h"

/**
 * Compute the destination point given a start point, bearing, and distance.
 *
 * "If I'm standing at (lat, lon) and walk `distance_m` meters in the
 * direction `bearing_deg`, where do I end up?"
 *
 * Uses the standard geodesic "destination point" formula, which accounts
 * for the fact that the Earth is a sphere.
 *
 * Parameters:
 *   lat_deg      - Starting latitude in degrees
 *   lon_deg      - Starting longitude in degrees
 *   bearing_deg  - Compass bearing in degrees (0=North, 90=East)
 *   distance_m   - Distance to travel in meters
 *   out_lat      - Output: destination latitude in degrees
 *   out_lon      - Output: destination longitude in degrees
 */
void peakline_destination_point(
    double lat_deg, double lon_deg,
    double bearing_deg, double distance_m,
    double *out_lat, double *out_lon
);

/**
 * Cast a single ray from the observer in a given azimuth direction,
 * finding the highest elevation angle along that ray.
 *
 * This is the inner loop of the horizon computation: march outward,
 * check terrain height at each step, and track the maximum angle.
 *
 * Parameters:
 *   observer_lat     - Observer latitude in degrees
 *   observer_lon     - Observer longitude in degrees
 *   observer_alt_m   - Observer altitude in meters ASL
 *   azimuth_deg      - Compass direction to cast the ray
 *   max_distance_m   - How far to cast (e.g., 100000 for 100km)
 *   tile             - Loaded DEM tile to sample elevations from
 *   out_distance_m   - Output: distance to the horizon point in meters
 *   out_terrain_h_m  - Output: terrain height at the horizon point
 *
 * Returns: The maximum elevation angle in degrees.
 */
float peakline_cast_ray(
    double observer_lat, double observer_lon, double observer_alt_m,
    double azimuth_deg, double max_distance_m,
    const PeaklineDemTile *tile,
    float *out_distance_m, float *out_terrain_h_m
);

/**
 * Compute the full horizon profile from an observer position.
 *
 * Sweeps from azimuth_start to azimuth_end, casting a ray at each
 * angular_step interval, and returns an array of horizon points.
 *
 * Parameters:
 *   observer_lat     - Observer latitude in degrees
 *   observer_lon     - Observer longitude in degrees
 *   observer_alt_m   - Observer altitude in meters ASL
 *   azimuth_start    - Start direction in degrees (e.g., 0 for north)
 *   azimuth_end      - End direction in degrees (e.g., 360 for full circle)
 *   angular_step     - Degrees between each ray (e.g., 0.1)
 *   max_distance_m   - Maximum ray distance in meters
 *   tile             - Loaded DEM tile
 *   result           - Output: filled with computed horizon points
 *
 * Returns: 0 on success, nonzero on error.
 */
int peakline_compute_horizon_from_tile(
    double observer_lat, double observer_lon, double observer_alt_m,
    double azimuth_start, double azimuth_end, double angular_step,
    double max_distance_m,
    const PeaklineDemTile *tile,
    PeaklineHorizonResult *result
);

#endif /* PEAKLINE_RAYCASTER_H */
