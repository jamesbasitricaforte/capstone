import 'dart:async';
import 'dart:typed_data';

import '../models/marketplace_messaging.dart';
import '../models/marketplace_purchase.dart';
import '../models/produce_listing.dart';

enum MarketplaceNotificationType { listing, purchase, reservation }

class MarketplaceNotification {
  const MarketplaceNotification({
    required this.id,
    required this.createdAt,
    this.type = MarketplaceNotificationType.listing,
    this.listing,
    this.buyerName,
    this.quantity,
    this.total,
    this.recipientUid,
    this.targetRole,
  });

  factory MarketplaceNotification.fromJson(Map<String, dynamic> json) =>
      MarketplaceNotification(
        id: json['id'].toString(),
        type: MarketplaceNotificationType.values.firstWhere(
          (type) => type.name == json['type'],
          orElse: () => MarketplaceNotificationType.listing,
        ),
        listing: json['listing'] is Map
            ? ProduceListing.fromJson(
                Map<String, dynamic>.from(json['listing'] as Map),
              )
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        buyerName: json['buyer_name'] as String?,
        quantity: (json['quantity'] as num?)?.toInt(),
        total: (json['total'] as num?)?.toInt(),
        recipientUid: json['recipient_uid'] as String?,
        targetRole: json['target_role'] as String?,
      );

  final String id;
  final DateTime createdAt;
  final MarketplaceNotificationType type;
  final ProduceListing? listing;
  final String? buyerName;
  final int? quantity;
  final int? total;
  final String? recipientUid;
  final String? targetRole;

  String get title => switch (type) {
    MarketplaceNotificationType.listing => 'Fresh produce just posted',
    MarketplaceNotificationType.purchase => 'New purchase',
    MarketplaceNotificationType.reservation => 'New reservation',
  };

  String get message {
    final produce = listing;
    if (type == MarketplaceNotificationType.listing) {
      if (produce == null) return 'A vendor posted a new listing.';
      return '${produce.name} · ${produce.priceLabel}/${produce.unit} · ${produce.vendor}';
    }
    if (produce == null) return 'A buyer placed an order.';
    final action = type == MarketplaceNotificationType.purchase
        ? 'purchased'
        : 'reserved';
    final buyer = buyerName?.trim();
    final buyerText = buyer == null || buyer.isEmpty ? 'A buyer' : buyer;
    final count = quantity ?? 1;
    final amount = total == null ? '' : ' · Total ₱$total';
    return '$buyerText $action $count ${produce.unit} of ${produce.name}$amount';
  }

  String get timeLabel {
    final localTime = createdAt.toLocal();
    final now = DateTime.now();
    final time =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    if (localTime.year == now.year &&
        localTime.month == now.month &&
        localTime.day == now.day) {
      return 'Today at $time';
    }
    return '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} at $time';
  }
}

class MarketplaceService {
  MarketplaceService();

  static final List<ProduceListing> _sampleListings = [
    const ProduceListing(
      id: 'tomatoes',
      name: 'Fresh Tomatoes',
      category: 'Vegetables',
      price: 40,
      unit: 'kg',
      quantity: '30',
      condition: 'Fresh',
      vendor: "Aling Rosa's Produce",
      vendorInitials: 'AR',
      location: 'Poblacion Market',
      imageUrl: 'https://images.unsplash.com/photo-1765862857099-cb03e1c3de07?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&q=85&w=1000&h=700',
      justPosted: true,
      description: 'Vine-ripened tomatoes harvested this morning. Arrange your preferred quantity and pickup directly with the vendor.',
    ),
    const ProduceListing(
      id: 'bananas',
      name: 'Sweet Lakatan Bananas',
      category: 'Fruits',
      price: 75,
      unit: 'dozen',
      quantity: '18',
      condition: 'Fresh',
      vendor: "Mang Ben's Farm",
      vendorInitials: 'MB',
      location: 'San Roque',
      imageUrl: 'https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&q=85&w=1000&h=700',
      justPosted: true,
      description: 'Naturally sweet Lakatan bananas from a family-run farm in San Roque.',
    ),
    const ProduceListing(
      id: 'pechay',
      name: 'Crisp Pechay',
      category: 'Vegetables',
      price: 35,
      unit: 'bundle',
      quantity: '24',
      condition: 'Fresh',
      vendor: 'Green Basket',
      vendorInitials: 'GB',
      location: 'Central Market',
      imageUrl: 'https://images.unsplash.com/photo-1768199439172-08b8c55e683b?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&q=85&w=1000&h=700',
      description:
          'Tender, locally grown pechay picked at peak freshness this week.',
    ),
    const ProduceListing(
      id: 'mangoes',
      name: 'Ripe Carabao Mangoes',
      category: 'Fruits',
      price: 120,
      unit: 'kg',
      quantity: '12',
      condition: 'Fresh',
      vendor: "Lola Cely's Fruits",
      vendorInitials: 'LC',
      location: 'Rizal Street',
      imageUrl: 'https://images.unsplash.com/photo-1553279768-865429fa0078?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&q=85&w=1000&h=700',
      justPosted: true,
      description:
          'Sweet, golden Carabao mangoes from a neighborhood fruit grower.',
    ),
    const ProduceListing(
      id: 'eggplant',
      name: 'Native Eggplant',
      category: 'Vegetables',
      price: 55,
      unit: 'kg',
      quantity: '16',
      condition: 'Fresh',
      vendor: 'Baryo Harvest',
      vendorInitials: 'BH',
      location: 'North Market',
      imageUrl: 'https://images.pexels.com/photos/321551/pexels-photo-321551.jpeg?auto=compress&cs=tinysrgb&w=1000',
      justPosted: true,
      description:
          'Firm native eggplant, harvested locally and ready for pickup.',
    ),
    const ProduceListing(
      id: 'calamansi',
      name: 'Fresh Calamansi',
      category: 'Fruits',
      price: 65,
      unit: 'kg',
      quantity: '20',
      condition: 'Fresh',
      vendor: 'Citrus Corner',
      vendorInitials: 'CC',
      location: 'Poblacion Market',
      imageUrl: 'https://images.unsplash.com/photo-1590502593747-42a996133562?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&q=85&w=1000&h=700',
      description:
          'Bright, juicy calamansi grown nearby and sold fresh by the kilo.',
    ),
  ];

  static final List<MarketplaceNotification> _notifications = [];
  static final Map<String, DateTime> _notificationReadAt = {};
  static final Map<String, int> _remainingInventory = {};
  static final Map<String, Map<String, int>> _buyerCarts = {};
  static final List<ProduceReservation> _reservations = [];
  static final List<ProduceOrder> _orders = [];
  static final Set<String> _hiddenBuyerOrders = {};
  static final Map<String, String> _vendorOrderStatuses = {};
  static final Map<String, MarketplaceConversation> _conversations = {};
  static final Map<String, StreamController<List<MarketplaceConversation>>>
  _conversationControllers = {};
  static final Map<String, List<MarketplaceMessage>> _messages = {};
  static final Map<String, Set<String>> _hiddenMessages = {};
  static final Map<String, StreamController<List<MarketplaceMessage>>>
  _messageControllers = {};
  static final StreamController<ProduceListing> _listingController =
      StreamController<ProduceListing>.broadcast();
  static final StreamController<String> _listingRemovalController =
      StreamController<String>.broadcast();
  static final StreamController<MarketplaceNotification>
  _notificationController =
      StreamController<MarketplaceNotification>.broadcast();
  static final StreamController<String> _notificationRemovalController =
      StreamController<String>.broadcast();

  Stream<ProduceListing> get listingUpdates => _listingController.stream;

  Stream<String> get listingRemovals => _listingRemovalController.stream;

  Stream<MarketplaceNotification> get notificationUpdates =>
      _notificationController.stream;

  Stream<String> get notificationRemovals =>
      _notificationRemovalController.stream;

  Future<List<ProduceListing>> loadListings() async =>
      List<ProduceListing>.unmodifiable(
        _sampleListings.map(_withAvailableQuantity),
      );

  Future<List<ProduceListing>> loadPublicListings() async =>
      List<ProduceListing>.unmodifiable(
        _sampleListings.map(
          (listing) => publicListing(_withAvailableQuantity(listing)),
        ),
      );

  ProduceListing publicListing(ProduceListing listing) => ProduceListing(
    id: listing.id,
    name: listing.name,
    category: listing.category,
    price: listing.price,
    unit: listing.unit,
    quantity: listing.quantity,
    condition: listing.condition,
    vendor: listing.vendor,
    vendorInitials: listing.vendorInitials,
    location: listing.location,
    distanceKm: listing.distanceKm,
    imageUrl: listing.imageUrl,
    imageBytes: listing.imageBytes,
    imageFileName: listing.imageFileName,
    imageUrls: listing.imageUrls,
    videoUrls: listing.videoUrls,
    pendingMedia: listing.pendingMedia,
    ownerUid: listing.ownerUid,
    latitude: listing.latitude,
    longitude: listing.longitude,
    postedAt: listing.postedAt,
    justPosted: listing.justPosted,
    description: listing.description,
  );

  Future<List<MarketplaceNotification>> loadNotifications() async =>
      List<MarketplaceNotification>.unmodifiable(_notifications);

  List<MarketplaceNotification> notificationsFor({
    required String userId,
    required String role,
  }) {
    final readAt =
        _notificationReadAt[userId] ?? DateTime.fromMillisecondsSinceEpoch(0);
    final notifications =
        _notifications.where((notification) {
          return notification.targetRole == role &&
              (notification.recipientUid == null ||
                  notification.recipientUid == userId) &&
              notification.createdAt.isAfter(readAt);
        }).toList()..sort(
          (first, second) => second.createdAt.compareTo(first.createdAt),
        );
    return List.unmodifiable(notifications);
  }

  void markNotificationsRead(String userId) {
    _notificationReadAt[userId] = DateTime.now();
  }

  Future<void> addListing(ProduceListing listing) async {
    _sampleListings.insert(0, listing);
    _remainingInventory[listing.id] = _parseInventory(listing.quantity);
    _listingController.add(listing);

    final notification = MarketplaceNotification(
      id: 'notification-${listing.id}',
      listing: listing,
      createdAt: DateTime.now(),
      targetRole: 'Buyer',
    );
    _notifications.insert(0, notification);
    _notificationController.add(notification);
  }

  Future<void> updateListing({
    required ProduceListing listing,
    required String ownerEmail,
  }) async {
    final index = _sampleListings.indexWhere(
      (item) => item.id == listing.id && item.ownerEmail == ownerEmail,
    );
    if (index == -1) {
      throw StateError('This listing does not belong to your vendor account.');
    }
    final quantity = _parseInventory(listing.quantity);
    if (listing.price < 0 || quantity < 0) {
      throw ArgumentError('Price and stock must not be negative.');
    }
    _sampleListings[index] = listing;
    _remainingInventory[listing.id] = quantity;
    _listingController.add(listing);
  }

  Future<bool> repostListing({
    required String listingId,
    required String ownerEmail,
  }) async {
    final index = _sampleListings.indexWhere(
      (listing) => listing.id == listingId && listing.ownerEmail == ownerEmail,
    );
    if (index == -1) return false;

    final listing = _sampleListings.removeAt(index);
    final reposted = ProduceListing(
      id: listing.id,
      name: listing.name,
      category: listing.category,
      price: listing.price,
      unit: listing.unit,
      quantity: listing.quantity,
      condition: listing.condition,
      vendor: listing.vendor,
      vendorInitials: listing.vendorInitials,
      location: listing.location,
      distanceKm: listing.distanceKm,
      imageUrl: listing.imageUrl,
      ownerEmail: listing.ownerEmail,
      imageBytes: listing.imageBytes,
      imageFileName: listing.imageFileName,
      imageUrls: listing.imageUrls,
      videoUrls: listing.videoUrls,
      pendingMedia: listing.pendingMedia,
      latitude: listing.latitude,
      longitude: listing.longitude,
      postedAt: DateTime.now(),
      justPosted: true,
      description: listing.description,
      isMine: listing.isMine,
    );
    _sampleListings.insert(0, reposted);
    _listingController.add(reposted);
    return true;
  }

  Future<bool> removeListing({
    required String listingId,
    required String ownerEmail,
  }) async {
    final index = _sampleListings.indexWhere(
      (listing) => listing.id == listingId && listing.ownerEmail == ownerEmail,
    );
    if (index == -1) return false;

    _sampleListings.removeAt(index);
    _remainingInventory.remove(listingId);
    for (final cart in _buyerCarts.values) {
      cart.remove(listingId);
    }
    _listingRemovalController.add(listingId);

    final notificationIds = _notifications
        .where((notification) => notification.listing?.id == listingId)
        .map((notification) => notification.id)
        .toList();
    _notifications.removeWhere(
      (notification) => notification.listing?.id == listingId,
    );
    for (final notificationId in notificationIds) {
      _notificationRemovalController.add(notificationId);
    }
    return true;
  }

  int availableQuantity(ProduceListing listing) => _remainingInventory
      .putIfAbsent(listing.id, () => _parseInventory(listing.quantity));

  Future<List<MarketplaceCartItem>> loadCart(String buyerEmail) async {
    final cart = _buyerCarts.putIfAbsent(buyerEmail, () => {});
    final items = <MarketplaceCartItem>[];
    for (final entry in cart.entries) {
      final index = _sampleListings.indexWhere(
        (listing) => listing.id == entry.key,
      );
      if (index == -1) continue;
      items.add(
        MarketplaceCartItem(
          listing: _withAvailableQuantity(_sampleListings[index]),
          quantity: entry.value,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  Future<void> addToCart({
    required String buyerEmail,
    required ProduceListing listing,
    required int quantity,
  }) async {
    _validateQuantity(quantity);
    final currentListing = _findListing(listing.id);
    final cart = _buyerCarts.putIfAbsent(buyerEmail, () => {});
    final updatedQuantity = (cart[listing.id] ?? 0) + quantity;
    if (updatedQuantity > availableQuantity(currentListing)) {
      throw StateError('The requested quantity is not available.');
    }
    cart[listing.id] = updatedQuantity;
  }

  Future<void> updateCartQuantity({
    required String buyerEmail,
    required String listingId,
    required int quantity,
  }) async {
    _validateQuantity(quantity);
    final listing = _findListing(listingId);
    if (quantity > availableQuantity(listing)) {
      throw StateError('The requested quantity is not available.');
    }
    _buyerCarts.putIfAbsent(buyerEmail, () => <String, int>{})[listingId] =
        quantity;
  }

  Future<void> removeFromCart({
    required String buyerEmail,
    required String listingId,
  }) async {
    _buyerCarts[buyerEmail]?.remove(listingId);
  }

  Future<ProduceReservation> reserveListing({
    required String buyerEmail,
    required ProduceListing listing,
    required int quantity,
  }) async {
    _validateQuantity(quantity);
    _decrementInventory(listing.id, quantity);
    final reservation = ProduceReservation(
      id: 'reservation-${DateTime.now().microsecondsSinceEpoch}',
      listing: _withAvailableQuantity(listing),
      quantity: quantity,
      buyerEmail: buyerEmail,
      createdAt: DateTime.now(),
    );
    _reservations.insert(0, reservation);
    _notifyVendorActivity(
      id: reservation.id,
      type: MarketplaceNotificationType.reservation,
      listing: listing,
      buyerName: buyerEmail,
      quantity: quantity,
      total: listing.price * quantity,
      createdAt: reservation.createdAt,
    );
    return reservation;
  }

  Future<ProduceOrder> buyListing({
    required String buyerEmail,
    required ProduceListing listing,
    required int quantity,
  }) async {
    _validateQuantity(quantity);
    _decrementInventory(listing.id, quantity);
    final order = ProduceOrder(
      id: 'order-${DateTime.now().microsecondsSinceEpoch}',
      items: [
        MarketplaceCartItem(
          listing: _withAvailableQuantity(listing),
          quantity: quantity,
          vendorUid: listing.ownerUid,
          status: 'pending_vendor_confirmation',
        ),
      ],
      buyerEmail: buyerEmail,
      createdAt: DateTime.now(),
      status: 'pending_vendor_confirmation',
    );
    _orders.insert(0, order);
    _notifyVendorActivity(
      id: order.id,
      type: MarketplaceNotificationType.purchase,
      listing: listing,
      buyerName: buyerEmail,
      quantity: quantity,
      total: order.total,
      createdAt: order.createdAt,
    );
    return order;
  }

  Future<ProduceOrder> checkoutCart(String buyerEmail) async {
    final cart = _buyerCarts.putIfAbsent(buyerEmail, () => {});
    if (cart.isEmpty) {
      throw StateError('Your cart is empty.');
    }

    final cartItems = await loadCart(buyerEmail);
    for (final item in cartItems) {
      if (item.quantity > availableQuantity(item.listing)) {
        throw StateError(
          'The available quantity for ${item.listing.name} has changed.',
        );
      }
    }
    for (final item in cartItems) {
      _decrementInventory(item.listing.id, item.quantity);
    }

    final order = ProduceOrder(
      id: 'order-${DateTime.now().microsecondsSinceEpoch}',
      items: cartItems
          .map(
            (item) => MarketplaceCartItem(
              listing: item.listing,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              vendorUid: item.listing.ownerUid,
              status: 'pending_vendor_confirmation',
            ),
          )
          .toList(),
      buyerEmail: buyerEmail,
      createdAt: DateTime.now(),
      status: 'pending_vendor_confirmation',
    );
    _orders.insert(0, order);
    for (final item in order.items) {
      _notifyVendorActivity(
        id: '${order.id}-${item.listing.id}',
        type: MarketplaceNotificationType.purchase,
        listing: item.listing,
        buyerName: buyerEmail,
        quantity: item.quantity,
        total: item.subtotal,
        createdAt: order.createdAt,
      );
    }
    cart.clear();
    return order;
  }

  void _notifyVendorActivity({
    required String id,
    required MarketplaceNotificationType type,
    required ProduceListing listing,
    required String buyerName,
    required int quantity,
    required int total,
    required DateTime createdAt,
  }) {
    final vendorId = listing.ownerUid ?? listing.ownerEmail;
    if (vendorId == null || vendorId.isEmpty) return;
    final notification = MarketplaceNotification(
      id: 'notification-$id',
      type: type,
      listing: listing,
      buyerName: buyerName,
      quantity: quantity,
      total: total,
      recipientUid: vendorId,
      targetRole: 'Vendor',
      createdAt: createdAt,
    );
    _notifications.insert(0, notification);
    _notificationController.add(notification);
  }

  List<ProduceReservation> reservationsFor(String buyerEmail) =>
      List.unmodifiable(
        _reservations.where((item) => item.buyerEmail == buyerEmail),
      );

  Future<bool> cancelReservation({
    required String buyerEmail,
    required String reservationId,
  }) async {
    final reservationIndex = _reservations.indexWhere(
      (item) => item.id == reservationId && item.buyerEmail == buyerEmail,
    );
    if (reservationIndex == -1) return false;

    final reservation = _reservations[reservationIndex];
    final listingIndex = _sampleListings.indexWhere(
      (listing) => listing.id == reservation.listing.id,
    );
    if (listingIndex == -1) {
      _reservations.removeAt(reservationIndex);
      return true;
    }

    final listing = _sampleListings[listingIndex];
    _remainingInventory[listing.id] =
        availableQuantity(listing) + reservation.quantity;
    _reservations.removeAt(reservationIndex);
    _listingController.add(_withAvailableQuantity(listing));
    return true;
  }

  List<ProduceOrder> ordersFor(String buyerEmail) {
    final buyerOrders = _orders
        .where(
          (item) =>
              item.buyerEmail == buyerEmail &&
              !_hiddenBuyerOrders.contains(_buyerOrderKey(buyerEmail, item.id)),
        )
        .map((order) {
          final items = order.items.map((item) {
            final vendorEmail = item.listing.ownerEmail;
            return MarketplaceCartItem(
              listing: item.listing,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              vendorUid: item.vendorUid,
              orderDocumentId: item.orderDocumentId,
              status: vendorEmail == null
                  ? order.status
                  : _vendorOrderStatuses['${order.id}:${vendorEmail.toLowerCase()}'] ??
                        order.status,
            );
          }).toList();
          final itemStatuses = items.map((item) => item.status).toSet();
          return ProduceOrder(
            id: order.id,
            items: items,
            buyerEmail: order.buyerEmail,
            createdAt: order.createdAt,
            totalAmount: order.totalAmount,
            status: itemStatuses.length == 1
                ? itemStatuses.single
                : 'multiple statuses',
          );
        })
        .toList();
    return List.unmodifiable(buyerOrders);
  }

  bool hideOrderForBuyer({
    required String orderId,
    required String buyerEmail,
  }) {
    final ownsOrder = _orders.any(
      (order) => order.id == orderId && order.buyerEmail == buyerEmail,
    );
    if (!ownsOrder) return false;
    return _hiddenBuyerOrders.add(_buyerOrderKey(buyerEmail, orderId));
  }

  String _buyerOrderKey(String buyerEmail, String orderId) =>
      '${buyerEmail.toLowerCase()}:$orderId';

  bool updateOrderStatus({
    required String orderId,
    required String vendorEmail,
    required String status,
  }) {
    final order = _orders.where((item) => item.id == orderId).firstOrNull;
    if (order == null) return false;
    final vendorItems = order.items
        .where((item) => item.listing.ownerEmail == vendorEmail)
        .toList();
    if (vendorItems.isEmpty) return false;
    final key = '$orderId:${vendorEmail.toLowerCase()}';
    final currentStatus = _vendorOrderStatuses[key] ?? order.status;
    final isValidTransition =
        (currentStatus == 'pending_vendor_confirmation' &&
            (status == 'approved' || status == 'declined')) ||
        (currentStatus == 'approved' && status == 'completed');
    if (!isValidTransition) return false;
    _vendorOrderStatuses[key] = status;
    if (status == 'declined') {
      for (final item in vendorItems) {
        _remainingInventory.update(
          item.listing.id,
          (quantity) => quantity + item.quantity,
          ifAbsent: () =>
              (int.tryParse(item.listing.quantity) ?? 0) + item.quantity,
        );
      }
    }
    return true;
  }

  MarketplaceConversation putConversation(
    MarketplaceConversation conversation,
  ) {
    final existing = _conversations[conversation.id];
    if (existing == null) {
      _conversations[conversation.id] = conversation;
      _notifyConversationUpdate(conversation);
      return conversation;
    }
    final updated = MarketplaceConversation(
      id: existing.id,
      listingId: conversation.listingId,
      listingName: conversation.listingName,
      buyerUid: existing.buyerUid,
      vendorUid: existing.vendorUid,
      buyerLabel: conversation.buyerLabel,
      vendorLabel: conversation.vendorLabel,
      updatedAt: conversation.updatedAt,
      lastMessage: existing.lastMessage,
      lastMessageSenderUid: existing.lastMessageSenderUid,
      buyerPhotoUrl: conversation.buyerPhotoUrl ?? existing.buyerPhotoUrl,
      vendorPhotoUrl: conversation.vendorPhotoUrl ?? existing.vendorPhotoUrl,
      buyerPhotoBytes: conversation.buyerPhotoBytes ?? existing.buyerPhotoBytes,
      vendorPhotoBytes:
          conversation.vendorPhotoBytes ?? existing.vendorPhotoBytes,
      hiddenBy: conversation.hiddenBy,
    );
    _conversations[conversation.id] = updated;
    _notifyConversationUpdate(updated);
    return updated;
  }

  MarketplaceConversation? conversationForPair(
    String buyerUid,
    String vendorUid,
  ) {
    final matches =
        _conversations.values
            .where(
              (conversation) =>
                  conversation.buyerUid == buyerUid &&
                  conversation.vendorUid == vendorUid,
            )
            .toList()
          ..sort(
            (first, second) => second.updatedAt.compareTo(first.updatedAt),
          );
    return matches.firstOrNull;
  }

  bool hideConversationForUser({
    required String conversationId,
    required String userId,
  }) {
    final target = _conversations[conversationId];
    if (target == null ||
        (target.buyerUid != userId && target.vendorUid != userId)) {
      return false;
    }

    for (final entry in _conversations.entries.toList()) {
      final conversation = entry.value;
      if (conversation.buyerUid != target.buyerUid ||
          conversation.vendorUid != target.vendorUid ||
          conversation.hiddenBy.contains(userId)) {
        continue;
      }
      _conversations[entry.key] = _copyConversation(
        conversation,
        hiddenBy: [...conversation.hiddenBy, userId],
      );
    }
    _notifyConversationUpdate(target);
    return true;
  }

  void updateProfilePhotoForUser(
    String userId, {
    required String? photoUrl,
    required Uint8List? photoBytes,
  }) {
    for (final entry in _conversations.entries.toList()) {
      final conversation = entry.value;
      if (conversation.buyerUid != userId && conversation.vendorUid != userId) {
        continue;
      }
      final updatedConversation = MarketplaceConversation(
        id: conversation.id,
        listingId: conversation.listingId,
        listingName: conversation.listingName,
        buyerUid: conversation.buyerUid,
        vendorUid: conversation.vendorUid,
        buyerLabel: conversation.buyerLabel,
        vendorLabel: conversation.vendorLabel,
        updatedAt: conversation.updatedAt,
        lastMessage: conversation.lastMessage,
        lastMessageSenderUid: conversation.lastMessageSenderUid,
        buyerPhotoUrl: conversation.buyerUid == userId
            ? photoUrl
            : conversation.buyerPhotoUrl,
        vendorPhotoUrl: conversation.vendorUid == userId
            ? photoUrl
            : conversation.vendorPhotoUrl,
        buyerPhotoBytes: conversation.buyerUid == userId
            ? photoBytes
            : conversation.buyerPhotoBytes,
        vendorPhotoBytes: conversation.vendorUid == userId
            ? photoBytes
            : conversation.vendorPhotoBytes,
        hiddenBy: conversation.hiddenBy,
      );
      _conversations[entry.key] = updatedConversation;
      _notifyConversationUpdate(updatedConversation);
    }
  }

  List<MarketplaceConversation> conversationsFor(String userId) {
    final latestByPair = <String, MarketplaceConversation>{};
    for (final conversation in _conversations.values) {
      if (conversation.buyerUid != userId && conversation.vendorUid != userId) {
        continue;
      }
      final key = '${conversation.buyerUid}\u0000${conversation.vendorUid}';
      final existing = latestByPair[key];
      if (existing == null ||
          conversation.updatedAt.isAfter(existing.updatedAt)) {
        latestByPair[key] = conversation;
      }
    }
    return latestByPair.values
        .where((conversation) => !conversation.hiddenBy.contains(userId))
        .toList()
      ..sort((first, second) => second.updatedAt.compareTo(first.updatedAt));
  }

  Stream<List<MarketplaceConversation>> watchConversations(String userId) {
    final controller = _conversationControllers.putIfAbsent(
      userId,
      () => StreamController<List<MarketplaceConversation>>.broadcast(),
    );
    scheduleMicrotask(
      () => controller.add(List.unmodifiable(conversationsFor(userId))),
    );
    return controller.stream;
  }

  void _notifyConversationUpdate(MarketplaceConversation conversation) {
    for (final userId in [conversation.buyerUid, conversation.vendorUid]) {
      _conversationControllers[userId]?.add(
        List.unmodifiable(conversationsFor(userId)),
      );
    }
  }

  Stream<List<MarketplaceMessage>> watchMessages(
    String conversationId,
    String userId,
  ) {
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<MarketplaceMessage>>.broadcast(),
    );
    scheduleMicrotask(
      () => controller.add(_visibleMessages(conversationId, userId)),
    );
    return controller.stream;
  }

  void addMessage(
    String conversationId,
    MarketplaceMessage message,
    String userId,
  ) {
    _messages.putIfAbsent(conversationId, () => []).add(message);
    final conversation = _conversations[conversationId];
    if (conversation != null) {
      final updatedConversation = MarketplaceConversation(
        id: conversation.id,
        listingId: conversation.listingId,
        listingName: conversation.listingName,
        buyerUid: conversation.buyerUid,
        vendorUid: conversation.vendorUid,
        buyerLabel: conversation.buyerLabel,
        vendorLabel: conversation.vendorLabel,
        updatedAt: message.createdAt,
        lastMessage: message.text.isEmpty ? 'Photo' : message.text,
        lastMessageSenderUid: message.senderUid,
        buyerPhotoUrl: conversation.buyerPhotoUrl,
        vendorPhotoUrl: conversation.vendorPhotoUrl,
        buyerPhotoBytes: conversation.buyerPhotoBytes,
        vendorPhotoBytes: conversation.vendorPhotoBytes,
        hiddenBy: conversation.hiddenBy,
      );
      _conversations[conversationId] = updatedConversation;
      _notifyConversationUpdate(updatedConversation);
    }
    _messageControllers[conversationId]?.add(
      _visibleMessages(conversationId, userId),
    );
  }

  bool hideMessageForUser({
    required String conversationId,
    required String messageId,
    required String userId,
  }) {
    final conversation = _conversations[conversationId];
    if (conversation == null ||
        (conversation.buyerUid != userId && conversation.vendorUid != userId)) {
      return false;
    }
    final messages = _messages[conversationId];
    if (messages == null ||
        !messages.any((message) => message.id == messageId)) {
      return false;
    }
    final hiddenByUser = _hiddenMessages.putIfAbsent(
      '$conversationId:$userId',
      () => {},
    );
    if (!hiddenByUser.add(messageId)) return false;
    _messageControllers[conversationId]?.add(
      _visibleMessages(conversationId, userId),
    );
    return true;
  }

  List<MarketplaceMessage> _visibleMessages(
    String conversationId,
    String userId,
  ) {
    final hidden = _hiddenMessages['$conversationId:$userId'] ?? const {};
    return List.unmodifiable(
      (_messages[conversationId] ?? []).where(
        (message) => !hidden.contains(message.id),
      ),
    );
  }

  MarketplaceConversation _copyConversation(
    MarketplaceConversation conversation, {
    required List<String> hiddenBy,
  }) => MarketplaceConversation(
    id: conversation.id,
    listingId: conversation.listingId,
    listingName: conversation.listingName,
    buyerUid: conversation.buyerUid,
    vendorUid: conversation.vendorUid,
    buyerLabel: conversation.buyerLabel,
    vendorLabel: conversation.vendorLabel,
    updatedAt: conversation.updatedAt,
    lastMessage: conversation.lastMessage,
    lastMessageSenderUid: conversation.lastMessageSenderUid,
    buyerPhotoUrl: conversation.buyerPhotoUrl,
    vendorPhotoUrl: conversation.vendorPhotoUrl,
    buyerPhotoBytes: conversation.buyerPhotoBytes,
    vendorPhotoBytes: conversation.vendorPhotoBytes,
    hiddenBy: List.unmodifiable(hiddenBy),
  );

  List<ProduceOrder> ordersForVendor(String vendorEmail) {
    final vendorOrders = <ProduceOrder>[];
    for (final order in _orders) {
      final vendorItems = order.items
          .where((item) => item.listing.ownerEmail == vendorEmail)
          .toList();
      if (vendorItems.isEmpty) continue;

      vendorOrders.add(
        ProduceOrder(
          id: order.id,
          items: vendorItems,
          buyerEmail: order.buyerEmail,
          createdAt: order.createdAt,
          totalAmount: vendorItems.fold<int>(
            0,
            (total, item) => total + item.subtotal,
          ),
          status:
              _vendorOrderStatuses['${order.id}:${vendorEmail.toLowerCase()}'] ??
              order.status,
          buyerUid: order.buyerUid,
        ),
      );
    }
    return List.unmodifiable(vendorOrders);
  }

  ProduceListing _findListing(String listingId) {
    final index = _sampleListings.indexWhere(
      (listing) => listing.id == listingId,
    );
    if (index == -1) {
      throw StateError('This produce listing is no longer available.');
    }
    return _sampleListings[index];
  }

  ProduceListing _withAvailableQuantity(ProduceListing listing) {
    final available = availableQuantity(listing);
    return ProduceListing(
      id: listing.id,
      name: listing.name,
      category: listing.category,
      price: listing.price,
      unit: listing.unit,
      quantity: '$available',
      condition: listing.condition,
      vendor: listing.vendor,
      vendorInitials: listing.vendorInitials,
      location: listing.location,
      distanceKm: listing.distanceKm,
      imageUrl: listing.imageUrl,
      imageUrls: listing.imageUrls,
      videoUrls: listing.videoUrls,
      ownerEmail: listing.ownerEmail,
      imageBytes: listing.imageBytes,
      imageFileName: listing.imageFileName,
      pendingMedia: listing.pendingMedia,
      latitude: listing.latitude,
      longitude: listing.longitude,
      postedAt: listing.postedAt,
      justPosted: listing.justPosted,
      description: listing.description,
    );
  }

  int _parseInventory(String quantity) =>
      int.tryParse(quantity.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  void _validateQuantity(int quantity) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be at least 1.');
    }
  }

  void _decrementInventory(String listingId, int quantity) {
    final listing = _findListing(listingId);
    final remaining = availableQuantity(listing);
    if (quantity > remaining) {
      throw StateError('The requested quantity is not available.');
    }
    _remainingInventory[listingId] = remaining - quantity;
  }
}
