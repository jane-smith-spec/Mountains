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
import 'package:flutter/foundation.dart';
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

  /// Ensure the DEM tile for a GPS coordinate is available locally.
  ///
  /// If the tile already exists, returns its path immediately.
  /// If not, downloads it at the given [quality] (default medium/90m)
  /// and returns the path on success, or null on failure.
  ///
  /// This is the on-demand auto-download used by the photo analyzer
  /// and live camera view — one tile at a time, kept permanently.
  Future<String?> ensureTileForCoordinate(
    double latDeg,
    double lonDeg, {
    DownloadQuality quality = DownloadQuality.medium,
    void Function(int received, int total)? onProgress,
  }) async {
    final tile = TileIndex.fromCoordinate(latDeg, lonDeg);

    // Already have it? Validate the file size is correct.
    if (await demRepository.hasTile(tile)) {
      final path = await demRepository.tileFilePath(tile);
      final fileSize = await File(path).length();
      // Valid .hgt sizes: 3601², 1201², or 401² × 2 bytes
      const validSizes = {
        3601 * 3601 * 2, // 30m
        1201 * 1201 * 2, // 90m
        401 * 401 * 2, // 250m
      };
      if (validSizes.contains(fileSize)) {
        return path;
      }
      // Bad file (e.g. raw GeoTIFF from old fallback) — delete and re-download
      debugPrint('DemDownloadService: ${tile.hgtFilename} has bad size '
          '($fileSize bytes) — deleting and re-downloading');
      await demRepository.deleteTile(tile);
    }

    debugPrint('DemDownloadService: auto-downloading ${tile.hgtFilename} '
        'at ${quality.label}');

    final success = await _downloadSingleTile(
      tile: tile,
      quality: quality,
      onTileProgress: onProgress ?? (_, __) {},
    );

    if (success) {
      return demRepository.tileFilePath(tile);
    }
    return null;
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
      debugPrint('DemDownload: fetching $url');
      await _dio.download(
        url,
        tmpPath,
        cancelToken: _cancelToken,
        onReceiveProgress: onTileProgress,
      );

      // Convert GeoTIFF → raw .hgt
      final tiffFile = File(tmpPath);
      final tiffBytes = await tiffFile.readAsBytes();
      debugPrint('DemDownload: downloaded ${tiffBytes.length} bytes');

      // Source grid: 1201 for 90m downloads, 3601 for 30m
      final sourceGrid = quality == DownloadQuality.high ? 3601 : 1201;
      final hgtBytes = _geotiffToHgt(tiffBytes, sourceGrid);

      if (hgtBytes != null) {
        debugPrint('DemDownload: converted to .hgt '
            '(${hgtBytes.length} bytes, expected ${sourceGrid * sourceGrid * 2})');

        // If low quality, downsample from 1201 → 401
        if (quality == DownloadQuality.low) {
          final downsampled = _downsampleHgt(hgtBytes, 1201, 401);
          await File(outPath).writeAsBytes(downsampled);
        } else {
          await File(outPath).writeAsBytes(hgtBytes);
        }
      } else {
        debugPrint('DemDownload: GeoTIFF conversion failed — '
            'tile will not be usable');
        // Don't fall back to renaming raw GeoTIFF as .hgt.
        // The C core would reject it due to wrong file size.
        final tmp = File(tmpPath);
        if (await tmp.exists()) await tmp.delete();
        return false;
      }

      // Clean up temp file
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();

      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return false;

      if (e.response?.statusCode == 404) {
        debugPrint('DemDownload: 404 for ${tile.hgtFilename} — '
            'writing flat (ocean) tile');
        await _writeFlatTile(outPath, quality.gridSize);
        return true;
      }

      debugPrint('DemDownload: network error for ${tile.hgtFilename}: $e');
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      return false;
    } catch (e) {
      debugPrint('DemDownload: unexpected error for ${tile.hgtFilename}: $e');
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
  /// Handles both uncompressed and DEFLATE-compressed GeoTIFFs
  /// (Copernicus COG tiles use DEFLATE compression).
  ///
  /// [expectedGrid] is the expected dimension (1201 for 90m, 3601 for 30m).
  /// Returns null if we can't parse the TIFF.
  static Uint8List? _geotiffToHgt(Uint8List tiffBytes, int expectedGrid) {
    try {
      if (tiffBytes.length < 8) {
        debugPrint('GeoTIFF: file too small (${tiffBytes.length} bytes)');
        return null;
      }

      final byteData = ByteData.sublistView(tiffBytes);
      final isLittle = tiffBytes[0] == 0x49; // 'II' = little-endian
      if (!isLittle && tiffBytes[0] != 0x4D) {
        debugPrint('GeoTIFF: not a TIFF (bad magic bytes)');
        return null;
      }

      final magic = isLittle
          ? byteData.getUint16(2, Endian.little)
          : byteData.getUint16(2, Endian.big);
      if (magic != 42) {
        debugPrint('GeoTIFF: not a TIFF (magic=$magic, expected 42)');
        return null;
      }

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
      int sampleFormat = 3; // default Float
      int bitsPerSample = 32;

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
          case 258: // BitsPerSample
            bitsPerSample =
                typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
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
          case 339: // SampleFormat (1=uint, 2=int, 3=float)
            sampleFormat =
                typeSize == 2 ? readU16(valueOff) : readU32(valueOff);
        }
      }

      debugPrint('GeoTIFF: ${width}x$height, compression=$compression, '
          'bps=$bitsPerSample, sampleFormat=$sampleFormat, '
          'tiles=${tileOffsets.length} (${tileWidth}x$tileHeight), '
          'strips=${stripOffsets.length}');

      if (width == 0 || height == 0) {
        debugPrint('GeoTIFF: invalid dimensions');
        return null;
      }

      // Supported compressions: 1=none, 8=DEFLATE, 32946=DEFLATE (alt)
      final isDeflate = compression == 8 || compression == 32946;
      if (compression != 1 && !isDeflate) {
        debugPrint('GeoTIFF: unsupported compression=$compression '
            '(only none/DEFLATE supported)');
        return null;
      }

      final bytesPerSample = bitsPerSample ~/ 8;
      final isFloat = sampleFormat == 3 && bitsPerSample == 32;
      final isInt16 = sampleFormat == 2 && bitsPerSample == 16;

      if (!isFloat && !isInt16) {
        debugPrint('GeoTIFF: unsupported format '
            '(sampleFormat=$sampleFormat, bps=$bitsPerSample)');
        return null;
      }

      /// Decompress a chunk of bytes if DEFLATE, otherwise return as-is.
      Uint8List decompressChunk(int offset, int compressedLen) {
        if (!isDeflate) {
          return Uint8List.sublistView(
              tiffBytes, offset, offset + compressedLen);
        }
        final compressed =
            tiffBytes.sublist(offset, offset + compressedLen);
        try {
          return Uint8List.fromList(zlib.decode(compressed));
        } catch (_) {
          // Some DEFLATE streams are raw (no zlib header) — try raw inflate
          try {
            final inflater = RawZLibFilter.inflate(raw: true);
            inflater.process(compressed, 0, compressed.length);
            final out = <int>[];
            for (;;) {
              final chunk = inflater.processed();
              if (chunk == null) break;
              out.addAll(chunk);
            }
            return Uint8List.fromList(out);
          } catch (_) {
            return Uint8List(0);
          }
        }
      }

      /// Read a Float32 from decompressed bytes.
      double readFloat(Uint8List data, int off) {
        if (off + 4 > data.length) return 0;
        final bd = ByteData.sublistView(data);
        return isLittle
            ? bd.getFloat32(off, Endian.little)
            : bd.getFloat32(off, Endian.big);
      }

      /// Read an Int16 from decompressed bytes.
      int readI16(Uint8List data, int off) {
        if (off + 2 > data.length) return -32768;
        final bd = ByteData.sublistView(data);
        return isLittle
            ? bd.getInt16(off, Endian.little)
            : bd.getInt16(off, Endian.big);
      }

      // Read elevation data into a flat array
      final elevations = Float32List(width * height);

      if (tileOffsets.isNotEmpty && tileWidth > 0) {
        final tilesAcross = (width + tileWidth - 1) ~/ tileWidth;
        final tilesDown = (height + tileHeight - 1) ~/ tileHeight;

        for (int ty = 0; ty < tilesDown; ty++) {
          for (int tx = 0; tx < tilesAcross; tx++) {
            final idx = ty * tilesAcross + tx;
            if (idx >= tileOffsets.length) continue;
            final offset = tileOffsets[idx];
            final byteCount =
                idx < tileByteCounts.length ? tileByteCounts[idx] : 0;
            if (byteCount == 0 || offset + byteCount > tiffBytes.length) {
              continue;
            }

            final decompressed = decompressChunk(offset, byteCount);

            for (int row = 0; row < tileHeight; row++) {
              final imgRow = ty * tileHeight + row;
              if (imgRow >= height) break;
              for (int col = 0; col < tileWidth; col++) {
                final imgCol = tx * tileWidth + col;
                if (imgCol >= width) break;
                final srcOff = (row * tileWidth + col) * bytesPerSample;
                final val = isFloat
                    ? readFloat(decompressed, srcOff)
                    : readI16(decompressed, srcOff).toDouble();
                elevations[imgRow * width + imgCol] = val;
              }
            }
          }
        }
      } else if (stripOffsets.isNotEmpty) {
        int pixelIdx = 0;
        for (int s = 0; s < stripOffsets.length; s++) {
          final offset = stripOffsets[s];
          final byteCount = s < stripByteCounts.length
              ? stripByteCounts[s]
              : (width * height * bytesPerSample - pixelIdx * bytesPerSample);
          if (offset + byteCount > tiffBytes.length) break;

          final decompressed = decompressChunk(offset, byteCount);
          final pixelCount = decompressed.length ~/ bytesPerSample;

          for (int p = 0;
              p < pixelCount && pixelIdx < width * height;
              p++) {
            final srcOff = p * bytesPerSample;
            final val = isFloat
                ? readFloat(decompressed, srcOff)
                : readI16(decompressed, srcOff).toDouble();
            elevations[pixelIdx++] = val;
          }
        }
      } else {
        debugPrint('GeoTIFF: no tiles or strips found');
        return null;
      }

      debugPrint('GeoTIFF: read ${elevations.length} elevation values '
          '(range: ${_rangeStr(elevations)})');

      // Convert to Int16 big-endian .hgt format
      final hgt = ByteData(width * height * 2);
      for (int i = 0; i < elevations.length; i++) {
        final val = elevations[i];
        if (val.isNaN || val < -500) {
          hgt.setInt16(i * 2, -32768, Endian.big);
        } else {
          final clamped = val.clamp(-500, 9000).toInt();
          hgt.setInt16(i * 2, clamped, Endian.big);
        }
      }

      return hgt.buffer.asUint8List();
    } catch (e) {
      debugPrint('GeoTIFF: conversion error: $e');
      return null;
    }
  }

  /// Helper for debug logging: find min/max of elevation data.
  static String _rangeStr(Float32List data) {
    if (data.isEmpty) return 'empty';
    double min = double.infinity, max = double.negativeInfinity;
    for (final v in data) {
      if (v.isNaN) continue;
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return '${min.toStringAsFixed(0)}m .. ${max.toStringAsFixed(0)}m';
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
