/**
 * test_raycaster.c — Tests for the ray-casting horizon engine.
 *
 * We test using synthetic (made-up) DEM tiles that have known shapes.
 * This way we can predict exactly what the horizon should look like
 * and verify our algorithm produces the right answer.
 *
 * Test scenarios:
 *
 * 1. Flat terrain: If you're standing on a perfectly flat plain at 500m,
 *    every direction should show the horizon slightly BELOW horizontal
 *    (because of Earth curvature — the ground curves away from you).
 *
 * 2. Mountain to the north: A flat plain with a single tall peak north
 *    of the observer. That direction should show a positive elevation
 *    angle, while other directions stay flat.
 *
 * 3. Destination point formula: Verify that walking 1km north from the
 *    equator moves you ~0.009° north (1km / ~111km per degree).
 */

#include "raycaster.h"
#include "dem_io.h"
#include "curvature.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/** Helper: check if two doubles are close enough. */
static int approx_equal(double a, double b, double tolerance) {
    return fabs(a - b) <= tolerance;
}

/**
 * Create a synthetic flat DEM tile.
 *
 * Returns a tile covering lat_south to lat_south+1, lon_west to lon_west+1,
 * with all elevations set to `height_m` meters.
 *
 * Uses a small grid (101x101) for speed — we don't need high resolution
 * in tests, just correct geometry.
 *
 * IMPORTANT: Caller must free tile.data when done.
 */
static PeaklineDemTile make_flat_tile(double lat_south, double lon_west, int16_t height_m) {
    const int samples = 101;  /* Small grid for fast tests */
    int num_values = samples * samples;

    int16_t *data = (int16_t *)malloc((size_t)num_values * sizeof(int16_t));
    for (int i = 0; i < num_values; i++) {
        data[i] = height_m;
    }

    PeaklineDemTile tile;
    tile.data = data;
    tile.cols = samples;
    tile.rows = samples;
    tile.lat_south = lat_south;
    tile.lon_west = lon_west;
    tile.cell_size = 1.0 / (double)(samples - 1);

    return tile;
}

int test_destination_point_north(void) {
    /*
     * Starting at the equator (0°N, 0°E), walk 1000m due north (bearing 0°).
     *
     * 1 degree of latitude ≈ 111,320 meters.
     * So 1000m north ≈ 1000/111320 ≈ 0.00898° change in latitude.
     * Longitude should stay the same (walking due north).
     */
    double out_lat, out_lon;
    peakline_destination_point(0.0, 0.0, 0.0, 1000.0, &out_lat, &out_lon);

    double expected_lat = 1000.0 / 111320.0;  /* ~0.00898 degrees */

    if (!approx_equal(out_lat, expected_lat, 0.0001)) {
        printf("    1km north: expected lat ~%.5f, got %.5f\n", expected_lat, out_lat);
        return 1;
    }
    if (!approx_equal(out_lon, 0.0, 0.0001)) {
        printf("    1km north: expected lon ~0, got %.5f\n", out_lon);
        return 1;
    }
    return 0;
}

int test_destination_point_east(void) {
    /*
     * Starting at the equator, walk 1000m due east (bearing 90°).
     *
     * At the equator, 1 degree of longitude ≈ 111,320 meters (same as lat).
     * So 1000m east ≈ 0.00898° change in longitude.
     * Latitude should stay approximately the same.
     */
    double out_lat, out_lon;
    peakline_destination_point(0.0, 0.0, 90.0, 1000.0, &out_lat, &out_lon);

    double expected_lon = 1000.0 / 111320.0;

    if (!approx_equal(out_lat, 0.0, 0.001)) {
        printf("    1km east: expected lat ~0, got %.5f\n", out_lat);
        return 1;
    }
    if (!approx_equal(out_lon, expected_lon, 0.0001)) {
        printf("    1km east: expected lon ~%.5f, got %.5f\n", expected_lon, out_lon);
        return 1;
    }
    return 0;
}

int test_destination_point_at_latitude(void) {
    /*
     * At 46°N (Swiss Alps), walk 10km due north.
     * Latitude should increase by about 10000/111320 ≈ 0.0898°.
     */
    double out_lat, out_lon;
    peakline_destination_point(46.0, 7.0, 0.0, 10000.0, &out_lat, &out_lon);

    double expected_lat = 46.0 + 10000.0 / 111320.0;

    if (!approx_equal(out_lat, expected_lat, 0.002)) {
        printf("    10km north from 46°N: expected lat ~%.4f, got %.4f\n",
               expected_lat, out_lat);
        return 1;
    }
    return 0;
}

int test_raycast_flat_terrain(void) {
    /*
     * On a flat plain at 500m altitude, looking in any direction, the
     * horizon should appear BELOW horizontal (negative elevation angle)
     * because of Earth curvature.
     *
     * The observer is at 46.5°N, 7.5°E, altitude 500m.
     * The terrain is flat at 500m everywhere.
     *
     * Since observer and terrain are at the same height, the maximum
     * elevation angle should be slightly negative (curvature makes
     * the ground drop away).
     */
    PeaklineDemTile tile = make_flat_tile(46.0, 7.0, 500);

    float dist, terrain_h;
    float angle = peakline_cast_ray(
        46.5, 7.5,   /* Observer at center of tile */
        500.0,        /* Observer altitude = same as terrain */
        0.0,          /* Looking north */
        50000.0,      /* Up to 50km away */
        &tile,
        &dist, &terrain_h
    );

    /* On flat terrain, the horizon angle should be slightly negative */
    if (angle >= 0.0f) {
        printf("    Flat terrain: expected negative angle, got %.4f\n", angle);
        free(tile.data);
        return 1;
    }

    /* Should be a small negative number (around -0.01 to -0.1 degrees) */
    if (angle < -1.0f) {
        printf("    Flat terrain: angle too negative (%.4f), expected near 0\n", angle);
        free(tile.data);
        return 1;
    }

    free(tile.data);
    return 0;
}

int test_raycast_elevated_observer(void) {
    /*
     * Observer standing on a high peak (3000m) looking over flat terrain (500m).
     * The horizon should be further below horizontal than in the flat case,
     * because we're looking DOWN at the terrain.
     */
    PeaklineDemTile tile = make_flat_tile(46.0, 7.0, 500);

    float dist, terrain_h;
    float angle = peakline_cast_ray(
        46.5, 7.5,   /* Observer at center of tile */
        3000.0,       /* Observer is HIGH up */
        0.0,          /* Looking north */
        50000.0,
        &tile,
        &dist, &terrain_h
    );

    /* Looking down from 3000m onto 500m terrain → clearly negative angle */
    if (angle >= 0.0f) {
        printf("    Elevated observer: expected negative angle, got %.4f\n", angle);
        free(tile.data);
        return 1;
    }

    /* The angle should be more negative than the flat case */
    if (angle > -0.1f) {
        printf("    Elevated observer: angle not negative enough (%.4f)\n", angle);
        free(tile.data);
        return 1;
    }

    free(tile.data);
    return 0;
}

int test_raycast_mountain_peak(void) {
    /*
     * A flat plain at 500m with a "mountain" (2500m) about 10km north.
     * The observer is at 46.5°N. The mountain is near 46.59°N.
     * (10km north ≈ 0.09° latitude)
     *
     * We create the mountain by setting a few cells in the DEM to 2500m.
     *
     * The ray cast northward should return a POSITIVE elevation angle
     * (we're looking UP at the mountain), while a ray cast southward
     * (away from the mountain) should be negative (flat terrain).
     */
    PeaklineDemTile tile = make_flat_tile(46.0, 7.0, 500);

    /*
     * Place the mountain at grid position corresponding to ~46.59°N, 7.5°E.
     * With 101 samples over 1 degree, cell_size = 0.01.
     * Row 0 = north edge (47.0°N), so:
     *   row for 46.59° = (47.0 - 46.59) / 0.01 = 41
     *   col for 7.5°   = (7.5 - 7.0) / 0.01 = 50
     *
     * We set a 3x3 block of cells to 2500m to make the peak.
     */
    for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
            int row = 41 + dr;
            int col = 50 + dc;
            if (row >= 0 && row < 101 && col >= 0 && col < 101) {
                tile.data[row * 101 + col] = 2500;
            }
        }
    }

    /* Cast a ray northward — should see the mountain (positive angle) */
    float dist_n, terrain_n;
    float angle_north = peakline_cast_ray(
        46.5, 7.5, 500.0,
        0.0,       /* Due north */
        50000.0,
        &tile,
        &dist_n, &terrain_n
    );

    /* Cast a ray southward — should see flat terrain (negative angle) */
    float dist_s, terrain_s;
    float angle_south = peakline_cast_ray(
        46.5, 7.5, 500.0,
        180.0,     /* Due south */
        50000.0,
        &tile,
        &dist_s, &terrain_s
    );

    /* The mountain should produce a positive angle */
    if (angle_north <= 0.0f) {
        printf("    Mountain peak: expected positive angle north, got %.4f\n", angle_north);
        free(tile.data);
        return 1;
    }

    /* South direction (no mountain) should be negative (flat terrain + curvature) */
    if (angle_south >= 0.0f) {
        printf("    Mountain peak: expected negative angle south, got %.4f\n", angle_south);
        free(tile.data);
        return 1;
    }

    /* The mountain was 2000m higher, ~10km away.
     * Expected angle ≈ atan2(2000, 10000) ≈ ~11.3° minus curvature correction.
     * Let's just verify it's in a reasonable range. */
    if (angle_north < 5.0f || angle_north > 15.0f) {
        printf("    Mountain peak: angle %.2f° out of expected 5–15° range\n", angle_north);
        free(tile.data);
        return 1;
    }

    /* The terrain height at the horizon point should be near 2500m */
    if (terrain_n < 2400.0f || terrain_n > 2600.0f) {
        printf("    Mountain peak: terrain height %.1f not near 2500m\n", terrain_n);
        free(tile.data);
        return 1;
    }

    free(tile.data);
    return 0;
}

int test_compute_horizon_profile(void) {
    /*
     * Compute a small horizon profile over flat terrain.
     * Verify the result has the right structure and reasonable values.
     */
    PeaklineDemTile tile = make_flat_tile(46.0, 7.0, 500);

    PeaklineHorizonResult result;
    int rc = peakline_compute_horizon_from_tile(
        46.5, 7.5, 500.0,   /* Observer at tile center, same altitude as terrain */
        0.0, 10.0, 1.0,      /* Azimuths 0° to 10°, 1° steps → 11 points */
        50000.0,              /* Max 50km range */
        &tile,
        &result
    );

    if (rc != 0) {
        printf("    compute_horizon failed with rc=%d\n", rc);
        free(tile.data);
        return 1;
    }

    /* Should have 11 points (0, 1, 2, ..., 10 degrees) */
    if (result.count != 11) {
        printf("    Expected 11 points, got %d\n", result.count);
        free(result.points);
        free(tile.data);
        return 1;
    }

    /* Check that azimuths are correct */
    for (int i = 0; i < result.count; i++) {
        float expected_az = (float)i;
        if (fabsf(result.points[i].azimuth_deg - expected_az) > 0.01f) {
            printf("    Point %d: expected azimuth %.1f, got %.1f\n",
                   i, expected_az, result.points[i].azimuth_deg);
            free(result.points);
            free(tile.data);
            return 1;
        }
    }

    /* All elevation angles should be negative on flat terrain */
    for (int i = 0; i < result.count; i++) {
        if (result.points[i].elevation_angle_deg >= 0.0f) {
            printf("    Point %d: expected negative angle on flat terrain, got %.4f\n",
                   i, result.points[i].elevation_angle_deg);
            free(result.points);
            free(tile.data);
            return 1;
        }
    }

    free(result.points);
    free(tile.data);
    return 0;
}
