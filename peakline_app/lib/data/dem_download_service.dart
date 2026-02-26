/// DEM download service — downloads elevation tiles from Copernicus open data.
///
/// Copernicus DEM tiles are hosted as open data on AWS S3, freely
/// accessible without authentication:
///
///   30m: copernicus-dem-30m.s3.eu-central-1.amazonaws.com  (~25 MB/tile)
///   90m: copernicus-dem-90m.s3.eu-central-1.amazonaws.com  (~2.8 MB/tile)
///
/// Users choose a download quality. For "low" (250m) we download the
/// 90m source and downsample on-device — this gives the fastest
/// downloads (~2.8 MB) with the smallest on-disk footprint (~314 KB).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tile_index.dart';
import 'dem_repository.dart';

// -----------------------------------------------------------------------
//  Download quality
// -----------------------------------------------------------------------

/// Resolution quality the user can choose for downloads.
enum DownloadQuality {
  /// ~250m resolution (9 arc-seconds). Download ~2.8 MB, store ~314 KB.
  /// Fastest downloads, smallest storage. Good enough for most use cases.
  low(
    label: '250m (fast)',
    description: '~314 KB/tile \u00B7 fastest download',
    gridSize: 401,
    approxDownloadMB: 2.8,
    approxStorageMB: 0.3,
  ),

  /// ~90m resolution (3 arc-seconds). Download & store ~2.8 MB/tile.
  /// Good balance of quality and size.
  medium(
    label: '90m',
    description: '~2.8 MB/tile \u00B7 good detail',
    gridSize: 1201,
    approxDownloadMB: 2.8,
    approxStorageMB: 2.8,
  ),

  /// ~30m resolution (1 arc-second). Download & store ~25 MB/tile.
  /// Highest detail, largest files.
  high(
    label: '30m (best)',
    description: '~25 MB/tile \u00B7 highest detail',
    gridSize: 3601,
    approxDownloadMB: 25.0,
    approxStorageMB: 25.0,
  );

  const DownloadQuality({
    required this.label,
    required this.description,
    required this.gridSize,
    required this.approxDownloadMB,
    required this.approxStorageMB,
  });

  final String label;
  final String description;
  final int gridSize;

  /// Approximate download size per tile in MB (GeoTIFF from server).
  final double approxDownloadMB;

  /// Approximate on-disk storage per tile in MB (.hgt file).
  final double approxStorageMB;
}

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

  final int totalTiles;
  final int completedTiles;
  final int failedTiles;
  final TileIndex? currentTile;
  final int currentTileBytes;
  final int currentTileTotalBytes;
  final bool isComplete;
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

  CancelToken? _cancelToken;

  bool get isDownloading => _cancelToken != null;

  /// Download a set of tiles at the specified quality.
  ///
  /// Skips tiles that are already available locally.
  /// Returns the number of tiles successfully downloaded.
  Future<int> downloadTiles({
    required Set<TileIndex> tiles,
    required void Function(DownloadProgress) onProgress,
    DownloadQuality quality = DownloadQuality.low,
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

    // Sort for deterministic order
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
        quality: quality,
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

  void cancel() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  /// Download a single tile at the given quality.
  Future<bool> _downloadSingleTile({
    required TileIndex tile,
    required DownloadQuality quality,
    required void Function(int received, int total) onTileProgress,
  }) async {
    // Low and medium both download from the 90m source (much smaller).
    // High downloads from the 30m source.
    final url = quality == DownloadQuality.high
        ? _tileUrl30m(tile)
        : _tileUrl90m(tile);

    final outPath = await demRepository.tileFilePath(tile);
    final tmpPath = '$outPath.tmp';

    try {
      await _dio.download(
        url,
        tmpPath,
        cancelToken: _cancelToken,
        onReceiveProgress: onTileProgress,
      );

      // Convert GeoTIFF → raw .hgt
      final tiffFile = File(tmpPath);
      final tiffBytes = await tiffFile.readAsBytes();

      // Source grid: 1201 for 90m downloads, 3601 for 30m
      final sourceGrid = quality == DownloadQuality.high ? 3601 : 1201;
      final hgtBytes = _geotiffToHgt(tiffBytes, sourceGrid);

      if (hgtBytes != null) {
        // If low quality, downsample from 1201 → 401
        if (quality == DownloadQuality.low) {
          final downsampled = _downsampleHgt(hgtBytes, 1201, 401);
          await File(outPath).writeAsBytes(downsampled);
        } else {
          await File(outPath).writeAsBytes(hgtBytes);
        }
      } else {
        // Fallback: keep the raw download
        await tiffFile.rename(outPath);
      }

      // Clean up temp file
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();

      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return false;

      if (e.response?.statusCode == 404) {
        await _writeFlatTile(outPath, quality.gridSize);
        return true;
      }

      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      return false;
    } catch (_) {
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      return false;
    }
  }

  // -----------------------------------------------------------------------
  //  URL builders
  // -----------------------------------------------------------------------

  static String _tileUrl30m(TileIndex tile) {
    final ns = tile.latDeg >= 0 ? 'N' : 'S';
    final ew = tile.lonDeg >= 0 ? 'E' : 'W';
    final lat = tile.latDeg.abs().toString().padLeft(2, '0');
    final lon = tile.lonDeg.abs().toString().padLeft(3, '0');
    final name = 'Copernicus_DSM_COG_10_${ns}${lat}_00_${ew}${lon}_00_DEM';
    return 'https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/'
        '$name/$name.tif';
  }

  static String _tileUrl90m(TileIndex tile) {
    final ns = tile.latDeg >= 0 ? 'N' : 'S';
    final ew = tile.lonDeg >= 0 ? 'E' : 'W';
    final lat = tile.latDeg.abs().toString().padLeft(2, '0');
    final lon = tile.lonDeg.abs().toString().padLeft(3, '0');
    final name = 'Copernicus_DSM_COG_30_${ns}${lat}_00_${ew}${lon}_00_DEM';
    return 'https://copernicus-dem-90m.s3.eu-central-1.amazonaws.com/'
        '$name/$name.tif';
  }

  // -----------------------------------------------------------------------
  //  Downsampling
  // -----------------------------------------------------------------------

  /// Downsample an .hgt byte buffer from one grid size to another.
  ///
  /// Both are big-endian Int16. Uses nearest-neighbor sampling.
  static Uint8List _downsampleHgt(
      Uint8List source, int sourceSize, int targetSize) {
    final srcData = ByteData.sublistView(source);
    final dst = ByteData(targetSize * targetSize * 2);

    for (int row = 0; row < targetSize; row++) {
      // Map target row to source row
      final srcRow =
          ((row * (sourceSize - 1)) / (targetSize - 1)).round();
      for (int col = 0; col < targetSize; col++) {
        final srcCol =
            ((col * (sourceSize - 1)) / (targetSize - 1)).round();
        final srcIdx = (srcRow * sourceSize + srcCol) * 2;
        final dstIdx = (row * targetSize + col) * 2;

        if (srcIdx + 1 < source.length) {
          dst.setInt16(dstIdx, srcData.getInt16(srcIdx, Endian.big), Endian.big);
        }
      }
    }

    return dst.buffer.asUint8List();
  }

  // -----------------------------------------------------------------------
  //  GeoTIFF → .hgt conversion
  // -----------------------------------------------------------------------

  /// Extract elevation data from a GeoTIFF into raw .hgt format.
  ///
  /// [expectedGrid] is the expected dimension (1201 for 90m, 3601 for 30m).
  /// Returns null if we can't parse the TIFF.
  static Uint8List? _geotiffToHgt(Uint8List tiffBytes, int expectedGrid) {
    try {
      if (tiffBytes.length < 8) return null;

      final byteData = ByteData.sublistView(tiffBytes);
      final isLittle = tiffBytes[0] == 0x49; // 'II' = little-endian
      if (!isLittle && tiffBytes[0] != 0x4D) return null;

      final magic = isLittle
          ? byteData.getUint16(2, Endian.little)
          : byteData.getUint16(2, Endian.big);
      if (magic != 42) return null;

      var ifdOffset = isLittle
          ? byteData.getUint32(4, Endian.little)
          : byteData.getUint32(4, Endian.big);

      int width = 0, height = 0;
      final stripOffsets = <int>[];
      final stripByteCounts = <int>[];
      int tileWidth = 0, tileHeight = 0;
      final tileOffsets = <int>[];
      final tileByteCounts = <int>[];
      int compression = 1;

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

        final typeSize =
            (type == 3) ? 2 : (type == 4) ? 4 : (type == 1) ? 1 : 4;
        final totalBytes = count * typeSize;
        final dataOffset =
            totalBytes <= 4 ? valueOff : readU32(valueOff);

        switch (tag) {
          case 256:
            width = totalBytes <= 4
                ? (typeSize == 2 ? readU16(valueOff) : readU32(valueOff))
                : readU32(dataOffset);
          case 257:
            height = totalBytes <= 4
                ? (typeSize == 2 ? readU16(valueOff) : readU32(valueOff))
                : readU32(dataOffset);
          case 259:
            compression =
                typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 273:
            stripOffsets.addAll(readArray(count, dataOffset, typeSize));
          case 279:
            stripByteCounts.addAll(readArray(count, dataOffset, typeSize));
          case 322:
            tileWidth =
                typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 323:
            tileHeight =
                typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
          case 324:
            tileOffsets.addAll(readArray(count, dataOffset, typeSize));
          case 325:
            tileByteCounts.addAll(readArray(count, dataOffset, typeSize));
        }
      }

      if (width == 0 || height == 0) return null;
      if (compression != 1) return null; // Can't decode compressed TIFFs

      // Read float data
      Float32List? floats;

      if (tileOffsets.isNotEmpty && tileWidth > 0) {
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
        floats = Float32List(width * height);
        int pixelIdx = 0;
        for (int s = 0; s < stripOffsets.length; s++) {
          final offset = stripOffsets[s];
          final byteCount = s < stripByteCounts.length
              ? stripByteCounts[s]
              : (width * height * 4 - pixelIdx * 4);
          final pixelCount = byteCount ~/ 4;

          for (int p = 0;
              p < pixelCount && pixelIdx < width * height;
              p++) {
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

      // Convert Float32 → Int16 big-endian
      final hgt = ByteData(width * height * 2);
      for (int i = 0; i < floats.length; i++) {
        var val = floats[i];
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
  static Future<void> _writeFlatTile(String path, int gridSize) async {
    final bytes = Uint8List(gridSize * gridSize * 2);
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
