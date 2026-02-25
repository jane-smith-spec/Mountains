import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/ui/painters/grid_painter.dart';

void main() {
  group('GridPainter', () {
    test('can be constructed with defaults', () {
      final painter = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(painter.headingDeg, 90.0);
      expect(painter.pitchDeg, 0.0);
      expect(painter.hFovDeg, 60.0);
      expect(painter.vFovDeg, 35.6);
      expect(painter.bearingIntervalDeg, 30.0);
      expect(painter.elevationIntervalDeg, 5.0);
      expect(painter.showCardinals, true);
    });

    test('can be constructed with custom intervals', () {
      final painter = GridPainter(
        headingDeg: 0.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
        bearingIntervalDeg: 10.0,
        elevationIntervalDeg: 2.0,
        showCardinals: false,
      );

      expect(painter.bearingIntervalDeg, 10.0);
      expect(painter.elevationIntervalDeg, 2.0);
      expect(painter.showCardinals, false);
    });

    test('shouldRepaint returns true when heading changes', () {
      final painter1 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );
      final painter2 = GridPainter(
        headingDeg: 91.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(painter2.shouldRepaint(painter1), true);
    });

    test('shouldRepaint returns true when pitch changes', () {
      final painter1 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );
      final painter2 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 5.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(painter2.shouldRepaint(painter1), true);
    });

    test('shouldRepaint returns false when nothing changes', () {
      final painter1 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );
      final painter2 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );

      expect(painter2.shouldRepaint(painter1), false);
    });

    test('shouldRepaint returns true when FOV changes', () {
      final painter1 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
      );
      final painter2 = GridPainter(
        headingDeg: 90.0,
        pitchDeg: 0.0,
        hFovDeg: 70.0,
        vFovDeg: 35.6,
      );

      expect(painter2.shouldRepaint(painter1), true);
    });

    test('colors can be customized', () {
      final painter = GridPainter(
        headingDeg: 0.0,
        pitchDeg: 0.0,
        hFovDeg: 60.0,
        vFovDeg: 35.6,
        gridColor: Colors.red,
        labelColor: Colors.blue,
        horizonColor: Colors.green,
      );

      expect(painter.gridColor, Colors.red);
      expect(painter.labelColor, Colors.blue);
      expect(painter.horizonColor, Colors.green);
    });
  });

  group('GridPainter painting', () {
    // These tests verify that the painter doesn't crash when drawing.
    // We can't easily verify exact pixel output, but we can ensure
    // no exceptions are thrown for various heading/pitch combinations.

    testWidgets('paints without error at heading=0 (North)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(400, 800),
            painter: GridPainter(
              headingDeg: 0.0,
              pitchDeg: 0.0,
              hFovDeg: 60.0,
              vFovDeg: 35.6,
            ),
          ),
        ),
      );
      // No assertion — just verify no crash
    });

    testWidgets('paints without error at heading=359 (near North wrap)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(400, 800),
            painter: GridPainter(
              headingDeg: 359.0,
              pitchDeg: 0.0,
              hFovDeg: 60.0,
              vFovDeg: 35.6,
            ),
          ),
        ),
      );
    });

    testWidgets('paints without error with negative pitch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(400, 800),
            painter: GridPainter(
              headingDeg: 180.0,
              pitchDeg: -15.0,
              hFovDeg: 60.0,
              vFovDeg: 35.6,
            ),
          ),
        ),
      );
    });

    testWidgets('paints without error with wide FOV', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(400, 800),
            painter: GridPainter(
              headingDeg: 90.0,
              pitchDeg: 10.0,
              hFovDeg: 120.0,
              vFovDeg: 70.0,
              bearingIntervalDeg: 10.0,
              elevationIntervalDeg: 2.0,
            ),
          ),
        ),
      );
    });

    testWidgets('paints without error with cardinals disabled',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(400, 800),
            painter: GridPainter(
              headingDeg: 45.0,
              pitchDeg: 0.0,
              hFovDeg: 60.0,
              vFovDeg: 35.6,
              showCardinals: false,
            ),
          ),
        ),
      );
    });
  });
}
