import 'dart:io';

import 'package:exif/exif.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_metadata.dart';

class PhotoRepository {
  PhotoRepository._(this._imagePicker);

  factory PhotoRepository() => _instance;

  static final PhotoRepository _instance = PhotoRepository._(ImagePicker());

  final ImagePicker _imagePicker;
  final Map<String, PhotoMetadata> _metadataCache = <String, PhotoMetadata>{};

  Future<PhotoMetadata?> pickAndReadMetadata() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return null;
    }
    return readMetadataForPath(image.path);
  }

  Future<PhotoMetadata> readMetadataForPath(String imagePath) async {
    final PhotoMetadata? cached = _metadataCache[imagePath];
    if (cached != null) {
      return cached;
    }

    final List<int> imageBytes = await File(imagePath).readAsBytes();
    final Map<String, IfdTag> tags = await readExifFromBytes(imageBytes);

    final double? latitude = _parseCoordinate(
      rawCoordinate: tags['GPS GPSLatitude']?.printable,
      directionRef: tags['GPS GPSLatitudeRef']?.printable,
    );
    final double? longitude = _parseCoordinate(
      rawCoordinate: tags['GPS GPSLongitude']?.printable,
      directionRef: tags['GPS GPSLongitudeRef']?.printable,
    );

    final PhotoMetadata metadata = PhotoMetadata(
      path: imagePath,
      latitude: latitude,
      longitude: longitude,
    );
    _metadataCache[imagePath] = metadata;
    return metadata;
  }

  static double? parseCoordinateForTest({
    required String? rawCoordinate,
    required String? directionRef,
  }) =>
      _parseCoordinate(rawCoordinate: rawCoordinate, directionRef: directionRef);

  static double? _parseCoordinate({
    required String? rawCoordinate,
    required String? directionRef,
  }) {
    if (rawCoordinate == null || rawCoordinate.trim().isEmpty) {
      return null;
    }

    final List<String> parts =
        rawCoordinate.split(',').map((String value) => value.trim()).toList();
    if (parts.isEmpty) {
      return null;
    }

    final double? degrees = _parseCoordinatePart(parts[0]);
    if (degrees == null) {
      return null;
    }
    final double minutes = parts.length > 1 ? (_parseCoordinatePart(parts[1]) ?? 0) : 0;
    final double seconds = parts.length > 2 ? (_parseCoordinatePart(parts[2]) ?? 0) : 0;

    final double unsigned = degrees + (minutes / 60.0) + (seconds / 3600.0);
    final String normalizedRef = directionRef?.trim().toUpperCase() ?? '';
    if (normalizedRef == 'S' || normalizedRef == 'W') {
      return -unsigned.abs();
    }
    return unsigned;
  }

  static double? _parseCoordinatePart(String rawValue) {
    if (rawValue.isEmpty) {
      return null;
    }

    final List<String> fraction = rawValue.split('/');
    if (fraction.length == 2) {
      final double? numerator = double.tryParse(fraction[0].trim());
      final double? denominator = double.tryParse(fraction[1].trim());
      if (numerator != null && denominator != null && denominator != 0) {
        return numerator / denominator;
      }
    }

    final RegExpMatch? match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(rawValue);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(0)!);
  }
}

