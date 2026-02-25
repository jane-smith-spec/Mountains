/// Home screen — the main menu and status dashboard.
///
/// Shows live sensor readings to verify hardware works, plus
/// navigation to all app features: live AR view, region download,
/// and (future) photo analysis.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dem_repository.dart';
import '../../services/location_service.dart';
import '../../services/sensor_service.dart';
import 'live_view_screen.dart';
import 'region_download_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _locationError;
  String _tileCount = '...';
  String _diskUsage = '...';

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadTileStatus();
  }

  Future<void> _requestLocationPermission() async {
    final service = ref.read(locationServiceProvider);
    final error = await service.checkAndRequestPermission();
    if (mounted) {
      setState(() => _locationError = error);
    }
  }

  Future<void> _loadTileStatus() async {
    final demRepo = ref.read(demRepositoryProvider);
    final tiles = await demRepo.availableTiles();
    final usage = await demRepo.diskUsageLabel();
    if (mounted) {
      setState(() {
        _tileCount = '${tiles.length}';
        _diskUsage = usage;
      });
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

            // Action buttons
            _buildActionButtons(theme),
            const SizedBox(height: 24),

            // DEM data status
            _buildDataCard(theme),
            const SizedBox(height: 16),

            // Live sensor readings
            _buildSensorCard(theme, orientation, location),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Column(
      children: [
        // Launch live view
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LiveViewScreen()),
            );
          },
          icon: const Icon(Icons.camera_alt),
          label: const Text('Launch Live View'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
        const SizedBox(height: 12),
        // Download regions
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RegionDownloadScreen(),
              ),
            );
            // Refresh tile status when returning
            _loadTileStatus();
          },
          icon: const Icon(Icons.download),
          label: const Text('Download Elevation Data'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildDataCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elevation Data',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _infoRow(theme, Icons.grid_view, 'Tiles downloaded', _tileCount),
            _infoRow(theme, Icons.storage, 'Disk usage', _diskUsage),
            if (_tileCount == '0') ...[
              const SizedBox(height: 8),
              Text(
                'Download elevation data to see the horizon overlay.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(
    ThemeData theme,
    AsyncValue<dynamic> orientation,
    AsyncValue<dynamic> location,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    theme,
                    Icons.explore,
                    'Heading',
                    '${o.headingDeg.toStringAsFixed(1)}°'
                        ' ${_headingLabel(o.headingDeg)}',
                  ),
                  _sensorRow(
                    theme,
                    Icons.straight,
                    'Pitch',
                    '${o.pitchDeg.toStringAsFixed(1)}°',
                  ),
                ],
              ),
              loading: () => _sensorRow(
                theme,
                Icons.explore,
                'Compass',
                'Starting sensors...',
              ),
              error: (e, _) => _sensorRow(
                theme,
                Icons.explore,
                'Compass',
                'Error: $e',
              ),
            ),

            const Divider(height: 24),

            // GPS
            if (_locationError != null)
              _sensorRow(theme, Icons.location_off, 'GPS', _locationError!)
            else
              location.when(
                data: (loc) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sensorRow(
                      theme,
                      Icons.location_on,
                      'Position',
                      '${loc.latitudeDeg.toStringAsFixed(4)}°N, '
                          '${loc.longitudeDeg.toStringAsFixed(4)}°E',
                    ),
                    _sensorRow(
                      theme,
                      Icons.height,
                      'Altitude',
                      '${loc.altitudeM.toStringAsFixed(0)}m '
                          '±${loc.accuracyM.toStringAsFixed(0)}m',
                    ),
                  ],
                ),
                loading: () => _sensorRow(
                  theme,
                  Icons.location_searching,
                  'GPS',
                  'Getting fix...',
                ),
                error: (e, _) => _sensorRow(
                  theme,
                  Icons.location_off,
                  'GPS',
                  'Error: $e',
                ),
              ),
          ],
        ),
      ),
    );
  }

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

  Widget _infoRow(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
