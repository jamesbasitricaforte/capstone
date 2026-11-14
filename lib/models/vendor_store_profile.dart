import 'dart:typed_data';

class VendorStoreProfile {
  const VendorStoreProfile({
    required this.id,
    required this.storeName,
    this.ownerName,
    this.description,
    this.businessType,
    this.address,
    this.zipCode,
    this.phone,
    this.latitude,
    this.longitude,
    this.profilePhotoUrl,
    this.profilePhotoBytes,
  });

  factory VendorStoreProfile.fromJson(String id, Map<String, dynamic> json) =>
      VendorStoreProfile(
        id: id,
        storeName:
            json['store_name'] as String? ??
            json['name'] as String? ??
            'Vendor store',
        ownerName: json['owner_name'] as String?,
        description: json['description'] as String?,
        businessType: json['business_type'] as String?,
        address: json['address'] as String?,
        zipCode: json['zip_code'] as String?,
        phone: json['phone'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        profilePhotoUrl: json['profile_photo_url'] as String?,
        profilePhotoBytes: json['profile_photo_bytes'] is Uint8List
            ? json['profile_photo_bytes'] as Uint8List
            : null,
      );

  final String id;
  final String storeName;
  final String? ownerName;
  final String? description;
  final String? businessType;
  final String? address;
  final String? zipCode;
  final String? phone;
  final double? latitude;
  final double? longitude;
  final String? profilePhotoUrl;
  final Uint8List? profilePhotoBytes;
}
