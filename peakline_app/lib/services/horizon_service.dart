/// Horizon service — orchestrates horizon profile computation.
///
/// This is the "brains" that connects the pieces:
///   1. Gets the observer's position (GPS) and orientation (sensors)
///   2. Calls the C native core via FFI to compute the horizon profile
///   3. Projects the profile points onto screen coordinates
///   4. Provides the result to the UI via Riverpod
///
/// The computation is done on a background isolate (via the C core)
/// so it doesn't block the UI thread. The result is cached and only
/// recomputed when the observer moves significantly.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/projection.dart';
import '../ffi/native_bridge.dart';
import '../models/observer_state.dart';
import '../models/sensor_data.dart';
import 'location_service.dart';
import 'sensor_service.dart';

/// How far the observer must move (in meters) before we recompute
/// the full horizon profile. Small movements don't change the distant
/// horizon significantly, so we save battery by not recomputing.
const double _recomputeDistanceThresholdM = 50.0;

/// Minimum time between full profile recomputations.
const Duration _recomputeCooldown = Duration(seconds: 5);

/// The horizon service state — what the UI consumes.
class HorizonState {
  const HorizonState({
    required this.profilePoints,
    required this.screenPoints,
    required this.observer,
    this.isComputing = false,
    this.error,
  });

  /// Empty state (before first computation).
  static const empty = HorizonState(
    profilePoints: [],
    screenPoints: [],
    observer: null,
    isComputing: false,
  );

  /// The raw horizon profile points from the C core.
  final List<HorizonPoint> profilePoints;

  /// Profile projected to current screen coordinates.
  /// Updated every frame as the camera heading/pitch changes.
  final List<ScreenPoint> screenPoints;

  /// The observer state used for the last computation.
  final ObserverState? observer;

  /// Whether a computation is currently running.
  final bool isComputing;

  /// Error message if the last computation failed.
  final String? error;

  /// Whether we have a valid profile to draw.
  bool get hasProfile => profilePoints.isNotEmpty;

  HorizonState copyWith({
    List<HorizonPoint>? profilePoints,
    List<ScreenPoint>? screenPoints,
    ObserverState? observer,
    bool? isComputing,
    String? error,
  }) {
    return HorizonState(
      profilePoints: profilePoints ?? this.profilePoints,
      screenPoints: screenPoints ?? this.screenPoints,
      observer: observer ?? this.observer,
      isComputing: isComputing ?? this.isComputing,
      error: error,
    );
  }
}

/// Service that manages horizon profile computation and projection.
class HorizonService {
  HorizonService({NativeBridge? bridge}) : _bridge = bridge;

  final NativeBridge? _bridge;

  HorizonProfile? _cachedProfile;
  ObserverState? _lastComputeState;
  DateTime? _lastComputeTime;

  /// Compute a new horizon profile for the given observer position.
  ///
  /// This calls the C core via FFI, which does the heavy lifting:
  /// ray-casting across the DEM to find the horizon shape.
  ///
  /// [demPath] is the path to the .hgt elevation tile file.
  /// If null, returns an empty result (no DEM data available yet).
  Future<List<HorizonPoint>> computeProfile({
    required ObserverState observer,
    String? demPath,
  }) async {
    if (_bridge == null || demPath == null) return [];

    // Check if we should skip (observer hasn't moved enough)
    if (_shouldSkipRecompute(observer)) {
      return _cachedProfile?.points ?? [];
    }

    try {
      // Dispose previous profile to free C memory
      _cachedProfile?.dispose();

      // Compute full 360° profile via C core
      _cachedProfile = _bridge!.computeHorizon(
        observerLat: observer.latitudeDeg,
        observerLon: observer.longitudeDeg,
        observerAltM: observer.altitudeM,
        demPath: demPath,
        azimuthStart: 0.0,
        azimuthEnd: 360.0,
        angularStep: defaultAngularStepDeg,
        maxDistanceM: maxRayDistanceM,
      );

      _lastComputeState = observer;
      _lastComputeTime = DateTime.now();

      if (_cachedProfile!.isSuccess) {
        return _cachedProfile!.points;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// Project the cached profile onto screen coordinates.
  ///
  /// This is fast (pure Dart math) and runs every frame as the
  /// camera heading/pitch changes from sensor updates.
  List<ScreenPoint> projectToScreen({
    required CameraViewParams camera,
  }) {
    final profile = _cachedProfile;
    if (profile == null || !profile.isSuccess) return [];

    // Convert HorizonPoints to the format projectHorizonProfile expects
    final points = profile.points
        .map((p) => (
              azimuthDeg: p.azimuthDeg,
              elevationAngleDeg: p.elevationAngleDeg,
            ))
        .toList();

    return projectHorizonProfile(points: points, camera: camera);
  }

  /// Check if we should skip recomputation (observer hasn't moved enough).
  bool _shouldSkipRecompute(ObserverState observer) {
    final lastState = _lastComputeState;
    final lastTime = _lastComputeTime;

    if (lastState == null || lastTime == null) return false;

    // Enforce cooldown
    if (DateTime.now().difference(lastTime) < _recomputeCooldown) {
      return true;
    }

    // Check if position changed significantly
    final latDiff = (observer.latitudeDeg - lastState.latitudeDeg).abs();
    final lonDiff = (observer.longitudeDeg - lastState.longitudeDeg).abs();
    // Rough conversion: 1° ≈ 111 km
    final distanceM = (latDiff + lonDiff) * 111000.0;

    return distanceM < _recomputeDistanceThresholdM;
  }

  /// Clean up C memory.
  void dispose() {
    _cachedProfile?.dispose();
    _cachedProfile = null;
  }
}

// -----------------------------------------------------------------------
//  Riverpod providers
// -----------------------------------------------------------------------

/// Provider for the NativeBridge (FFI connection to C core).
///
/// This will throw on platforms where the native library isn't available
/// (e.g., during tests). Use [horizonServiceProvider] instead, which
/// handles the null case.
final nativeBridgeProvider = Provider<NativeBridge?>((ref) {
  try {
    return NativeBridge();
  } catch (_) {
    // Native library not available (e.g., during tests or on web)
    return null;
  }
});

/// Provider for the HorizonService.
final horizonServiceProvider = Provider<HorizonService>((ref) {
  final bridge = ref.watch(nativeBridgeProvider);
  final service = HorizonService(bridge: bridge);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Combines sensor orientation and GPS location into an ObserverState stream.
///
/// This merges the two sensor streams so downstream providers get a
/// single combined snapshot of "where am I and which way am I looking?"
final observerStateProvider = StreamProvider<ObserverState>((ref) {
  final sensorService = ref.watch(sensorServiceProvider);
  final locationService = ref.watch(locationServiceProvider);

  sensorService.start();
  locationService.startListening();

  ref.onDispose(() {
    sensorService.stop();
    locationService.stopListening();
  });

  // Combine orientation and location streams.
  // We emit a new ObserverState whenever either stream updates,
  // using the latest value from the other stream.
  DeviceLocation? lastLocation;
  DeviceOrientation? lastOrientation;

  final controller = StreamController<ObserverState>.broadcast();

  void tryEmit() {
    final loc = lastLocation;
    final orient = lastOrientation;
    if (loc != null && orient != null) {
      controller.add(ObserverState.from(
        location: loc,
        orientation: orient,
      ));
    }
  }

  final orientSub = sensorService.orientationStream.listen((o) {
    lastOrientation = o;
    tryEmit();
  });

  final locSub = locationService.locationStream.listen((l) {
    lastLocation = l;
    tryEmit();
  });

  ref.onDispose(() {
    orientSub.cancel();
    locSub.cancel();
    controller.close();
  });

  return controller.stream;
});
