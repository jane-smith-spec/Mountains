/// Toggle panel — floating buttons to turn AR overlay layers on/off.
///
/// The panel lets users independently control:
///   - Horizon topo line
///   - Peak labels
///   - Landmark pins (by category)
///
/// State is managed via Riverpod so all widgets react instantly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/landmark.dart';

// -----------------------------------------------------------------------
//  Layer visibility state
// -----------------------------------------------------------------------

/// Which overlay layers are currently visible.
class LayerVisibility {
  const LayerVisibility({
    this.showHorizon = true,
    this.showPeaks = true,
    this.showLandmarks = true,
    this.enabledLandmarkCategories = const {
      LandmarkCategory.hut,
      LandmarkCategory.lake,
      LandmarkCategory.pass,
      LandmarkCategory.glacier,
      LandmarkCategory.town,
    },
  });

  final bool showHorizon;
  final bool showPeaks;
  final bool showLandmarks;
  final Set<LandmarkCategory> enabledLandmarkCategories;

  LayerVisibility copyWith({
    bool? showHorizon,
    bool? showPeaks,
    bool? showLandmarks,
    Set<LandmarkCategory>? enabledLandmarkCategories,
  }) {
    return LayerVisibility(
      showHorizon: showHorizon ?? this.showHorizon,
      showPeaks: showPeaks ?? this.showPeaks,
      showLandmarks: showLandmarks ?? this.showLandmarks,
      enabledLandmarkCategories:
          enabledLandmarkCategories ?? this.enabledLandmarkCategories,
    );
  }
}

/// Riverpod notifier for layer visibility state.
class LayerVisibilityNotifier extends StateNotifier<LayerVisibility> {
  LayerVisibilityNotifier() : super(const LayerVisibility());

  void toggleHorizon() =>
      state = state.copyWith(showHorizon: !state.showHorizon);

  void togglePeaks() =>
      state = state.copyWith(showPeaks: !state.showPeaks);

  void toggleLandmarks() =>
      state = state.copyWith(showLandmarks: !state.showLandmarks);

  void toggleLandmarkCategory(LandmarkCategory category) {
    final current = Set<LandmarkCategory>.from(state.enabledLandmarkCategories);
    if (current.contains(category)) {
      current.remove(category);
    } else {
      current.add(category);
    }
    state = state.copyWith(enabledLandmarkCategories: current);
  }
}

/// Provider for layer visibility state.
final layerVisibilityProvider =
    StateNotifierProvider<LayerVisibilityNotifier, LayerVisibility>(
  (ref) => LayerVisibilityNotifier(),
);

// -----------------------------------------------------------------------
//  Toggle Panel Widget
// -----------------------------------------------------------------------

/// Floating panel with toggle buttons for each overlay layer.
///
/// Positioned in the top-right corner of the live view, this panel
/// lets users quickly turn layers on and off without leaving the AR view.
class TogglePanel extends ConsumerStatefulWidget {
  const TogglePanel({super.key});

  @override
  ConsumerState<TogglePanel> createState() => _TogglePanelState();
}

class _TogglePanelState extends ConsumerState<TogglePanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibility = ref.watch(layerVisibilityProvider);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main toggle buttons (always visible)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toggleButton(
                icon: Icons.show_chart,
                label: 'Topo',
                isOn: visibility.showHorizon,
                onTap: () => ref
                    .read(layerVisibilityProvider.notifier)
                    .toggleHorizon(),
              ),
              const SizedBox(width: 4),
              _toggleButton(
                icon: Icons.flag,
                label: 'Peaks',
                isOn: visibility.showPeaks,
                onTap: () => ref
                    .read(layerVisibilityProvider.notifier)
                    .togglePeaks(),
              ),
              const SizedBox(width: 4),
              _toggleButton(
                icon: Icons.place,
                label: 'POI',
                isOn: visibility.showLandmarks,
                onTap: () => ref
                    .read(layerVisibilityProvider.notifier)
                    .toggleLandmarks(),
              ),
              const SizedBox(width: 4),
              // Expand/collapse for landmark categories
              _toggleButton(
                icon: _expanded ? Icons.expand_less : Icons.expand_more,
                label: '',
                isOn: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
                compact: true,
              ),
            ],
          ),

          // Expanded landmark category toggles
          if (_expanded && visibility.showLandmarks) ...[
            const SizedBox(height: 4),
            _buildCategoryToggles(visibility),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryToggles(LayerVisibility visibility) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: LandmarkCategory.values.map((cat) {
          final isOn = visibility.enabledLandmarkCategories.contains(cat);
          return GestureDetector(
            onTap: () => ref
                .read(layerVisibilityProvider.notifier)
                .toggleLandmarkCategory(cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isOn
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isOn ? Colors.white54 : Colors.white24,
                  width: 0.5,
                ),
              ),
              child: Text(
                cat.label,
                style: TextStyle(
                  color: isOn ? Colors.white : Colors.white38,
                  fontSize: 10,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required String label,
    required bool isOn,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isOn
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOn ? Colors.white54 : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isOn ? Colors.white : Colors.white38,
              size: 16,
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isOn ? Colors.white : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
