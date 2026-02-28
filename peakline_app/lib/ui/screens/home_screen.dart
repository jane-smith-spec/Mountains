import 'package:flutter/material.dart';
import 'live_view_screen.dart';
import 'photo_debug_screen.dart';
import 'photo_view_screen.dart';
import 'region_download_screen.dart';
import 'settings_screen.dart';

/// The initial home screen of PeakLine.
///
/// For Step 1 this is just a welcome/placeholder screen that proves the app
/// builds and runs. In later steps we'll replace this with navigation to:
///   - Live AR view (Step 7+)
///   - Photo analysis (Step 16)
///   - Settings / region downloads (Step 15)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PeakLine'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mountain icon
              Icon(
                Icons.terrain,
                size: 96,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),

              // App title
              Text(
                'PeakLine',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),

              // Tagline
              Text(
                'Identify mountains with your camera',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),

              // Status card showing what's working
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 1: Project Scaffold',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _statusRow(context, 'Flutter project', true),
                      _statusRow(context, 'Material 3 theming', true),
                      _statusRow(context, 'Riverpod state management', true),
                      _statusRow(context, 'C native core (desktop build)', true),
                      _statusRow(context, 'Camera preview', false),
                      _statusRow(context, 'Sensor integration', false),
                      _statusRow(context, 'Horizon overlay', false),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LiveViewScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Live View'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PhotoViewScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Photo View'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegionDownloadScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Region Download'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Settings'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PhotoDebugScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.science),
                    label: const Text('Photo Debug'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusRow(BuildContext context, String label, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: done
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
