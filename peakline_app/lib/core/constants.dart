/// App-wide constants for the PeakLine computation engine.
///
/// These values control the precision, range, and default camera
/// parameters used throughout the horizon computation and projection.
library;

import 'dart:math' as math;

// -----------------------------------------------------------------------
//  Earth geometry
// -----------------------------------------------------------------------

/// Mean radius of the Earth in meters (WGS-84 mean).
const double earthRadiusM = 6371000.0;

/// Atmospheric refraction coefficient.
///
/// Light bends slightly as it passes through the atmosphere, making
/// distant objects appear about 13% higher than pure geometry predicts.
/// The standard refraction coefficient is 0.13 (k = 0.13).
/// The "effective Earth radius" used in curvature calculations is:
///   R_eff = R / (1 - k) ≈ R × 1.13
const double refractionCoefficient = 0.13;

/// Effective Earth radius accounting for atmospheric refraction.
const double effectiveEarthRadiusM =
    earthRadiusM / (1.0 - refractionCoefficient);

// -----------------------------------------------------------------------
//  Horizon computation defaults
// -----------------------------------------------------------------------

/// Maximum distance to cast rays, in meters (100 km).
///
/// Beyond ~100 km, even tall peaks are below the horizon due to
/// Earth curvature, and DEM resolution is too coarse to be useful.
const double maxRayDistanceM = 100000.0;

/// Minimum distance for ray-casting, in meters (100 m).
///
/// We skip the first 100 m because very close terrain creates
/// extreme elevation angles that aren't useful for the overlay.
const double minRayDistanceM = 100.0;

/// Default angular step for ray-casting, in degrees.
///
/// 0.1° gives 3600 points per full circle. This is fine enough
/// that the horizon line looks smooth on screen.
const double defaultAngularStepDeg = 0.1;

// -----------------------------------------------------------------------
//  Camera / field of view defaults
// -----------------------------------------------------------------------

/// Default horizontal field of view in degrees.
///
/// Most phone cameras have a ~60-70° horizontal FOV. We use 60° as
/// a conservative default. This can be refined per-device using the
/// camera's reported focal length and sensor size.
const double defaultHorizontalFovDeg = 60.0;

/// Default vertical field of view in degrees.
///
/// Derived from horizontal FOV assuming a 16:9 aspect ratio:
///   vFOV = 2 × atan(tan(hFOV/2) × (9/16))
/// For 60° horizontal → ~35.6° vertical.
const double defaultVerticalFovDeg = 35.6;

// -----------------------------------------------------------------------
//  Conversion helpers
// -----------------------------------------------------------------------

/// Degrees to radians.
const double deg2Rad = math.pi / 180.0;

/// Radians to degrees.
const double rad2Deg = 180.0 / math.pi;
