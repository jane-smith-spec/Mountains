/**
 * test_dem_io.c — Tests for DEM tile loading and elevation lookup.
 *
 * We can't rely on real .hgt files being available during testing, so we
 * take two approaches:
 *
 * 1. For the filename parser and elevation lookup: we create a fake
 *    PeaklineDemTile in memory with known elevation values and verify
 *    that looking up coordinates returns the right heights.
 *
 * 2. For the file loader: we create a small synthetic .hgt file on disk,
 *    load it, and verify the values match.
 *
 * This lets us test everything without needing real elevation data.
 */

#include "dem_io.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** Helper: check if two floats are close enough. */
static int approx_equal_f(float a, float b, float tolerance) {
    return fabsf(a - b) <= tolerance;
}

int test_dem_get_elevation_center(void) {
    /*
     * Create a small synthetic DEM tile: 5x5 grid covering 46°N–47°N, 7°E–8°E.
     * Each cell is 0.25° apart (since cell_size = 1.0 / (5-1) = 0.25).
     *
     * We fill it with elevation values that increase from west to east
     * and north to south, making it easy to verify lookups:
     *
     *   Row 0 (47°N):  1000  1100  1200  1300  1400
     *   Row 1 (46.75°N): 1500  1600  1700  1800  1900
     *   Row 2 (46.5°N):  2000  2100  2200  2300  2400
     *   Row 3 (46.25°N): 2500  2600  2700  2800  2900
     *   Row 4 (46°N):    3000  3100  3200  3300  3400
     */
    int16_t data[] = {
        1000, 1100, 1200, 1300, 1400,
        1500, 1600, 1700, 1800, 1900,
        2000, 2100, 2200, 2300, 2400,
        2500, 2600, 2700, 2800, 2900,
        3000, 3100, 3200, 3300, 3400
    };

    PeaklineDemTile tile;
    tile.data = data;
    tile.cols = 5;
    tile.rows = 5;
    tile.lat_south = 46.0;
    tile.lon_west = 7.0;
    tile.cell_size = 0.25;

    /* Lookup the exact center of the tile: lat=46.5, lon=7.5
     * This maps to grid position (2.0, 2.0) → value 2200 */
    float elev = peakline_dem_get_elevation(&tile, 46.5, 7.5);
    if (!approx_equal_f(elev, 2200.0f, 0.1f)) {
        printf("    Expected 2200 at center, got %.2f\n", elev);
        return 1;
    }

    /* Lookup the northwest corner: lat=47.0, lon=7.0
     * This maps to grid position (0.0, 0.0) → value 1000 */
    float nw = peakline_dem_get_elevation(&tile, 47.0, 7.0);
    if (!approx_equal_f(nw, 1000.0f, 0.1f)) {
        printf("    Expected 1000 at NW corner, got %.2f\n", nw);
        return 1;
    }

    return 0;
}

int test_dem_get_elevation_interpolated(void) {
    /*
     * Same 5x5 tile as above. Test a point that falls BETWEEN grid cells
     * to verify bilinear interpolation is working.
     *
     * Point: lat=46.875, lon=7.125 → grid pos (0.5, 0.5)
     * This is at the center of the top-left 2x2 quadrant.
     * Values: 1000, 1100, 1500, 1600 → average = 1300
     */
    int16_t data[] = {
        1000, 1100, 1200, 1300, 1400,
        1500, 1600, 1700, 1800, 1900,
        2000, 2100, 2200, 2300, 2400,
        2500, 2600, 2700, 2800, 2900,
        3000, 3100, 3200, 3300, 3400
    };

    PeaklineDemTile tile;
    tile.data = data;
    tile.cols = 5;
    tile.rows = 5;
    tile.lat_south = 46.0;
    tile.lon_west = 7.0;
    tile.cell_size = 0.25;

    float elev = peakline_dem_get_elevation(&tile, 46.875, 7.125);
    if (!approx_equal_f(elev, 1300.0f, 1.0f)) {
        printf("    Expected ~1300 at (46.875, 7.125), got %.2f\n", elev);
        return 1;
    }

    return 0;
}

int test_dem_get_elevation_out_of_bounds(void) {
    /*
     * Points outside the tile should return DEM_VOID_VALUE.
     */
    int16_t data[] = {
        1000, 1100, 1200, 1300, 1400,
        1500, 1600, 1700, 1800, 1900,
        2000, 2100, 2200, 2300, 2400,
        2500, 2600, 2700, 2800, 2900,
        3000, 3100, 3200, 3300, 3400
    };

    PeaklineDemTile tile;
    tile.data = data;
    tile.cols = 5;
    tile.rows = 5;
    tile.lat_south = 46.0;
    tile.lon_west = 7.0;
    tile.cell_size = 0.25;

    /* Too far north (above tile boundary) */
    float north = peakline_dem_get_elevation(&tile, 47.5, 7.5);
    /* Too far south (below tile boundary) */
    float south = peakline_dem_get_elevation(&tile, 45.5, 7.5);
    /* Too far west */
    float west = peakline_dem_get_elevation(&tile, 46.5, 6.5);
    /* Too far east */
    float east = peakline_dem_get_elevation(&tile, 46.5, 8.5);

    /* All should return -9999 (out of bounds from interpolation) or DEM_VOID */
    if (north > -9998.0f || south > -9998.0f || west > -9998.0f || east > -9998.0f) {
        printf("    Out-of-bounds lookup didn't return void/error\n");
        printf("    north=%.1f south=%.1f west=%.1f east=%.1f\n",
               north, south, west, east);
        return 1;
    }

    return 0;
}

int test_dem_load_synthetic_hgt(void) {
    /*
     * Create a tiny synthetic .hgt file and verify we can load it.
     *
     * We'll make a minimal SRTM3-format file (1201 x 1201 samples).
     * All values are set to 500m, except one known cell that's 2000m.
     * Then we load it and check the values match.
     *
     * The filename "N46E007.hgt" tells the loader: lat_south=46, lon_west=7.
     */
    const int samples = 1201;
    const int num_values = samples * samples;
    int16_t *data = (int16_t *)malloc((size_t)num_values * sizeof(int16_t));
    if (!data) {
        printf("    Failed to allocate test data\n");
        return 1;
    }

    /* Fill with 500m everywhere */
    for (int i = 0; i < num_values; i++) {
        /* Swap bytes to big-endian (the format .hgt uses) */
        uint16_t val = 500;
        data[i] = (int16_t)((val >> 8) | (val << 8));
    }

    /* Set one cell to 2000m: row 600, col 600 */
    {
        uint16_t val = 2000;
        data[600 * samples + 600] = (int16_t)((val >> 8) | (val << 8));
    }

    /* Write to disk */
    const char *path = "/tmp/N46E007.hgt";
    FILE *f = fopen(path, "wb");
    if (!f) {
        printf("    Failed to create test file at %s\n", path);
        free(data);
        return 1;
    }
    fwrite(data, sizeof(int16_t), (size_t)num_values, f);
    fclose(f);
    free(data);

    /* Now load it back and verify */
    PeaklineDemTile tile;
    int rc = peakline_dem_load_hgt(path, &tile);
    if (rc != 0) {
        printf("    Failed to load test .hgt file, error=%d\n", rc);
        remove(path);
        return 1;
    }

    /* Check metadata */
    if (tile.cols != 1201 || tile.rows != 1201) {
        printf("    Wrong dimensions: %d x %d (expected 1201 x 1201)\n",
               tile.cols, tile.rows);
        peakline_dem_free(&tile);
        remove(path);
        return 1;
    }

    if (fabs(tile.lat_south - 46.0) > 0.001 || fabs(tile.lon_west - 7.0) > 0.001) {
        printf("    Wrong bounds: lat_south=%.3f lon_west=%.3f\n",
               tile.lat_south, tile.lon_west);
        peakline_dem_free(&tile);
        remove(path);
        return 1;
    }

    /* Check that most cells read as 500m */
    if (tile.data[0] != 500) {
        printf("    First cell: expected 500, got %d\n", tile.data[0]);
        peakline_dem_free(&tile);
        remove(path);
        return 1;
    }

    /* Check the special cell (row 600, col 600) reads as 2000m */
    if (tile.data[600 * 1201 + 600] != 2000) {
        printf("    Special cell: expected 2000, got %d\n",
               tile.data[600 * 1201 + 600]);
        peakline_dem_free(&tile);
        remove(path);
        return 1;
    }

    peakline_dem_free(&tile);
    remove(path);
    return 0;
}
