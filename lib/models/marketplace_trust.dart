import 'dart:typed_data';

class MarketplaceReview {
  const MarketplaceReview({
    required this.id,
    required this.vendorId,
    required this.buyerEmail,
    required this.buyerName,
    this.buyerUid,
    this.orderId,
    required this.rating,
    required this.comment,
    required this.isVerifiedPurchase,
    required this.createdAt,
    this.buyerPhotoUrl,
    this.buyerPhotoBytes,
  });

  final String id;
  final String vendorId;
  final String buyerEmail;
  final String buyerName;
  final String? buyerUid;
  final String? buyerPhotoUrl;
  final Uint8List? buyerPhotoBytes;
  final String? orderId;
  final int rating;
  final String comment;
  final bool isVerifiedPurchase;
  final DateTime createdAt;
}

class VendorTrustSummary {
  const VendorTrustSummary({
    required this.verificationStatus,
    required this.averageRating,
    required this.reviewCount,
    required this.reviews,
  });

  final String verificationStatus;
  final double averageRating;
  final int reviewCount;
  final List<MarketplaceReview> reviews;

  Map<int, int> get ratingBreakdown => Map.unmodifiable({
    for (var rating = 1; rating <= 5; rating++)
      rating: reviews.where((review) => review.rating == rating).length,
  });
}
