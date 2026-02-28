/**
 * peakline_api.c — Public API implementation (FFI-exported functions).
 *
 * This is the entry point that Dart calls via FFI. It delegates to the
 * internal modules (raycaster, dem_io, etc.).
 *
 * The flow for computing a horizon profile:
 *   1. Dart calls peakline_compute_horizon() with observer position + DEM path
 *   2. We load the DEM tile from the .hgt file
 *   3. We call the raycaster to sweep across the azimuth range
 *   4. We return the result (array of horizon points)
 *   5. Dart calls peakline_free_profile() when it's done with the data
 */

#include "peakline.h"
#include "raycaster.h"
#include "dem_io.h"
#include <stdlib.h>

int32_t peakline_version(void) {
    /* Version 0.2.0 = 0*10000 + 2*100 + 0 = 200 */
    return 200;
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
    PeaklineHorizonResult result;
    result.points = NULL;
    result.count = 0;
    result.status = -1;

    /* Load the DEM tile from disk */
    PeaklineDemTile tile;
    int load_status = peakline_dem_load_hgt(dem_path, &tile);
    if (load_status != 0) {
        result.status = load_status - 10;  /* Offset error code so caller can tell it's a load error */
        return result;
    }

    /* Run the ray-caster across the requested azimuth range */
    int rc = peakline_compute_horizon_from_tile(
        observer_lat, observer_lon, observer_alt_m,
        azimuth_start, azimuth_end, angular_step,
        max_distance_m, &tile, &result
    );

    /* Free the DEM tile — we're done with it, results are in `result` */
    peakline_dem_free(&tile);

    if (rc != 0) {
        result.status = rc;
    }

    return result;
}

void peakline_free_profile(PeaklineHorizonResult *result) {
    if (result && result->points) {
        free(result->points);
        result->points = NULL;
        result->count = 0;
    }
}
