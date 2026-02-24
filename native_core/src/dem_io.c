/**
 * dem_io.c — Loading DEM tile files (.hgt format).
 *
 * .hgt files are the standard format for SRTM and Copernicus elevation data.
 * They're very simple: just a grid of 16-bit signed integers (heights in
 * meters), stored in big-endian byte order, with no header at all.
 *
 * The filename encodes the geographic location. For example:
 *   "N46E007.hgt" covers latitude 46°N to 47°N, longitude 7°E to 8°E.
 *   "S34W071.hgt" covers latitude 34°S to 33°S, longitude 71°W to 70°W.
 *
 * The grid dimensions are inferred from the file size:
 *   SRTM1 (1 arc-second, ~30m): 3601 x 3601 = 25,934,402 bytes
 *   SRTM3 (3 arc-second, ~90m): 1201 x 1201 =  2,884,802 bytes
 *
 * Row 0 is the NORTHERN edge, and values go south. Column 0 is the WESTERN
 * edge, values go east. This means the grid is oriented like a map.
 */

#include "dem_io.h"
#include "interpolation.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Expected file sizes for the two standard .hgt resolutions */
#define SRTM1_SAMPLES 3601
#define SRTM1_FILESIZE (SRTM1_SAMPLES * SRTM1_SAMPLES * 2)  /* 25,934,402 bytes */
#define SRTM3_SAMPLES 1201
#define SRTM3_FILESIZE (SRTM3_SAMPLES * SRTM3_SAMPLES * 2)  /* 2,884,802 bytes */

/**
 * Parse the southwest corner coordinates from a .hgt filename.
 *
 * Filenames look like "N46E007.hgt" or "/some/path/S34W071.hgt".
 * We extract the last path component and parse N/S + lat, E/W + lon.
 *
 * Returns 0 on success, -1 on parse error.
 */
static int parse_hgt_filename(const char *path, double *lat_south, double *lon_west) {
    /* Find the filename part (after the last '/' or '\') */
    const char *fname = path;
    const char *p;
    for (p = path; *p; p++) {
        if (*p == '/' || *p == '\\') {
            fname = p + 1;
        }
    }

    /* We need at least 7 chars: e.g., "N46E007" */
    if (strlen(fname) < 7) {
        return -1;
    }

    /* Parse latitude: N or S, then 2 digits */
    char ns = fname[0];
    if (ns != 'N' && ns != 'n' && ns != 'S' && ns != 's') {
        return -1;
    }

    int lat_deg = (fname[1] - '0') * 10 + (fname[2] - '0');
    if (lat_deg < 0 || lat_deg > 90) {
        return -1;
    }

    /* Parse longitude: E or W, then 3 digits */
    char ew = fname[3];
    if (ew != 'E' && ew != 'e' && ew != 'W' && ew != 'w') {
        return -1;
    }

    int lon_deg = (fname[4] - '0') * 100 + (fname[5] - '0') * 10 + (fname[6] - '0');
    if (lon_deg < 0 || lon_deg > 180) {
        return -1;
    }

    *lat_south = (ns == 'S' || ns == 's') ? -lat_deg : lat_deg;
    *lon_west  = (ew == 'W' || ew == 'w') ? -lon_deg : lon_deg;

    return 0;
}

/**
 * Swap bytes of a 16-bit integer (big-endian to little-endian or vice versa).
 *
 * .hgt files store values in big-endian byte order (most significant byte
 * first), but most modern computers use little-endian. We need to swap.
 */
static int16_t swap_bytes_16(int16_t val) {
    uint16_t u = (uint16_t)val;
    return (int16_t)((u >> 8) | (u << 8));
}

/**
 * Detect whether this machine is little-endian (needs byte swap for .hgt).
 */
static int is_little_endian(void) {
    uint16_t test = 1;
    return *((uint8_t *)&test) == 1;
}

int peakline_dem_load_hgt(const char *path, PeaklineDemTile *tile) {
    if (!path || !tile) {
        return -1;
    }

    /* Parse lat/lon from the filename */
    double lat_south, lon_west;
    if (parse_hgt_filename(path, &lat_south, &lon_west) != 0) {
        return -2;  /* Couldn't parse filename */
    }

    /* Open the file and get its size */
    FILE *f = fopen(path, "rb");
    if (!f) {
        return -3;  /* Couldn't open file */
    }

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    /* Determine grid dimensions from file size */
    int samples;
    if (file_size == SRTM1_FILESIZE) {
        samples = SRTM1_SAMPLES;  /* 3601 — high resolution (~30m) */
    } else if (file_size == SRTM3_FILESIZE) {
        samples = SRTM3_SAMPLES;  /* 1201 — lower resolution (~90m) */
    } else {
        fclose(f);
        return -4;  /* Unrecognized file size */
    }

    /* Allocate memory for the elevation data */
    int num_values = samples * samples;
    int16_t *data = (int16_t *)malloc((size_t)num_values * sizeof(int16_t));
    if (!data) {
        fclose(f);
        return -5;  /* Out of memory */
    }

    /* Read the entire file */
    size_t read_count = fread(data, sizeof(int16_t), (size_t)num_values, f);
    fclose(f);

    if ((int)read_count != num_values) {
        free(data);
        return -6;  /* Incomplete read */
    }

    /* Swap bytes if this machine is little-endian (most are) */
    if (is_little_endian()) {
        for (int i = 0; i < num_values; i++) {
            data[i] = swap_bytes_16(data[i]);
        }
    }

    /* Fill in the tile metadata */
    tile->data = data;
    tile->cols = samples;
    tile->rows = samples;
    tile->lat_south = lat_south;
    tile->lon_west = lon_west;
    /*
     * Cell size: each tile covers exactly 1 degree, with (samples-1) cells.
     * For SRTM1: 1/3600 degrees per cell (~30 meters at the equator).
     * For SRTM3: 1/1200 degrees per cell (~90 meters at the equator).
     */
    tile->cell_size = 1.0 / (double)(samples - 1);

    return 0;  /* Success */
}

float peakline_dem_get_elevation(const PeaklineDemTile *tile, double lat, double lon) {
    if (!tile || !tile->data) {
        return (float)DEM_VOID_VALUE;
    }

    /*
     * Convert lat/lon to grid coordinates.
     *
     * Row 0 is the NORTH edge (lat_south + 1), row (rows-1) is the south edge.
     * Col 0 is the WEST edge, col (cols-1) is the east edge.
     *
     * y (row) = how far south from the north edge:
     *   north_edge = lat_south + 1.0
     *   y = (north_edge - lat) / cell_size
     *
     * x (col) = how far east from the west edge:
     *   x = (lon - lon_west) / cell_size
     */
    double north_edge = tile->lat_south + 1.0;
    double y = (north_edge - lat) / tile->cell_size;
    double x = (lon - tile->lon_west) / tile->cell_size;

    /* Use the bilinear interpolation we already built */
    return peakline_interpolate_bilinear(tile->data, tile->cols, tile->rows,
                                         (float)x, (float)y);
}

void peakline_dem_free(PeaklineDemTile *tile) {
    if (tile && tile->data) {
        free(tile->data);
        tile->data = NULL;
    }
}
