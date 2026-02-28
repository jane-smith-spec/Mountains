/// Landmark pin widget — a small marker for points of interest.
///
/// Landmarks (huts, lakes, passes, etc.) are shown with a category
/// icon and name. They're smaller than peak flags to avoid clutter.
library;

import 'package:flutter/material.dart';

import '../../models/landmark.dart';
import '../../services/peak_visibility_service.dart';

/// Displays a landmark marker at its projected screen position.
class LandmarkPin extends StatelessWidget {
  const LandmarkPin({
    super.key,
    required this.visibleLandmark,
  });

  final VisibleLandmark visibleLandmark;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: visibleLandmark.screenPoint.x - 50,
      top: visibleLandmark.screenPoint.y - 30,
      child: SizedBox(
        width: 100,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _iconForCategory(visibleLandmark.landmark.category),
                color: _colorForCategory(visibleLandmark.landmark.category),
                size: 12,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  visibleLandmark.landmark.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForCategory(LandmarkCategory category) {
    return switch (category) {
      LandmarkCategory.hut => Icons.house,
      LandmarkCategory.lake => Icons.water,
      LandmarkCategory.pass => Icons.swap_calls,
      LandmarkCategory.glacier => Icons.ac_unit,
      LandmarkCategory.town => Icons.location_city,
      LandmarkCategory.other => Icons.place,
    };
  }

  Color _colorForCategory(LandmarkCategory category) {
    return switch (category) {
      LandmarkCategory.hut => const Color(0xFFFFAA00),
      LandmarkCategory.lake => const Color(0xFF4FC3F7),
      LandmarkCategory.pass => const Color(0xFF81C784),
      LandmarkCategory.glacier => const Color(0xFFB3E5FC),
      LandmarkCategory.town => const Color(0xFFFFCC80),
      LandmarkCategory.other => const Color(0xFFBDBDBD),
    };
  }
}
