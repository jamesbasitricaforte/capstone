import 'dart:async';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'location_services.dart';
import '../models/marketplace_purchase.dart';
import '../models/marketplace_messaging.dart';
import '../models/produce_listing.dart';
import '../models/marketplace_trust.dart';
import '../models/vendor_location.dart';
import '../models/vendor_store_profile.dart';
import 'marketplace_service.dart';

class MarketplaceAccount {
  const MarketplaceAccount({
    required this.id,
    required this.role,
    required this.email,
    this.emailVerified = true,
    this.fullName,
    this.companyName,
    this.companyDescription,
    this.addressLine1,
    this.zipCode,
    this.phone,
    this.taxId,
    this.businessType,
    this.latitude,
    this.longitude,
    this.profilePhotoUrl,
    this.profilePhotoBytes,
  });

  final String id;
  final String role;
  final String email;
  final bool emailVerified;
  final String? fullName;
  final String? companyName;
  final String? companyDescription;
  final String? addressLine1;
  final String? zipCode;
  final String? phone;
  final String? taxId;
  final String? businessType;
  final double? latitude;
  final double? longitude;
  final String? profilePhotoUrl;
  final Uint8List? profilePhotoBytes;

  MarketplaceAccount copyWith({
    String? profilePhotoUrl,
    Uint8List? profilePhotoBytes,
    bool? emailVerified,
  }) => MarketplaceAccount(
    id: id,
    role: role,
    email: email,
    emailVerified: emailVerified ?? this.emailVerified,
    fullName: fullName,
    companyName: companyName,
    companyDescription: companyDescription,
    addressLine1: addressLine1,
    zipCode: zipCode,
    phone: phone,
    taxId: taxId,
    businessType: businessType,
    latitude: latitude,
    longitude: longitude,
    profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
    profilePhotoBytes: profilePhotoBytes ?? this.profilePhotoBytes,
  );
}

class MarketplaceCredentials {
  const MarketplaceCredentials({
    required this.email,
    required this.password,
    required this.role,
    this.fullName,
    this.passwordConfirmation,
    this.companyName,
    this.companyDescription,
    this.addressLine1,
    this.zipCode,
    this.phone,
    this.taxId,
    this.businessType,
    this.latitude,
    this.longitude,
  });

  final String email;
  final String password;
  final String role;
  final String? fullName;
  final String? passwordConfirmation;
  final String? companyName;
  final String? companyDescription;
  final String? addressLine1;
  final String? zipCode;
  final String? phone;
  final String? taxId;
  final String? businessType;
  final double? latitude;
  final double? longitude;
}

class MarketplaceApiException implements Exception {
  const MarketplaceApiException(
    this.message, {
    this.statusCode,
    this.validationErrors = const {},
  });

  final String message;
  final int? statusCode;
  final Map<String, List<String>> validationErrors;

  @override
  String toString() {
    final details = validationErrors.values.expand((messages) => messages);
    final detailText = details.isEmpty ? '' : ' ${details.join(' ')}';
    if (details.isEmpty || details.every(message.contains)) return message;
    return '$message$detailText';
  }
}

abstract interface class MarketplaceRepository implements ReverseGeocoder {
  bool get supportsRemoteListings;

  Stream<ProduceListing> get listingUpdates;
  Stream<String> get listingRemovals;
  Stream<MarketplaceNotification> get notificationUpdates;
  Stream<String> get notificationRemovals;

  Future<MarketplaceAccount?> restoreSession();
  Future<MarketplaceAccount> signIn(MarketplaceCredentials credentials);
  Future<MarketplaceAccount> signInDemo(String role);
  Future<MarketplaceAccount> register(MarketplaceCredentials credentials);
  Future<void> sendEmailVerification();
  Future<MarketplaceAccount?> refreshEmailVerificationStatus();
  Future<void> requestPasswordReset(String email);
  Future<void> signOut();
  Future<List<ProduceListing>> loadListings();
  Future<List<ProduceListing>> loadPublicListings();
  Future<List<ProduceListing>> loadNearbyListings({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  });
  @override
  Future<String?> addressFor(LatLng location);
  Future<List<VendorLocation>> loadVendors();
  Future<VendorStoreProfile?> loadVendorStoreProfile(String vendorId);
  Future<List<ProduceListing>> loadVendorListings(String vendorId);
  Future<VendorLocation> updateVendorLocation({
    required double latitude,
    required double longitude,
    String? addressLine1,
  });
  Future<MarketplaceAccount> updateProfilePhoto({
    required Uint8List imageBytes,
    required String imageName,
  });
  Future<MarketplaceAccount> updateProfilePhotoUrl({required String photoUrl});
  ProduceListing publicListing(ProduceListing listing);
  Future<List<MarketplaceNotification>> loadNotifications();
  Future<void> markNotificationsRead();
  Stream<MarketplaceNotification> watchVendorNotifications();
  Future<Set<String>> loadFavorites();
  Future<void> setFavorite({required String listingId, required bool saved});
  Future<VendorTrustSummary> loadVendorTrust(String vendorId);
  Future<void> requestVendorVerification();
  Future<void> reportVendor({
    required String vendorId,
    required String reason,
    required String details,
  });
  Future<void> reviewVendor({
    required String vendorId,
    // Omit orderId for unverified store feedback.
    String? orderId,
    required int rating,
    required String comment,
  });
  Future<void> addListing(ProduceListing listing);
  Future<void> updateListing(ProduceListing listing);
  Future<bool> repostListing({required String listingId});
  Future<bool> removeListing({required String listingId});
  int availableQuantity(ProduceListing listing);
  Future<List<MarketplaceCartItem>> loadCart();
  Future<void> addToCart({
    required ProduceListing listing,
    required int quantity,
  });
  Future<void> updateCartQuantity({
    required String listingId,
    required int quantity,
  });
  Future<void> removeFromCart({required String listingId});
  Future<ProduceReservation> reserveListing({
    required ProduceListing listing,
    required int quantity,
  });
  Future<ProduceOrder> buyListing({
    required ProduceListing listing,
    required int quantity,
  });
  Future<ProduceOrder> checkoutCart();
  Future<List<ProduceReservation>> loadReservations();
  Future<bool> cancelReservation({required String reservationId});
  Future<List<ProduceOrder>> loadOrders();
  Future<bool> deleteBuyerOrder({required String orderId});
  Future<List<ProduceOrder>> loadVendorOrders();
  Future<bool> updateVendorOrder({
    required String orderId,
    required String status,
  });
  Future<MarketplaceConversation> openConversation({
    required String listingId,
    required String listingName,
    required String otherUserId,
    required String otherName,
    String? orderDocumentId,
  });
  Future<List<MarketplaceConversation>> loadConversations();
  Stream<List<MarketplaceConversation>> watchConversations();
  Stream<List<MarketplaceMessage>> watchMessages(String conversationId);
  Future<void> sendMessage({
    required String conversationId,
    required String text,
    Uint8List? imageBytes,
    String? imageName,
  });
  Future<void> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  });
  Future<void> deleteConversationForMe({required String conversationId});
  void dispose();
}

class InMemoryMarketplaceRepository implements MarketplaceRepository {
  InMemoryMarketplaceRepository({MarketplaceService? service})
    : _service = service ?? MarketplaceService();

  final MarketplaceService _service;
  final Map<String, MarketplaceAccount> _accounts = {};
  final Map<String, Set<String>> _favorites = {};
  final Map<String, VendorLocation> _vendorLocations = {};
  final Map<String, String> _verificationStatuses = {};
  static final Map<String, List<MarketplaceReview>> _vendorReviews = {};
  final Set<String> _reportedVendorIds = {};
  MarketplaceAccount? _currentAccount;

  @override
  bool get supportsRemoteListings => false;

  @override
  Stream<ProduceListing> get listingUpdates => _service.listingUpdates;

  @override
  Stream<String> get listingRemovals => _service.listingRemovals;

  @override
  Stream<MarketplaceNotification> get notificationUpdates =>
      _service.notificationUpdates;

  @override
  Stream<String> get notificationRemovals => _service.notificationRemovals;

  @override
  Future<MarketplaceAccount?> restoreSession() async => _currentAccount;

  void setAuthenticatedAccount(MarketplaceAccount account) {
    _currentAccount = account;
  }

  @override
  Future<MarketplaceAccount> signIn(MarketplaceCredentials credentials) async {
    final email = credentials.email.toLowerCase();
    final account = _accounts.putIfAbsent(
      email,
      () => MarketplaceAccount(
        id: email,
        role: credentials.role,
        email: credentials.email,
      ),
    );
    if (account.role != credentials.role) {
      throw MarketplaceApiException(
        'This account is registered as ${account.role}. '
        'Select ${account.role} account type to sign in.',
      );
    }
    _currentAccount = account;
    return account;
  }

  @override
  Future<MarketplaceAccount> signInDemo(String role) async {
    if (role != 'Buyer' && role != 'Vendor') {
      throw const MarketplaceApiException('Unknown demo account role.');
    }
    final isVendor = role == 'Vendor';
    final account = MarketplaceAccount(
      id: 'demo:${role.toLowerCase()}',
      role: role,
      email: 'demo.${role.toLowerCase()}@local.test',
      fullName: isVendor ? 'Demo Vendor' : 'Demo Buyer',
      companyName: isVendor ? 'Demo Produce Stand' : null,
      companyDescription: isVendor
          ? 'Sample vendor account for exploring the app.'
          : null,
      addressLine1: isVendor ? 'Demo location' : null,
      businessType: isVendor ? 'Both' : null,
    );
    _accounts[account.email] = account;
    _currentAccount = account;
    return account;
  }

  @override
  Future<MarketplaceAccount> register(
    MarketplaceCredentials credentials,
  ) async {
    final email = credentials.email.toLowerCase();
    if (_accounts.containsKey(email)) {
      throw const MarketplaceApiException(
        'An account already exists for this email.',
        validationErrors: {
          'email': ['This email address is already registered.'],
        },
      );
    }
    final account = MarketplaceAccount(
      id: email,
      role: credentials.role,
      email: credentials.email,
      fullName: credentials.fullName,
      companyName: credentials.companyName,
      companyDescription: credentials.companyDescription,
      addressLine1: credentials.addressLine1,
      zipCode: credentials.zipCode,
      phone: credentials.phone,
      taxId: credentials.taxId,
      businessType: credentials.businessType,
      latitude: credentials.latitude,
      longitude: credentials.longitude,
    );
    _accounts[email] = account;
    _currentAccount = account;
    if (account.role == 'Vendor' &&
        account.latitude != null &&
        account.longitude != null) {
      _vendorLocations[email] = VendorLocation(
        id: email,
        name: account.companyName ?? email,
        businessType: account.businessType,
        address: account.addressLine1 ?? '',
        latitude: account.latitude!,
        longitude: account.longitude!,
      );
    }
    return account;
  }

  @override
  Future<void> sendEmailVerification() async {
    throw const MarketplaceApiException(
      'Email verification is available only for Firebase accounts.',
    );
  }

  @override
  Future<MarketplaceAccount?> refreshEmailVerificationStatus() async =>
      _currentAccount;

  @override
  Future<void> requestPasswordReset(String email) async {
    throw const MarketplaceApiException(
      'Password reset is unavailable for accounts stored only on this device.',
    );
  }

  @override
  Future<void> signOut() async {
    _currentAccount = null;
  }

  @override
  Future<List<ProduceListing>> loadListings() => _service.loadListings();

  @override
  Future<List<ProduceListing>> loadPublicListings() =>
      _service.loadPublicListings();

  @override
  Future<List<ProduceListing>> loadNearbyListings({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    throw const MarketplaceApiException(
      'Nearby listings require vendor locations saved on this device.',
    );
  }

  @override
  Future<String?> addressFor(LatLng location) async => null;

  @override
  Future<List<VendorLocation>> loadVendors() async =>
      List.unmodifiable(_vendorLocations.values);

  @override
  Future<VendorStoreProfile?> loadVendorStoreProfile(String vendorId) async {
    for (final account in _accounts.values) {
      if (account.role == 'Vendor' &&
          (account.id == vendorId ||
              account.email.toLowerCase() == vendorId.toLowerCase())) {
        return VendorStoreProfile(
          id: account.id,
          storeName: account.companyName?.trim().isNotEmpty == true
              ? account.companyName!.trim()
              : account.fullName?.trim().isNotEmpty == true
              ? account.fullName!.trim()
              : 'Local vendor',
          ownerName: account.fullName,
          description: account.companyDescription,
          businessType: account.businessType,
          address: account.addressLine1,
          zipCode: account.zipCode,
          phone: account.phone,
          latitude: account.latitude,
          longitude: account.longitude,
          profilePhotoUrl: account.profilePhotoUrl,
          profilePhotoBytes: account.profilePhotoBytes,
        );
      }
    }

    for (final location in _vendorLocations.values) {
      if (location.id == vendorId) {
        return VendorStoreProfile(
          id: location.id,
          storeName: location.name,
          businessType: location.businessType,
          address: location.address,
          latitude: location.latitude,
          longitude: location.longitude,
        );
      }
    }

    final listings = await _service.loadPublicListings();
    for (final listing in listings) {
      if (listing.vendor == vendorId) {
        return VendorStoreProfile(
          id: vendorId,
          storeName: listing.vendor,
          address: listing.location,
          latitude: listing.latitude,
          longitude: listing.longitude,
        );
      }
    }
    return null;
  }

  @override
  Future<List<ProduceListing>> loadVendorListings(String vendorId) async {
    final listings = await _service.loadListings();
    return List.unmodifiable(
      listings
          .where(
            (listing) =>
                listing.ownerUid == vendorId ||
                listing.ownerEmail?.toLowerCase() == vendorId.toLowerCase() ||
                (listing.ownerUid == null &&
                    listing.ownerEmail == null &&
                    listing.vendor == vendorId),
          )
          .map(_service.publicListing),
    );
  }

  @override
  Future<VendorLocation> updateVendorLocation({
    required double latitude,
    required double longitude,
    String? addressLine1,
  }) async {
    final account = _requireAccount();
    if (account.role != 'Vendor') {
      throw const MarketplaceApiException(
        'Only vendor accounts can update a vendor location.',
        statusCode: 403,
      );
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const MarketplaceApiException(
        'Choose a location with valid latitude and longitude.',
      );
    }

    final updatedAccount = MarketplaceAccount(
      id: account.id,
      role: account.role,
      email: account.email,
      companyName: account.companyName,
      companyDescription: account.companyDescription,
      addressLine1: addressLine1 ?? account.addressLine1,
      zipCode: account.zipCode,
      phone: account.phone,
      taxId: account.taxId,
      businessType: account.businessType,
      latitude: latitude,
      longitude: longitude,
      profilePhotoUrl: account.profilePhotoUrl,
      profilePhotoBytes: account.profilePhotoBytes,
    );
    _accounts[account.email.toLowerCase()] = updatedAccount;
    _currentAccount = updatedAccount;
    _vendorLocations[account.email] = VendorLocation(
      id: account.email,
      name: account.companyName ?? account.email,
      businessType: account.businessType,
      address: updatedAccount.addressLine1 ?? '',
      latitude: latitude,
      longitude: longitude,
    );
    return _vendorLocations[account.email]!;
  }

  @override
  Future<MarketplaceAccount> updateProfilePhoto({
    required Uint8List imageBytes,
    required String imageName,
  }) async {
    final account = _requireAccount();
    if (imageBytes.isEmpty || imageBytes.length > 20 * 1024 * 1024) {
      throw const MarketplaceApiException(
        'Choose an image that is no larger than 20 MB.',
      );
    }
    final updatedAccount = account.copyWith(profilePhotoBytes: imageBytes);
    _accounts[account.email.toLowerCase()] = updatedAccount;
    _currentAccount = updatedAccount;
    _service.updateProfilePhotoForUser(
      account.id,
      photoUrl: null,
      photoBytes: imageBytes,
    );
    return updatedAccount;
  }

  @override
  Future<MarketplaceAccount> updateProfilePhotoUrl({
    required String photoUrl,
  }) async {
    final account = _requireAccount();
    final url = photoUrl.trim();
    if (url.isNotEmpty && !isHostedMediaUrl(url)) {
      throw const MarketplaceApiException(
        'Use a publicly accessible HTTPS image URL.',
      );
    }
    final updatedAccount = MarketplaceAccount(
      id: account.id,
      role: account.role,
      email: account.email,
      fullName: account.fullName,
      companyName: account.companyName,
      companyDescription: account.companyDescription,
      addressLine1: account.addressLine1,
      zipCode: account.zipCode,
      phone: account.phone,
      taxId: account.taxId,
      businessType: account.businessType,
      latitude: account.latitude,
      longitude: account.longitude,
      profilePhotoUrl: url.isEmpty ? null : url,
    );
    _accounts[account.email.toLowerCase()] = updatedAccount;
    _currentAccount = updatedAccount;
    _service.updateProfilePhotoForUser(
      account.id,
      photoUrl: updatedAccount.profilePhotoUrl,
      photoBytes: null,
    );
    return updatedAccount;
  }

  @override
  ProduceListing publicListing(ProduceListing listing) =>
      _service.publicListing(listing);

  @override
  Future<List<MarketplaceNotification>> loadNotifications() async {
    final account = _requireAccount();
    return _service.notificationsFor(userId: account.id, role: account.role);
  }

  @override
  Future<void> markNotificationsRead() async {
    _service.markNotificationsRead(_requireAccount().id);
  }

  @override
  Stream<MarketplaceNotification> watchVendorNotifications() {
    final account = _requireVendor();
    return _service.notificationUpdates.where(
      (notification) =>
          notification.targetRole == 'Vendor' &&
          notification.recipientUid == account.id,
    );
  }

  @override
  Future<Set<String>> loadFavorites() async =>
      Set.unmodifiable(_favoritesForCurrentAccount());

  @override
  Future<void> setFavorite({
    required String listingId,
    required bool saved,
  }) async {
    final favorites = _favoritesForCurrentAccount();
    if (saved) {
      favorites.add(listingId);
    } else {
      favorites.remove(listingId);
    }
  }

  @override
  Future<VendorTrustSummary> loadVendorTrust(String vendorId) async {
    final reviews = List<MarketplaceReview>.of(
      _vendorReviews[vendorId.trim().toLowerCase()] ??
          const <MarketplaceReview>[],
    )..sort((first, second) => second.createdAt.compareTo(first.createdAt));
    final total = reviews.fold<int>(0, (sum, review) => sum + review.rating);
    return VendorTrustSummary(
      verificationStatus: _verificationStatuses[vendorId] ?? 'not_requested',
      averageRating: reviews.isEmpty ? 0 : total / reviews.length,
      reviewCount: reviews.length,
      reviews: reviews,
    );
  }

  @override
  Future<void> requestVendorVerification() async {
    final vendor = _requireVendor();
    _verificationStatuses.putIfAbsent(vendor.email, () => 'pending');
  }

  @override
  Future<void> reportVendor({
    required String vendorId,
    required String reason,
    required String details,
  }) async {
    _requireBuyer();
    if (vendorId.trim().isEmpty || reason.trim().isEmpty) {
      throw const MarketplaceApiException('Choose a report reason.');
    }
    final reportKey = '$vendorId:${reason.trim()}:${details.trim()}';
    if (!_reportedVendorIds.add(reportKey)) {
      throw const MarketplaceApiException(
        'This report has already been saved on this device.',
      );
    }
  }

  @override
  Future<void> reviewVendor({
    required String vendorId,
    String? orderId,
    required int rating,
    required String comment,
  }) async {
    final buyer = _requireBuyer();
    final normalizedVendorId = vendorId.trim().toLowerCase();
    final normalizedOrderId = orderId?.trim();
    final trimmedComment = comment.trim();
    if (normalizedVendorId.isEmpty ||
        (normalizedOrderId != null && normalizedOrderId.isEmpty)) {
      throw const MarketplaceApiException(
        'This review is missing its vendor or purchase reference.',
      );
    }
    if (rating < 1 || rating > 5) {
      throw const MarketplaceApiException('Choose a rating from 1 to 5.');
    }
    if (trimmedComment.isEmpty) {
      throw const MarketplaceApiException(
        'Write a short comment before submitting your review.',
      );
    }
    if (trimmedComment.length > 500) {
      throw const MarketplaceApiException(
        'Reviews must be 500 characters or fewer.',
      );
    }
    final eligibleOrder =
        normalizedOrderId == null ||
        _service
            .ordersFor(buyer.email)
            .any(
              (order) =>
                  order.id == normalizedOrderId &&
                  order.buyerEmail.toLowerCase() == buyer.email.toLowerCase() &&
                  order.items.any(
                    (item) =>
                        (item.status == 'completed' ||
                            (item.status.isEmpty &&
                                order.status == 'completed')) &&
                        (item.listing.ownerEmail?.toLowerCase() ==
                                normalizedVendorId ||
                            item.vendorUid?.toLowerCase() ==
                                normalizedVendorId),
                  ),
            );
    if (!eligibleOrder) {
      throw const MarketplaceApiException(
        'A completed purchase from this vendor is required to leave a review.',
      );
    }
    final reviews = _vendorReviews.putIfAbsent(
      normalizedVendorId,
      () => <MarketplaceReview>[],
    );
    if (reviews.any((review) {
      if (review.buyerEmail.toLowerCase() != buyer.email.toLowerCase()) {
        return false;
      }
      return normalizedOrderId == null
          ? review.orderId == null
          : review.orderId == normalizedOrderId;
    })) {
      throw const MarketplaceApiException(
        'You have already left feedback for this vendor.',
      );
    }
    reviews.insert(
      0,
      MarketplaceReview(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        vendorId: normalizedVendorId,
        buyerEmail: buyer.email,
        buyerName: buyer.fullName?.trim().isNotEmpty == true
            ? buyer.fullName!.trim()
            : 'Marketplace customer',
        buyerUid: buyer.id,
        buyerPhotoUrl: buyer.profilePhotoUrl,
        buyerPhotoBytes: buyer.profilePhotoBytes,
        orderId: normalizedOrderId,
        rating: rating,
        comment: trimmedComment,
        isVerifiedPurchase: normalizedOrderId != null,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> addListing(ProduceListing listing) =>
      _service.addListing(listing);

  @override
  Future<void> updateListing(ProduceListing listing) async {
    final vendor = _requireVendor();
    await _service.updateListing(listing: listing, ownerEmail: vendor.email);
  }

  @override
  Future<bool> repostListing({required String listingId}) => _service
      .repostListing(listingId: listingId, ownerEmail: _requireVendor().email);

  @override
  Future<bool> removeListing({required String listingId}) => _service
      .removeListing(listingId: listingId, ownerEmail: _requireAccount().email);

  @override
  int availableQuantity(ProduceListing listing) =>
      _service.availableQuantity(listing);

  @override
  Future<List<MarketplaceCartItem>> loadCart() =>
      _service.loadCart(_requireBuyer().email);

  @override
  Future<void> addToCart({
    required ProduceListing listing,
    required int quantity,
  }) => _service.addToCart(
    buyerEmail: _requireBuyer().email,
    listing: listing,
    quantity: quantity,
  );

  @override
  Future<void> updateCartQuantity({
    required String listingId,
    required int quantity,
  }) => _service.updateCartQuantity(
    buyerEmail: _requireBuyer().email,
    listingId: listingId,
    quantity: quantity,
  );

  @override
  Future<void> removeFromCart({required String listingId}) => _service
      .removeFromCart(buyerEmail: _requireBuyer().email, listingId: listingId);

  @override
  Future<ProduceReservation> reserveListing({
    required ProduceListing listing,
    required int quantity,
  }) => _service.reserveListing(
    buyerEmail: _requireBuyer().email,
    listing: listing,
    quantity: quantity,
  );

  @override
  Future<ProduceOrder> buyListing({
    required ProduceListing listing,
    required int quantity,
  }) => _service.buyListing(
    buyerEmail: _requireBuyer().email,
    listing: listing,
    quantity: quantity,
  );

  @override
  Future<ProduceOrder> checkoutCart() =>
      _service.checkoutCart(_requireBuyer().email);

  @override
  Future<List<ProduceReservation>> loadReservations() async =>
      _service.reservationsFor(_requireBuyer().email);

  @override
  Future<bool> cancelReservation({required String reservationId}) async =>
      _service.cancelReservation(
        buyerEmail: _requireBuyer().email,
        reservationId: reservationId,
      );

  @override
  Future<List<ProduceOrder>> loadOrders() async =>
      _service.ordersFor(_requireBuyer().email);

  @override
  Future<bool> deleteBuyerOrder({required String orderId}) async => _service
      .hideOrderForBuyer(orderId: orderId, buyerEmail: _requireBuyer().email);

  @override
  Future<List<ProduceOrder>> loadVendorOrders() async =>
      _service.ordersForVendor(_requireVendor().email);

  @override
  Future<bool> updateVendorOrder({
    required String orderId,
    required String status,
  }) async {
    if (status != 'approved' && status != 'declined' && status != 'completed') {
      throw const MarketplaceApiException(
        'Choose approve, decline, or mark completed.',
      );
    }
    return _service.updateOrderStatus(
      orderId: orderId,
      vendorEmail: _requireVendor().email,
      status: status,
    );
  }

  @override
  Future<MarketplaceConversation> openConversation({
    required String listingId,
    required String listingName,
    required String otherUserId,
    required String otherName,
    String? orderDocumentId,
  }) async {
    final account = _requireAccount();
    final isBuyer = account.role == 'Buyer';
    if (!isBuyer && account.role != 'Vendor') {
      throw const MarketplaceApiException(
        'Sign in as a buyer or vendor to send messages.',
        statusCode: 403,
      );
    }
    final buyerUid = isBuyer ? account.id : otherUserId;
    final vendorUid = isBuyer ? otherUserId : account.id;
    final existing = _service.conversationForPair(buyerUid, vendorUid);
    final otherAccount = _accounts.values
        .where((candidate) => candidate.id == otherUserId)
        .firstOrNull;
    final proposedBuyerLabel = isBuyer
        ? _buyerDisplayName(account)
        : _counterpartyDisplayName(otherAccount, otherName, 'Buyer');
    final proposedVendorLabel = isBuyer
        ? _counterpartyDisplayName(otherAccount, otherName, 'Vendor')
        : _vendorDisplayName(account);
    final buyerLabel = existing == null
        ? proposedBuyerLabel
        : _preserveExistingDisplayName(
            proposedLabel: proposedBuyerLabel,
            existingLabel: existing.buyerLabel,
            roleFallback: 'Buyer',
          );
    final vendorLabel = existing == null
        ? proposedVendorLabel
        : _preserveExistingDisplayName(
            proposedLabel: proposedVendorLabel,
            existingLabel: existing.vendorLabel,
            roleFallback: 'Vendor',
          );
    final id = existing?.id ?? 'pair:$buyerUid:$vendorUid';
    return _service.putConversation(
      MarketplaceConversation(
        id: id,
        listingId: listingId,
        listingName: listingName,
        buyerUid: buyerUid,
        vendorUid: vendorUid,
        buyerLabel: buyerLabel,
        vendorLabel: vendorLabel,
        updatedAt: DateTime.now(),
        buyerPhotoUrl: isBuyer
            ? account.profilePhotoUrl
            : otherAccount?.profilePhotoUrl,
        vendorPhotoUrl: isBuyer
            ? otherAccount?.profilePhotoUrl
            : account.profilePhotoUrl,
        buyerPhotoBytes: isBuyer
            ? account.profilePhotoBytes
            : otherAccount?.profilePhotoBytes,
        vendorPhotoBytes: isBuyer
            ? otherAccount?.profilePhotoBytes
            : account.profilePhotoBytes,
        hiddenBy: (existing?.hiddenBy ?? const <String>[])
            .where((userId) => userId != account.id)
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<List<MarketplaceConversation>> loadConversations() async =>
      _service.conversationsFor(_requireAccount().id);

  @override
  Stream<List<MarketplaceConversation>> watchConversations() =>
      _service.watchConversations(_requireAccount().id);

  @override
  Stream<List<MarketplaceMessage>> watchMessages(String conversationId) =>
      _service.watchMessages(conversationId, _requireAccount().id);

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String text,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    final account = _requireAccount();
    if (text.trim().isEmpty && (imageBytes == null || imageBytes.isEmpty)) {
      throw const MarketplaceApiException(
        'Enter a message or attach an image.',
      );
    }
    final conversation = _service
        .conversationsFor(account.id)
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      throw const MarketplaceApiException('Conversation not found.');
    }
    _service.addMessage(
      conversationId,
      MarketplaceMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        senderUid: account.id,
        text: text.trim(),
        createdAt: DateTime.now(),
        imageBytes: imageBytes,
      ),
      account.id,
    );
  }

  @override
  Future<void> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  }) async {
    final account = _requireAccount();
    if (!_service.hideMessageForUser(
      conversationId: conversationId,
      messageId: messageId,
      userId: account.id,
    )) {
      throw const MarketplaceApiException('Message is no longer available.');
    }
  }

  @override
  Future<void> deleteConversationForMe({required String conversationId}) async {
    final account = _requireAccount();
    if (!_service.hideConversationForUser(
      conversationId: conversationId,
      userId: account.id,
    )) {
      throw const MarketplaceApiException(
        'Conversation is no longer available.',
      );
    }
  }

  @override
  void dispose() {}

  String _buyerDisplayName(MarketplaceAccount account) {
    final name = account.fullName?.trim();
    return name == null || name.isEmpty ? account.email : name;
  }

  String _vendorDisplayName(MarketplaceAccount account) {
    final companyName = _nameWithoutEmail(account.companyName, 'Vendor');
    if (companyName != 'Vendor') return companyName;
    final fullName = account.fullName?.trim();
    return fullName == null || fullName.isEmpty ? account.email : fullName;
  }

  String _counterpartyDisplayName(
    MarketplaceAccount? account,
    String suggestedName,
    String roleFallback,
  ) {
    if (account != null) {
      return account.role == 'Buyer'
          ? _buyerDisplayName(account)
          : _vendorDisplayName(account);
    }
    final name = suggestedName.trim();
    return name.isEmpty ? roleFallback : name;
  }

  String _preserveExistingDisplayName({
    required String proposedLabel,
    required String existingLabel,
    required String roleFallback,
  }) {
    final existingIsSpecificName =
        existingLabel != roleFallback && existingLabel.isNotEmpty;
    final proposedIsFallback = proposedLabel == roleFallback;
    final proposedIsEmail = proposedLabel.contains('@');
    final existingIsEmail = existingLabel.contains('@');
    if (existingIsSpecificName &&
        (proposedIsFallback || (proposedIsEmail && !existingIsEmail))) {
      return existingLabel;
    }
    return proposedLabel;
  }

  String _nameWithoutEmail(String? value, String fallback) {
    final name = value?.trim() ?? '';
    return name.isEmpty || name.contains('@') ? fallback : name;
  }

  MarketplaceAccount _requireAccount() {
    final account = _currentAccount;
    if (account == null) {
      throw const MarketplaceApiException('Please sign in to continue.');
    }
    return account;
  }

  MarketplaceAccount _requireBuyer() {
    final account = _requireAccount();
    if (account.role != 'Buyer') {
      throw const MarketplaceApiException('A buyer account is required.');
    }
    return account;
  }

  MarketplaceAccount _requireVendor() {
    final account = _requireAccount();
    if (account.role != 'Vendor') {
      throw const MarketplaceApiException('A vendor account is required.');
    }
    return account;
  }

  Set<String> _favoritesForCurrentAccount() =>
      _favorites.putIfAbsent(_requireBuyer().email, () => <String>{});
}
