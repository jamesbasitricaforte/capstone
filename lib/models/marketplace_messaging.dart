import 'dart:typed_data';

class MarketplaceConversation {
  const MarketplaceConversation({
    required this.id,
    required this.listingId,
    required this.listingName,
    required this.buyerUid,
    required this.vendorUid,
    required this.buyerLabel,
    required this.vendorLabel,
    required this.updatedAt,
    this.lastMessage = '',
    this.lastMessageSenderUid,
    this.buyerPhotoUrl,
    this.vendorPhotoUrl,
    this.buyerPhotoBytes,
    this.vendorPhotoBytes,
    this.hiddenBy = const [],
  });

  final String id;
  final String listingId;
  final String listingName;
  final String buyerUid;
  final String vendorUid;
  final String buyerLabel;
  final String vendorLabel;
  final DateTime updatedAt;
  final String lastMessage;
  final String? lastMessageSenderUid;
  final String? buyerPhotoUrl;
  final String? vendorPhotoUrl;
  final Uint8List? buyerPhotoBytes;
  final Uint8List? vendorPhotoBytes;
  final List<String> hiddenBy;
}

class MarketplaceMessage {
  const MarketplaceMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
    this.imageUrl,
    this.imageBytes,
  });

  final String id;
  final String senderUid;
  final String text;
  final DateTime createdAt;
  final String? imageUrl;
  final Uint8List? imageBytes;
}
