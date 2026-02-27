/// Live view screen — the main AR camera view.
///
/// Full-screen camera with layered AR overlays:
///   Layer 1: Camera preview
///   Layer 2: Bearing/elevation grid (optional)
///   Layer 3: Horizon topo line (toggleable)
///   Layer 4: Peak flags and landmark pins (toggleable)
///   Layer 5: HUD — compass, elevation, toggle panel, capture button
///
/// Now supports gyro-stabilized overlay for smoother tracking.
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/dem_download_service.dart';
import '../../services/camera_service.dart';
import '../../services/gyro_stabilizer.dart';
import '../../services/horizon_service.dart';
import '../../models/sensor_data.dart';
import '../../services/location_service.dart';
import '../../services/sensor_service.dart';
import '../../services/share_service.dart';
import '../../models/observer_state.dart';
import '../painters/grid_painter.dart';
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
  bool _showGrid = false;
  bool _useGyroStabilization = true;
  bool _isCapturing = false;

  /// Whether we've triggered the initial horizon computation.
  bool _horizonTriggered = false;
  bool _horizonDownloading = false;

  /// Key for the RepaintBoundary wrapping the AR content.
  final _captureKey = GlobalKey();

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

  Future<void> _captureAndShare() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final shareService = ref.read(shareServiceProvider);
      final result = await shareService.captureAndSave(
        boundaryKey: _captureKey,
      );

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to ${result.filePath}'),
              action: SnackBarAction(
                label: 'OK',
                onPressed: () {},
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Capture failed: ${result.error}'),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Auto-download the DEM tile for the current GPS location and
  /// compute the horizon profile so the overlay appears.
  Future<void> _ensureHorizonForLocation(DeviceLocation loc) async {
    if (mounted) setState(() => _horizonDownloading = true);

    try {
      final downloadService = ref.read(demDownloadServiceProvider);
      final demPath = await downloadService.ensureTileForCoordinate(
        loc.latitudeDeg,
        loc.longitudeDeg,
        quality: DownloadQuality.medium,
      );

      if (!mounted || demPath == null) {
        if (mounted) setState(() => _horizonDownloading = false);
        return;
      }

      setState(() => _horizonDownloading = false);

      // Compute horizon profile so the overlay has data
      final horizonService = ref.read(horizonServiceProvider);
      await horizonService.computeProfile(
        observer: ObserverState(
          latitudeDeg: loc.latitudeDeg,
          longitudeDeg: loc.longitudeDeg,
          altitudeM: loc.altitudeM,
          headingDeg: 0, // full 360° profile, heading doesn't matter
          pitchDeg: 0,
        ),
        demPath: demPath,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _horizonDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraService = ref.watch(cameraServiceProvider);
    final visibility = ref.watch(layerVisibilityProvider);

    // Choose between gyro-stabilized and standard orientation
    final orientationAsync = _useGyroStabilization
        ? ref.watch(stabilizedOrientationProvider)
        : ref.watch(deviceOrientationProvider);

    final location = ref.watch(deviceLocationProvider);

    // Trigger horizon computation when GPS becomes available
    if (!_horizonTriggered) {
      location.whenData((loc) {
        _horizonTriggered = true;
        _ensureHorizonForLocation(loc);
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RepaintBoundary(
        key: _captureKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Camera preview (or loading/error state)
            _buildCameraLayer(cameraService),

            // Layer 2: Bearing/elevation grid (optional)
            if (cameraService.isInitialized && _showGrid)
              orientationAsync.when(
                data: (o) => CustomPaint(
                  size: Size.infinite,
                  painter: GridPainter(
                    headingDeg: o.headingDeg,
                    pitchDeg: o.pitchDeg,
                    hFovDeg: defaultHorizontalFovDeg,
                    vFovDeg: defaultVerticalFovDeg,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

            // Layer 3: Horizon topo line overlay (toggleable)
            if (cameraService.isInitialized && visibility.showHorizon)
              const HorizonOverlay(),

            // Tile download indicator
            if (_horizonDownloading)
              Positioned(
                top: MediaQuery.of(context).padding.top + 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white70,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Downloading elevation data...',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Layer 4: (Future) Peak flags and landmark pins will be
            // added here once the peak database is loaded

            // Layer 5: HUD widgets
            if (cameraService.isInitialized) ...[
              // Compass at top center
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 0,
                right: 0,
                child: Center(
                  child: orientationAsync.when(
                    data: (o) => CompassIndicator(headingDeg: o.headingDeg),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
              ),

              // Toggle panel at top right
              const TogglePanel(),

              // Bottom bar: elevation readout + action buttons
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Elevation readout
                    location.when(
                      data: (loc) => ElevationReadout(
                        altitudeM: loc.altitudeM,
                        accuracyM: loc.accuracyM,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    const Spacer(),

                    // Action buttons (grid, gyro, capture)
                    _buildActionButtons(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bottom-right action buttons for grid, gyro toggle, and capture.
  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Grid toggle
        _circleButton(
          icon: Icons.grid_on,
          isActive: _showGrid,
          tooltip: 'Toggle grid',
          onTap: () => setState(() => _showGrid = !_showGrid),
        ),
        const SizedBox(height: 8),
        // Gyro stabilization toggle
        _circleButton(
          icon: Icons.screen_rotation,
          isActive: _useGyroStabilization,
          tooltip: _useGyroStabilization ? 'Gyro ON' : 'Gyro OFF',
          onTap: () => setState(
            () => _useGyroStabilization = !_useGyroStabilization,
          ),
        ),
        const SizedBox(height: 8),
        // Capture button
        _circleButton(
          icon: _isCapturing ? Icons.hourglass_empty : Icons.camera,
          isActive: false,
          tooltip: 'Capture',
          onTap: _isCapturing ? null : _captureAndShare,
          size: 48,
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool isActive,
    required String tooltip,
    VoidCallback? onTap,
    double size = 36,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.5),
            border: Border.all(
              color: isActive ? Colors.white70 : Colors.white30,
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.white : Colors.white54,
            size: size * 0.5,
          ),
        ),
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
