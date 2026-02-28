/// Dart FFI bridge to the PeakLine C native core library.
///
/// This file is the "bridge" between the Flutter/Dart world and the C code.
/// It handles:
///   1. Finding and loading the compiled C library (.so on Android/Linux,
///      .dylib on macOS/iOS, .dll on Windows)
///   2. Looking up each C function by its name
///   3. Wrapping them in clean Dart methods with proper types
///   4. Managing C memory (the C code allocates arrays that we must free)
///
/// Usage:
///   final bridge = NativeBridge();
///   print('Version: ${bridge.version()}');
///
///   final result = bridge.computeHorizon(
///     observerLat: 46.5,
///     observerLon: 7.5,
///     observerAltM: 1500,
///     demPath: '/path/to/N46E007.hgt',
///   );
///   // ... use result ...
///   bridge.freeProfile(result);  // IMPORTANT: free C memory when done
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import 'ffi_types.dart';

// ---------------------------------------------------------------------------
//  C function signatures (what the C functions look like to Dart)
// ---------------------------------------------------------------------------

// These typedefs describe the C function signatures. Dart needs two versions
// of each: one for C (using C types) and one for Dart (using Dart types).

/// C signature: int32_t peakline_version(void)
typedef PeaklineVersionC = Int32 Function();
typedef PeaklineVersionDart = int Function();

/// C signature: PeaklineHorizonResult peakline_compute_horizon(
///     double, double, double, double, double, double, double, const char*)
typedef PeaklineComputeHorizonC = PeaklineHorizonResult Function(
  Double observerLat,
  Double observerLon,
  Double observerAltM,
  Double azimuthStart,
  Double azimuthEnd,
  Double angularStep,
  Double maxDistanceM,
  Pointer<Utf8> demPath,
);
typedef PeaklineComputeHorizonDart = PeaklineHorizonResult Function(
  double observerLat,
  double observerLon,
  double observerAltM,
  double azimuthStart,
  double azimuthEnd,
  double angularStep,
  double maxDistanceM,
  Pointer<Utf8> demPath,
);

/// C signature: void peakline_free_profile(PeaklineHorizonResult*)
typedef PeaklineFreeProfileC = Void Function(
  Pointer<PeaklineHorizonResult> result,
);
typedef PeaklineFreeProfileDart = void Function(
  Pointer<PeaklineHorizonResult> result,
);

// ---------------------------------------------------------------------------
//  NativeBridge — the main class your Dart code uses
// ---------------------------------------------------------------------------

/// Bridge to the PeakLine C native core.
///
/// This class loads the compiled C library and provides Dart methods
/// that call into the C functions. It's a singleton-style class — you
/// typically create one instance and reuse it throughout the app.
class NativeBridge {
  /// Load the native library.
  ///
  /// The library name depends on the platform:
  ///   - Android/Linux: libpeakline_core.so
  ///   - macOS:         libpeakline_core.dylib
  ///   - iOS:           linked into the app binary (no separate file)
  ///   - Windows:       peakline_core.dll
  NativeBridge() : _lib = _loadLibrary() {
    // Look up each C function by name. This happens once at construction
    // time, not on every call, so it's efficient.
    _version = _lib.lookupFunction<PeaklineVersionC, PeaklineVersionDart>(
      'peakline_version',
    );
    _computeHorizon = _lib
        .lookupFunction<PeaklineComputeHorizonC, PeaklineComputeHorizonDart>(
      'peakline_compute_horizon',
    );
    _freeProfile =
        _lib.lookupFunction<PeaklineFreeProfileC, PeaklineFreeProfileDart>(
      'peakline_free_profile',
    );
  }

  final DynamicLibrary _lib;
  late final PeaklineVersionDart _version;
  late final PeaklineComputeHorizonDart _computeHorizon;
  late final PeaklineFreeProfileDart _freeProfile;

  /// Load the correct native library for the current platform.
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libpeakline_core.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libpeakline_core.dylib');
    } else if (Platform.isIOS) {
      // On iOS, native code is statically linked into the app binary.
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('peakline_core.dll');
    } else {
      throw UnsupportedError(
        'PeakLine native core is not supported on this platform.',
      );
    }
  }

  // -------------------------------------------------------------------------
  //  Public API — these are the methods you call from Dart code
  // -------------------------------------------------------------------------

  /// Get the native library version.
  ///
  /// Returns a packed integer: major*10000 + minor*100 + patch.
  /// For example, version 0.2.0 returns 200.
  ///
  /// Use this to verify the Dart side is linked to the right native library.
  int version() => _version();

  /// Get the version as a human-readable string (e.g., "0.2.0").
  String versionString() {
    final v = _version();
    final major = v ~/ 10000;
    final minor = (v % 10000) ~/ 100;
    final patch = v % 100;
    return '$major.$minor.$patch';
  }

  /// Compute the horizon profile from an observer position.
  ///
  /// Parameters:
  ///   - [observerLat]: Observer latitude in degrees (positive = North)
  ///   - [observerLon]: Observer longitude in degrees (positive = East)
  ///   - [observerAltM]: Observer altitude in meters above sea level
  ///   - [demPath]: Path to the .hgt DEM tile file
  ///   - [azimuthStart]: Start of azimuth sweep in degrees (default: 0 = North)
  ///   - [azimuthEnd]: End of azimuth sweep in degrees (default: 360 = full circle)
  ///   - [angularStep]: Resolution in degrees (default: 0.1 = 3600 points per circle)
  ///   - [maxDistanceM]: Maximum ray distance in meters (default: 100km)
  ///
  /// Returns a [HorizonProfile] with the computed points.
  ///
  /// The computation happens entirely in C for speed. A full 360° profile
  /// at 0.1° resolution takes roughly 0.5–2 seconds depending on the device.
  HorizonProfile computeHorizon({
    required double observerLat,
    required double observerLon,
    required double observerAltM,
    required String demPath,
    double azimuthStart = 0.0,
    double azimuthEnd = 360.0,
    double angularStep = 0.1,
    double maxDistanceM = 100000.0,
  }) {
    // Convert Dart String to C string (null-terminated UTF-8)
    final pathPtr = demPath.toNativeUtf8();

    try {
      // Call the C function
      final result = _computeHorizon(
        observerLat,
        observerLon,
        observerAltM,
        azimuthStart,
        azimuthEnd,
        angularStep,
        maxDistanceM,
        pathPtr,
      );

      // Convert the C result into a Dart-friendly object
      return HorizonProfile._fromCResult(result, this);
    } finally {
      // Always free the C string, even if an error occurs
      malloc.free(pathPtr);
    }
  }

  /// Free a C-allocated horizon result.
  ///
  /// This is called automatically by [HorizonProfile.dispose], but you
  /// can also call it manually if needed.
  void _freeProfileResult(Pointer<PeaklineHorizonResult> ptr) {
    _freeProfile(ptr);
  }
}

// ---------------------------------------------------------------------------
//  HorizonProfile — Dart-friendly wrapper around the C result
// ---------------------------------------------------------------------------

/// A single point in the horizon profile (Dart-friendly version).
///
/// This is a pure Dart class (not an FFI struct), so it's safe to use
/// anywhere in Dart code, pass between isolates, serialize, etc.
class HorizonPoint {
  const HorizonPoint({
    required this.azimuthDeg,
    required this.elevationAngleDeg,
    required this.distanceM,
    required this.terrainHeightM,
  });

  /// Compass direction in degrees (0=North, 90=East, 180=South, 270=West).
  final double azimuthDeg;

  /// Angle above the horizontal in degrees. Positive = looking up.
  final double elevationAngleDeg;

  /// Distance to the horizon point in meters.
  final double distanceM;

  /// Elevation of the terrain at the horizon point (meters above sea level).
  final double terrainHeightM;

  @override
  String toString() =>
      'HorizonPoint(az=${azimuthDeg.toStringAsFixed(1)}°, '
      'el=${elevationAngleDeg.toStringAsFixed(2)}°, '
      'dist=${(distanceM / 1000).toStringAsFixed(1)}km, '
      'h=${terrainHeightM.toStringAsFixed(0)}m)';
}

/// The result of a horizon profile computation.
///
/// Contains an array of [HorizonPoint]s representing the shape of the
/// horizon as seen from the observer position. Each point tells you:
/// "In compass direction X, the highest visible terrain is at angle Y
/// above horizontal, Z kilometers away, at elevation H meters."
///
/// IMPORTANT: Call [dispose] when you're done with this object to free
/// the C-allocated memory. Dart's garbage collector can't do this
/// automatically because the memory was allocated by C, not Dart.
class HorizonProfile {
  HorizonProfile._({
    required this.points,
    required this.status,
    required Pointer<PeaklineHorizonResult>? nativePtr,
    required NativeBridge? bridge,
  })  : _nativePtr = nativePtr,
        _bridge = bridge;

  /// Create a HorizonProfile from a C result.
  ///
  /// This copies all the point data from C memory into Dart lists,
  /// so the Dart data is safe to use even after disposing.
  factory HorizonProfile._fromCResult(
    PeaklineHorizonResult cResult,
    NativeBridge bridge,
  ) {
    final points = <HorizonPoint>[];

    if (cResult.status == 0 && cResult.count > 0) {
      for (int i = 0; i < cResult.count; i++) {
        final p = cResult.points[i];
        points.add(HorizonPoint(
          azimuthDeg: p.azimuthDeg,
          elevationAngleDeg: p.elevationAngleDeg,
          distanceM: p.distanceM,
          terrainHeightM: p.terrainHeightM,
        ));
      }
    }

    // We need to keep a pointer to free the C memory later.
    // Allocate a Pointer<PeaklineHorizonResult> and copy the struct into it.
    final ptr = malloc<PeaklineHorizonResult>();
    ptr.ref.points = cResult.points;
    ptr.ref.count = cResult.count;
    ptr.ref.status = cResult.status;

    return HorizonProfile._(
      points: points,
      status: cResult.status,
      nativePtr: ptr,
      bridge: bridge,
    );
  }

  /// The horizon points, sorted by azimuth.
  final List<HorizonPoint> points;

  /// Status code: 0 = success, nonzero = error.
  final int status;

  /// Whether the computation succeeded.
  bool get isSuccess => status == 0;

  /// Number of points in the profile.
  int get length => points.length;

  // Private fields for C memory management
  Pointer<PeaklineHorizonResult>? _nativePtr;
  final NativeBridge? _bridge;
  bool _disposed = false;

  /// Free the C-allocated memory for this profile.
  ///
  /// You MUST call this when you're done with the profile. If you forget,
  /// the C memory will leak (Dart's GC can't free it).
  void dispose() {
    final ptr = _nativePtr;
    final bridge = _bridge;
    if (!_disposed && ptr != null && bridge != null) {
      bridge._freeProfileResult(ptr);
      malloc.free(ptr);
      _nativePtr = null;
      _disposed = true;
    }
  }
}
