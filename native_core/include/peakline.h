/**
 * peakline.h — Public API for the PeakLine native core library.
 *
 * This is the single header that Dart FFI calls into. All functions here
 * are exported as C symbols (no C++ name mangling).
 *
 * The native core handles the computationally expensive work:
 *   - Loading and interpolating DEM (elevation) tiles
 *   - Ray-casting horizon profiles
 *   - Earth curvature and atmospheric refraction correction
 *   - Skyline matching (NCC) for photo heading detection
 *
 * This file is the "contract" between Dart and C. If you change a function
 * signature here, you must also update native_bridge.dart on the Dart side.
 */

#ifndef PEAKLINE_H
#define PEAKLINE_H

#include <stdint.h>

#ifdef _WIN32
#define PEAKLINE_EXPORT __declspec(dllexport)
#else
#define PEAKLINE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Returns the library version as a packed integer: major*10000 + minor*100 + patch.
 * Example: version 0.1.0 returns 100.
 *
 * Use this to verify the Dart side is linked to the expected native library version.
 */
PEAKLINE_EXPORT int32_t peakline_version(void);

/**
 * A single point in a horizon profile.
 */
typedef struct {
    float azimuth_deg;        /* Compass direction in degrees (0=North, 90=East) */
    float elevation_angle_deg; /* Angle above horizontal in degrees */
    float distance_m;          /* Distance to the horizon point in meters */
    float terrain_height_m;    /* Elevation of the terrain at that point (meters ASL) */
} PeaklineHorizonPoint;

/**
 * Result of a horizon profile computation.
 * The caller must free this with peakline_free_profile().
 */
typedef struct {
    PeaklineHorizonPoint *points; /* Array of horizon points */
    int32_t count;                /* Number of points in the array */
    int32_t status;               /* 0 = success, nonzero = error code */
} PeaklineHorizonResult;

/**
 * Compute the horizon profile visible from an observer position.
 *
 * Parameters:
 *   observer_lat    - Observer latitude in degrees (positive = North)
 *   observer_lon    - Observer longitude in degrees (positive = East)
 *   observer_alt_m  - Observer altitude in meters above sea level
 *   azimuth_start   - Start of azimuth range in degrees (e.g., 0 for full circle)
 *   azimuth_end     - End of azimuth range in degrees (e.g., 360 for full circle)
 *   angular_step    - Angular resolution in degrees (e.g., 0.1)
 *   max_distance_m  - Maximum ray-cast distance in meters (e.g., 100000 for 100km)
 *   dem_path        - Path to the DEM tile file (.hgt format)
 *
 * Returns: A PeaklineHorizonResult. Caller must free with peakline_free_profile().
 *
 * NOTE: This is a placeholder signature. It will be expanded in Step 5 to support
 * multiple DEM tiles and the full tile manager.
 */
PEAKLINE_EXPORT PeaklineHorizonResult peakline_compute_horizon(
    double observer_lat,
    double observer_lon,
    double observer_alt_m,
    double azimuth_start,
    double azimuth_end,
    double angular_step,
    double max_distance_m,
    const char *dem_path
);

/**
 * Free a horizon result previously returned by peakline_compute_horizon().
 */
PEAKLINE_EXPORT void peakline_free_profile(PeaklineHorizonResult *result);

#ifdef __cplusplus
}
#endif

#endif /* PEAKLINE_H */
