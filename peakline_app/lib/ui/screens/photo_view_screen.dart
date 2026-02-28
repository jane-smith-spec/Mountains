/// Photo view screen — analyze an existing mountain photo.
///
/// This screen lets users:
///   1. Import a photo from their gallery
///   2. See extracted EXIF metadata (GPS, heading, focal length)
///   3. View the horizon overlay on the photo
///   4. Manually adjust the heading if auto-detection is off
///   5. Use a compass dial to set heading when EXIF has none
///
/// If the photo has GPS + compass heading, the overlay is placed
/// automatically. If only GPS is available, a compass dial lets the
/// user set the heading manually. The user can always drag to adjust.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/projection.dart';
import '../../data/dem_download_service.dart';
import '../../data/photo_repository.dart';
import '../../services/horizon_service.dart';
import '../../models/observer_state.dart';
import '../painters/horizon_painter.dart';

/// Status of the horizon overlay computation.
enum _HorizonStatus {
  /// No photo loaded yet.
  idle,

  /// Downloading the DEM tile for this location.
  downloading,

  /// Computing the horizon profile from DEM data.
  computing,

  /// Profile computed successfully — overlay is visible.
  ready,

  /// Download failed (network error, etc.).
  downloadFailed,

  /// Computation failed (C core error or missing data).
  failed,
}

class PhotoViewScreen extends ConsumerStatefulWidget {
  const PhotoViewScreen({super.key});

  @override
  ConsumerState<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends ConsumerState<PhotoViewScreen> {
  ImportedPhoto? _photo;
  bool _importing = false;
  String? _error;

  // Horizon overlay state
  _HorizonStatus _horizonStatus = _HorizonStatus.idle;
  int _profilePointCount = 0;

  // Heading: from EXIF, compass dial, or default
  double _headingDeg = 180.0;
  bool _headingFromExif = false;
  bool _showCompass = false;

  // Manual heading/pitch adjustment (drag to fine-tune)
  double _headingOffset = 0.0;
  double _pitchOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Analysis'),
        actions: [
          // Debug: test the overlay pipeline with synthetic data
          IconButton(
            icon: const Icon(Icons.science),
            onPressed: _testOverlayPipeline,
            tooltip: 'Test overlay (debug)',
          ),
          if (_photo != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showMetadataSheet(context),
              tooltip: 'Photo info',
            ),
        ],
      ),
      body: _photo == null
          ? _buildImportView(theme)
          : _buildAnalysisView(theme),
      floatingActionButton: _photo == null
          ? FloatingActionButton.extended(
              onPressed: _importing ? null : _pickPhoto,
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Photo'),
            )
          : FloatingActionButton(
              onPressed: _pickPhoto,
              child: const Icon(Icons.photo_library),
            ),
    );
  }

  Widget _buildImportView(ThemeData theme) {
    if (_importing) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Import a mountain photo',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a photo from your gallery. The app will read '
              'GPS and compass data from the photo to identify peaks.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  Analysis view — photo + overlay + controls
  // -----------------------------------------------------------------------

  Widget _buildAnalysisView(ThemeData theme) {
    final photo = _photo!;
    final meta = photo.metadata;

    return Column(
      children: [
        // Status banner (shows computing / errors / no tiles)
        if (_horizonStatus != _HorizonStatus.idle &&
            _horizonStatus != _HorizonStatus.ready)
          _buildStatusBanner(theme),

        // Photo with overlay
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: _showCompass
                ? null
                : (details) {
                    setState(() {
                      _headingOffset += details.delta.dx * 0.1;
                    });
                  },
            onVerticalDragUpdate: _showCompass
                ? null
                : (details) {
                    setState(() {
                      _pitchOffset -= details.delta.dy * 0.05;
                    });
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The photo
                Image.file(
                  File(photo.filePath),
                  fit: BoxFit.contain,
                ),

                // Horizon overlay — always show when we have a profile,
                // even if heading is uncertain. User can drag to align.
                if (meta.hasGps && _profilePointCount > 0)
                  _buildHorizonOverlay(meta),

                // Compass dial (when heading is unknown or user wants to set it)
                if (_showCompass)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildCompassDial(theme),
                  ),

                // Adjustment hint
                if (!_showCompass)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _headingOffset != 0 || _pitchOffset != 0
                              ? 'Offset: ${_headingOffset.toStringAsFixed(1)}\u00B0 H, '
                                  '${_pitchOffset.toStringAsFixed(1)}\u00B0 V'
                              : _horizonStatus == _HorizonStatus.ready
                                  ? 'Drag to adjust overlay alignment'
                                  : '',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Metadata bar
        _buildMetadataBar(theme, meta),
      ],
    );
  }

  // -----------------------------------------------------------------------
  //  Status banner — shows above photo when something needs attention
  // -----------------------------------------------------------------------

  Widget _buildStatusBanner(ThemeData theme) {
    IconData icon;
    String message;
    Color bgColor;
    Color fgColor;
    VoidCallback? action;
    String? actionLabel;

    switch (_horizonStatus) {
      case _HorizonStatus.downloading:
        icon = Icons.cloud_download;
        message = 'Downloading elevation data for this location...';
        bgColor = theme.colorScheme.primaryContainer;
        fgColor = theme.colorScheme.onPrimaryContainer;
      case _HorizonStatus.computing:
        icon = Icons.hourglass_top;
        message = 'Computing horizon profile...';
        bgColor = theme.colorScheme.primaryContainer;
        fgColor = theme.colorScheme.onPrimaryContainer;
      case _HorizonStatus.downloadFailed:
        icon = Icons.cloud_off;
        message = 'Could not download elevation data. '
            'Check your connection, or download tiles from Regions.';
        bgColor = theme.colorScheme.errorContainer;
        fgColor = theme.colorScheme.onErrorContainer;
        actionLabel = 'Retry';
        action = () => _computeHorizon();
      case _HorizonStatus.failed:
        icon = Icons.warning_amber;
        message = 'Failed to compute horizon profile. '
            'Try a photo from a different location.';
        bgColor = theme.colorScheme.errorContainer;
        fgColor = theme.colorScheme.onErrorContainer;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fgColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
            ),
          ),
          if (action != null && actionLabel != null)
            TextButton(
              onPressed: action,
              child: Text(actionLabel, style: TextStyle(color: fgColor)),
            ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  Horizon overlay — draws the topo silhouette over the photo
  // -----------------------------------------------------------------------

  Widget _buildHorizonOverlay(PhotoMetadata meta) {
    final horizonService = ref.watch(horizonServiceProvider);
    final heading = (_headingDeg + _headingOffset) % 360.0;
    final pitch = _pitchOffset;
    final fov = meta.estimatedHorizontalFovDeg ?? defaultHorizontalFovDeg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final camera = CameraViewParams(
          headingDeg: heading,
          pitchDeg: pitch,
          screenWidth: constraints.maxWidth,
          screenHeight: constraints.maxHeight,
          horizontalFovDeg: fov,
        );

        final screenPoints = horizonService.projectToScreen(camera: camera);

        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: HorizonPainter(
            points: screenPoints,
            lineColor: const Color(0xFF00E676),
            lineWidth: 2.0,
          ),
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  //  Compass dial — circular heading selector
  // -----------------------------------------------------------------------

  Widget _buildCompassDial(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Set camera direction',
            style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Rotate the dial to match the direction you were facing',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Compass rose with draggable heading
          SizedBox(
            height: 160,
            width: 160,
            child: GestureDetector(
              onPanUpdate: (details) {
                final center = const Offset(80, 80);
                final pos = details.localPosition;
                final angle =
                    math.atan2(pos.dx - center.dx, center.dy - pos.dy) *
                        rad2Deg;
                setState(() {
                  _headingDeg = (angle + 360) % 360;
                });
              },
              child: CustomPaint(
                size: const Size(160, 160),
                painter: _CompassPainter(headingDeg: _headingDeg),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_headingDeg.toStringAsFixed(0)}\u00B0 '
            '${_compassLabel(_headingDeg)}',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => setState(() => _showCompass = false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white60)),
              ),
              FilledButton(
                onPressed: () async {
                  setState(() => _showCompass = false);
                  await _computeHorizon();
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _compassLabel(double deg) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((deg + 22.5) / 45.0).floor() % 8;
    return labels[index];
  }

  // -----------------------------------------------------------------------
  //  Metadata bar
  // -----------------------------------------------------------------------

  Widget _buildMetadataBar(ThemeData theme, PhotoMetadata meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          // GPS status
          _metaChip(
            theme,
            meta.hasGps ? Icons.location_on : Icons.location_off,
            meta.hasGps
                ? '${meta.latitudeDeg!.toStringAsFixed(3)}\u00B0, '
                    '${meta.longitudeDeg!.toStringAsFixed(3)}\u00B0'
                : 'No GPS',
            meta.hasGps,
          ),
          const SizedBox(width: 8),
          // Heading status — tappable to open compass
          GestureDetector(
            onTap: () => setState(() => _showCompass = !_showCompass),
            child: _metaChip(
              theme,
              Icons.explore,
              _headingFromExif || _showCompass
                  ? '${_headingDeg.toStringAsFixed(0)}\u00B0'
                  : 'Set heading',
              _headingFromExif || _showCompass,
            ),
          ),
          const SizedBox(width: 8),
          // Focal length
          if (meta.focalLengthMm != null)
            _metaChip(
              theme,
              Icons.camera,
              '${meta.focalLengthMm!.toStringAsFixed(1)}mm',
              true,
            ),
          const Spacer(),
          // Profile point count
          if (_profilePointCount > 0)
            Text(
              '$_profilePointCount pts',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          const SizedBox(width: 8),
          // Reset button
          if (_headingOffset != 0 || _pitchOffset != 0)
            TextButton(
              onPressed: () => setState(() {
                _headingOffset = 0;
                _pitchOffset = 0;
              }),
              child: const Text('Reset'),
            ),
        ],
      ),
    );
  }

  Widget _metaChip(
    ThemeData theme,
    IconData icon,
    String label,
    bool available,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: available
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: available
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: available
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  void _showMetadataSheet(BuildContext context) {
    final meta = _photo!.metadata;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photo Metadata', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (meta.hasGps) ...[
              _metaRow('Latitude',
                  '${meta.latitudeDeg!.toStringAsFixed(5)}\u00B0'),
              _metaRow('Longitude',
                  '${meta.longitudeDeg!.toStringAsFixed(5)}\u00B0'),
            ] else
              _metaRow('GPS', 'Not available'),
            if (meta.altitudeM != null)
              _metaRow(
                  'Altitude', '${meta.altitudeM!.toStringAsFixed(0)} m'),
            _metaRow(
                'Heading',
                _headingFromExif
                    ? '${_headingDeg.toStringAsFixed(1)}\u00B0 (from EXIF)'
                    : '${_headingDeg.toStringAsFixed(1)}\u00B0 (manual)'),
            if (meta.focalLengthMm != null)
              _metaRow('Focal length',
                  '${meta.focalLengthMm!.toStringAsFixed(1)} mm'),
            if (meta.estimatedHorizontalFovDeg != null)
              _metaRow('Est. FOV',
                  '${meta.estimatedHorizontalFovDeg!.toStringAsFixed(1)}\u00B0'),
            if (meta.cameraMake != null)
              _metaRow('Camera',
                  '${meta.cameraMake} ${meta.cameraModel ?? ''}'),
            if (meta.dateTime != null)
              _metaRow('Date', meta.dateTime.toString()),
            _metaRow(
                'Horizon',
                _horizonStatus == _HorizonStatus.ready
                    ? '$_profilePointCount points'
                    : _horizonStatus.name),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  Photo picking and horizon computation
  // -----------------------------------------------------------------------

  Future<void> _pickPhoto() async {
    setState(() {
      _importing = true;
      _error = null;
      _horizonStatus = _HorizonStatus.idle;
    });

    try {
      final photoRepo = ref.read(photoRepositoryProvider);
      final result = await photoRepo.pickFromGallery();

      if (mounted) {
        setState(() {
          _importing = false;
          _photo = result;
          _headingOffset = 0;
          _pitchOffset = 0;
          _profilePointCount = 0;

          if (result == null) {
            _error = null; // user cancelled
          } else if (!result.metadata.hasGps) {
            _error =
                'No GPS data in photo. Overlay requires GPS coordinates.';
          }

          // Set heading from EXIF or prompt for manual
          if (result != null && result.metadata.hasHeading) {
            _headingDeg = result.metadata.headingDeg!;
            _headingFromExif = true;
            _showCompass = false;
          } else {
            _headingDeg = 180.0;
            _headingFromExif = false;
            // Auto-show compass when heading is missing but GPS is present
            _showCompass = result != null && result.metadata.hasGps;
          }
        });

        // If we have GPS, compute the horizon
        if (result != null && result.metadata.hasGps) {
          await _computeHorizon();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = 'Failed to import photo: $e';
        });
      }
    }
  }

  /// Compute horizon profile using DEM tiles for the photo's GPS location.
  ///
  /// If the tile isn't downloaded yet, auto-downloads it at medium quality
  /// (90m) and keeps it permanently for future use.
  Future<void> _computeHorizon() async {
    final meta = _photo?.metadata;
    if (meta == null || !meta.hasGps) return;

    try {
      // Ensure the DEM tile is available — auto-download if missing
      final downloadService = ref.read(demDownloadServiceProvider);

      setState(() => _horizonStatus = _HorizonStatus.downloading);

      final demPath = await downloadService.ensureTileForCoordinate(
        meta.latitudeDeg!,
        meta.longitudeDeg!,
        quality: DownloadQuality.medium,
      );

      if (!mounted) return;

      if (demPath == null) {
        setState(() => _horizonStatus = _HorizonStatus.downloadFailed);
        return;
      }

      // Compute the 360° horizon profile via C native core
      setState(() => _horizonStatus = _HorizonStatus.computing);

      final horizonService = ref.read(horizonServiceProvider);
      final points = await horizonService.computeProfile(
        observer: ObserverState(
          latitudeDeg: meta.latitudeDeg!,
          longitudeDeg: meta.longitudeDeg!,
          altitudeM: meta.altitudeM ?? 0,
          headingDeg: _headingDeg,
          pitchDeg: 0,
        ),
        demPath: demPath,
      );

      if (mounted) {
        setState(() {
          _profilePointCount = points.length;
          _horizonStatus = points.isNotEmpty
              ? _HorizonStatus.ready
              : _HorizonStatus.failed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _horizonStatus = _HorizonStatus.failed);
      }
    }
  }

  /// Debug: Test the full overlay pipeline with synthetic terrain data.
  ///
  /// Creates a known .hgt file with a simple mountain (bypasses GeoTIFF
  /// conversion entirely) and feeds it to the C core. This isolates
  /// whether the problem is in GeoTIFF conversion vs C core/projection.
  Future<void> _testOverlayPipeline() async {
    setState(() {
      _horizonStatus = _HorizonStatus.computing;
      _error = null;
    });

    try {
      // Create a synthetic 401×401 .hgt tile (250m resolution)
      // Centered at N46 E007 (Swiss Alps area)
      const grid = 401;
      const lat = 46;
      const lon = 7;

      final appDir = await getApplicationDocumentsDirectory();
      final demDir = Directory('${appDir.path}/dem_tiles');
      if (!await demDir.exists()) {
        await demDir.create(recursive: true);
      }
      final hgtPath = '${demDir.path}/N${lat}E${lon.toString().padLeft(3, '0')}.hgt';

      debugPrint('TestOverlay: creating synthetic .hgt at $hgtPath');

      // Build terrain: a cone mountain that peaks at center (200,200)
      // with elevation from 500m (edges) to 4000m (summit)
      final data = ByteData(grid * grid * 2);
      for (int row = 0; row < grid; row++) {
        for (int col = 0; col < grid; col++) {
          final dy = (row - 200).abs();
          final dx = (col - 200).abs();
          final dist = math.sqrt((dx * dx + dy * dy).toDouble());
          final maxDist = 200.0;
          final elevation = dist < maxDist
              ? (500 + (3500 * (1.0 - dist / maxDist))).toInt()
              : 500;
          data.setInt16((row * grid + col) * 2, elevation, Endian.big);
        }
      }

      await File(hgtPath).writeAsBytes(data.buffer.asUint8List());

      final fileSize = await File(hgtPath).length();
      debugPrint('TestOverlay: wrote $fileSize bytes '
          '(expected ${grid * grid * 2})');

      // Observer at the SW corner of the tile, looking NE toward the mountain
      const obsLat = 46.1;
      const obsLon = 7.1;
      const obsAlt = 800.0;
      const heading = 45.0; // NE toward mountain

      setState(() {
        _headingDeg = heading;
        _headingFromExif = false;
        _showCompass = false;
      });

      // Compute horizon profile via C native core
      final horizonService = ref.read(horizonServiceProvider);
      final points = await horizonService.computeProfile(
        observer: const ObserverState(
          latitudeDeg: obsLat,
          longitudeDeg: obsLon,
          altitudeM: obsAlt,
          headingDeg: heading,
          pitchDeg: 0,
        ),
        demPath: hgtPath,
      );

      debugPrint('TestOverlay: got ${points.length} horizon points');
      if (points.isNotEmpty) {
        // Log a few sample points
        for (int i = 0; i < points.length && i < 5; i++) {
          debugPrint('  point[$i]: az=${points[i].azimuthDeg.toStringAsFixed(1)}° '
              'el=${points[i].elevationAngleDeg.toStringAsFixed(2)}° '
              'dist=${(points[i].distanceM / 1000).toStringAsFixed(1)}km');
        }
      }

      if (mounted) {
        setState(() {
          _profilePointCount = points.length;
          if (points.isNotEmpty) {
            _horizonStatus = _HorizonStatus.ready;
            _error = null;
          } else {
            _horizonStatus = _HorizonStatus.failed;
            _error = 'C core returned 0 points. '
                'Native library may not be loaded.';
          }
        });

        // Show result dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(points.isNotEmpty
                  ? 'Test Overlay: SUCCESS'
                  : 'Test Overlay: No Points'),
              content: Text(
                points.isNotEmpty
                    ? '${points.length} horizon points computed.\n'
                        'The overlay pipeline works!\n\n'
                        'If you don\'t see a line on real photos, the '
                        'issue is likely in the GeoTIFF download/conversion.'
                    : 'The C core returned 0 points.\n'
                        'The native library may not be loaded.\n'
                        'This is expected in debug mode without the C '
                        'library compiled.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('TestOverlay: error: $e');
      if (mounted) {
        setState(() {
          _horizonStatus = _HorizonStatus.failed;
          _error = 'Test overlay error: $e';
        });
      }
    }
  }
}

// -------------------------------------------------------------------------
//  Compass painter — draws a simple compass rose
// -------------------------------------------------------------------------

class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.headingDeg});

  final double headingDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Outer circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Cardinal direction labels
    const labels = ['N', 'E', 'S', 'W'];
    const angles = [0.0, 90.0, 180.0, 270.0];
    final textStyle = TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    for (int i = 0; i < 4; i++) {
      final angle = (angles[i] - 90) * deg2Rad;
      final x = center.dx + (radius - 16) * math.cos(angle);
      final y = center.dy + (radius - 16) * math.sin(angle);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: labels[i] == 'N'
              ? textStyle.copyWith(color: Colors.red)
              : textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // Tick marks every 30 degrees
    for (int deg = 0; deg < 360; deg += 30) {
      final angle = (deg - 90) * deg2Rad;
      final outerR = radius;
      final innerR = deg % 90 == 0 ? radius - 10 : radius - 6;
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(angle),
            center.dy + innerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle),
            center.dy + outerR * math.sin(angle)),
        Paint()
          ..color = Colors.white38
          ..strokeWidth = 1.5,
      );
    }

    // Direction indicator (pointer at current heading)
    final pointerAngle = (headingDeg - 90) * deg2Rad;
    final pointerX = center.dx + (radius + 2) * math.cos(pointerAngle);
    final pointerY = center.dy + (radius + 2) * math.sin(pointerAngle);
    canvas.drawCircle(
      Offset(pointerX, pointerY),
      6,
      Paint()..color = const Color(0xFF00E676),
    );

    // Line from center to pointer
    canvas.drawLine(
      center,
      Offset(
        center.dx + (radius - 24) * math.cos(pointerAngle),
        center.dy + (radius - 24) * math.sin(pointerAngle),
      ),
      Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      headingDeg != oldDelegate.headingDeg;
}
