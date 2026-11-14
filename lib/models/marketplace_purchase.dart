import 'produce_listing.dart';

class MarketplaceCartItem {
  const MarketplaceCartItem({
    required this.listing,
    required this.quantity,
    this.unitPrice,
    this.vendorUid,
    this.orderDocumentId,
    this.status = '',
  });

  factory MarketplaceCartItem.fromJson(Map<String, dynamic> json) =>
      MarketplaceCartItem(
        listing: ProduceListing.fromJson(
          json['listing'] as Map<String, dynamic>,
        ),
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unit_price'] as num?)?.toInt(),
        vendorUid: json['vendor_uid'] as String?,
        orderDocumentId: json['order_document_id'] as String?,
        status: json['status'] as String? ?? '',
      );

  final ProduceListing listing;
  final int quantity;
  final int? unitPrice;
  final String? vendorUid;
  final String? orderDocumentId;
  final String status;

  int get subtotal => (unitPrice ?? listing.price) * quantity;
}

class ProduceReservation {
  const ProduceReservation({
    required this.id,
    required this.listing,
    required this.quantity,
    required this.buyerEmail,
    required this.createdAt,
    this.totalAmount,
  });

  factory ProduceReservation.fromJson(Map<String, dynamic> json) =>
      ProduceReservation(
        id: json['id'].toString(),
        listing: ProduceListing.fromJson(
          json['listing'] as Map<String, dynamic>,
        ),
        quantity: (json['quantity'] as num).toInt(),
        buyerEmail: json['buyer_email'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        totalAmount: (json['total'] as num?)?.toInt(),
      );

  final String id;
  final ProduceListing listing;
  final int quantity;
  final String buyerEmail;
  final DateTime createdAt;
  final int? totalAmount;

  int get total => totalAmount ?? listing.price * quantity;
}

class ProduceOrder {
  const ProduceOrder({
    required this.id,
    required this.items,
    required this.buyerEmail,
    required this.createdAt,
    this.totalAmount,
    this.status = 'placed',
    this.buyerUid,
  });

  factory ProduceOrder.fromJson(Map<String, dynamic> json) => ProduceOrder(
    id: json['id'].toString(),
    items: (json['items'] as List<dynamic>)
        .map(
          (item) => MarketplaceCartItem.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    buyerEmail: json['buyer_email'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    totalAmount: (json['total'] as num?)?.toInt(),
    status: json['status'] as String? ?? 'placed',
    buyerUid: json['buyer_uid'] as String?,
  );

  final String id;
  final List<MarketplaceCartItem> items;
  final String buyerEmail;
  final DateTime createdAt;
  final int? totalAmount;
  final String status;
  final String? buyerUid;

  int get total =>
      totalAmount ?? items.fold(0, (sum, item) => sum + item.subtotal);
}
