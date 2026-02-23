/**
 * interpolation.c — Bilinear interpolation on elevation grids.
 *
 * Given a point at fractional grid coordinates (x, y), we find the four
 * surrounding integer grid cells and blend their values:
 *
 *     (x0,y0)----(x1,y0)      Q1 = grid[y0][x0]   Q2 = grid[y0][x1]
 *         |    P    |          Q3 = grid[y1][x0]   Q4 = grid[y1][x1]
 *     (x0,y1)----(x1,y1)
 *
 *     fx = x - x0   (fractional part, 0.0 to 1.0)
 *     fy = y - y0
 *
 *     result = Q1*(1-fx)*(1-fy) + Q2*fx*(1-fy) + Q3*(1-fx)*fy + Q4*fx*fy
 */

#include "interpolation.h"
#include <math.h>

float peakline_interpolate_bilinear(
    const int16_t *grid,
    int cols,
    int rows,
    float x,
    float y
) {
    /* Bounds check: need at least one cell of margin on right and bottom */
    if (x < 0.0f || y < 0.0f || x >= (float)(cols - 1) || y >= (float)(rows - 1)) {
        return -9999.0f;
    }

    /* Integer coordinates of the top-left corner cell */
    int x0 = (int)floorf(x);
    int y0 = (int)floorf(y);
    int x1 = x0 + 1;
    int y1 = y0 + 1;

    /* Fractional position within the cell (0.0 to 1.0) */
    float fx = x - (float)x0;
    float fy = y - (float)y0;

    /* Read the four corner values */
    int16_t q1 = grid[y0 * cols + x0]; /* top-left */
    int16_t q2 = grid[y0 * cols + x1]; /* top-right */
    int16_t q3 = grid[y1 * cols + x0]; /* bottom-left */
    int16_t q4 = grid[y1 * cols + x1]; /* bottom-right */

    /* Skip void values (DEM no-data marker) */
    if (q1 == -32768 || q2 == -32768 || q3 == -32768 || q4 == -32768) {
        return -9999.0f;
    }

    /* Bilinear blend */
    float result =
        (float)q1 * (1.0f - fx) * (1.0f - fy) +
        (float)q2 * fx * (1.0f - fy) +
        (float)q3 * (1.0f - fx) * fy +
        (float)q4 * fx * fy;

    return result;
}
