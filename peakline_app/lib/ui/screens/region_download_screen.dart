/// Region download screen — browse and download DEM elevation data.
///
/// Two-level hierarchy:
///   Country → State/Province
///
/// Users can download an entire country (broad) or pick individual
/// states/provinces (fine-grained) depending on their storage budget.
///
/// Tiles are downloaded directly from Copernicus open data (AWS S3),
/// no account or authentication required.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dem_download_service.dart';
import '../../data/dem_repository.dart';
import '../../data/region_data.dart';
import '../../models/tile_index.dart';

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

  /// Which countries are currently expanded in the list.
  final Set<String> _expandedCountries = {};

  /// Active download progress (null when idle).
  DownloadProgress? _downloadProgress;

  /// Selected download quality (default to fastest/smallest).
  DownloadQuality _quality = DownloadQuality.low;

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
          : Column(
              children: [
                // Download progress bar (visible during downloads)
                if (_downloadProgress != null &&
                    !_downloadProgress!.isComplete)
                  _buildDownloadBanner(theme),

                // Main content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStorageCard(theme),
                      const SizedBox(height: 12),
                      Text(
                        '${_availableTiles.length} tile${_availableTiles.length == 1 ? '' : 's'} downloaded',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ...kCountryCatalog.map(
                          (country) => _buildCountrySection(theme, country)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // -----------------------------------------------------------------------
  //  Download progress banner
  // -----------------------------------------------------------------------

  Widget _buildDownloadBanner(ThemeData theme) {
    final p = _downloadProgress!;
    return Container(
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _cancelDownload,
                child: Text(
                  'Cancel',
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: p.overallProgress,
            backgroundColor:
                theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  Storage card
  // -----------------------------------------------------------------------

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

  // -----------------------------------------------------------------------
  //  Country section — expandable with state rows
  // -----------------------------------------------------------------------

  Widget _buildCountrySection(ThemeData theme, Country country) {
    final isExpanded = _expandedCountries.contains(country.code);
    final countryTiles = country.tiles;
    final available = countryTiles.intersection(_availableTiles);
    final progress =
        countryTiles.isEmpty ? 0.0 : available.length / countryTiles.length;
    final allDone =
        available.length == countryTiles.length && countryTiles.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Country header — tap to expand/collapse
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCountries.remove(country.code);
                } else {
                  _expandedCountries.add(country.code);
                }
              });
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(country.emoji,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              country.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${country.states.length} region${country.states.length == 1 ? '' : 's'}'
                              ' \u00B7 ${countryTiles.length} tile${countryTiles.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (allDone)
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.primary, size: 20)
                      else if (available.isNotEmpty)
                        Text(
                          '${available.length}/${countryTiles.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                ],
              ),
            ),
          ),

          // Expanded: show individual state rows
          if (isExpanded) ...[
            const Divider(height: 1),
            _buildCountryDownloadRow(
                theme, country, countryTiles, available),
            const Divider(height: 1),
            ...country.states.map(
              (state) => _buildStateRow(theme, country, state),
            ),
          ],
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  "Download entire country" row
  // -----------------------------------------------------------------------

  Widget _buildCountryDownloadRow(
    ThemeData theme,
    Country country,
    Set<TileIndex> countryTiles,
    Set<TileIndex> available,
  ) {
    final missing = countryTiles.difference(available);
    final sizeMB = countryTiles.length * _quality.approxStorageMB;

    return InkWell(
      onTap: () => _showRegionDetail(
        name: '${country.emoji} ${country.name} (all)',
        subtitle:
            '${country.states.length} regions \u00B7 ~${sizeMB.toStringAsFixed(0)} MB',
        tiles: countryTiles,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.public,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Entire country',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '~${sizeMB.toStringAsFixed(0)} MB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 4),
            if (missing.isEmpty)
              Icon(Icons.check_circle,
                  size: 16, color: theme.colorScheme.primary)
            else
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  Individual state row
  // -----------------------------------------------------------------------

  Widget _buildStateRow(ThemeData theme, Country country, StateRegion state) {
    final stateTiles = state.bbox.tiles;
    final available = stateTiles.intersection(_availableTiles);
    final progress =
        stateTiles.isEmpty ? 0.0 : available.length / stateTiles.length;
    final allDone =
        available.length == stateTiles.length && stateTiles.isNotEmpty;
    final sizeMB = stateTiles.length * _quality.approxStorageMB;

    return InkWell(
      onTap: () => _showRegionDetail(
        name: state.name,
        subtitle: state.description ?? '',
        tiles: stateTiles,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.name,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        allDone
                            ? '${stateTiles.length} tiles'
                            : '${available.length}/${stateTiles.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (allDone)
                        Icon(Icons.check_circle,
                            size: 14, color: theme.colorScheme.primary)
                      else
                        Icon(Icons.chevron_right,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                  if (state.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${state.description!} \u00B7 ~${sizeMB.toStringAsFixed(0)} MB',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (!allDone && available.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  //  Region detail bottom sheet
  // -----------------------------------------------------------------------

  void _showRegionDetail({
    required String name,
    required String subtitle,
    required Set<TileIndex> tiles,
  }) {
    final available = tiles.intersection(_availableTiles);
    final missing = tiles.difference(available);
    var sheetQuality = _quality;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (sheetContext, scrollController) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final theme = Theme.of(sheetContext);
              final isDownloading =
                  ref.read(demDownloadServiceProvider).isDownloading;

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
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Quality selector
                  Text(
                    'Download quality',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<DownloadQuality>(
                    segments: DownloadQuality.values.map((q) {
                      return ButtonSegment<DownloadQuality>(
                        value: q,
                        label: Text(q.label),
                      );
                    }).toList(),
                    selected: {sheetQuality},
                    onSelectionChanged: (selected) {
                      setSheetState(() => sheetQuality = selected.first);
                      _quality = selected.first;
                    },
                    style: ButtonStyle(
                      textStyle: WidgetStatePropertyAll(
                        theme.textTheme.bodySmall,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sheetQuality.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Stats
                  _detailRow(theme, 'Total tiles', '${tiles.length}'),
                  _detailRow(theme, 'Downloaded', '${available.length}'),
                  _detailRow(theme, 'Missing', '${missing.length}'),
                  _detailRow(theme, 'Est. download',
                      '~${(missing.length * sheetQuality.approxDownloadMB).toStringAsFixed(0)} MB'),
                  _detailRow(theme, 'Est. storage',
                      '~${(missing.length * sheetQuality.approxStorageMB).toStringAsFixed(0)} MB'),
                  const SizedBox(height: 16),

                  // Download button
                  if (missing.isNotEmpty) ...[
                    FilledButton.icon(
                      onPressed: isDownloading
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              _startDownload(tiles, sheetQuality);
                            },
                      icon: Icon(isDownloading
                          ? Icons.hourglass_empty
                          : Icons.download),
                      label: Text(isDownloading
                          ? 'Download in progress...'
                          : 'Download ${missing.length} tile${missing.length == 1 ? '' : 's'} (${sheetQuality.label})'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Free download from Copernicus open data.\n'
                      'No account required.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  if (missing.isEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'All tiles downloaded',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Delete
                  if (available.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => _confirmDelete(name, available),
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

  // -----------------------------------------------------------------------
  //  Download actions
  // -----------------------------------------------------------------------

  Future<void> _startDownload(Set<TileIndex> tiles, DownloadQuality quality) async {
    final downloadService = ref.read(demDownloadServiceProvider);

    await downloadService.downloadTiles(
      tiles: tiles,
      quality: quality,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _downloadProgress = progress);

          // Refresh status when done
          if (progress.isComplete) {
            _loadStatus();

            // Show result snackbar
            final msg = progress.failedTiles > 0
                ? '${progress.completedTiles} downloaded, ${progress.failedTiles} failed'
                : '${progress.completedTiles} tiles downloaded';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }
      },
    );
  }

  void _cancelDownload() {
    ref.read(demDownloadServiceProvider).cancel();
    setState(() => _downloadProgress = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download cancelled')),
    );
  }

  // -----------------------------------------------------------------------
  //  Delete confirmation
  // -----------------------------------------------------------------------

  void _confirmDelete(String regionName, Set<TileIndex> tiles) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete tiles?'),
        content: Text(
          'Delete ${tiles.length} tile${tiles.length == 1 ? '' : 's'} '
          'for $regionName? You can re-download them later.',
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
