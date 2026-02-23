cmake_minimum_required(VERSION 3.16)
project(peakline_core C)

# Use C11 standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Enable warnings — helps catch bugs early
add_compile_options(-Wall -Wextra -Wpedantic)

# ---- Shared library (what Flutter/Dart FFI links to) ----
add_library(peakline_core SHARED
    src/peakline_api.c
    src/curvature.c
    src/interpolation.c
    src/dem_io.c
)
target_include_directories(peakline_core PUBLIC include)
target_link_libraries(peakline_core m)  # Link math library (for atan2, sqrt, etc.)

# ---- Static library (for tests and desktop tools) ----
add_library(peakline_core_static STATIC
    src/peakline_api.c
    src/curvature.c
    src/interpolation.c
    src/dem_io.c
)
target_include_directories(peakline_core_static PUBLIC include)
target_link_libraries(peakline_core_static m)

# ---- Test executable ----
add_executable(run_tests
    test/test_main.c
    test/test_curvature.c
    test/test_interpolation.c
)
target_link_libraries(run_tests peakline_core_static m)
target_include_directories(run_tests PRIVATE include)

# Enable CTest integration
enable_testing()
add_test(NAME peakline_tests COMMAND run_tests)
