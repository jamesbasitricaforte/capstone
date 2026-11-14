import 'dart:typed_data';

bool isHostedMediaUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

class ListingMediaAsset {
  const ListingMediaAsset({
    required this.fileName,
    required this.contentType,
    required this.isVideo,
    this.path,
    this.bytes,
  });

  final String fileName;
  final String contentType;
  final bool isVideo;
  final String? path;
  final Uint8List? bytes;
}

class ProduceListing {
  const ProduceListing({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.unit,
    required this.quantity,
    required this.condition,
    required this.vendor,
    required this.vendorInitials,
    required this.location,
    this.distanceKm,
    required this.imageUrl,
    this.ownerEmail,
    this.ownerUid,
    this.imageBytes,
    this.imageFileName,
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.pendingMedia = const [],
    this.latitude,
    this.longitude,
    this.postedAt,
    this.justPosted = false,
    this.description = '',
    this.isMine = false,
  });

  factory ProduceListing.fromJson(Map<String, dynamic> json) {
    final quantity = json['quantity'];
    final imageUrls = _stringList(json['image_urls']);
    final videoUrls = _stringList(json['video_urls']);
    return ProduceListing(
      id: json['id'].toString(),
      name: json['name'] as String,
      category: json['category'] as String,
      price: (json['price'] as num).round(),
      unit: json['unit'] as String,
      quantity: quantity.toString(),
      condition: json['condition'] as String? ?? 'Fresh',
      vendor: json['vendor'] as String? ?? 'Local vendor',
      vendorInitials: json['vendor_initials'] as String? ?? '',
      location: json['location'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      imageUrl: imageUrls.isNotEmpty
          ? imageUrls.first
          : json['image_url'] as String? ?? '',
      imageBytes: json['image_bytes'] is Uint8List
          ? json['image_bytes'] as Uint8List
          : null,
      ownerEmail: json['owner_email'] as String?,
      ownerUid: json['owner_uid'] as String?,
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      postedAt: switch (json['posted_at']) {
        final DateTime dateTime => dateTime,
        final String value => DateTime.tryParse(value),
        _ => null,
      },
      justPosted: json['just_posted'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      isMine: json['is_mine'] as bool? ?? false,
    );
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  final String id;
  final String name;
  final String category;
  final int price;
  final String unit;
  final String quantity;
  final String condition;
  final String vendor;
  final String vendorInitials;
  final String location;
  final double? distanceKm;
  final String imageUrl;
  final String? ownerEmail;
  final String? ownerUid;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final List<ListingMediaAsset> pendingMedia;
  final double? latitude;
  final double? longitude;
  final DateTime? postedAt;
  final bool justPosted;
  final String description;
  final bool isMine;

  String get priceLabel => '₱$price';

  String get inventoryLabel => '$quantity $unit';

  String? get postedAtLabel {
    final localTime = postedAt?.toLocal();
    if (localTime == null) return null;
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${localTime.year}-${twoDigits(localTime.month)}-'
        '${twoDigits(localTime.day)} ${twoDigits(localTime.hour)}:'
        '${twoDigits(localTime.minute)}:${twoDigits(localTime.second)}';
  }
}
