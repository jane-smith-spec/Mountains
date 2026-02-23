/**
 * test_interpolation.c — Tests for bilinear interpolation.
 *
 * We use a small 3x3 grid with known values and verify that interpolating
 * at various positions gives the expected results.
 *
 * Grid layout (3 columns x 3 rows):
 *
 *     100  200  300       row 0 (y=0)
 *     400  500  600       row 1 (y=1)
 *     700  800  900       row 2 (y=2)
 *
 * So grid[row * 3 + col] gives the value at (col, row).
 */

#include "interpolation.h"
#include <math.h>
#include <stdio.h>

/* Our test grid */
static const int16_t test_grid[] = {
    100, 200, 300,
    400, 500, 600,
    700, 800, 900
};
static const int GRID_COLS = 3;
static const int GRID_ROWS = 3;

/** Helper: check if two floats are close enough. */
static int approx_equal_f(float a, float b, float tolerance) {
    return fabsf(a - b) <= tolerance;
}

int test_interpolation_center(void) {
    /*
     * The exact center of the grid at (1.0, 1.0) should return 500
     * (the value of the center cell).
     */
    float val = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 1.0f, 1.0f);
    if (!approx_equal_f(val, 500.0f, 0.01f)) {
        printf("    Expected 500.0 at center, got %.2f\n", val);
        return 1;
    }
    return 0;
}

int test_interpolation_corners(void) {
    /* Top-left corner (0,0) = 100 */
    float tl = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 0.0f, 0.0f);
    if (!approx_equal_f(tl, 100.0f, 0.01f)) {
        printf("    Expected 100.0 at (0,0), got %.2f\n", tl);
        return 1;
    }

    /* Top-right corner (1,0) = 200 — note: (1,0) not (2,0) because we need margin */
    float tr = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 1.0f, 0.0f);
    if (!approx_equal_f(tr, 200.0f, 0.01f)) {
        printf("    Expected 200.0 at (1,0), got %.2f\n", tr);
        return 1;
    }

    /* Bottom-left corner (0,1) = 400 */
    float bl = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 0.0f, 1.0f);
    if (!approx_equal_f(bl, 400.0f, 0.01f)) {
        printf("    Expected 400.0 at (0,1), got %.2f\n", bl);
        return 1;
    }
    return 0;
}

int test_interpolation_edges(void) {
    /*
     * Midpoint between (0,0)=100 and (1,0)=200 at x=0.5, y=0:
     * Should be 150.
     */
    float mid_top = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 0.5f, 0.0f);
    if (!approx_equal_f(mid_top, 150.0f, 0.01f)) {
        printf("    Expected 150.0 at (0.5, 0), got %.2f\n", mid_top);
        return 1;
    }

    /*
     * Midpoint between (0,0)=100 and (0,1)=400 at x=0, y=0.5:
     * Should be 250.
     */
    float mid_left = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 0.0f, 0.5f);
    if (!approx_equal_f(mid_left, 250.0f, 0.01f)) {
        printf("    Expected 250.0 at (0, 0.5), got %.2f\n", mid_left);
        return 1;
    }

    /*
     * Center of the top-left quadrant at (0.5, 0.5):
     * Average of 100, 200, 400, 500 = 300.
     */
    float quad_center = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 0.5f, 0.5f);
    if (!approx_equal_f(quad_center, 300.0f, 0.01f)) {
        printf("    Expected 300.0 at (0.5, 0.5), got %.2f\n", quad_center);
        return 1;
    }
    return 0;
}

int test_interpolation_out_of_bounds(void) {
    /* Negative coordinates should return -9999 */
    float neg = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, -0.1f, 0.0f);
    if (!approx_equal_f(neg, -9999.0f, 0.01f)) {
        printf("    Expected -9999 for negative x, got %.2f\n", neg);
        return 1;
    }

    /* Beyond the grid boundary (x >= cols-1 = 2.0) should return -9999 */
    float beyond = peakline_interpolate_bilinear(test_grid, GRID_COLS, GRID_ROWS, 2.0f, 0.0f);
    if (!approx_equal_f(beyond, -9999.0f, 0.01f)) {
        printf("    Expected -9999 for x=2.0 (at boundary), got %.2f\n", beyond);
        return 1;
    }
    return 0;
}

int test_interpolation_void_values(void) {
    /* Grid with a void (-32768) value */
    int16_t void_grid[] = {
        100,    200,    300,
        400,    -32768, 600,
        700,    800,    900
    };

    /* Interpolating near the void cell should return -9999 */
    float val = peakline_interpolate_bilinear(void_grid, 3, 3, 0.5f, 0.5f);
    if (!approx_equal_f(val, -9999.0f, 0.01f)) {
        printf("    Expected -9999 near void cell, got %.2f\n", val);
        return 1;
    }
    return 0;
}
