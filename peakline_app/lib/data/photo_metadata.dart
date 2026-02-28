class PhotoMetadata {
  const PhotoMetadata({
    required this.path,
    required this.latitude,
    required this.longitude,
  });

  final String path;
  final double? latitude;
  final double? longitude;

  bool get hasGps => latitude != null && longitude != null;
}

