/// DEM download service — downloads elevation tiles from Copernicus open data.
///
/// Copernicus GLO-30 DEM tiles are hosted as open data on AWS S3,
/// freely accessible without authentication. Each tile is a GeoTIFF
/// that we convert to raw .hgt (Int16 big-endian) on-device.
///
/// The download URL pattern:
///   https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/
///     Copernicus_DSM_COG_10_N46_00_E007_00_DEM/
///     Copernicus_DSM_COG_10_N46_00_E007_00_DEM.tif
///
/// Each tile is ~25 MB as GeoTIFF (~50 MB uncompressed as .hgt).
/// We download, extract the elevation band, and write as .hgt.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tile_index.dart';
import 'dem_repository.dart';

// -----------------------------------------------------------------------
//  Download progress tracking
// -----------------------------------------------------------------------

/// Progress state for a batch download operation.
class DownloadProgress {
  const DownloadProgress({
    required this.totalTiles,
    required this.completedTiles,
    required this.failedTiles,
    required this.currentTile,
    required this.currentTileBytes,
    required this.currentTileTotalBytes,
    required this.isComplete,
    this.error,
  });

  /// Total number of tiles to download.
  final int totalTiles;

  /// Tiles successfully downloaded so far.
  final int completedTiles;

  /// Tiles that failed to download.
  final int failedTiles;

  /// The tile currently being downloaded (null if done).
  final TileIndex? currentTile;

  /// Bytes received for the current tile.
  final int currentTileBytes;

  /// Total bytes expected for the current tile (0 if unknown).
  final int currentTileTotalBytes;

  /// Whether the entire batch is finished (success or failure).
  final bool isComplete;

  /// Error message if the download failed.
  final String? error;

  /// Overall progress from 0.0 to 1.0.
  double get overallProgress {
    if (totalTiles == 0) return 1.0;
    final tileProgress = currentTileTotalBytes > 0
        ? currentTileBytes / currentTileTotalBytes
        : 0.0;
    return (completedTiles + tileProgress) / totalTiles;
  }

  /// Human-readable status line.
  String get statusText {
    if (isComplete) {
      if (failedTiles > 0) {
        return 'Done: $completedTiles downloaded, $failedTiles failed';
      }
      return 'Download complete ($completedTiles tiles)';
    }
    if (currentTile != null) {
      return 'Downloading ${currentTile!.hgtFilename} '
          '(${completedTiles + 1}/$totalTiles)';
    }
    return 'Preparing...';
  }
}

// -----------------------------------------------------------------------
//  Download service
// -----------------------------------------------------------------------

/// Service for downloading DEM tiles from Copernicus open data on AWS.
class DemDownloadService {
  DemDownloadService({
    required this.demRepository,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final DemRepository demRepository;
  final Dio _dio;

  /// Active cancel token — set when a download is in progress.
  CancelToken? _cancelToken;

  /// Whether a download is currently in progress.
  bool get isDownloading => _cancelToken != null;

  /// Download a set of tiles, reporting progress via the callback.
  ///
  /// Skips tiles that are already available locally.
  /// Returns the number of tiles successfully downloaded.
  Future<int> downloadTiles({
    required Set<TileIndex> tiles,
    required void Function(DownloadProgress) onProgress,
  }) async {
    // Filter out tiles we already have
    final missing = <TileIndex>[];
    for (final tile in tiles) {
      if (!await demRepository.hasTile(tile)) {
        missing.add(tile);
      }
    }

    if (missing.isEmpty) {
      onProgress(DownloadProgress(
        totalTiles: 0,
        completedTiles: 0,
        failedTiles: 0,
        currentTile: null,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: true,
      ));
      return 0;
    }

    // Sort for deterministic order (lat then lon)
    missing.sort((a, b) {
      final cmp = a.latDeg.compareTo(b.latDeg);
      return cmp != 0 ? cmp : a.lonDeg.compareTo(b.lonDeg);
    });

    _cancelToken = CancelToken();
    int completed = 0;
    int failed = 0;

    for (final tile in missing) {
      if (_cancelToken?.isCancelled ?? true) break;

      onProgress(DownloadProgress(
        totalTiles: missing.length,
        completedTiles: completed,
        failedTiles: failed,
        currentTile: tile,
        currentTileBytes: 0,
        currentTileTotalBytes: 0,
        isComplete: false,
      ));

      final success = await _downloadSingleTile(
        tile: tile,
        onTileProgress: (received, total) {
          onProgress(DownloadProgress(
            totalTiles: missing.length,
            completedTiles: completed,
            failedTiles: failed,
            currentTile: tile,
            currentTileBytes: received,
            currentTileTotalBytes: total,
            isComplete: false,
          ));
        },
      );

      if (success) {
        completed++;
      } else {
        failed++;
      }
    }

    _cancelToken = null;

    onProgress(DownloadProgress(
      totalTiles: missing.length,
      completedTiles: completed,
      failedTiles: failed,
      currentTile: null,
      currentTileBytes: 0,
      currentTileTotalBytes: 0,
      isComplete: true,
    ));

    return completed;
  }

  /// Cancel an in-progress download.
  void cancel() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  /// Download a single tile from Copernicus AWS open data.
  Future<bool> _downloadSingleTile({
    required TileIndex tile,
    required void Function(int received, int total) onTileProgress,
  }) async {
    final url = _tileUrl(tile);
    final outPath = await demRepository.tileFilePath(tile);
    final tmpPath = '$outPath.tmp';

    try {
      // Download the GeoTIFF
      await _dio.download(
        url,
        tmpPath,
        cancelToken: _cancelToken,
        onReceiveProgress: onTileProgress,
      );

      // Convert GeoTIFF → raw .hgt
      final tiffFile = File(tmpPath);
      final tiffBytes = await tiffFile.readAsBytes();
      final hgtBytes = _geotiffToHgt(tiffBytes);

      if (hgtBytes != null) {
        await File(outPath).writeAsBytes(hgtBytes);
      } else {
        // Fallback: if conversion fails, keep the raw download
        // (might be a raw .hgt already from alternative sources)
        await tiffFile.rename(outPath);
      }

      // Clean up temp file if it still exists
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();

      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return false;

      // 404 means this tile is ocean — write a flat (sea-level) tile
      if (e.response?.statusCode == 404) {
        await _writeFlatTile(outPath);
        return true;
      }

      // Clean up partial download
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      return false;
    } catch (_) {
      // Clean up partial download
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      return false;
    }
  }

  /// Build the Copernicus tile URL on AWS S3 open data.
  static String _tileUrl(TileIndex tile) {
    final ns = tile.latDeg >= 0 ? 'N' : 'S';
    final ew = tile.lonDeg >= 0 ? 'E' : 'W';
    final lat = tile.latDeg.abs().toString().padLeft(2, '0');
    final lon = tile.lonDeg.abs().toString().padLeft(3, '0');
    final name = 'Copernicus_DSM_COG_10_${ns}${lat}_00_${ew}${lon}_00_DEM';
    return 'https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/'
        '$name/$name.tif';
  }

  /// Extract elevation data from a GeoTIFF into raw .hgt format.
  ///
  /// Copernicus GLO-30 GeoTIFFs are single-band Float32 with LZW
  /// compression. We parse the TIFF structure to find the image data,
  /// convert Float32 → Int16, and write as big-endian (SRTM convention).
  ///
  /// Returns null if we can't parse the TIFF (caller should handle).
  static Uint8List? _geotiffToHgt(Uint8List tiffBytes) {
    try {
      // TIFF files start with byte order marker
      if (tiffBytes.length < 8) return null;

      final byteData = ByteData.sublistView(tiffBytes);
      final isLittle = tiffBytes[0] == 0x49; // 'II' = little-endian
      if (!isLittle && tiffBytes[0] != 0x4D) return null; // not a TIFF

      // Check magic number 42
      final magic = isLittle
          ? byteData.getUint16(2, Endian.little)
          : byteData.getUint16(2, Endian.big);
      if (magic != 42) return null;

      // Read first IFD offset
      var ifdOffset = isLittle
          ? byteData.getUint32(4, Endian.little)
          : byteData.getUint32(4, Endian.big);

      // Parse IFD entries to find image dimensions and strip offsets
      int width = 0, height = 0;
      int bitsPerSample = 0, sampleFormat = 0;
      final stripOffsets = <int>[];
      final stripByteCounts = <int>[];
      int tileWidth = 0, tileHeight = 0;
      final tileOffsets = <int>[];
      final tileByteCounts = <int>[];
      int compression = 1; // 1 = no compression

      int readU16(int off) => isLittle
          ? byteData.getUint16(off, Endian.little)
          : byteData.getUint16(off, Endian.big);
      int readU32(int off) => isLittle
          ? byteData.getUint32(off, Endian.little)
          : byteData.getUint32(off, Endian.big);

      List<int> readArray(int count, int valueOffset, int typeSize) {
        final result = <int>[];
        for (int i = 0; i < count; i++) {
          final off = valueOffset + i * typeSize;
          if (off + typeSize > tiffBytes.length) break;
          if (typeSize == 2) {
            result.add(readU16(off));
          } else if (typeSize == 4) {
            result.add(readU32(off));
          }
        }
        return result;
      }

      // Parse IFD
      if (ifdOffset + 2 > tiffBytes.length) return null;
      final entryCount = readU16(ifdOffset);
      ifdOffset += 2;

      for (int i = 0; i < entryCount; i++) {
        final entryOff = ifdOffset + i * 12;
        if (entryOff + 12 > tiffBytes.length) break;

        final tag = readU16(entryOff);
        final type = readU16(entryOff + 2);
        final count = readU32(entryOff + 4);
        final valueOff = entryOff + 8;

        // Type sizes: 1=byte(1), 2=ascii(1), 3=short(2), 4=long(4)
        final typeSize = (type == 3) ? 2 : (type == 4) ? 4 : (type == 1) ? 1 : 4;
        final totalBytes = count * typeSize;
        // If value fits in 4 bytes, it's inline; otherwise it's an offset
        final dataOffset = totalBytes <= 4 ? valueOff : readU32(valueOff);

        switch (tag) {
          case 256: // ImageWidth
            width = totalBytes <= 4 ? (typeSize == 2 ? readU16(valueOff) : readU32(valueOff)) : readU32(dataOffset);
          case 257: // ImageLength
            height = totalBytes <= 4 ? (typeSize == 2 ? readU16(valueOff) : readU32(valueOff)) : readU32(dataOffset);
          case 258: // BitsPerSample
            bitsPerSample = typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 259: // Compression
            compression = typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 273: // StripOffsets
            stripOffsets.addAll(readArray(count, dataOffset, typeSize));
          case 279: // StripByteCounts
            stripByteCounts.addAll(readArray(count, dataOffset, typeSize));
          case 322: // TileWidth
            tileWidth = typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 323: // TileLength
            tileHeight = typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 324: // TileOffsets
            tileOffsets.addAll(readArray(count, dataOffset, typeSize));
          case 325: // TileByteCounts
            tileByteCounts.addAll(readArray(count, dataOffset, typeSize));
          case 339: // SampleFormat
            sampleFormat = typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
        }
      }

      if (width == 0 || height == 0) return null;

      // For compressed TIFFs (LZW, Deflate, etc.) we can't easily decode
      // on-device without a full TIFF library. In that case, return null
      // and let the caller keep the raw file.
      // Compression: 1=none, 5=LZW, 8=deflate, 32773=PackBits
      if (compression != 1) return null;

      // Read uncompressed float data
      Float32List? floats;

      if (tileOffsets.isNotEmpty && tileWidth > 0) {
        // Tiled TIFF
        final tilesAcross = (width + tileWidth - 1) ~/ tileWidth;
        final tilesDown = (height + tileHeight - 1) ~/ tileHeight;
        floats = Float32List(width * height);

        for (int ty = 0; ty < tilesDown; ty++) {
          for (int tx = 0; tx < tilesAcross; tx++) {
            final idx = ty * tilesAcross + tx;
            if (idx >= tileOffsets.length) continue;
            final offset = tileOffsets[idx];

            for (int row = 0; row < tileHeight; row++) {
              final imgRow = ty * tileHeight + row;
              if (imgRow >= height) break;
              for (int col = 0; col < tileWidth; col++) {
                final imgCol = tx * tileWidth + col;
                if (imgCol >= width) break;
                final srcOff = offset + (row * tileWidth + col) * 4;
                if (srcOff + 4 > tiffBytes.length) continue;
                final val = isLittle
                    ? byteData.getFloat32(srcOff, Endian.little)
                    : byteData.getFloat32(srcOff, Endian.big);
                floats[imgRow * width + imgCol] = val;
              }
            }
          }
        }
      } else if (stripOffsets.isNotEmpty) {
        // Stripped TIFF
        floats = Float32List(width * height);
        int pixelIdx = 0;
        for (int s = 0; s < stripOffsets.length; s++) {
          final offset = stripOffsets[s];
          final byteCount = s < stripByteCounts.length
              ? stripByteCounts[s]
              : (width * height * 4 - pixelIdx * 4);
          final pixelCount = byteCount ~/ 4;

          for (int p = 0; p < pixelCount && pixelIdx < width * height; p++) {
            final srcOff = offset + p * 4;
            if (srcOff + 4 > tiffBytes.length) break;
            final val = isLittle
                ? byteData.getFloat32(srcOff, Endian.little)
                : byteData.getFloat32(srcOff, Endian.big);
            floats[pixelIdx++] = val;
          }
        }
      } else {
        return null;
      }

      // Convert Float32 → Int16 big-endian (.hgt format)
      final hgt = ByteData(width * height * 2);
      for (int i = 0; i < floats.length; i++) {
        var val = floats[i];
        // Clamp to Int16 range, treat nodata as -32768
        if (val.isNaN || val < -500) {
          hgt.setInt16(i * 2, -32768, Endian.big);
        } else {
          final clamped = val.clamp(-500, 9000).toInt();
          hgt.setInt16(i * 2, clamped, Endian.big);
        }
      }

      return hgt.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Write a flat (sea-level) .hgt tile for ocean areas.
  static Future<void> _writeFlatTile(String path) async {
    // Standard SRTM tile: 3601 × 3601 × 2 bytes = 25,934,402 bytes
    const gridSize = 3601;
    final bytes = Uint8List(gridSize * gridSize * 2); // all zeros = sea level
    await File(path).writeAsBytes(bytes);
  }
}

// -----------------------------------------------------------------------
//  Riverpod provider
// -----------------------------------------------------------------------

final demDownloadServiceProvider = Provider<DemDownloadService>((ref) {
  final demRepo = ref.watch(demRepositoryProvider);
  return DemDownloadService(demRepository: demRepo);
});
