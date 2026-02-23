import 'package:flutter/material.dart';
import 'ui/screens/home_screen.dart';

/// The root widget of the PeakLine app.
///
/// This sets up the MaterialApp with theming and routing.
/// Right now it just shows a single home screen — we'll add
/// navigation to live view, photo view, settings, etc. in later steps.
class PeakLineApp extends StatelessWidget {
  const PeakLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeakLine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // Mountain green
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
