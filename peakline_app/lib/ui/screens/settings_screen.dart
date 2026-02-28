/// Settings screen — user preferences for the PeakLine app.
///
/// Lets users configure:
///   - Units (metric / imperial)
///   - Max peak display distance
///   - Sensor smoothing level (Kalman filter tuning)
///   - Horizon line appearance
///   - Peak label density
///   - Theme mode (system / light / dark)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kalman_filter.dart';

// -----------------------------------------------------------------------
//  App Settings model + notifier
// -----------------------------------------------------------------------

/// Unit system for displaying distances and elevations.
enum UnitSystem {
  metric('Metric (m, km)'),
  imperial('Imperial (ft, mi)');

  const UnitSystem(this.label);
  final String label;
}

/// How much detail to show on peak labels.
enum LabelDensity {
  compact('Compact', 'Name only'),
  normal('Normal', 'Name + elevation'),
  detailed('Detailed', 'Name + elevation + distance');

  const LabelDensity(this.label, this.description);
  final String label;
  final String description;
}

/// All user-configurable app settings.
class AppSettings {
  const AppSettings({
    this.unitSystem = UnitSystem.metric,
    this.maxDisplayDistanceKm = 100.0,
    this.smoothingLevel = SmoothingLevel.medium,
    this.labelDensity = LabelDensity.normal,
    this.horizonLineOpacity = 0.8,
    this.horizonLineWidth = 2.0,
    this.showDistanceOnLabels = true,
    this.themeMode = ThemeMode.system,
  });

  final UnitSystem unitSystem;
  final double maxDisplayDistanceKm;
  final SmoothingLevel smoothingLevel;
  final LabelDensity labelDensity;
  final double horizonLineOpacity;
  final double horizonLineWidth;
  final bool showDistanceOnLabels;
  final ThemeMode themeMode;

  AppSettings copyWith({
    UnitSystem? unitSystem,
    double? maxDisplayDistanceKm,
    SmoothingLevel? smoothingLevel,
    LabelDensity? labelDensity,
    double? horizonLineOpacity,
    double? horizonLineWidth,
    bool? showDistanceOnLabels,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      unitSystem: unitSystem ?? this.unitSystem,
      maxDisplayDistanceKm: maxDisplayDistanceKm ?? this.maxDisplayDistanceKm,
      smoothingLevel: smoothingLevel ?? this.smoothingLevel,
      labelDensity: labelDensity ?? this.labelDensity,
      horizonLineOpacity: horizonLineOpacity ?? this.horizonLineOpacity,
      horizonLineWidth: horizonLineWidth ?? this.horizonLineWidth,
      showDistanceOnLabels: showDistanceOnLabels ?? this.showDistanceOnLabels,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// Format a distance value according to the current unit system.
  String formatDistance(double meters) {
    switch (unitSystem) {
      case UnitSystem.metric:
        if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
        return '${(meters / 1000).toStringAsFixed(1)}km';
      case UnitSystem.imperial:
        final feet = meters * 3.28084;
        if (feet < 5280) return '${feet.toStringAsFixed(0)}ft';
        return '${(feet / 5280).toStringAsFixed(1)}mi';
    }
  }

  /// Format an elevation value according to the current unit system.
  String formatElevation(double meters) {
    switch (unitSystem) {
      case UnitSystem.metric:
        return '${meters.toStringAsFixed(0)}m';
      case UnitSystem.imperial:
        return '${(meters * 3.28084).toStringAsFixed(0)}ft';
    }
  }
}

/// Riverpod notifier for app settings.
class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings());

  void setUnitSystem(UnitSystem value) =>
      state = state.copyWith(unitSystem: value);

  void setMaxDisplayDistance(double km) =>
      state = state.copyWith(maxDisplayDistanceKm: km);

  void setSmoothingLevel(SmoothingLevel value) =>
      state = state.copyWith(smoothingLevel: value);

  void setLabelDensity(LabelDensity value) =>
      state = state.copyWith(labelDensity: value);

  void setHorizonLineOpacity(double value) =>
      state = state.copyWith(horizonLineOpacity: value);

  void setHorizonLineWidth(double value) =>
      state = state.copyWith(horizonLineWidth: value);

  void setShowDistanceOnLabels(bool value) =>
      state = state.copyWith(showDistanceOnLabels: value);

  void setThemeMode(ThemeMode value) =>
      state = state.copyWith(themeMode: value);

  void resetToDefaults() => state = const AppSettings();
}

/// Provider for app settings state.
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(),
);

// -----------------------------------------------------------------------
//  Settings Screen Widget
// -----------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset') {
                _showResetDialog(context, notifier);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset to Defaults'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          // -- Units section --
          _sectionHeader(theme, 'Units'),
          _buildUnitSelector(settings, notifier),

          // -- Display section --
          _sectionHeader(theme, 'Display'),
          _buildMaxDistanceSlider(settings, notifier),
          _buildLabelDensitySelector(settings, notifier),
          SwitchListTile(
            title: const Text('Show distance on labels'),
            subtitle: const Text('Display km/mi on peak flags'),
            value: settings.showDistanceOnLabels,
            onChanged: notifier.setShowDistanceOnLabels,
          ),

          // -- Horizon Line section --
          _sectionHeader(theme, 'Horizon Line'),
          _buildOpacitySlider(settings, notifier),
          _buildLineWidthSlider(settings, notifier),

          // -- Sensor Smoothing section --
          _sectionHeader(theme, 'Sensor Smoothing'),
          _buildSmoothingSelector(settings, notifier),

          // -- Theme section --
          _sectionHeader(theme, 'Appearance'),
          _buildThemeSelector(settings, notifier),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildUnitSelector(AppSettings settings, AppSettingsNotifier notifier) {
    return Column(
      children: UnitSystem.values.map((unit) {
        return RadioListTile<UnitSystem>(
          title: Text(unit.label),
          value: unit,
          groupValue: settings.unitSystem,
          onChanged: (value) {
            if (value != null) notifier.setUnitSystem(value);
          },
        );
      }).toList(),
    );
  }

  Widget _buildMaxDistanceSlider(
    AppSettings settings,
    AppSettingsNotifier notifier,
  ) {
    return ListTile(
      title: const Text('Max peak distance'),
      subtitle: Slider(
        value: settings.maxDisplayDistanceKm,
        min: 10,
        max: 150,
        divisions: 14,
        label: '${settings.maxDisplayDistanceKm.toStringAsFixed(0)} km',
        onChanged: notifier.setMaxDisplayDistance,
      ),
      trailing: Text(
        '${settings.maxDisplayDistanceKm.toStringAsFixed(0)} km',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildLabelDensitySelector(
    AppSettings settings,
    AppSettingsNotifier notifier,
  ) {
    return Column(
      children: LabelDensity.values.map((density) {
        return RadioListTile<LabelDensity>(
          title: Text(density.label),
          subtitle: Text(density.description),
          value: density,
          groupValue: settings.labelDensity,
          onChanged: (value) {
            if (value != null) notifier.setLabelDensity(value);
          },
        );
      }).toList(),
    );
  }

  Widget _buildOpacitySlider(
    AppSettings settings,
    AppSettingsNotifier notifier,
  ) {
    return ListTile(
      title: const Text('Line opacity'),
      subtitle: Slider(
        value: settings.horizonLineOpacity,
        min: 0.2,
        max: 1.0,
        divisions: 8,
        label: '${(settings.horizonLineOpacity * 100).toStringAsFixed(0)}%',
        onChanged: notifier.setHorizonLineOpacity,
      ),
      trailing: Text(
        '${(settings.horizonLineOpacity * 100).toStringAsFixed(0)}%',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildLineWidthSlider(
    AppSettings settings,
    AppSettingsNotifier notifier,
  ) {
    return ListTile(
      title: const Text('Line width'),
      subtitle: Slider(
        value: settings.horizonLineWidth,
        min: 1.0,
        max: 5.0,
        divisions: 8,
        label: '${settings.horizonLineWidth.toStringAsFixed(1)}px',
        onChanged: notifier.setHorizonLineWidth,
      ),
      trailing: Text(
        '${settings.horizonLineWidth.toStringAsFixed(1)}px',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildSmoothingSelector(
    AppSettings settings,
    AppSettingsNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Controls how aggressively sensor jitter is filtered. '
              '"Low" gives the smoothest overlay but may feel laggy '
              'when turning. "High" responds instantly but shows more jitter.',
            ),
          ),
          SegmentedButton<SmoothingLevel>(
            segments: SmoothingLevel.values.map((level) {
              return ButtonSegment(
                value: level,
                label: Text(level.label),
              );
            }).toList(),
            selected: {settings.smoothingLevel},
            onSelectionChanged: (selection) {
              notifier.setSmoothingLevel(selection.first);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(
    AppSettings settings,
    AppSettingsNotifier notifier,
  ) {
    return Column(
      children: [
        RadioListTile<ThemeMode>(
          title: const Text('System default'),
          value: ThemeMode.system,
          groupValue: settings.themeMode,
          onChanged: (value) {
            if (value != null) notifier.setThemeMode(value);
          },
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Light'),
          value: ThemeMode.light,
          groupValue: settings.themeMode,
          onChanged: (value) {
            if (value != null) notifier.setThemeMode(value);
          },
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Dark'),
          value: ThemeMode.dark,
          groupValue: settings.themeMode,
          onChanged: (value) {
            if (value != null) notifier.setThemeMode(value);
          },
        ),
      ],
    );
  }

  void _showResetDialog(BuildContext context, AppSettingsNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'This will reset all settings to their default values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              notifier.resetToDefaults();
              Navigator.of(ctx).pop();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
