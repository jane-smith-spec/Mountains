/**
 * dem_io.h — Loading DEM (Digital Elevation Model) tile files.
 *
 * DEM files store elevation data as a grid of height values. The most common
 * format is .hgt (used by SRTM and NASADEM):
 *   - Raw signed 16-bit big-endian integers
 *   - Row-major order (north to south, west to east)
 *   - No header — the file size tells you the grid dimensions:
 *       SRTM1: 3601x3601 = 25,934,402 bytes (1 arc-second, ~30m resolution)
 *       SRTM3: 1201x1201 =  2,884,802 bytes (3 arc-second, ~90m resolution)
 *   - Heights in meters above the EGM96 geoid
 *   - Void (no data) = -32768
 */

#ifndef PEAKLINE_DEM_IO_H
#define PEAKLINE_DEM_IO_H

#include <stdint.h>

/** Special value indicating no elevation data (void). */
#define DEM_VOID_VALUE (-32768)

/**
 * A loaded DEM tile.
 * The data array is row-major: data[row * cols + col].
 * Row 0 is the northern edge, row (rows-1) is the southern edge.
 */
typedef struct {
    int16_t *data;    /* Elevation values in meters (row-major) */
    int cols;         /* Number of columns (e.g., 3601 for SRTM1) */
    int rows;         /* Number of rows (e.g., 3601 for SRTM1) */
    double lat_south; /* Latitude of southern edge in degrees */
    double lon_west;  /* Longitude of western edge in degrees */
    double cell_size; /* Size of one grid cell in degrees (e.g., 1/3600) */
} PeaklineDemTile;

/**
 * Load a .hgt DEM tile from disk.
 *
 * The tile's geographic bounds are parsed from the filename (e.g., "N46E007.hgt"
 * means the tile covers 46°N to 47°N, 7°E to 8°E).
 *
 * Parameters:
 *   path - Path to the .hgt file
 *   tile - Output: populated on success
 *
 * Returns: 0 on success, nonzero on error.
 *
 * The caller must free the tile with peakline_dem_free().
 */
int peakline_dem_load_hgt(const char *path, PeaklineDemTile *tile);

/**
 * Get the elevation at a given lat/lon from a loaded tile, using bilinear
 * interpolation.
 *
 * Parameters:
 *   tile - A loaded DEM tile
 *   lat  - Latitude in degrees
 *   lon  - Longitude in degrees
 *
 * Returns: Elevation in meters, or DEM_VOID_VALUE if the point is outside
 *          the tile or on a void cell.
 */
float peakline_dem_get_elevation(const PeaklineDemTile *tile, double lat, double lon);

/**
 * Free a DEM tile previously loaded with peakline_dem_load_hgt().
 */
void peakline_dem_free(PeaklineDemTile *tile);

#endif /* PEAKLINE_DEM_IO_H */
