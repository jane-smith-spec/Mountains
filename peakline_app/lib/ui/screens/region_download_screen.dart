/// Region download screen — select and download DEM elevation data.
///
/// This screen lets users:
///   1. Pick from predefined popular regions (Swiss Alps, etc.)
///   2. See which tiles are available vs. missing for their area
///   3. Monitor disk usage
///   4. Delete downloaded data they no longer need
///
/// DEM data is required for the horizon computation. Without it,
/// the app can show the camera and sensors but no topo overlay.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dem_repository.dart';
import '../../data/tile_manager.dart';
import '../../models/tile_index.dart';

// -----------------------------------------------------------------------
//  Predefined regions
// -----------------------------------------------------------------------

/// A predefined region that users can quickly select.
class RegionPreset {
  const RegionPreset({
    required this.name,
    required this.description,
    required this.centerLat,
    required this.centerLon,
    required this.radiusKm,
  });

  final String name;
  final String description;
  final double centerLat;
  final double centerLon;
  final double radiusKm;
}

/// Popular regions. Ordered roughly by expected user demand.
const List<RegionPreset> kRegionPresets = [
  RegionPreset(
    name: 'Swiss Alps',
    description: 'Matterhorn, Eiger, Jungfrau, Mont Blanc area',
    centerLat: 46.5,
    centerLon: 7.8,
    radiusKm: 100,
  ),
  RegionPreset(
    name: 'Austrian Alps',
    description: 'Tyrol, Grossglockner, Dachstein',
    centerLat: 47.1,
    centerLon: 12.0,
    radiusKm: 100,
  ),
  RegionPreset(
    name: 'Dolomites',
    description: 'Tre Cime, Marmolada, South Tyrol',
    centerLat: 46.4,
    centerLon: 11.8,
    radiusKm: 60,
  ),
  RegionPreset(
    name: 'French Alps',
    description: 'Chamonix, Vanoise, Écrins',
    centerLat: 45.5,
    centerLon: 6.5,
    radiusKm: 80,
  ),
  RegionPreset(
    name: 'Colorado Rockies',
    description: 'Front Range, 14ers, Rocky Mountain NP',
    centerLat: 39.5,
    centerLon: -105.8,
    radiusKm: 100,
  ),
  RegionPreset(
    name: 'Pacific Northwest',
    description: 'Mt. Rainier, Mt. Hood, Cascades',
    centerLat: 46.8,
    centerLon: -121.8,
    radiusKm: 100,
  ),
  RegionPreset(
    name: 'Pyrenees',
    description: 'Aneto, Monte Perdido, Franco-Spanish border',
    centerLat: 42.6,
    centerLon: 0.5,
    radiusKm: 80,
  ),
  RegionPreset(
    name: 'Scottish Highlands',
    description: 'Ben Nevis, Cairngorms',
    centerLat: 56.8,
    centerLon: -5.0,
    radiusKm: 80,
  ),
];

// -----------------------------------------------------------------------
//  Screen
// -----------------------------------------------------------------------

class RegionDownloadScreen extends ConsumerStatefulWidget {
  const RegionDownloadScreen({super.key});

  @override
  ConsumerState<RegionDownloadScreen> createState() =>
      _RegionDownloadScreenState();
}

class _RegionDownloadScreenState extends ConsumerState<RegionDownloadScreen> {
  String _diskUsage = '...';
  Set<TileIndex> _availableTiles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    final demRepo = ref.read(demRepositoryProvider);
    final usage = await demRepo.diskUsageLabel();
    final tiles = await demRepo.availableTiles();
    if (mounted) {
      setState(() {
        _diskUsage = usage;
        _availableTiles = tiles;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Regions'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Disk usage summary
                _buildStorageCard(theme),
                const SizedBox(height: 16),

                // Available tiles count
                Text(
                  '${_availableTiles.length} tile${_availableTiles.length == 1 ? '' : 's'} downloaded',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),

                // Region presets
                ...kRegionPresets.map((region) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildRegionCard(theme, region),
                    )),
              ],
            ),
    );
  }

  Widget _buildStorageCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.storage, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DEM Storage', style: theme.textTheme.titleSmall),
                  Text(
                    _diskUsage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadStatus,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionCard(ThemeData theme, RegionPreset region) {
    // Count how many tiles this region needs vs. how many we have
    final needed = TileIndex.tilesForRadius(
      region.centerLat,
      region.centerLon,
      region.radiusKm,
    );
    final available = needed.intersection(_availableTiles);
    final progress = needed.isEmpty ? 0.0 : available.length / needed.length;
    final allDownloaded = available.length == needed.length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showRegionDetail(region, needed, available),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      region.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (allDownloaded)
                    Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 20)
                  else
                    Text(
                      '${available.length}/${needed.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                region.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRegionDetail(
    RegionPreset region,
    Set<TileIndex> needed,
    Set<TileIndex> available,
  ) {
    final missing = needed.difference(available);
    final tileManager = ref.read(tileManagerProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                region.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${region.centerLat.toStringAsFixed(1)}°N, '
                '${region.centerLon.toStringAsFixed(1)}°E · '
                '${region.radiusKm.toStringAsFixed(0)} km radius',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 16),

              // Tile stats
              _detailRow(theme, 'Total tiles', '${needed.length}'),
              _detailRow(theme, 'Downloaded', '${available.length}'),
              _detailRow(theme, 'Missing', '${missing.length}'),
              const SizedBox(height: 16),

              // Instruction for downloading
              if (missing.isNotEmpty)
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to get elevation data',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1. Register at Copernicus (free)\n'
                          '2. Run the prepare_dem_tiles.py tool\n'
                          '3. Copy .hgt files to the app\'s dem_tiles/ folder\n\n'
                          'Missing tiles:',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: missing
                              .map((t) => Chip(
                                    label: Text(
                                      t.hgtFilename,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),

              // Resolution breakdown
              const SizedBox(height: 16),
              Text(
                'Resolution tiers',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _detailRow(theme, '30m (0–10 km)',
                  '${TileResolution.full.gridSize}×${TileResolution.full.gridSize}'),
              _detailRow(theme, '90m (10–40 km)',
                  '${TileResolution.medium.gridSize}×${TileResolution.medium.gridSize}'),
              _detailRow(theme, '250m (40–100 km)',
                  '${TileResolution.low.gridSize}×${TileResolution.low.gridSize}'),

              // Delete button for downloaded tiles
              if (available.isNotEmpty) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(region, available),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                      'Delete ${available.length} tile${available.length == 1 ? '' : 's'}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
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

  void _confirmDelete(RegionPreset region, Set<TileIndex> tiles) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete tiles?'),
        content: Text(
          'Delete ${tiles.length} tile${tiles.length == 1 ? '' : 's'} '
          'for ${region.name}? You can re-download them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close bottom sheet
              final demRepo = ref.read(demRepositoryProvider);
              for (final tile in tiles) {
                await demRepo.deleteTile(tile);
              }
              _loadStatus();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
