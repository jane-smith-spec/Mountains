/// Camera service — manages the phone's camera for the live AR view.
///
/// This service handles:
///   - Discovering available cameras (front, back)
///   - Initializing the camera controller with appropriate resolution
///   - Providing a Riverpod provider so the UI can reactively display
///     the camera preview
///   - Cleaning up camera resources when the screen is dismissed
///
/// The `camera` package requires platform-specific setup:
///   - Android: CAMERA permission in AndroidManifest.xml, minSdkVersion 21
///   - iOS: NSCameraUsageDescription in Info.plist
library;

import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -----------------------------------------------------------------------
//  Camera Service
// -----------------------------------------------------------------------

/// Service that manages camera initialization and lifecycle.
///
/// Usage:
///   1. Call [initialize] to discover cameras and set up the controller
///   2. Access [controller] to get the CameraController for the preview
///   3. Call [dispose] when done (handled automatically by Riverpod)
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  String? _error;

  /// The active camera controller. Null until [initialize] completes.
  CameraController? get controller => _controller;

  /// Whether the camera has been successfully initialized.
  bool get isInitialized => _isInitialized;

  /// Error message if initialization failed, null otherwise.
  String? get error => _error;

  /// The list of available cameras on this device.
  List<CameraDescription> get cameras => _cameras;

  /// Initialize the camera.
  ///
  /// Discovers available cameras, selects the back camera (for pointing
  /// at mountains), and initializes the controller at medium resolution
  /// (a good balance between quality and performance for AR overlay).
  ///
  /// Returns true if initialization succeeded, false otherwise.
  /// Check [error] for details on failure.
  Future<bool> initialize() async {
    try {
      // Discover cameras on the device
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        _error = 'No cameras found on this device.';
        return false;
      }

      // Prefer the back camera (for pointing at mountains)
      final backCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      // Create the controller with medium resolution.
      // ResolutionPreset.medium (480p) is good for AR — high enough
      // to see the landscape clearly, low enough that overlay drawing
      // stays smooth.
      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false, // We don't need audio for mountain viewing
      );

      await _controller!.initialize();
      _isInitialized = true;
      _error = null;
      return true;
    } on CameraException catch (e) {
      _error = 'Camera error: ${e.description}';
      _isInitialized = false;
      return false;
    } catch (e) {
      _error = 'Failed to initialize camera: $e';
      _isInitialized = false;
      return false;
    }
  }

  /// Clean up camera resources.
  ///
  /// Always call this when leaving the camera screen. The camera is a
  /// shared hardware resource — if we don't release it, other apps
  /// (and even our own app on re-entry) can't use it.
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}

// -----------------------------------------------------------------------
//  Riverpod providers
// -----------------------------------------------------------------------

/// Provider that creates and manages the CameraService lifecycle.
///
/// The service is automatically disposed when the provider is no longer
/// watched (e.g., when navigating away from the camera screen).
final cameraServiceProvider = Provider.autoDispose<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});
