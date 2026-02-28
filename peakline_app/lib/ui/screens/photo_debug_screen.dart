import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/photo_metadata.dart';
import '../../data/photo_repository.dart';
import '../widgets/topo_silhouette_painter.dart';

class PhotoDebugScreen extends StatefulWidget {
  const PhotoDebugScreen({super.key});

  @override
  State<PhotoDebugScreen> createState() => _PhotoDebugScreenState();
}

class _PhotoDebugScreenState extends State<PhotoDebugScreen> {
  final PhotoRepository _photoRepository = PhotoRepository();

  PhotoMetadata? _photoMetadata;
  String? _error;
  bool _isLoading = false;

  Future<void> _pickPhoto() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final PhotoMetadata? metadata = await _photoRepository.pickAndReadMetadata();
      setState(() {
        _photoMetadata = metadata;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not read photo metadata: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Photo Mode (Debug)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _pickPhoto,
            icon: const Icon(Icons.photo_library),
            label: Text(_isLoading ? 'Opening...' : 'Open Photo'),
          ),
          const SizedBox(height: 12),
          if (_photoMetadata != null) ...[
            Text(
              _photoMetadata!.hasGps
                  ? 'GPS: ${_photoMetadata!.latitude!.toStringAsFixed(6)}, ${_photoMetadata!.longitude!.toStringAsFixed(6)}'
                  : 'GPS: not found in EXIF',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(_photoMetadata!.path),
                      fit: BoxFit.cover,
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: TopoSilhouettePainter(color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('Open a photo to inspect EXIF GPS metadata.', style: theme.textTheme.bodyMedium),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Topo silhouette preview', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomPaint(
                        painter: TopoSilhouettePainter(color: theme.colorScheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
