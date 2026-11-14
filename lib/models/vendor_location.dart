class VendorLocation {
  const VendorLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.businessType,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? businessType;

  factory VendorLocation.fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Vendor map coordinates are invalid.');
    }

    return VendorLocation(
      id: json['id'].toString(),
      name: json['name'] as String? ?? 'Local vendor',
      businessType: json['business_type'] as String?,
      address: json['address'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  }
}
