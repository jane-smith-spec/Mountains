/// Photo view screen — analyze an existing mountain photo.
///
/// This screen lets users:
///   1. Import a photo from their gallery
///   2. See extracted EXIF metadata (GPS, heading, focal length)
///   3. View the horizon overlay on the photo
///   4. Manually adjust the heading if auto-detection is off
///   5. See peak labels on the photo
///
/// If the photo has GPS + compass heading, the overlay is placed
/// automatically. If only GPS is available, the skyline matcher
/// attempts to find the heading. The user can always drag to adjust.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/projection.dart';
import '../../data/photo_repository.dart';
import '../../services/horizon_service.dart';
import '../../models/observer_state.dart';
import '../painters/horizon_painter.dart';

class PhotoViewScreen extends ConsumerStatefulWidget {
  const PhotoViewScreen({super.key});

  @override
  ConsumerState<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends ConsumerState<PhotoViewScreen> {
  ImportedPhoto? _photo;
  bool _importing = false;
  String? _error;

  // Manual heading adjustment
  double _headingOffset = 0.0;
  double _pitchOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Analysis'),
        actions: [
          if (_photo != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showMetadataSheet(context),
              tooltip: 'Photo info',
            ),
        ],
      ),
      body: _photo == null ? _buildImportView(theme) : _buildAnalysisView(theme),
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

  Widget _buildAnalysisView(ThemeData theme) {
    final photo = _photo!;
    final meta = photo.metadata;

    return Column(
      children: [
        // Photo with overlay
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                // Drag left/right to adjust heading
                _headingOffset += details.delta.dx * 0.1;
              });
            },
            onVerticalDragUpdate: (details) {
              setState(() {
                // Drag up/down to adjust pitch
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

                // Horizon overlay (if we have GPS)
                if (meta.hasGps) _buildHorizonOverlay(meta),

                // Adjustment hint
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
                            ? 'Offset: ${_headingOffset.toStringAsFixed(1)}° H, '
                                '${_pitchOffset.toStringAsFixed(1)}° V'
                            : 'Drag to adjust overlay alignment',
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

  Widget _buildHorizonOverlay(PhotoMetadata meta) {
    final horizonService = ref.watch(horizonServiceProvider);
    final heading = (meta.headingDeg ?? 180.0) + _headingOffset;
    final pitch = _pitchOffset;
    final fov = meta.estimatedHorizontalFovDeg ?? defaultHorizontalFovDeg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final camera = CameraViewParams(
          headingDeg: heading % 360.0,
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
                ? '${meta.latitudeDeg!.toStringAsFixed(3)}°, '
                    '${meta.longitudeDeg!.toStringAsFixed(3)}°'
                : 'No GPS',
            meta.hasGps,
          ),
          const SizedBox(width: 8),
          // Heading status
          _metaChip(
            theme,
            meta.hasHeading ? Icons.explore : Icons.explore_off,
            meta.hasHeading
                ? '${meta.headingDeg!.toStringAsFixed(0)}°'
                : 'No heading',
            meta.hasHeading,
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
            Text('Photo Metadata',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (meta.hasGps) ...[
              _metaRow('Latitude', '${meta.latitudeDeg!.toStringAsFixed(5)}°'),
              _metaRow('Longitude', '${meta.longitudeDeg!.toStringAsFixed(5)}°'),
            ] else
              _metaRow('GPS', 'Not available'),
            if (meta.altitudeM != null)
              _metaRow('Altitude', '${meta.altitudeM!.toStringAsFixed(0)} m'),
            if (meta.hasHeading)
              _metaRow('Heading', '${meta.headingDeg!.toStringAsFixed(1)}°'),
            if (meta.focalLengthMm != null)
              _metaRow('Focal length', '${meta.focalLengthMm!.toStringAsFixed(1)} mm'),
            if (meta.estimatedHorizontalFovDeg != null)
              _metaRow('Est. FOV',
                  '${meta.estimatedHorizontalFovDeg!.toStringAsFixed(1)}°'),
            if (meta.cameraMake != null)
              _metaRow('Camera', '${meta.cameraMake} ${meta.cameraModel ?? ''}'),
            if (meta.dateTime != null)
              _metaRow('Date', meta.dateTime.toString()),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _importing = true;
      _error = null;
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
          if (result == null) {
            _error = null; // user cancelled, not an error
          } else if (!result.metadata.hasGps) {
            _error = 'No GPS data in photo. Overlay requires GPS coordinates.';
          }
        });

        // If we have GPS, trigger a horizon computation
        if (result != null && result.metadata.hasGps) {
          final horizonService = ref.read(horizonServiceProvider);
          await horizonService.computeProfile(
            observer: ObserverState(
              latitudeDeg: result.metadata.latitudeDeg!,
              longitudeDeg: result.metadata.longitudeDeg!,
              altitudeM: result.metadata.altitudeM ?? 0,
              headingDeg: result.metadata.headingDeg ?? 180,
              pitchDeg: 0,
            ),
          );
          if (mounted) setState(() {});
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
}
