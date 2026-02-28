/// Integration test for the DEM → horizon pipeline.
///
/// Tests the GeoTIFF conversion, .hgt file creation, and
/// the projection math. The C native core can only be tested
/// on a real device/emulator.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:peakline_app/core/projection.dart';
import 'package:peakline_app/core/constants.dart';
import 'package:peakline_app/data/dem_download_service.dart';

void main() {
  group('GeoTIFF → .hgt conversion', () {
    test('converts uncompressed Float32 strip TIFF', () {
      // Create a minimal valid uncompressed GeoTIFF in memory.
      // 4×4 grid, Float32, strip-based, little-endian.
      const width = 4;
      const height = 4;
      const numPixels = width * height;

      // Elevation data: simple ramp from 100m to 1600m
      final elevations = Float32List(numPixels);
      for (int i = 0; i < numPixels; i++) {
        elevations[i] = (i + 1) * 100.0;
      }
      final elevBytes = elevations.buffer.asUint8List();

      // Build TIFF structure
      final buf = BytesBuilder();

      // TIFF header (8 bytes)
      buf.add([0x49, 0x49]); // 'II' = little-endian
      buf.add(_u16LE(42)); // magic
      buf.add(_u32LE(8)); // IFD offset = right after header

      // IFD: 7 entries (2 + 7*12 + 4 = 90 bytes, at offset 8)
      buf.add(_u16LE(7)); // entry count

      // Tag 256: ImageWidth = 4 (SHORT)
      buf.add(_ifdEntry(256, 3, 1, width));
      // Tag 257: ImageLength = 4 (SHORT)
      buf.add(_ifdEntry(257, 3, 1, height));
      // Tag 258: BitsPerSample = 32 (SHORT)
      buf.add(_ifdEntry(258, 3, 1, 32));
      // Tag 259: Compression = 1 (none) (SHORT)
      buf.add(_ifdEntry(259, 3, 1, 1));
      // Tag 273: StripOffsets = offset to pixel data (LONG)
      // IFD ends at 8 + 2 + 7*12 + 4 = 98
      buf.add(_ifdEntry(273, 4, 1, 98));
      // Tag 279: StripByteCounts = numPixels * 4 (LONG)
      buf.add(_ifdEntry(279, 4, 1, numPixels * 4));
      // Tag 339: SampleFormat = 3 (Float) (SHORT)
      buf.add(_ifdEntry(339, 3, 1, 3));

      // Next IFD offset = 0 (no more IFDs)
      buf.add(_u32LE(0));

      // Pixel data starts at offset 98
      buf.add(elevBytes);

      final tiffBytes = Uint8List.fromList(buf.toBytes());
      expect(tiffBytes.length, 98 + numPixels * 4);

      // Convert
      final hgt = DemDownloadServiceTestHelper.geotiffToHgt(tiffBytes, width);

      expect(hgt, isNotNull);
      expect(hgt!.length, width * height * 2); // Int16 big-endian

      // Verify pixel values (should be Int16 big-endian)
      final bd = ByteData.sublistView(hgt);
      for (int i = 0; i < numPixels; i++) {
        final val = bd.getInt16(i * 2, Endian.big);
        expect(val, (i + 1) * 100,
            reason: 'pixel $i should be ${(i + 1) * 100}, got $val');
      }
    });

    test('converts DEFLATE compressed Float32 with Predictor=3', () {
      // Simulates the Copernicus COG format:
      // - Tiled GeoTIFF
      // - DEFLATE compression (type 8)
      // - Float predictor (Predictor=3, tag 317)
      // - Float32 samples
      //
      // We use a 4x4 grid stored as a single 4x4 tile.
      const width = 4;
      const height = 4;
      const tW = 4; // tile width = image width
      const tH = 4; // tile height = image height
      const numPixels = width * height;
      const bps = 4; // bytes per sample

      // Elevation data: known values
      final elevations = Float32List(numPixels);
      for (int i = 0; i < numPixels; i++) {
        elevations[i] = (i + 1) * 100.0;
      }
      final rawBytes = elevations.buffer.asUint8List();

      // Encode with float predictor (Predictor=3):
      // For each row: rearrange bytes into byte planes, then difference.
      final encoded = Uint8List(numPixels * bps);
      for (int row = 0; row < height; row++) {
        final rowStart = row * tW * bps;

        // Step 1: Rearrange into byte planes
        final rearranged = Uint8List(tW * bps);
        for (int sample = 0; sample < tW; sample++) {
          for (int b = 0; b < bps; b++) {
            rearranged[b * tW + sample] =
                rawBytes[rowStart + sample * bps + b];
          }
        }

        // Step 2: Apply horizontal byte differencing
        final diffed = Uint8List(tW * bps);
        diffed[0] = rearranged[0];
        for (int i = 1; i < tW * bps; i++) {
          diffed[i] = (rearranged[i] - rearranged[i - 1]) & 0xFF;
        }

        encoded.setRange(rowStart, rowStart + tW * bps, diffed);
      }

      // DEFLATE compress the encoded data
      final compressed = Uint8List.fromList(zlib.encode(encoded));

      // Build TIFF with tile structure
      final buf = BytesBuilder();

      // TIFF header (8 bytes)
      buf.add([0x49, 0x49]); // little-endian
      buf.add(_u16LE(42));
      buf.add(_u32LE(8)); // IFD at offset 8

      // IFD: 10 entries
      // IFD size: 2 + 10*12 + 4 = 126, ends at offset 8+126 = 134
      buf.add(_u16LE(10));

      buf.add(_ifdEntry(256, 3, 1, width)); // ImageWidth
      buf.add(_ifdEntry(257, 3, 1, height)); // ImageLength
      buf.add(_ifdEntry(258, 3, 1, 32)); // BitsPerSample
      buf.add(_ifdEntry(259, 3, 1, 8)); // Compression = DEFLATE
      buf.add(_ifdEntry(317, 3, 1, 3)); // Predictor = float
      buf.add(_ifdEntry(322, 3, 1, tW)); // TileWidth
      buf.add(_ifdEntry(323, 3, 1, tH)); // TileLength
      buf.add(_ifdEntry(324, 4, 1, 134)); // TileOffsets → offset 134
      buf.add(_ifdEntry(325, 4, 1, compressed.length)); // TileByteCounts
      buf.add(_ifdEntry(339, 3, 1, 3)); // SampleFormat = Float

      buf.add(_u32LE(0)); // next IFD = 0

      // Tile data at offset 134
      buf.add(compressed);

      final tiffBytes = Uint8List.fromList(buf.toBytes());

      // Convert
      final hgt = DemDownloadServiceTestHelper.geotiffToHgt(tiffBytes, width);

      expect(hgt, isNotNull,
          reason: 'geotiffToHgt should handle DEFLATE+Predictor=3');
      expect(hgt!.length, width * height * 2);

      // Verify pixel values
      final bd = ByteData.sublistView(hgt);
      for (int i = 0; i < numPixels; i++) {
        final val = bd.getInt16(i * 2, Endian.big);
        expect(val, (i + 1) * 100,
            reason: 'pixel $i should be ${(i + 1) * 100}, got $val '
                '(DEFLATE+Predictor=3 decoding may be wrong)');
      }
    });

    test('resamples GeoTIFF when dimensions differ from expectedGrid', () {
      // Create a 6×6 uncompressed GeoTIFF but request a 4×4 output.
      const srcWidth = 6;
      const srcHeight = 6;
      const targetGrid = 4;
      const numSrcPixels = srcWidth * srcHeight;

      // All elevations = 500.0
      final elevations = Float32List(numSrcPixels);
      for (int i = 0; i < numSrcPixels; i++) {
        elevations[i] = 500.0;
      }
      final elevBytes = elevations.buffer.asUint8List();

      final buf = BytesBuilder();
      buf.add([0x49, 0x49]);
      buf.add(_u16LE(42));
      buf.add(_u32LE(8));

      buf.add(_u16LE(7));
      buf.add(_ifdEntry(256, 3, 1, srcWidth));
      buf.add(_ifdEntry(257, 3, 1, srcHeight));
      buf.add(_ifdEntry(258, 3, 1, 32));
      buf.add(_ifdEntry(259, 3, 1, 1));
      buf.add(_ifdEntry(273, 4, 1, 98));
      buf.add(_ifdEntry(279, 4, 1, numSrcPixels * 4));
      buf.add(_ifdEntry(339, 3, 1, 3));
      buf.add(_u32LE(0));
      buf.add(elevBytes);

      final tiffBytes = Uint8List.fromList(buf.toBytes());

      // Request targetGrid=4, source is 6x6 → should resample
      final hgt =
          DemDownloadServiceTestHelper.geotiffToHgt(tiffBytes, targetGrid);

      expect(hgt, isNotNull);
      expect(hgt!.length, targetGrid * targetGrid * 2,
          reason: 'Output should be resampled to ${targetGrid}x$targetGrid');

      // All values should be 500 (uniform input → uniform output)
      final bd = ByteData.sublistView(hgt);
      for (int i = 0; i < targetGrid * targetGrid; i++) {
        final val = bd.getInt16(i * 2, Endian.big);
        expect(val, 500, reason: 'pixel $i should be 500 after resampling');
      }
    });

    test('rejects non-TIFF data', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final result =
          DemDownloadServiceTestHelper.geotiffToHgt(garbage, 1201);
      expect(result, isNull);
    });

    test('rejects too-small data', () {
      final tiny = Uint8List.fromList([0x49, 0x49, 42, 0]);
      final result =
          DemDownloadServiceTestHelper.geotiffToHgt(tiny, 1201);
      expect(result, isNull);
    });
  });

  group('Downsampling', () {
    test('downsample preserves corner values', () {
      // Create a 5x5 .hgt grid with known corners
      const srcSize = 5;
      const dstSize = 3;
      final src = ByteData(srcSize * srcSize * 2);

      // Set corners to known values
      src.setInt16(0, 1000, Endian.big); // top-left
      src.setInt16((srcSize - 1) * 2, 2000, Endian.big); // top-right
      src.setInt16(((srcSize - 1) * srcSize) * 2, 3000,
          Endian.big); // bottom-left
      src.setInt16(((srcSize * srcSize) - 1) * 2, 4000,
          Endian.big); // bottom-right

      final result = DemDownloadServiceTestHelper.downsampleHgt(
        src.buffer.asUint8List(),
        srcSize,
        dstSize,
      );

      expect(result.length, dstSize * dstSize * 2);

      final bd = ByteData.sublistView(result);
      expect(bd.getInt16(0, Endian.big), 1000,
          reason: 'top-left corner should be preserved');
      expect(bd.getInt16((dstSize - 1) * 2, Endian.big), 2000,
          reason: 'top-right corner should be preserved');
      expect(bd.getInt16(((dstSize - 1) * dstSize) * 2, Endian.big), 3000,
          reason: 'bottom-left corner should be preserved');
      expect(bd.getInt16(((dstSize * dstSize) - 1) * 2, Endian.big), 4000,
          reason: 'bottom-right corner should be preserved');
    });
  });

  group('Projection math', () {
    test('projects center point to screen center', () {
      final camera = CameraViewParams(
        headingDeg: 180.0,
        pitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 300,
        horizontalFovDeg: 60.0,
      );

      final pt = projectToScreen(
        azimuthDeg: 180.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(pt.x, closeTo(200, 1)); // center x
      expect(pt.y, closeTo(150, 1)); // center y
      expect(pt.isVisible, true);
    });

    test('projects point at FOV edge to screen edge', () {
      final camera = CameraViewParams(
        headingDeg: 180.0,
        pitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 300,
        horizontalFovDeg: 60.0,
      );

      // Point at +30° (half FOV) from heading → right edge
      final pt = projectToScreen(
        azimuthDeg: 210.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(pt.x, closeTo(400, 1)); // right edge
      expect(pt.isVisible, true);
    });

    test('marks out-of-FOV points as not visible', () {
      final camera = CameraViewParams(
        headingDeg: 180.0,
        pitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 300,
        horizontalFovDeg: 60.0,
      );

      // Point at 90° from heading → way off screen
      final pt = projectToScreen(
        azimuthDeg: 270.0,
        elevationAngleDeg: 0.0,
        camera: camera,
      );

      expect(pt.isVisible, false);
    });

    test('projects elevated point above center', () {
      final camera = CameraViewParams(
        headingDeg: 180.0,
        pitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 300,
        horizontalFovDeg: 60.0,
        verticalFovDeg: 35.6,
      );

      // Point at 5° elevation → above center
      final pt = projectToScreen(
        azimuthDeg: 180.0,
        elevationAngleDeg: 5.0,
        camera: camera,
      );

      expect(pt.x, closeTo(200, 1)); // still centered horizontally
      expect(pt.y, lessThan(150)); // above center
      expect(pt.isVisible, true);
    });

    test('projectHorizonProfile filters to FOV', () {
      final camera = CameraViewParams(
        headingDeg: 180.0,
        pitchDeg: 0.0,
        screenWidth: 400,
        screenHeight: 300,
        horizontalFovDeg: 60.0,
      );

      // Full 360° profile
      final points = <({double azimuthDeg, double elevationAngleDeg})>[];
      for (double az = 0; az < 360; az += 1.0) {
        points.add((azimuthDeg: az, elevationAngleDeg: 2.0));
      }

      final screen = projectHorizonProfile(
        points: points,
        camera: camera,
        marginDeg: 5.0,
      );

      // Only points within ~65° of heading 180 should survive
      // (60/2 + 5 margin = 35° each side → ~70 points)
      expect(screen.length, greaterThan(50));
      expect(screen.length, lessThan(80));

      // All points should have reasonable x coordinates
      for (final sp in screen) {
        expect(sp.x, greaterThanOrEqualTo(-100));
        expect(sp.x, lessThanOrEqualTo(500));
      }
    });
  });

  group('Synthetic .hgt file', () {
    test('creates valid .hgt file with known terrain', () async {
      // Create a 1201×1201 .hgt file with a mountain in the center
      final dir = await Directory.systemTemp.createTemp('peakline_test');
      final path = '${dir.path}/N46E007.hgt';

      final grid = 1201;
      final data = ByteData(grid * grid * 2);
      for (int row = 0; row < grid; row++) {
        for (int col = 0; col < grid; col++) {
          // Mountain that peaks at center (600,600)
          final dy = (row - 600).abs();
          final dx = (col - 600).abs();
          final dist = (dx * dx + dy * dy).toDouble();
          final elevation =
              (4000 * (1.0 - dist / (600 * 600))).clamp(500, 4000).toInt();
          data.setInt16((row * grid + col) * 2, elevation, Endian.big);
        }
      }

      await File(path).writeAsBytes(data.buffer.asUint8List());

      final file = File(path);
      expect(await file.exists(), true);
      expect(await file.length(), grid * grid * 2);

      // Clean up
      await dir.delete(recursive: true);
    });
  });
}

// ---------------------------------------------------------------------------
//  TIFF building helpers for test data
// ---------------------------------------------------------------------------

Uint8List _u16LE(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

Uint8List _u32LE(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Uint8List _ifdEntry(int tag, int type, int count, int value) {
  final buf = ByteData(12);
  buf.setUint16(0, tag, Endian.little);
  buf.setUint16(2, type, Endian.little);
  buf.setUint32(4, count, Endian.little);
  // Value fits in 4 bytes
  if (type == 3) {
    // SHORT
    buf.setUint16(8, value, Endian.little);
  } else {
    // LONG
    buf.setUint32(8, value, Endian.little);
  }
  return buf.buffer.asUint8List();
}
