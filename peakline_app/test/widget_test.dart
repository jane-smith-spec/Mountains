import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peakline_app/app.dart';

void main() {
  testWidgets('PeakLineApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PeakLineApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Home screen shows Launch Live View button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PeakLineApp(),
      ),
    );

    expect(find.text('Launch Live View'), findsOneWidget);
  });

  testWidgets('Home screen shows camera preview as completed',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PeakLineApp(),
      ),
    );

    // Camera preview row should exist in the build progress card
    expect(find.text('Camera preview'), findsOneWidget);
  });
}
