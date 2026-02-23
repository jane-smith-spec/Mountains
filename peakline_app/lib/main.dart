import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    // ProviderScope is required for Riverpod state management.
    // It holds the state for all providers in the app.
    const ProviderScope(
      child: PeakLineApp(),
    ),
  );
}
