import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/models/landmark.dart';
import 'package:peakline_app/ui/widgets/toggle_panel.dart';

void main() {
  group('LayerVisibility', () {
    test('defaults: all layers on, all categories enabled', () {
      const visibility = LayerVisibility();
      expect(visibility.showHorizon, isTrue);
      expect(visibility.showPeaks, isTrue);
      expect(visibility.showLandmarks, isTrue);
      expect(
        visibility.enabledLandmarkCategories,
        containsAll([
          LandmarkCategory.hut,
          LandmarkCategory.lake,
          LandmarkCategory.pass,
          LandmarkCategory.glacier,
          LandmarkCategory.town,
        ]),
      );
    });

    test('copyWith preserves unmodified fields', () {
      const original = LayerVisibility();
      final modified = original.copyWith(showHorizon: false);
      expect(modified.showHorizon, isFalse);
      expect(modified.showPeaks, isTrue);
      expect(modified.showLandmarks, isTrue);
    });
  });

  group('LayerVisibilityNotifier', () {
    test('toggleHorizon flips horizon visibility', () {
      final notifier = LayerVisibilityNotifier();
      expect(notifier.state.showHorizon, isTrue);
      notifier.toggleHorizon();
      expect(notifier.state.showHorizon, isFalse);
      notifier.toggleHorizon();
      expect(notifier.state.showHorizon, isTrue);
    });

    test('togglePeaks flips peak visibility', () {
      final notifier = LayerVisibilityNotifier();
      expect(notifier.state.showPeaks, isTrue);
      notifier.togglePeaks();
      expect(notifier.state.showPeaks, isFalse);
    });

    test('toggleLandmarks flips landmark visibility', () {
      final notifier = LayerVisibilityNotifier();
      expect(notifier.state.showLandmarks, isTrue);
      notifier.toggleLandmarks();
      expect(notifier.state.showLandmarks, isFalse);
    });

    test('toggleLandmarkCategory adds/removes category', () {
      final notifier = LayerVisibilityNotifier();
      // Hut is enabled by default
      expect(
        notifier.state.enabledLandmarkCategories,
        contains(LandmarkCategory.hut),
      );

      // Toggle off
      notifier.toggleLandmarkCategory(LandmarkCategory.hut);
      expect(
        notifier.state.enabledLandmarkCategories,
        isNot(contains(LandmarkCategory.hut)),
      );

      // Toggle back on
      notifier.toggleLandmarkCategory(LandmarkCategory.hut);
      expect(
        notifier.state.enabledLandmarkCategories,
        contains(LandmarkCategory.hut),
      );
    });

    test('toggling one category does not affect others', () {
      final notifier = LayerVisibilityNotifier();
      notifier.toggleLandmarkCategory(LandmarkCategory.lake);
      // Lake removed, but hut still there
      expect(
        notifier.state.enabledLandmarkCategories,
        contains(LandmarkCategory.hut),
      );
      expect(
        notifier.state.enabledLandmarkCategories,
        isNot(contains(LandmarkCategory.lake)),
      );
    });
  });
}
