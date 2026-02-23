/**
 * test_main.c — Test runner for the PeakLine native core.
 *
 * A simple test framework: each test function returns 0 on pass, nonzero on fail.
 * We collect results and print a summary.
 *
 * This is intentionally minimal — no external test framework dependencies.
 * Just compile and run.
 */

#include <stdio.h>

/* Test functions defined in other test files */
extern int test_curvature_drop_at_known_distances(void);
extern int test_curvature_drop_at_zero(void);
extern int test_elevation_angle_same_altitude(void);
extern int test_elevation_angle_higher_target(void);
extern int test_elevation_angle_with_curvature(void);

extern int test_interpolation_center(void);
extern int test_interpolation_corners(void);
extern int test_interpolation_edges(void);
extern int test_interpolation_out_of_bounds(void);
extern int test_interpolation_void_values(void);

typedef int (*test_fn)(void);

typedef struct {
    const char *name;
    test_fn fn;
} TestCase;

int main(void) {
    TestCase tests[] = {
        /* Curvature tests */
        {"curvature_drop_at_known_distances", test_curvature_drop_at_known_distances},
        {"curvature_drop_at_zero",            test_curvature_drop_at_zero},
        {"elevation_angle_same_altitude",     test_elevation_angle_same_altitude},
        {"elevation_angle_higher_target",     test_elevation_angle_higher_target},
        {"elevation_angle_with_curvature",    test_elevation_angle_with_curvature},

        /* Interpolation tests */
        {"interpolation_center",       test_interpolation_center},
        {"interpolation_corners",      test_interpolation_corners},
        {"interpolation_edges",        test_interpolation_edges},
        {"interpolation_out_of_bounds", test_interpolation_out_of_bounds},
        {"interpolation_void_values",  test_interpolation_void_values},
    };

    int num_tests = sizeof(tests) / sizeof(tests[0]);
    int passed = 0;
    int failed = 0;

    printf("Running %d tests...\n\n", num_tests);

    for (int i = 0; i < num_tests; i++) {
        int result = tests[i].fn();
        if (result == 0) {
            printf("  PASS  %s\n", tests[i].name);
            passed++;
        } else {
            printf("  FAIL  %s\n", tests[i].name);
            failed++;
        }
    }

    printf("\n--- Results: %d passed, %d failed, %d total ---\n",
           passed, failed, num_tests);

    return failed > 0 ? 1 : 0;
}
