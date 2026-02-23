/**
 * dem_io.c — Loading DEM tile files (.hgt format).
 *
 * Full implementation comes in Step 4. For now, this is a stub that
 * returns an error, so the library compiles and links.
 */

#include "dem_io.h"
#include <stdlib.h>

int peakline_dem_load_hgt(const char *path, PeaklineDemTile *tile) {
    /* Stub — will be implemented in Step 4 */
    (void)path;
    (void)tile;
    return -1; /* Not yet implemented */
}

float peakline_dem_get_elevation(const PeaklineDemTile *tile, double lat, double lon) {
    /* Stub — will be implemented in Step 4 */
    (void)tile;
    (void)lat;
    (void)lon;
    return (float)DEM_VOID_VALUE;
}

void peakline_dem_free(PeaklineDemTile *tile) {
    if (tile && tile->data) {
        free(tile->data);
        tile->data = NULL;
    }
}
