/**
 * interpolation.h — Bilinear interpolation on elevation grids.
 *
 * "Bilinear interpolation" means: given a point that falls between four grid
 * cells, estimate its value by blending the four surrounding values based on
 * how close the point is to each one.
 *
 * Think of it like reading between the lines on graph paper — if your point
 * is 70% of the way from cell A to cell B horizontally, and 30% of the way
 * from A to C vertically, you blend all four corners proportionally.
 */

#ifndef PEAKLINE_INTERPOLATION_H
#define PEAKLINE_INTERPOLATION_H

#include <stdint.h>

/**
 * Perform bilinear interpolation on a 2D grid of int16 elevation values.
 *
 * Parameters:
 *   grid     - Pointer to the elevation grid (row-major order)
 *   cols     - Number of columns in the grid
 *   rows     - Number of rows in the grid
 *   x        - Fractional column position (0.0 = left edge, cols-1 = right edge)
 *   y        - Fractional row position (0.0 = top edge, rows-1 = bottom edge)
 *
 * Returns: Interpolated elevation value as a float.
 *          Returns -9999.0 if the position is out of bounds.
 */
float peakline_interpolate_bilinear(
    const int16_t *grid,
    int cols,
    int rows,
    float x,
    float y
);

#endif /* PEAKLINE_INTERPOLATION_H */
