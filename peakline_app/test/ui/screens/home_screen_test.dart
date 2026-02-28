import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/ui/screens/home_screen.dart';

void main() {
  testWidgets('shows primary navigation actions', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Live View'), findsOneWidget);
    expect(find.text('Photo View'), findsOneWidget);
    expect(find.text('Region Download'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
