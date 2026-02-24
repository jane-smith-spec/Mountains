/// Live view screen — the main AR camera view.
///
/// This is where the magic happens: the phone's camera feed is displayed
/// full-screen, and later we'll overlay the horizon topo line, peak labels,
/// and landmark pins on top of it.
///
/// For now (Step 5), this screen:
///   - Initializes the camera on entry
///   - Shows a full-screen camera preview
///   - Displays live sensor readings (heading, pitch) as a HUD overlay
///   - Handles permission errors and loading states gracefully
///   - Cleans up camera resources on exit
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/camera_service.dart';
import '../../services/sensor_service.dart';

/// The live AR camera view screen.
///
/// Uses [ConsumerStatefulWidget] because we need both:
///   - Riverpod (Consumer) for watching sensor/camera providers
///   - StatefulWidget lifecycle (initState/dispose) for camera init
class LiveViewScreen extends ConsumerStatefulWidget {
  const LiveViewScreen({super.key});

  @override
  ConsumerState<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends ConsumerState<LiveViewScreen>
    with WidgetsBindingObserver {
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Watch for app lifecycle changes (e.g., user switches to another app).
    // We need to pause/resume the camera accordingly.
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Handle app lifecycle changes.
  ///
  /// When the user switches away from the app, we pause the camera to
  /// save battery and release the hardware. When they come back, we
  /// resume it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraService = ref.read(cameraServiceProvider);
    if (!cameraService.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      // App is going to background — pause camera
      cameraService.controller?.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
      // App is coming back — resume camera
      cameraService.controller?.resumePreview();
    }
  }

  Future<void> _initializeCamera() async {
    final cameraService = ref.read(cameraServiceProvider);
    final success = await cameraService.initialize();

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _error = success ? null : cameraService.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraService = ref.watch(cameraServiceProvider);
    final orientation = ref.watch(deviceOrientationProvider);

    return Scaffold(
      // Make the camera fill the entire screen, including behind the status bar
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Camera preview (or loading/error state)
          _buildCameraLayer(cameraService),

          // Layer 2: Sensor HUD overlay (heading, pitch, GPS)
          if (cameraService.isInitialized) _buildSensorHud(orientation),

          // Layer 3: (Future) Horizon overlay will go here

          // Layer 4: (Future) Peak labels will go here
        ],
      ),
    );
  }

  /// Build the camera preview or a placeholder.
  Widget _buildCameraLayer(CameraService cameraService) {
    if (_isInitializing) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Starting camera...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isInitializing = true;
                      _error = null;
                    });
                    _initializeCamera();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(color: Colors.black);
    }

    // Fill the screen with the camera preview, cropping as needed.
    // CameraPreview maintains its aspect ratio, so we use a FittedBox
    // with BoxFit.cover to ensure it fills the entire screen.
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize!.height,
          height: controller.value.previewSize!.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// Build the sensor heads-up display overlay.
  ///
  /// Shows the current compass heading and pitch on top of the camera
  /// feed so you can see which direction you're pointing. This data
  /// will later be used to align the horizon overlay.
  Widget _buildSensorHud(AsyncValue<dynamic> orientation) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
        child: SafeArea(
          top: false,
          child: orientation.when(
            data: (o) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _hudItem(
                  Icons.explore,
                  '${o.headingDeg.toStringAsFixed(0)}°',
                  _headingLabel(o.headingDeg),
                ),
                _hudItem(
                  Icons.straight,
                  '${o.pitchDeg.toStringAsFixed(0)}°',
                  'Pitch',
                ),
                _hudItem(
                  Icons.screen_rotation,
                  '${o.rollDeg.toStringAsFixed(0)}°',
                  'Roll',
                ),
              ],
            ),
            loading: () => const Text(
              'Starting sensors...',
              style: TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            error: (e, _) => Text(
              'Sensor error: $e',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  /// A single HUD readout item.
  Widget _hudItem(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  /// Cardinal direction label for a heading.
  String _headingLabel(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading < 67.5) return 'NE';
    if (heading < 112.5) return 'E';
    if (heading < 157.5) return 'SE';
    if (heading < 202.5) return 'S';
    if (heading < 247.5) return 'SW';
    if (heading < 292.5) return 'W';
    return 'NW';
  }
}
