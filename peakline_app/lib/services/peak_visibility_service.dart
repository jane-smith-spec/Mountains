/// Peak visibility — determines which peaks are visible from the observer.
///
/// This service answers: "Given my position and the horizon profile,
/// which peaks can I actually see, and where should they appear on screen?"
///
/// A peak is visible if its elevation angle from the observer is ABOVE
/// the horizon profile at the same compass bearing. If a closer ridge
/// is higher, it blocks the view and the peak is hidden.
///
/// Algorithm:
///   1. For each peak within range, compute bearing and elevation angle
///   2. Look up the horizon elevation at that bearing
///   3. If peak's elevation angle > horizon angle → visible
///   4. Project visible peaks to screen coordinates
library;

import '../core/coordinate_utils.dart';
import '../core/constants.dart';
import '../core/projection.dart';
import '../ffi/native_bridge.dart';
import '../models/landmark.dart';
import '../models/observer_state.dart';
import '../models/peak.dart';

/// A peak that has been checked for visibility and projected to screen.
class VisiblePeak {
  const VisiblePeak({
    required this.peak,
    required this.bearingDeg,
    required this.elevationAngleDeg,
    required this.distanceM,
    required this.screenPoint,
  });

  /// The peak data (name, coordinates, elevation).
  final Peak peak;

  /// Compass bearing from observer to this peak.
  final double bearingDeg;

  /// Elevation angle above horizontal in degrees.
  final double elevationAngleDeg;

  /// Distance from observer in meters.
  final double distanceM;

  /// Where on screen to draw the label.
  final ScreenPoint screenPoint;

  /// Distance formatted for display (e.g., "12.3 km").
  String get distanceLabel {
    if (distanceM < 1000) {
      return '${distanceM.toStringAsFixed(0)} m';
    }
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }
}

/// A landmark that has been checked for visibility and projected to screen.
class VisibleLandmark {
  const VisibleLandmark({
    required this.landmark,
    required this.bearingDeg,
    required this.elevationAngleDeg,
    required this.distanceM,
    required this.screenPoint,
  });

  final Landmark landmark;
  final double bearingDeg;
  final double elevationAngleDeg;
  final double distanceM;
  final ScreenPoint screenPoint;

  String get distanceLabel {
    if (distanceM < 1000) {
      return '${distanceM.toStringAsFixed(0)} m';
    }
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }
}

/// Determines which peaks and landmarks are visible from the observer.
class PeakVisibilityService {
  /// Find all visible peaks from the given observer position.
  ///
  /// [peaks] — all candidate peaks within range.
  /// [horizonProfile] — the computed horizon profile (from the C core).
  /// [observer] — the observer's position and altitude.
  /// [camera] — current camera view for screen projection.
  /// [maxDistanceM] — maximum distance to consider (default: 100 km).
  ///
  /// Returns only peaks that are:
  ///   1. Within [maxDistanceM]
  ///   2. Not hidden behind a closer ridge (horizon check)
  ///   3. Within the camera's field of view
  List<VisiblePeak> findVisiblePeaks({
    required List<Peak> peaks,
    required List<HorizonPoint> horizonProfile,
    required ObserverState observer,
    required CameraViewParams camera,
    double maxDistanceM = maxRayDistanceM,
  }) {
    if (peaks.isEmpty || horizonProfile.isEmpty) return [];

    final result = <VisiblePeak>[];

    for (final peak in peaks) {
      // Step 1: Compute distance
      final distance = haversineDistanceM(
        observer.latitudeDeg,
        observer.longitudeDeg,
        peak.latitudeDeg,
        peak.longitudeDeg,
      );
      if (distance > maxDistanceM || distance < 50) continue;

      // Step 2: Compute bearing from observer to peak
      final bearing = bearingDeg(
        observer.latitudeDeg,
        observer.longitudeDeg,
        peak.latitudeDeg,
        peak.longitudeDeg,
      );

      // Step 3: Compute elevation angle to peak summit
      final elAngle = elevationAngleDeg(
        observerAltM: observer.altitudeM,
        targetAltM: peak.elevationM,
        distanceM: distance,
      );

      // Step 4: Check visibility against horizon profile
      final horizonAngle = _horizonAngleAtBearing(horizonProfile, bearing);
      // Peak is visible if it pokes above the horizon.
      // Use a small tolerance (0.05°) to avoid edge cases.
      if (elAngle < horizonAngle - 0.05) continue;

      // Step 5: Project to screen
      final screenPt = projectToScreen(
        azimuthDeg: bearing,
        elevationAngleDeg: elAngle,
        camera: camera,
      );

      // Only include if on screen
      if (!screenPt.isVisible) continue;

      result.add(VisiblePeak(
        peak: peak,
        bearingDeg: bearing,
        elevationAngleDeg: elAngle,
        distanceM: distance,
        screenPoint: screenPt,
      ));
    }

    // Sort by distance (closest first) for label priority
    result.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return result;
  }

  /// Find all visible landmarks from the observer position.
  ///
  /// Same algorithm as peaks, but for landmarks.
  List<VisibleLandmark> findVisibleLandmarks({
    required List<Landmark> landmarks,
    required List<HorizonPoint> horizonProfile,
    required ObserverState observer,
    required CameraViewParams camera,
    required Set<LandmarkCategory> enabledCategories,
    double maxDistanceM = maxRayDistanceM,
  }) {
    if (landmarks.isEmpty) return [];

    final result = <VisibleLandmark>[];

    for (final landmark in landmarks) {
      // Skip disabled categories
      if (!enabledCategories.contains(landmark.category)) continue;

      final distance = haversineDistanceM(
        observer.latitudeDeg,
        observer.longitudeDeg,
        landmark.latitudeDeg,
        landmark.longitudeDeg,
      );
      if (distance > maxDistanceM || distance < 50) continue;

      final bearing = bearingDeg(
        observer.latitudeDeg,
        observer.longitudeDeg,
        landmark.latitudeDeg,
        landmark.longitudeDeg,
      );

      final elAngle = elevationAngleDeg(
        observerAltM: observer.altitudeM,
        targetAltM: landmark.elevationM,
        distanceM: distance,
      );

      // Landmarks don't require horizon visibility check — huts and
      // lakes may be below the horizon but still useful to label.
      // We only skip if they're completely behind terrain AND below
      // the horizon by more than 1°.
      if (horizonProfile.isNotEmpty) {
        final horizonAngle = _horizonAngleAtBearing(horizonProfile, bearing);
        if (elAngle < horizonAngle - 1.0) continue;
      }

      final screenPt = projectToScreen(
        azimuthDeg: bearing,
        elevationAngleDeg: elAngle,
        camera: camera,
      );

      if (!screenPt.isVisible) continue;

      result.add(VisibleLandmark(
        landmark: landmark,
        bearingDeg: bearing,
        elevationAngleDeg: elAngle,
        distanceM: distance,
        screenPoint: screenPt,
      ));
    }

    result.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return result;
  }

  /// Look up the horizon elevation angle at a given compass bearing.
  ///
  /// Interpolates between the two nearest profile points for accuracy.
  double _horizonAngleAtBearing(
    List<HorizonPoint> profile,
    double targetBearing,
  ) {
    if (profile.isEmpty) return -90.0;

    // Find the two profile points that bracket the target bearing.
    // Profile points are sorted by azimuth (0° to 360°).
    HorizonPoint? before;
    HorizonPoint? after;

    for (int i = 0; i < profile.length; i++) {
      if (profile[i].azimuthDeg >= targetBearing) {
        after = profile[i];
        before = i > 0 ? profile[i - 1] : profile.last;
        break;
      }
    }

    // If we didn't find a bracket, wrap around
    if (after == null) {
      before = profile.last;
      after = profile.first;
    }

    // Linear interpolation between the two points
    final az1 = before!.azimuthDeg;
    final az2 = after.azimuthDeg;
    final el1 = before.elevationAngleDeg;
    final el2 = after.elevationAngleDeg;

    // Handle wraparound (e.g., 359° to 1°)
    double span = az2 - az1;
    if (span < 0) span += 360.0;
    if (span == 0) return el1;

    double offset = targetBearing - az1;
    if (offset < 0) offset += 360.0;

    final t = offset / span;
    return el1 + t * (el2 - el1);
  }
}
