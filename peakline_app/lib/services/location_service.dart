/// Location service — reads GPS position from the phone.
///
/// This tells the app WHERE you are on Earth (latitude, longitude, altitude)
/// so it knows which elevation data to load and where to compute the
/// horizon from.
///
/// GPS readings need two things to work:
///   1. The user has granted location permission
///   2. Location services are enabled on the device
///
/// This service handles checking both, requesting permission if needed,
/// and streaming position updates via Riverpod.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/sensor_data.dart';

// -----------------------------------------------------------------------
//  Location Service
// -----------------------------------------------------------------------

/// Service that manages GPS position reading and permissions.
class LocationService {
  StreamSubscription<Position>? _positionSub;
  final _locationController = StreamController<DeviceLocation>.broadcast();

  /// Stream of GPS location updates.
  Stream<DeviceLocation> get locationStream => _locationController.stream;

  /// Check if we have location permission, and request it if not.
  ///
  /// Returns a human-readable error message if something is wrong,
  /// or null if everything is OK.
  ///
  /// You should call this before starting location updates, and show
  /// the error message to the user if it returns one.
  Future<String?> checkAndRequestPermission() async {
    // First check if location services are turned on
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. '
          'Please enable GPS in your device settings.';
    }

    // Check current permission status
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // Ask the user for permission
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission was denied. '
            'PeakLine needs GPS to know where you are.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return 'Location permission is permanently denied. '
          'Please enable it in your device settings under App Permissions.';
    }

    // Permission granted (either "always" or "while in use")
    return null;
  }

  /// Get the current position once (not a stream).
  ///
  /// Useful for a one-time lookup, like when analyzing a photo.
  /// Returns null if we can't get a position.
  Future<DeviceLocation?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return _positionToLocation(position);
    } catch (e) {
      return null;
    }
  }

  /// Start streaming GPS position updates.
  ///
  /// Updates come roughly every 1-5 seconds depending on movement and
  /// GPS signal quality. Each update triggers a rebuild of any widget
  /// watching the location provider.
  void startListening() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Only notify us if position changed by at least 5 meters.
        // This prevents unnecessary updates when standing still.
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        _locationController.add(_positionToLocation(position));
      },
      onError: (error) {
        _locationController.addError(error);
      },
    );
  }

  /// Stop listening to GPS (saves battery).
  void stopListening() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  /// Clean up resources.
  void dispose() {
    stopListening();
    _locationController.close();
  }

  /// Convert a geolocator Position to our DeviceLocation model.
  DeviceLocation _positionToLocation(Position position) {
    return DeviceLocation(
      latitudeDeg: position.latitude,
      longitudeDeg: position.longitude,
      altitudeM: position.altitude,
      accuracyM: position.accuracy,
    );
  }
}

// -----------------------------------------------------------------------
//  Riverpod providers
// -----------------------------------------------------------------------

/// Provider that creates and manages the LocationService lifecycle.
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for live GPS location.
///
/// Before watching this provider, make sure to call
/// `ref.read(locationServiceProvider).checkAndRequestPermission()`
/// to ensure we have permission.
///
/// Example:
/// ```dart
/// final location = ref.watch(deviceLocationProvider);
/// location.when(
///   data: (loc) => Text('${loc.latitudeDeg.toStringAsFixed(4)}°N'),
///   loading: () => Text('Getting GPS fix...'),
///   error: (e, s) => Text('GPS error: $e'),
/// );
/// ```
final deviceLocationProvider = StreamProvider<DeviceLocation>((ref) {
  final service = ref.watch(locationServiceProvider);
  service.startListening();
  ref.onDispose(() => service.stopListening());
  return service.locationStream;
});
