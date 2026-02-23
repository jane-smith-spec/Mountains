/**
 * peakline_api.c — Public API implementation (FFI-exported functions).
 *
 * This is the entry point that Dart calls via FFI. It delegates to the
 * internal modules (raycaster, dem_io, etc.).
 */

#include "peakline.h"
#include <stdlib.h>

int32_t peakline_version(void) {
    /* Version 0.1.0 = 0*10000 + 1*100 + 0 = 100 */
    return 100;
}

PeaklineHorizonResult peakline_compute_horizon(
    double observer_lat,
    double observer_lon,
    double observer_alt_m,
    double azimuth_start,
    double azimuth_end,
    double angular_step,
    double max_distance_m,
    const char *dem_path
) {
    /*
     * Stub — will be implemented in Steps 4-5.
     * Returns an empty result with status = -1 (not yet implemented).
     */
    (void)observer_lat;
    (void)observer_lon;
    (void)observer_alt_m;
    (void)azimuth_start;
    (void)azimuth_end;
    (void)angular_step;
    (void)max_distance_m;
    (void)dem_path;

    PeaklineHorizonResult result;
    result.points = NULL;
    result.count = 0;
    result.status = -1; /* Not yet implemented */
    return result;
}

void peakline_free_profile(PeaklineHorizonResult *result) {
    if (result && result->points) {
        free(result->points);
        result->points = NULL;
        result->count = 0;
    }
}
