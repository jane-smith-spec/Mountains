/// Live view screen — the main AR camera view.
///
/// Full-screen camera with layered AR overlays:
///   Layer 1: Camera preview
///   Layer 2: Horizon topo line (toggleable)
///   Layer 3: Peak flags and landmark pins (toggleable)
///   Layer 4: HUD — compass, elevation, toggle panel
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/camera_service.dart';
import '../../services/location_service.dart';
import '../../services/sensor_service.dart';
import '../widgets/compass_indicator.dart';
import '../widgets/elevation_readout.dart';
import '../widgets/horizon_overlay.dart';
import '../widgets/toggle_panel.dart';

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
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraService = ref.read(cameraServiceProvider);
    if (!cameraService.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      cameraService.controller?.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
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
    final location = ref.watch(deviceLocationProvider);
    final visibility = ref.watch(layerVisibilityProvider);

    return Scaffold(
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

          // Layer 2: Horizon topo line overlay (toggleable)
          if (cameraService.isInitialized && visibility.showHorizon)
            const HorizonOverlay(),

          // Layer 3: (Future) Peak flags and landmark pins will be
          // added here once the peak database is loaded

          // Layer 4: HUD widgets
          if (cameraService.isInitialized) ...[
            // Compass at top center
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: orientation.when(
                  data: (o) => CompassIndicator(headingDeg: o.headingDeg),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),

            // Toggle panel at top right
            const TogglePanel(),

            // Elevation readout at bottom left
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              child: location.when(
                data: (loc) => ElevationReadout(
                  altitudeM: loc.altitudeM,
                  accuracyM: loc.accuracyM,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ],
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
}
