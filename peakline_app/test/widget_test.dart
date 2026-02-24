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
}
