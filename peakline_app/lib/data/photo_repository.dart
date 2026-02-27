/// Photo repository — imports photos and extracts EXIF metadata.
///
/// When a user picks a mountain photo from their gallery, this
/// repository:
///   1. Reads the image file
///   2. Extracts GPS coordinates (where the photo was taken)
///   3. Extracts compass heading (which direction the camera faced)
///   4. Extracts focal length (to estimate the field of view)
///
/// If GPS is present but compass heading is missing, the app can
/// still work by using the skyline matcher to figure out the heading.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Metadata extracted from a photo's EXIF data.
class PhotoMetadata {
  const PhotoMetadata({
    this.latitudeDeg,
    this.longitudeDeg,
    this.altitudeM,
    this.headingDeg,
    this.focalLengthMm,
    this.dateTime,
    this.cameraMake,
    this.cameraModel,
  });

  /// GPS latitude (null if no GPS data in photo).
  final double? latitudeDeg;

  /// GPS longitude (null if no GPS data in photo).
  final double? longitudeDeg;

  /// GPS altitude in meters (null if not available).
  final double? altitudeM;

  /// Compass heading the camera was pointing (null if not recorded).
  /// This is the key piece — without it we need skyline matching.
  final double? headingDeg;

  /// Focal length in millimeters (used to estimate FOV).
  final double? focalLengthMm;

  /// When the photo was taken.
  final DateTime? dateTime;

  /// Camera manufacturer (e.g., "Apple", "Samsung").
  final String? cameraMake;

  /// Camera model (e.g., "iPhone 15 Pro", "Galaxy S24").
  final String? cameraModel;

  /// Whether we have GPS coordinates.
  bool get hasGps => latitudeDeg != null && longitudeDeg != null;

  /// Whether we have compass heading.
  bool get hasHeading => headingDeg != null;

  /// Estimate horizontal FOV from focal length.
  ///
  /// Uses a typical phone sensor width of 6.17mm (iPhone/Samsung).
  /// FOV = 2 × atan(sensorWidth / (2 × focalLength))
  ///
  /// Returns null if focal length is not available.
  double? get estimatedHorizontalFovDeg {
    final fl = focalLengthMm;
    if (fl == null || fl <= 0) return null;

    // Typical phone sensor width in mm
    const sensorWidthMm = 6.17;
    // FOV = 2 * atan(sensor_width / (2 * focal_length)) in degrees
    // atan approximation: atan(x) ≈ x for small x, but we need better
    // Use the identity: atan(x) ≈ x - x³/3 + x⁵/5 for |x| < 1
    final x = sensorWidthMm / (2.0 * fl);
    final atanX = x - (x * x * x) / 3.0 + (x * x * x * x * x) / 5.0;
    return 2.0 * atanX * (180.0 / 3.14159265358979);
  }

  @override
  String toString() {
    final parts = <String>[];
    if (hasGps) {
      parts.add('${latitudeDeg!.toStringAsFixed(4)}°N, '
          '${longitudeDeg!.toStringAsFixed(4)}°E');
    }
    if (hasHeading) parts.add('heading=${headingDeg!.toStringAsFixed(0)}°');
    if (focalLengthMm != null) {
      parts.add('${focalLengthMm!.toStringAsFixed(2)}mm');
    }
    return 'PhotoMetadata(${parts.join(', ')})';
  }
}

/// The result of importing a photo.
class ImportedPhoto {
  const ImportedPhoto({
    required this.filePath,
    required this.metadata,
  });

  /// Path to the image file on disk.
  final String filePath;

  /// Extracted EXIF metadata.
  final PhotoMetadata metadata;
}

/// Repository for importing and reading photo metadata.
class PhotoRepository {
  final _picker = ImagePicker();

  /// Pick a photo from the device gallery and extract its metadata.
  ///
  /// Returns null if the user cancelled the picker.
  ///
  /// The image bytes are captured once from the picker, then:
  ///   1. Saved to permanent app storage (survives picker cache cleanup)
  ///   2. EXIF is parsed from those same raw bytes
  ///
  /// This avoids Android content-URI permission expiry and image_picker
  /// cache issues that can strip EXIF data on repeated picks.
  Future<ImportedPhoto?> pickFromGallery() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return null;

    // Capture the raw bytes immediately — this is our one reliable read.
    final bytes = await xFile.readAsBytes();

    // Save to our own permanent file so we're independent of the picker.
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/imported_photos');
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = xFile.name.contains('.') ? xFile.name.split('.').last : 'jpg';
    final permanentPath = '${photosDir.path}/photo_$timestamp.$ext';
    await File(permanentPath).writeAsBytes(bytes);

    // Parse EXIF from the raw bytes we just captured.
    final metadata = await extractMetadataFromBytes(bytes);
    debugPrint('PhotoRepository: imported to $permanentPath — $metadata');

    return ImportedPhoto(
      filePath: permanentPath,
      metadata: metadata,
    );
  }

  /// Extract EXIF metadata from a photo file on disk.
  ///
  /// Prefer passing bytes directly via [extractMetadataFromBytes] when
  /// you already have them (e.g. from XFile.readAsBytes()), since that
  /// avoids issues with Android content URI permissions expiring.
  Future<PhotoMetadata> extractMetadata(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      return extractMetadataFromBytes(bytes);
    } catch (e) {
      debugPrint('PhotoRepository: failed to read file $filePath: $e');
      return const PhotoMetadata();
    }
  }

  /// Extract EXIF metadata from raw image bytes.
  ///
  /// This is separated from [extractMetadata] for testability —
  /// tests can pass in-memory bytes without needing a real file.
  Future<PhotoMetadata> extractMetadataFromBytes(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return const PhotoMetadata();

      return PhotoMetadata(
        latitudeDeg: _parseGpsLatitude(tags),
        longitudeDeg: _parseGpsLongitude(tags),
        altitudeM: _parseGpsAltitude(tags),
        headingDeg: _parseGpsHeading(tags),
        focalLengthMm: _parseFocalLength(tags),
        dateTime: _parseDateTime(tags),
        cameraMake: _parseString(tags, 'Image Make'),
        cameraModel: _parseString(tags, 'Image Model'),
      );
    } catch (_) {
      return const PhotoMetadata();
    }
  }

  // -----------------------------------------------------------------------
  //  EXIF parsing helpers
  // -----------------------------------------------------------------------

  double? _parseGpsLatitude(Map<String, IfdTag> tags) {
    final lat = _parseGpsCoordinate(tags, 'GPS GPSLatitude');
    if (lat == null) return null;
    final ref = _parseString(tags, 'GPS GPSLatitudeRef');
    return (ref == 'S') ? -lat : lat;
  }

  double? _parseGpsLongitude(Map<String, IfdTag> tags) {
    final lon = _parseGpsCoordinate(tags, 'GPS GPSLongitude');
    if (lon == null) return null;
    final ref = _parseString(tags, 'GPS GPSLongitudeRef');
    return (ref == 'W') ? -lon : lon;
  }

  double? _parseGpsCoordinate(Map<String, IfdTag> tags, String key) {
    final tag = tags[key];
    if (tag == null) return null;

    // Try structured IfdRatios first (degrees, minutes, seconds)
    final values = tag.values;
    if (values is IfdRatios && values.ratios.length >= 3) {
      final ratios = values.ratios;
      // Guard against zero denominators (produces NaN)
      if (ratios[0].denominator == 0) return null;
      final degrees = ratios[0].numerator / ratios[0].denominator;
      final minutes = ratios[1].denominator != 0
          ? ratios[1].numerator / ratios[1].denominator
          : 0.0;
      final seconds = ratios[2].denominator != 0
          ? ratios[2].numerator / ratios[2].denominator
          : 0.0;
      final result = degrees + minutes / 60.0 + seconds / 3600.0;
      if (result.isNaN || result.isInfinite) return null;
      return result;
    }

    // Fallback: parse from the printable representation
    // Some devices/formats produce strings like "[47, 15, 23.456]"
    // or "47/1, 15/1, 2345/100"
    return _parseCoordinateFromPrintable(tag.printable);
  }

  double? _parseCoordinateFromPrintable(String printable) {
    try {
      // Strip brackets
      var s = printable.trim();
      if (s.startsWith('[')) s = s.substring(1);
      if (s.endsWith(']')) s = s.substring(0, s.length - 1);

      final parts = s.split(',').map((p) => p.trim()).toList();
      if (parts.length < 3) return null;

      double parseComponent(String c) {
        if (c.contains('/')) {
          final frac = c.split('/');
          final num = double.parse(frac[0].trim());
          final den = double.parse(frac[1].trim());
          return den != 0 ? num / den : 0.0;
        }
        return double.parse(c);
      }

      final degrees = parseComponent(parts[0]);
      final minutes = parseComponent(parts[1]);
      final seconds = parseComponent(parts[2]);
      final result = degrees + minutes / 60.0 + seconds / 3600.0;
      if (result.isNaN || result.isInfinite) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  double? _parseGpsAltitude(Map<String, IfdTag> tags) {
    final tag = tags['GPS GPSAltitude'];
    if (tag == null) return null;

    double? alt = _parseRatio(tag);
    if (alt == null) return null;

    // Check altitude ref: 0 = above sea level, 1 = below
    final ref = tags['GPS GPSAltitudeRef'];
    if (ref != null && ref.printable.trim() == '1') {
      alt = -alt;
    }
    return alt;
  }

  double? _parseGpsHeading(Map<String, IfdTag> tags) {
    // GPS ImgDirection is the compass heading the camera faced
    final tag = tags['GPS GPSImgDirection'];
    if (tag == null) return null;
    return _parseRatio(tag);
  }

  double? _parseFocalLength(Map<String, IfdTag> tags) {
    final tag = tags['EXIF FocalLength'];
    if (tag == null) return null;
    return _parseRatio(tag);
  }

  /// Parse a single rational EXIF value (altitude, heading, focal length).
  double? _parseRatio(IfdTag tag) {
    final values = tag.values;
    if (values is IfdRatios && values.ratios.isNotEmpty) {
      final ratio = values.ratios.first;
      if (ratio.denominator == 0) return null;
      final result = ratio.numerator / ratio.denominator;
      if (result.isNaN || result.isInfinite) return null;
      return result.toDouble();
    }

    // Fallback: parse from printable (e.g., "1234/100" or "12.34")
    return _parseRatioFromPrintable(tag.printable);
  }

  double? _parseRatioFromPrintable(String printable) {
    try {
      var s = printable.trim();
      if (s.isEmpty) return null;

      // Handle "numerator/denominator" format
      if (s.contains('/')) {
        final parts = s.split('/');
        final num = double.parse(parts[0].trim());
        final den = double.parse(parts[1].trim());
        if (den == 0) return null;
        final result = num / den;
        return (result.isNaN || result.isInfinite) ? null : result;
      }

      // Plain number
      final result = double.parse(s);
      return (result.isNaN || result.isInfinite) ? null : result;
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDateTime(Map<String, IfdTag> tags) {
    final str = _parseString(tags, 'EXIF DateTimeOriginal') ??
        _parseString(tags, 'Image DateTime');
    if (str == null) return null;

    // Format: "2024:03:15 14:30:00"
    try {
      final parts = str.split(' ');
      if (parts.length != 2) return null;
      final dateParts = parts[0].split(':');
      final timeParts = parts[1].split(':');
      if (dateParts.length != 3 || timeParts.length != 3) return null;

      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  String? _parseString(Map<String, IfdTag> tags, String key) {
    final tag = tags[key];
    if (tag == null) return null;
    final str = tag.printable.trim();
    return str.isEmpty ? null : str;
  }
}

// -----------------------------------------------------------------------
//  Riverpod provider
// -----------------------------------------------------------------------

final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  return PhotoRepository();
});
