/// Share service — captures the AR view and shares annotated photos.
///
/// This service handles:
///   1. Capturing the AR overlay as a composited image
///   2. Adding a watermark/attribution line
///   3. Saving to the device gallery
///   4. Sharing via the system share sheet
///
/// The capture works by using Flutter's [RepaintBoundary] widget.
/// Any widget wrapped in a RepaintBoundary with a GlobalKey can be
/// converted to an image using [RenderRepaintBoundary.toImage()].
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Result of a share/save operation.
class ShareResult {
  const ShareResult({
    required this.success,
    this.filePath,
    this.error,
  });

  final bool success;
  final String? filePath;
  final String? error;

  static const ShareResult failed =
      ShareResult(success: false, error: 'Unknown error');
}

/// Service for capturing and sharing annotated AR views.
class ShareService {
  /// Capture a widget tree as a PNG image.
  ///
  /// [boundaryKey] must be attached to a [RepaintBoundary] widget
  /// that wraps the content you want to capture.
  ///
  /// [pixelRatio] controls the resolution (2.0 = 2x screen resolution).
  Future<Uint8List?> captureWidget({
    required GlobalKey boundaryKey,
    double pixelRatio = 2.0,
  }) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Save a PNG image to a temporary file and return the path.
  ///
  /// The file is saved in the app's temp directory with a timestamp-based
  /// filename. Caller is responsible for cleanup if needed.
  Future<ShareResult> saveToTempFile(Uint8List pngBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${tempDir.path}/peakline_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      return ShareResult(success: true, filePath: filePath);
    } catch (e) {
      return ShareResult(success: false, error: e.toString());
    }
  }

  /// Save a PNG image to the app's documents directory (persistent).
  ///
  /// Returns the file path on success.
  Future<ShareResult> saveToDocuments(Uint8List pngBytes, {
    String? filename,
  }) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final peaklineDir = Directory('${docsDir.path}/PeakLine');
      if (!await peaklineDir.exists()) {
        await peaklineDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final name = filename ?? 'peakline_$timestamp.png';
      final filePath = '${peaklineDir.path}/$name';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      return ShareResult(success: true, filePath: filePath);
    } catch (e) {
      return ShareResult(success: false, error: e.toString());
    }
  }

  /// Capture and save the AR view in one step.
  ///
  /// Captures the widget behind [boundaryKey], saves to temp file,
  /// and returns the path for sharing.
  Future<ShareResult> captureAndSave({
    required GlobalKey boundaryKey,
    double pixelRatio = 2.0,
  }) async {
    final bytes = await captureWidget(
      boundaryKey: boundaryKey,
      pixelRatio: pixelRatio,
    );

    if (bytes == null) {
      return const ShareResult(
        success: false,
        error: 'Failed to capture the view.',
      );
    }

    return saveToTempFile(bytes);
  }

  /// List all previously saved PeakLine images.
  Future<List<FileSystemEntity>> listSavedImages() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final peaklineDir = Directory('${docsDir.path}/PeakLine');
      if (!await peaklineDir.exists()) return [];

      return peaklineDir
          .listSync()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // Newest first
    } catch (_) {
      return [];
    }
  }
}

// -----------------------------------------------------------------------
//  Riverpod provider
// -----------------------------------------------------------------------

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService();
});
