import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/services/kalman_filter.dart';
import 'package:peakline_app/ui/screens/settings_screen.dart';

void main() {
  group('AppSettings', () {
    test('defaults are sensible', () {
      const settings = AppSettings();
      expect(settings.unitSystem, UnitSystem.metric);
      expect(settings.maxDisplayDistanceKm, 100.0);
      expect(settings.smoothingLevel, SmoothingLevel.medium);
      expect(settings.labelDensity, LabelDensity.normal);
      expect(settings.horizonLineOpacity, 0.8);
      expect(settings.horizonLineWidth, 2.0);
      expect(settings.showDistanceOnLabels, true);
      expect(settings.themeMode, ThemeMode.system);
    });

    test('copyWith replaces only specified fields', () {
      const original = AppSettings();
      final modified = original.copyWith(
        unitSystem: UnitSystem.imperial,
        maxDisplayDistanceKm: 50.0,
      );

      expect(modified.unitSystem, UnitSystem.imperial);
      expect(modified.maxDisplayDistanceKm, 50.0);
      // Unchanged fields
      expect(modified.smoothingLevel, SmoothingLevel.medium);
      expect(modified.labelDensity, LabelDensity.normal);
      expect(modified.horizonLineOpacity, 0.8);
      expect(modified.themeMode, ThemeMode.system);
    });

    test('copyWith with no args returns equivalent object', () {
      const original = AppSettings();
      final copy = original.copyWith();

      expect(copy.unitSystem, original.unitSystem);
      expect(copy.maxDisplayDistanceKm, original.maxDisplayDistanceKm);
      expect(copy.smoothingLevel, original.smoothingLevel);
      expect(copy.labelDensity, original.labelDensity);
      expect(copy.horizonLineOpacity, original.horizonLineOpacity);
      expect(copy.horizonLineWidth, original.horizonLineWidth);
      expect(copy.showDistanceOnLabels, original.showDistanceOnLabels);
      expect(copy.themeMode, original.themeMode);
    });

    group('formatDistance', () {
      test('metric: small distance in meters', () {
        const settings = AppSettings(unitSystem: UnitSystem.metric);
        expect(settings.formatDistance(500), '500m');
      });

      test('metric: large distance in km', () {
        const settings = AppSettings(unitSystem: UnitSystem.metric);
        expect(settings.formatDistance(2500), '2.5km');
      });

      test('imperial: small distance in feet', () {
        const settings = AppSettings(unitSystem: UnitSystem.imperial);
        final result = settings.formatDistance(100);
        // 100m ≈ 328ft
        expect(result, endsWith('ft'));
        expect(result, contains('328'));
      });

      test('imperial: large distance in miles', () {
        const settings = AppSettings(unitSystem: UnitSystem.imperial);
        final result = settings.formatDistance(5000);
        // 5000m ≈ 3.1 mi
        expect(result, endsWith('mi'));
        expect(result, contains('3.1'));
      });
    });

    group('formatElevation', () {
      test('metric: elevation in meters', () {
        const settings = AppSettings(unitSystem: UnitSystem.metric);
        expect(settings.formatElevation(4478), '4478m');
      });

      test('imperial: elevation in feet', () {
        const settings = AppSettings(unitSystem: UnitSystem.imperial);
        final result = settings.formatElevation(4478);
        // 4478m ≈ 14692ft
        expect(result, endsWith('ft'));
        expect(result, contains('14692'));
      });
    });
  });

  group('AppSettingsNotifier', () {
    test('initial state has defaults', () {
      final notifier = AppSettingsNotifier();
      expect(notifier.state.unitSystem, UnitSystem.metric);
    });

    test('setUnitSystem updates unit system', () {
      final notifier = AppSettingsNotifier();
      notifier.setUnitSystem(UnitSystem.imperial);
      expect(notifier.state.unitSystem, UnitSystem.imperial);
    });

    test('setMaxDisplayDistance updates distance', () {
      final notifier = AppSettingsNotifier();
      notifier.setMaxDisplayDistance(50.0);
      expect(notifier.state.maxDisplayDistanceKm, 50.0);
    });

    test('setSmoothingLevel updates level', () {
      final notifier = AppSettingsNotifier();
      notifier.setSmoothingLevel(SmoothingLevel.high);
      expect(notifier.state.smoothingLevel, SmoothingLevel.high);
    });

    test('setLabelDensity updates density', () {
      final notifier = AppSettingsNotifier();
      notifier.setLabelDensity(LabelDensity.compact);
      expect(notifier.state.labelDensity, LabelDensity.compact);
    });

    test('setHorizonLineOpacity updates opacity', () {
      final notifier = AppSettingsNotifier();
      notifier.setHorizonLineOpacity(0.5);
      expect(notifier.state.horizonLineOpacity, 0.5);
    });

    test('setHorizonLineWidth updates width', () {
      final notifier = AppSettingsNotifier();
      notifier.setHorizonLineWidth(3.5);
      expect(notifier.state.horizonLineWidth, 3.5);
    });

    test('setShowDistanceOnLabels updates flag', () {
      final notifier = AppSettingsNotifier();
      notifier.setShowDistanceOnLabels(false);
      expect(notifier.state.showDistanceOnLabels, false);
    });

    test('setThemeMode updates theme', () {
      final notifier = AppSettingsNotifier();
      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state.themeMode, ThemeMode.dark);
    });

    test('resetToDefaults restores all defaults', () {
      final notifier = AppSettingsNotifier();

      // Change everything
      notifier.setUnitSystem(UnitSystem.imperial);
      notifier.setMaxDisplayDistance(50.0);
      notifier.setSmoothingLevel(SmoothingLevel.high);
      notifier.setLabelDensity(LabelDensity.detailed);
      notifier.setHorizonLineOpacity(0.3);
      notifier.setHorizonLineWidth(4.0);
      notifier.setShowDistanceOnLabels(false);
      notifier.setThemeMode(ThemeMode.dark);

      // Reset
      notifier.resetToDefaults();

      final s = notifier.state;
      expect(s.unitSystem, UnitSystem.metric);
      expect(s.maxDisplayDistanceKm, 100.0);
      expect(s.smoothingLevel, SmoothingLevel.medium);
      expect(s.labelDensity, LabelDensity.normal);
      expect(s.horizonLineOpacity, 0.8);
      expect(s.horizonLineWidth, 2.0);
      expect(s.showDistanceOnLabels, true);
      expect(s.themeMode, ThemeMode.system);
    });
  });

  group('UnitSystem', () {
    test('has two values', () {
      expect(UnitSystem.values.length, 2);
    });

    test('each has a label', () {
      for (final unit in UnitSystem.values) {
        expect(unit.label, isNotEmpty);
      }
    });
  });

  group('LabelDensity', () {
    test('has three values', () {
      expect(LabelDensity.values.length, 3);
    });

    test('each has label and description', () {
      for (final density in LabelDensity.values) {
        expect(density.label, isNotEmpty);
        expect(density.description, isNotEmpty);
      }
    });
  });
}
