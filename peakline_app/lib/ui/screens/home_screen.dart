import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sensor_service.dart';
import '../../services/location_service.dart';
import 'live_view_screen.dart';

/// The home screen of PeakLine.
///
/// Shows build progress and live sensor readings so you can verify
/// the compass, gyro, and GPS are working on your device.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _locationError;

  @override
  void initState() {
    super.initState();
    // Request location permission when the screen loads
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    final service = ref.read(locationServiceProvider);
    final error = await service.checkAndRequestPermission();
    if (mounted) {
      setState(() => _locationError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orientation = ref.watch(deviceOrientationProvider);
    final location = ref.watch(deviceLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PeakLine'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Mountain icon + title
            Icon(
              Icons.terrain,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'PeakLine',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Identify mountains with your camera',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),

            // Build progress card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build Progress',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _statusRow(context, 'Flutter project + theming', true),
                    _statusRow(context, 'C native core (curvature, interpolation)', true),
                    _statusRow(context, 'DEM file loader (.hgt elevation data)', true),
                    _statusRow(context, 'Ray-casting horizon engine', true),
                    _statusRow(context, 'Dart FFI bridge to C core', true),
                    _statusRow(context, 'Sensor integration (compass + GPS)', true),
                    _statusRow(context, 'Camera preview', true),
                    _statusRow(context, 'Horizon overlay', false),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live sensor readings card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Sensors',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Compass / orientation
                    orientation.when(
                      data: (o) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sensorRow(
                            context,
                            Icons.explore,
                            'Heading',
                            '${o.headingDeg.toStringAsFixed(1)}°'
                                ' ${_headingLabel(o.headingDeg)}',
                          ),
                          _sensorRow(
                            context,
                            Icons.straight,
                            'Pitch',
                            '${o.pitchDeg.toStringAsFixed(1)}°',
                          ),
                          _sensorRow(
                            context,
                            Icons.screen_rotation,
                            'Roll',
                            '${o.rollDeg.toStringAsFixed(1)}°',
                          ),
                        ],
                      ),
                      loading: () => _sensorRow(
                        context,
                        Icons.explore,
                        'Compass',
                        'Starting sensors...',
                      ),
                      error: (e, _) => _sensorRow(
                        context,
                        Icons.explore,
                        'Compass',
                        'Error: $e',
                      ),
                    ),

                    const Divider(height: 24),

                    // GPS location
                    if (_locationError != null)
                      _sensorRow(
                        context,
                        Icons.location_off,
                        'GPS',
                        _locationError!,
                      )
                    else
                      location.when(
                        data: (loc) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sensorRow(
                              context,
                              Icons.location_on,
                              'Latitude',
                              '${loc.latitudeDeg.toStringAsFixed(5)}°',
                            ),
                            _sensorRow(
                              context,
                              Icons.location_on,
                              'Longitude',
                              '${loc.longitudeDeg.toStringAsFixed(5)}°',
                            ),
                            _sensorRow(
                              context,
                              Icons.height,
                              'Altitude',
                              '${loc.altitudeM.toStringAsFixed(0)}m '
                                  '(±${loc.accuracyM.toStringAsFixed(0)}m)',
                            ),
                          ],
                        ),
                        loading: () => _sensorRow(
                          context,
                          Icons.location_searching,
                          'GPS',
                          'Getting fix...',
                        ),
                        error: (e, _) => _sensorRow(
                          context,
                          Icons.location_off,
                          'GPS',
                          'Error: $e',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Launch camera button
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LiveViewScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Launch Live View'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cardinal direction label for a heading.
  String _headingLabel(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading < 67.5) return 'NE';
    if (heading < 112.5) return 'E';
    if (heading < 157.5) return 'SE';
    if (heading < 202.5) return 'S';
    if (heading < 247.5) return 'SW';
    if (heading < 292.5) return 'W';
    return 'NW';
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
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
