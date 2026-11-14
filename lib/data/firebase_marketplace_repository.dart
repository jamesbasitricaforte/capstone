import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import '../models/marketplace_purchase.dart';
import '../models/marketplace_trust.dart';
import '../models/produce_listing.dart';
import '../models/vendor_location.dart';
import '../models/vendor_store_profile.dart';
import 'firestore_image_compressor.dart';
import 'firebase_listing_service.dart';
import 'marketplace_repository.dart';

class FirebaseMarketplaceRepository extends InMemoryMarketplaceRepository {
  FirebaseMarketplaceRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseListingService? listingService,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _listingService =
           listingService ??
           FirebaseListingService(
             auth: auth ?? FirebaseAuth.instance,
             firestore: firestore ?? FirebaseFirestore.instance,
           ) {
    _listingSubscription = _listingService.watchListings().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.removed) {
            _listingRemovals.add(change.doc.id);
          } else {
            unawaited(_publishListing(change.doc));
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _listingUpdates.addError(error, stackTrace);
      },
    );
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseListingService _listingService;
  final StreamController<ProduceListing> _listingUpdates =
      StreamController<ProduceListing>.broadcast();
  final StreamController<String> _listingRemovals =
      StreamController<String>.broadcast();
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  _listingSubscription;

  Future<void> _publishListing(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    try {
      final listing = await _listingService.listingFromDocument(document);
      if (!_listingUpdates.isClosed) _listingUpdates.add(listing);
    } catch (error, stackTrace) {
      if (!_listingUpdates.isClosed) {
        _listingUpdates.addError(error, stackTrace);
      }
    }
  }

  @override
  bool get supportsRemoteListings => true;

  @override
  Stream<ProduceListing> get listingUpdates => _listingUpdates.stream;

  @override
  Stream<String> get listingRemovals => _listingRemovals.stream;

  @override
  Future<MarketplaceAccount?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return null;
      await refreshedUser.getIdToken(true);

      final document = await _userDocument(refreshedUser).get();
      final account = document.exists
          ? _accountFromData(refreshedUser, document.data()!)
          : _accountFromData(refreshedUser, const {'role': 'Buyer'});
      if (!document.exists) {
        await _userDocument(refreshedUser).set(_accountData(account));
      }
      if (account.role == 'Vendor' && account.emailVerified) {
        await _writeVendorPublicProfile(account);
      }
      super.setAuthenticatedAccount(account);
      return account;
    } on FirebaseException catch (error) {
      throw MarketplaceApiException(
        'Could not restore your Firebase account: ${error.message ?? error.code}',
      );
    }
  }

  @override
  Future<MarketplaceAccount> signIn(MarketplaceCredentials credentials) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: credentials.email.trim(),
        password: credentials.password,
      );
      final user = result.user;
      if (user == null) {
        throw const MarketplaceApiException(
          'Firebase did not return a signed-in user.',
        );
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        throw const MarketplaceApiException(
          'Firebase did not return a refreshed signed-in user.',
        );
      }
      await refreshedUser.getIdToken(true);

      final document = await _userDocument(refreshedUser).get();
      if (!document.exists) {
        await signOut();
        throw const MarketplaceApiException(
          'This account has no saved profile. Please contact support.',
        );
      }
      final account = _accountFromData(refreshedUser, document.data()!);
      if (account.role != credentials.role) {
        await signOut();
        throw MarketplaceApiException(
          'This account is registered as ${account.role}. '
          'Select ${account.role} account type to sign in.',
        );
      }
      if (account.role == 'Vendor' && account.emailVerified) {
        await _writeVendorPublicProfile(account);
      }
      super.setAuthenticatedAccount(account);
      return account;
    } on FirebaseAuthException catch (error) {
      throw MarketplaceApiException(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw MarketplaceApiException(
        'Signed in, but the account profile could not be loaded: '
        '${error.message ?? error.code}',
      );
    }
  }

  @override
  Future<MarketplaceAccount> register(
    MarketplaceCredentials credentials,
  ) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: credentials.email.trim(),
        password: credentials.password,
      );
      final user = result.user;
      if (user == null) {
        throw const MarketplaceApiException(
          'Firebase did not return the newly created user.',
        );
      }

      final account = _accountFromCredentials(user, credentials);
      await _userDocument(user).set(_accountData(account));
      super.setAuthenticatedAccount(account);
      return account;
    } on FirebaseAuthException catch (error) {
      throw MarketplaceApiException(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw MarketplaceApiException(
        'The Firebase account was created, but its profile could not be saved: '
        '${error.message ?? error.code}',
      );
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    return;
  }

  @override
  Future<MarketplaceAccount?> refreshEmailVerificationStatus() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return null;
      await refreshedUser.getIdToken(true);

      final document = await _userDocument(refreshedUser).get();
      if (!document.exists) {
        throw const MarketplaceApiException(
          'Your account profile could not be found. Please sign in again.',
        );
      }
      final account = _accountFromData(refreshedUser, document.data()!);
      if (account.role == 'Vendor' && account.emailVerified) {
        await _writeVendorPublicProfile(account);
        if (account.latitude != null && account.longitude != null) {
          await _firestore
              .collection('vendor_locations')
              .doc(account.id)
              .set(_vendorLocationData(account));
        }
      }
      super.setAuthenticatedAccount(account);
      return account;
    } on FirebaseAuthException catch (error) {
      throw MarketplaceApiException(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw MarketplaceApiException(
        'Could not refresh email verification status: '
        '${error.message ?? error.code}',
      );
    }
  }

  @override
  Future<MarketplaceAccount> signInDemo(String role) async {
    try {
      await _auth.signOut();
    } on FirebaseException catch (error) {
      throw MarketplaceApiException(
        'Could not sign out of Firebase: ${error.message ?? error.code}',
      );
    }
    return super.signInDemo(role);
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw MarketplaceApiException(_authErrorMessage(error));
    }
  }

  @override
  Future<void> signOut() async {
    await super.signOut();
    try {
      await _auth.signOut();
    } on FirebaseException catch (error) {
      throw MarketplaceApiException(
        'Signed out locally, but Firebase sign-out failed: '
        '${error.message ?? error.code}',
      );
    }
  }

  @override
  Future<List<ProduceListing>> loadListings() => _listingService.loadListings();

  @override
  Future<List<ProduceListing>> loadPublicListings() async =>
      (await _listingService.loadPublicListings())
          .map(publicListing)
          .toList(growable: false);

  @override
  Future<List<ProduceListing>> loadNearbyListings({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !radiusKm.isFinite ||
        radiusKm <= 0) {
      throw ArgumentError('Choose a valid location and distance radius.');
    }

    final center = LatLng(latitude, longitude);
    final distance = const Distance();
    final nearby = <ProduceListing>[];
    for (final listing in await loadPublicListings()) {
      final listingLatitude = listing.latitude;
      final listingLongitude = listing.longitude;
      if (listingLatitude == null || listingLongitude == null) continue;
      final distanceKm = distance.as(
        LengthUnit.Kilometer,
        center,
        LatLng(listingLatitude, listingLongitude),
      );
      if (distanceKm <= radiusKm && availableQuantity(listing) > 0) {
        nearby.add(_withDistance(listing, distanceKm));
      }
    }
    nearby.sort(
      (first, second) => first.distanceKm!.compareTo(second.distanceKm!),
    );
    return List.unmodifiable(nearby);
  }

  @override
  int availableQuantity(ProduceListing listing) {
    final quantity = int.tryParse(listing.quantity.trim());
    if (quantity == null || quantity < 0) {
      throw FormatException(
        'Listing ${listing.id} has an invalid available quantity.',
      );
    }
    return quantity;
  }

  @override
  Future<VendorTrustSummary> loadVendorTrust(String vendorId) async {
    final normalizedVendorId = _resolveReviewVendorUid(vendorId);
    final snapshot = await _vendorReviews
        .where('vendor_uid', isEqualTo: normalizedVendorId)
        .get();
    final reviews = snapshot.docs.map(_reviewFromDocument).toList()
      ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
    final totalRating = reviews.fold<int>(
      0,
      (total, review) => total + review.rating,
    );
    final statusKey = _auth.currentUser?.uid == normalizedVendorId
        ? _auth.currentUser?.email ?? vendorId
        : vendorId;
    final localTrust = await super.loadVendorTrust(statusKey);
    return VendorTrustSummary(
      verificationStatus: localTrust.verificationStatus,
      averageRating: reviews.isEmpty ? 0 : totalRating / reviews.length,
      reviewCount: reviews.length,
      reviews: List.unmodifiable(reviews),
    );
  }

  @override
  Future<void> reviewVendor({
    required String vendorId,
    String? orderId,
    required int rating,
    required String comment,
  }) async {
    final buyer = await _requireCommerceAccount('Buyer');
    final normalizedVendorId = _resolveReviewVendorUid(vendorId);
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

    final reviewId =
        '${normalizedVendorId}_${buyer.id}_${normalizedOrderId ?? 'store'}';
    final reviewReference = _vendorReviews.doc(reviewId);
    final orderReference = normalizedOrderId == null
        ? null
        : _marketplaceTransactions.doc(normalizedOrderId);
    await _firestore.runTransaction((transaction) async {
      final existingReview = await transaction.get(reviewReference);
      if (existingReview.exists) {
        throw const MarketplaceApiException(
          'You have already left feedback for this vendor.',
        );
      }
      if (orderReference != null) {
        final order = await transaction.get(orderReference);
        final data = order.data();
        if (data == null ||
            data['kind'] != 'order' ||
            data['buyer_uid'] != buyer.id ||
            data['vendor_uid'] != normalizedVendorId ||
            data['status'] != 'completed') {
          throw const MarketplaceApiException(
            'A completed purchase from this vendor is required to leave a review.',
          );
        }
      }
      transaction.set(reviewReference, {
        'id': reviewId,
        'vendor_uid': normalizedVendorId,
        'buyer_uid': buyer.id,
        'buyer_name': buyer.fullName?.trim().isNotEmpty == true
            ? buyer.fullName!.trim()
            : 'Marketplace customer',
        'buyer_photo_url': buyer.profilePhotoUrl,
        'order_id': normalizedOrderId,
        'rating': rating,
        'comment': trimmedComment,
        'is_verified_purchase': normalizedOrderId != null,
        'created_at': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<List<MarketplaceCartItem>> loadCart() async {
    final buyer = await _requireCommerceAccount('Buyer');
    final cart = await _cartCollection(buyer.id).get();
    final items = <MarketplaceCartItem>[];
    for (final cartDocument in cart.docs) {
      final listingDocument = await _firestore
          .collection('listings')
          .doc(cartDocument.id)
          .get();
      if (!listingDocument.exists) {
        await cartDocument.reference.delete();
        continue;
      }
      final listing = await _listingService.listingFromDocument(
        listingDocument,
      );
      final quantity = _positiveInt(
        cartDocument.data()['quantity'],
        'The cart contains an invalid quantity.',
      );
      items.add(
        MarketplaceCartItem(
          listing: listing,
          quantity: quantity,
          unitPrice: listing.price,
          vendorUid: listing.ownerUid,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  @override
  Future<void> addToCart({
    required ProduceListing listing,
    required int quantity,
  }) async {
    final buyer = await _requireCommerceAccount('Buyer');
    _validateQuantity(quantity);
    final listingReference = _firestore.collection('listings').doc(listing.id);
    final cartReference = _cartCollection(buyer.id).doc(listing.id);

    await _firestore.runTransaction((transaction) async {
      final listingDocument = await transaction.get(listingReference);
      final cartDocument = await transaction.get(cartReference);
      final data = _requirePurchasableListing(
        listingDocument,
        listing.id,
        buyer.id,
        quantity,
      );
      final alreadyInCart = cartDocument.exists
          ? _positiveInt(
              cartDocument.data()?['quantity'],
              'The cart contains an invalid quantity.',
            )
          : 0;
      if (alreadyInCart + quantity > _availableFromData(data, listing.id)) {
        throw StateError('The requested quantity is not available.');
      }
      transaction.set(cartReference, {
        'listing_id': listing.id,
        'quantity': alreadyInCart + quantity,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> updateCartQuantity({
    required String listingId,
    required int quantity,
  }) async {
    final buyer = await _requireCommerceAccount('Buyer');
    _validateQuantity(quantity);
    final listingReference = _firestore.collection('listings').doc(listingId);
    final cartReference = _cartCollection(buyer.id).doc(listingId);

    await _firestore.runTransaction((transaction) async {
      final listingDocument = await transaction.get(listingReference);
      final cartDocument = await transaction.get(cartReference);
      if (!cartDocument.exists) {
        throw StateError('This produce listing is no longer in your cart.');
      }
      final data = _requirePurchasableListing(
        listingDocument,
        listingId,
        buyer.id,
        quantity,
      );
      if (quantity > _availableFromData(data, listingId)) {
        throw StateError('The requested quantity is not available.');
      }
      transaction.update(cartReference, {
        'quantity': quantity,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> removeFromCart({required String listingId}) async {
    final buyer = await _requireCommerceAccount('Buyer');
    await _cartCollection(buyer.id).doc(listingId).delete();
  }

  @override
  Future<ProduceReservation> reserveListing({
    required ProduceListing listing,
    required int quantity,
  }) async {
    final buyer = await _requireCommerceAccount('Buyer');
    _validateQuantity(quantity);
    final listingReference = _firestore.collection('listings').doc(listing.id);
    final transactionReference = _marketplaceTransactions.doc();
    final createdAt = DateTime.now();

    return _firestore.runTransaction((transaction) async {
      final listingDocument = await transaction.get(listingReference);
      final data = _requirePurchasableListing(
        listingDocument,
        listing.id,
        buyer.id,
        quantity,
      );
      final remaining = _availableFromData(data, listing.id) - quantity;
      final snapshot = _listingSnapshot(data, listing.id, remaining);
      final total = _priceFromData(data, listing.id) * quantity;

      transaction.update(listingReference, {
        'quantity': remaining.toString(),
        'availability': remaining > 0,
        'status': remaining > 0 ? 'active' : 'sold_out',
        'updated_at': FieldValue.serverTimestamp(),
        'last_inventory_transaction_id': transactionReference.id,
      });
      transaction.set(
        transactionReference,
        _commerceTransactionData(
          id: transactionReference.id,
          kind: 'reservation',
          buyer: buyer,
          listingData: data,
          listingId: listing.id,
          listingSnapshot: snapshot,
          quantity: quantity,
          total: total,
          status: 'reserved',
        ),
      );
      return ProduceReservation(
        id: transactionReference.id,
        listing: ProduceListing.fromJson(snapshot),
        quantity: quantity,
        buyerEmail: buyer.email,
        createdAt: createdAt,
        totalAmount: total,
      );
    });
  }

  @override
  Future<ProduceOrder> buyListing({
    required ProduceListing listing,
    required int quantity,
  }) async {
    final buyer = await _requireCommerceAccount('Buyer');
    _validateQuantity(quantity);
    final listingReference = _firestore.collection('listings').doc(listing.id);
    final transactionReference = _marketplaceTransactions.doc();
    final createdAt = DateTime.now();

    return _firestore.runTransaction((transaction) async {
      final listingDocument = await transaction.get(listingReference);
      final data = _requirePurchasableListing(
        listingDocument,
        listing.id,
        buyer.id,
        quantity,
      );
      final remaining = _availableFromData(data, listing.id) - quantity;
      final snapshot = _listingSnapshot(data, listing.id, remaining);
      final price = _priceFromData(data, listing.id);
      final total = price * quantity;
      const status = 'pending_vendor_confirmation';

      transaction.update(listingReference, {
        'quantity': remaining.toString(),
        'availability': remaining > 0,
        'status': remaining > 0 ? 'active' : 'sold_out',
        'updated_at': FieldValue.serverTimestamp(),
        'last_inventory_transaction_id': transactionReference.id,
      });
      transaction.set(
        transactionReference,
        _commerceTransactionData(
          id: transactionReference.id,
          kind: 'order',
          buyer: buyer,
          listingData: data,
          listingId: listing.id,
          listingSnapshot: snapshot,
          quantity: quantity,
          total: total,
          status: status,
        ),
      );
      return ProduceOrder(
        id: transactionReference.id,
        items: [
          MarketplaceCartItem(
            listing: ProduceListing.fromJson(snapshot),
            quantity: quantity,
            unitPrice: price,
            vendorUid: data['vendor_uid'] as String,
            orderDocumentId: transactionReference.id,
            status: status,
          ),
        ],
        buyerEmail: buyer.email,
        createdAt: createdAt,
        totalAmount: total,
        status: status,
        buyerUid: buyer.id,
      );
    });
  }

  @override
  Future<ProduceOrder> checkoutCart() async {
    final buyer = await _requireCommerceAccount('Buyer');
    final cartSnapshot = await _cartCollection(buyer.id).get();
    if (cartSnapshot.docs.isEmpty) throw StateError('Your cart is empty.');
    if (cartSnapshot.docs.length > 100) {
      throw StateError(
        'Checkout is limited to 100 produce listings at a time.',
      );
    }

    final cartReferences = {
      for (final document in cartSnapshot.docs) document.id: document.reference,
    };
    final orderReferences = {
      for (final listingId in cartReferences.keys)
        listingId: _marketplaceTransactions.doc(),
    };
    final createdAt = DateTime.now();

    return _firestore.runTransaction((transaction) async {
      final cartData = <String, Map<String, dynamic>>{};
      final listingData = <String, Map<String, dynamic>>{};
      for (final entry in cartReferences.entries) {
        final cartDocument = await transaction.get(entry.value);
        final listingDocument = await transaction.get(
          _firestore.collection('listings').doc(entry.key),
        );
        if (!cartDocument.exists) {
          throw StateError(
            'Your cart changed. Please review it and try again.',
          );
        }
        cartData[entry.key] = cartDocument.data()!;
        listingData[entry.key] = _requirePurchasableListing(
          listingDocument,
          entry.key,
          buyer.id,
          _positiveInt(
            cartDocument.data()!['quantity'],
            'The cart contains an invalid quantity.',
          ),
        );
      }

      final items = <MarketplaceCartItem>[];
      var totalAmount = 0;
      for (final entry in cartReferences.entries) {
        final listingId = entry.key;
        final data = listingData[listingId]!;
        final quantity = _positiveInt(
          cartData[listingId]!['quantity'],
          'The cart contains an invalid quantity.',
        );
        final remaining = _availableFromData(data, listingId) - quantity;
        final snapshot = _listingSnapshot(data, listingId, remaining);
        final price = _priceFromData(data, listingId);
        final total = price * quantity;
        const status = 'pending_vendor_confirmation';
        final orderReference = orderReferences[listingId]!;

        transaction.update(_firestore.collection('listings').doc(listingId), {
          'quantity': remaining.toString(),
          'availability': remaining > 0,
          'status': remaining > 0 ? 'active' : 'sold_out',
          'updated_at': FieldValue.serverTimestamp(),
          'last_inventory_transaction_id': orderReference.id,
        });
        transaction.set(
          orderReference,
          _commerceTransactionData(
            id: orderReference.id,
            kind: 'order',
            buyer: buyer,
            listingData: data,
            listingId: listingId,
            listingSnapshot: snapshot,
            quantity: quantity,
            total: total,
            status: status,
          ),
        );
        transaction.delete(entry.value);
        items.add(
          MarketplaceCartItem(
            listing: ProduceListing.fromJson(snapshot),
            quantity: quantity,
            unitPrice: price,
            vendorUid: data['vendor_uid'] as String,
            orderDocumentId: orderReference.id,
            status: status,
          ),
        );
        totalAmount += total;
      }
      return ProduceOrder(
        id: orderReferences.values.first.id,
        items: List.unmodifiable(items),
        buyerEmail: buyer.email,
        createdAt: createdAt,
        totalAmount: totalAmount,
        status: 'pending_vendor_confirmation',
        buyerUid: buyer.id,
      );
    });
  }

  @override
  Future<List<ProduceReservation>> loadReservations() async {
    final buyer = await _requireCommerceAccount('Buyer');
    final snapshot = await _marketplaceTransactions
        .where('buyer_uid', isEqualTo: buyer.id)
        .get();
    final reservations =
        snapshot.docs
            .where(
              (document) =>
                  document.data()['kind'] == 'reservation' &&
                  document.data()['status'] == 'reserved',
            )
            .map(_reservationFromDocument)
            .toList()
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
    return List.unmodifiable(reservations);
  }

  @override
  Future<bool> cancelReservation({required String reservationId}) async {
    final buyer = await _requireCommerceAccount('Buyer');
    final reservationReference = _marketplaceTransactions.doc(reservationId);

    return _firestore.runTransaction((transaction) async {
      final reservationDocument = await transaction.get(reservationReference);
      final reservationData = reservationDocument.data();
      if (reservationData == null ||
          reservationData['buyer_uid'] != buyer.id ||
          reservationData['kind'] != 'reservation' ||
          reservationData['status'] != 'reserved') {
        return false;
      }

      final listingId = reservationData['listing_id'];
      if (listingId is! String || listingId.isEmpty) {
        throw const FormatException(
          'The reservation does not contain a valid listing ID.',
        );
      }
      final listingReference = _firestore.collection('listings').doc(listingId);
      final listingDocument = await transaction.get(listingReference);
      if (!listingDocument.exists) {
        throw StateError(
          'The listing was removed, so its reserved quantity cannot be restored.',
        );
      }

      final listingData = listingDocument.data()!;
      final restoredQuantity =
          _availableFromData(listingData, listingId) +
          _positiveInt(
            reservationData['quantity'],
            'The reservation contains an invalid quantity.',
          );
      transaction.update(listingReference, {
        'quantity': restoredQuantity.toString(),
        'availability': restoredQuantity > 0,
        'status': restoredQuantity > 0 ? 'active' : 'sold_out',
        'updated_at': FieldValue.serverTimestamp(),
        'last_inventory_transaction_id': reservationId,
      });
      transaction.update(reservationReference, {'status': 'cancelled'});
      return true;
    });
  }

  @override
  Future<List<ProduceOrder>> loadOrders() async {
    final buyer = await _requireCommerceAccount('Buyer');
    final snapshot = await _marketplaceTransactions
        .where('buyer_uid', isEqualTo: buyer.id)
        .get();
    final orders =
        snapshot.docs
            .where(
              (document) =>
                  document.data()['kind'] == 'order' &&
                  document.data()['buyer_hidden'] != true,
            )
            .map(_orderFromDocument)
            .toList()
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
    return List.unmodifiable(orders);
  }

  @override
  Future<bool> deleteBuyerOrder({required String orderId}) async {
    final buyer = await _requireCommerceAccount('Buyer');
    final reference = _marketplaceTransactions.doc(orderId);
    return _firestore.runTransaction((transaction) async {
      final document = await transaction.get(reference);
      if (!document.exists || document.data()?['buyer_uid'] != buyer.id) {
        return false;
      }
      if (document.data()?['kind'] != 'order') return false;
      transaction.update(reference, {'buyer_hidden': true});
      return true;
    });
  }

  @override
  Future<List<ProduceOrder>> loadVendorOrders() async {
    final vendor = await _requireCommerceAccount('Vendor');
    final snapshot = await _marketplaceTransactions
        .where('vendor_uid', isEqualTo: vendor.id)
        .get();
    final orders =
        snapshot.docs
            .where((document) => document.data()['kind'] == 'order')
            .map(_orderFromDocument)
            .toList()
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
    return List.unmodifiable(orders);
  }

  @override
  Future<bool> updateVendorOrder({
    required String orderId,
    required String status,
  }) async {
    final vendor = await _requireCommerceAccount('Vendor');
    if (!const {'approved', 'declined', 'completed'}.contains(status)) {
      throw ArgumentError('Choose a valid order status.');
    }
    final orderReference = _marketplaceTransactions.doc(orderId);

    return _firestore.runTransaction((transaction) async {
      final orderDocument = await transaction.get(orderReference);
      final data = orderDocument.data();
      if (data == null ||
          data['kind'] != 'order' ||
          data['vendor_uid'] != vendor.id) {
        return false;
      }
      final currentStatus = data['status'];
      final validTransition =
          (currentStatus == 'pending_vendor_confirmation' &&
              (status == 'approved' || status == 'declined')) ||
          (currentStatus == 'approved' && status == 'completed');
      if (!validTransition) return false;

      if (status == 'declined') {
        final listingId = data['listing_id'] as String;
        final listingReference = _firestore
            .collection('listings')
            .doc(listingId);
        final listingDocument = await transaction.get(listingReference);
        if (!listingDocument.exists) {
          throw StateError(
            'The listing was removed, so its reserved quantity cannot be restored.',
          );
        }
        final listingData = listingDocument.data()!;
        final restoredQuantity =
            _availableFromData(listingData, listingId) +
            _positiveInt(
              data['quantity'],
              'The order contains an invalid quantity.',
            );
        transaction.update(listingReference, {
          'quantity': restoredQuantity.toString(),
          'availability': restoredQuantity > 0,
          'status': restoredQuantity > 0 ? 'active' : 'sold_out',
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(orderReference, {'status': status});
      return true;
    });
  }

  @override
  Future<List<VendorLocation>> loadVendors() async {
    final snapshot = await _firestore.collection('vendor_locations').get();
    return List.unmodifiable(
      snapshot.docs.map(
        (document) =>
            VendorLocation.fromJson({...document.data(), 'id': document.id}),
      ),
    );
  }

  @override
  Future<VendorStoreProfile?> loadVendorStoreProfile(String vendorId) async {
    final profile = await _firestore
        .collection('vendor_public_profiles')
        .doc(vendorId)
        .get();
    if (profile.exists) {
      return _vendorStoreProfileFromData(vendorId, profile.data()!);
    }

    final location = await _firestore
        .collection('vendor_locations')
        .doc(vendorId)
        .get();
    if (!location.exists) return null;
    return VendorStoreProfile.fromJson(vendorId, location.data()!);
  }

  @override
  Future<List<ProduceListing>> loadVendorListings(String vendorId) async {
    final snapshot = await _firestore
        .collection('listings')
        .where('owner_uid', isEqualTo: vendorId)
        .get();
    final visibleDocuments = snapshot.docs.where((document) {
      final data = document.data();
      return data['status'] == 'active' || data['status'] == 'sold_out';
    });
    final listings = await Future.wait(
      visibleDocuments.map(_listingService.listingFromDocument),
    );
    return List.unmodifiable(listings.map(publicListing));
  }

  @override
  Future<VendorLocation> updateVendorLocation({
    required double latitude,
    required double longitude,
    String? addressLine1,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const MarketplaceApiException('Please sign in to continue.');
    }
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      throw const MarketplaceApiException(
        'Choose a location with valid latitude and longitude.',
      );
    }

    final profileReference = _userDocument(user);
    final profile = await profileReference.get();
    final account = _accountFromData(user, profile.data() ?? const {});
    if (account.role != 'Vendor') {
      throw const MarketplaceApiException(
        'Only vendor accounts can update a vendor location.',
        statusCode: 403,
      );
    }

    final address = addressLine1 ?? account.addressLine1 ?? '';
    final updatedAccount = MarketplaceAccount(
      id: account.id,
      role: account.role,
      email: account.email,
      fullName: account.fullName,
      companyName: account.companyName,
      companyDescription: account.companyDescription,
      addressLine1: address,
      zipCode: account.zipCode,
      phone: account.phone,
      taxId: account.taxId,
      businessType: account.businessType,
      latitude: latitude,
      longitude: longitude,
      profilePhotoUrl: account.profilePhotoUrl,
      profilePhotoBytes: account.profilePhotoBytes,
    );
    final batch = _firestore.batch()
      ..update(profileReference, {
        'address_line_1': address,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': FieldValue.serverTimestamp(),
      })
      ..set(
        _firestore.collection('vendor_locations').doc(account.id),
        _vendorLocationData(updatedAccount),
      )
      ..set(
        _firestore.collection('vendor_public_profiles').doc(account.id),
        _vendorPublicProfileData(updatedAccount),
      );
    await batch.commit();
    final location = _vendorLocationFor(updatedAccount);
    super.setAuthenticatedAccount(updatedAccount);
    return location;
  }

  @override
  Future<MarketplaceAccount> updateProfilePhotoUrl({
    required String photoUrl,
  }) async {
    final url = photoUrl.trim();
    if (url.isNotEmpty && !isHostedMediaUrl(url)) {
      throw const MarketplaceApiException(
        'Use a publicly accessible HTTPS image URL.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const MarketplaceApiException('Please sign in to continue.');
    }
    await _userDocument(user).update({
      'profile_photo_url': url.isEmpty ? null : url,
      'profile_photo_bytes': null,
      'updated_at': FieldValue.serverTimestamp(),
    });
    final profile = await _userDocument(user).get();
    final account = _accountFromData(user, profile.data() ?? const {});
    if (account.role == 'Vendor') {
      await _writeVendorPublicProfile(account);
    }
    super.setAuthenticatedAccount(account);
    return account;
  }

  @override
  Future<MarketplaceAccount> updateProfilePhoto({
    required Uint8List imageBytes,
    required String imageName,
  }) async {
    if (imageBytes.isEmpty ||
        imageBytes.length > maxFirestoreProfilePhotoBytes) {
      throw const MarketplaceApiException(
        'Choose a profile photo that fits within Firestore limits.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const MarketplaceApiException('Please sign in to continue.');
    }
    await _userDocument(user).update({
      'profile_photo_url': null,
      'profile_photo_bytes': Blob(imageBytes),
      'updated_at': FieldValue.serverTimestamp(),
    });
    final profile = await _userDocument(user).get();
    final account = _accountFromData(user, profile.data() ?? const {});
    if (account.role == 'Vendor') {
      await _writeVendorPublicProfile(account);
    }
    super.setAuthenticatedAccount(account);
    return account;
  }

  @override
  Future<void> addListing(ProduceListing listing) =>
      _listingService.addListing(listing);

  @override
  Future<void> updateListing(ProduceListing listing) =>
      _listingService.updateListing(listing);

  @override
  Future<bool> repostListing({required String listingId}) =>
      _listingService.repostListing(listingId: listingId);

  @override
  Future<bool> removeListing({required String listingId}) =>
      _listingService.deleteListing(listingId);

  @override
  void dispose() {
    unawaited(_listingSubscription.cancel());
    unawaited(_listingUpdates.close());
    unawaited(_listingRemovals.close());
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _marketplaceTransactions =>
      _firestore.collection('marketplace_transactions');

  CollectionReference<Map<String, dynamic>> get _vendorReviews =>
      _firestore.collection('vendor_reviews');

  CollectionReference<Map<String, dynamic>> _cartCollection(String userId) =>
      _firestore.collection('users').doc(userId).collection('cart');

  Future<MarketplaceAccount> _requireCommerceAccount(String role) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const MarketplaceApiException('Please sign in to continue.');
    }
    final profile = await _userDocument(user).get();
    if (!profile.exists) {
      throw const MarketplaceApiException(
        'Your account profile could not be found. Please sign in again.',
      );
    }
    final account = _accountFromData(user, profile.data()!);
    if (account.role != role) {
      throw MarketplaceApiException(
        'Only $role accounts can use this feature.',
        statusCode: 403,
      );
    }
    return account;
  }

  String _resolveReviewVendorUid(String vendorId) {
    final value = vendorId.trim();
    final currentUser = _auth.currentUser;
    if (currentUser?.email?.toLowerCase() == value.toLowerCase()) {
      return currentUser!.uid;
    }
    return value;
  }

  MarketplaceReview _reviewFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final rating = data['rating'];
    if (rating is! int || rating < 1 || rating > 5) {
      throw FormatException(
        'Review ${document.id} has an invalid star rating.',
      );
    }
    final comment = data['comment'];
    if (comment is! String || comment.trim().isEmpty) {
      throw FormatException('Review ${document.id} has no written feedback.');
    }
    final photoBytes = data['buyer_photo_bytes'];
    return MarketplaceReview(
      id: document.id,
      vendorId: data['vendor_uid'] as String,
      buyerEmail: '',
      buyerName: data['buyer_name'] as String? ?? 'Marketplace customer',
      buyerUid: data['buyer_uid'] as String?,
      buyerPhotoUrl: data['buyer_photo_url'] as String?,
      buyerPhotoBytes: photoBytes is Blob ? photoBytes.bytes : null,
      orderId: data['order_id'] as String?,
      rating: rating,
      comment: comment,
      isVerifiedPurchase: data['is_verified_purchase'] as bool? ?? false,
      createdAt: _dateFromValue(data['created_at']),
    );
  }

  Map<String, dynamic> _requirePurchasableListing(
    DocumentSnapshot<Map<String, dynamic>> document,
    String listingId,
    String buyerId,
    int quantity,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('This produce listing is no longer available.');
    }
    if (data['status'] != 'active' || data['availability'] != true) {
      throw StateError('This produce listing is no longer available.');
    }
    final vendorId = data['vendor_uid'];
    if (vendorId is! String || vendorId.isEmpty || vendorId == buyerId) {
      throw StateError('This produce listing cannot be purchased.');
    }
    final available = _availableFromData(data, listingId);
    if (available == 0) {
      throw StateError('This produce listing is no longer available.');
    }
    if (quantity > available) {
      throw StateError('The requested quantity is not available.');
    }
    _priceFromData(data, listingId);
    return data;
  }

  int _availableFromData(Map<String, dynamic> data, String listingId) {
    final quantity = int.tryParse(data['quantity']?.toString().trim() ?? '');
    if (quantity == null || quantity < 0) {
      throw FormatException(
        'Listing $listingId has an invalid available quantity.',
      );
    }
    return quantity;
  }

  int _priceFromData(Map<String, dynamic> data, String listingId) {
    final price = data['price'];
    if (price is! int || price <= 0) {
      throw FormatException('Listing $listingId has an invalid price.');
    }
    return price;
  }

  int _positiveInt(Object? value, String message) {
    final result = value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
    if (result == null || result < 1) throw FormatException(message);
    return result;
  }

  void _validateQuantity(int quantity) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be at least one.');
    }
  }

  Map<String, dynamic> _listingSnapshot(
    Map<String, dynamic> data,
    String listingId,
    int remainingQuantity,
  ) {
    final postedAt = data['posted_at'];
    return {
      'id': listingId,
      'owner_uid': data['owner_uid'],
      'vendor_uid': data['vendor_uid'],
      'name': data['name'],
      'category': data['category'],
      'description': data['description'],
      'price': data['price'],
      'unit': data['unit'],
      'quantity': remainingQuantity.toString(),
      'availability': remainingQuantity > 0,
      'status': remainingQuantity > 0 ? 'active' : 'sold_out',
      'condition': data['condition'],
      'vendor': data['vendor'],
      'vendor_initials': data['vendor_initials'],
      'location': data['location'],
      'image_url': data['image_url'],
      'image_urls': data['image_urls'],
      'video_urls': data['video_urls'],
      'latitude': data['latitude'],
      'longitude': data['longitude'],
      'posted_at': postedAt is Timestamp ? postedAt.toDate() : postedAt,
      'just_posted': data['just_posted'],
      'is_mine': false,
    };
  }

  Map<String, dynamic> _commerceTransactionData({
    required String id,
    required String kind,
    required MarketplaceAccount buyer,
    required Map<String, dynamic> listingData,
    required String listingId,
    required Map<String, dynamic> listingSnapshot,
    required int quantity,
    required int total,
    required String status,
  }) => {
    'id': id,
    'kind': kind,
    'buyer_uid': buyer.id,
    'buyer_email': buyer.email,
    'vendor_uid': listingData['vendor_uid'],
    'listing_id': listingId,
    'listing': listingSnapshot,
    'quantity': quantity,
    'unit_price': _priceFromData(listingData, listingId),
    'total': total,
    'status': status,
    'buyer_hidden': false,
    'created_at': FieldValue.serverTimestamp(),
  };

  DateTime _dateFromValue(Object? value) => switch (value) {
    final Timestamp timestamp => timestamp.toDate(),
    final DateTime dateTime => dateTime,
    final String text => DateTime.parse(text),
    _ => throw const FormatException('A marketplace record has no valid date.'),
  };

  ProduceReservation _reservationFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return ProduceReservation(
      id: document.id,
      listing: ProduceListing.fromJson(
        Map<String, dynamic>.from(data['listing'] as Map),
      ),
      quantity: _positiveInt(
        data['quantity'],
        'The reservation contains an invalid quantity.',
      ),
      buyerEmail: data['buyer_email'] as String? ?? '',
      createdAt: _dateFromValue(data['created_at']),
      totalAmount: _positiveInt(
        data['total'],
        'The reservation contains an invalid total.',
      ),
    );
  }

  ProduceOrder _orderFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final listing = ProduceListing.fromJson(
      Map<String, dynamic>.from(data['listing'] as Map),
    );
    final quantity = _positiveInt(
      data['quantity'],
      'The order contains an invalid quantity.',
    );
    final price = _positiveInt(
      data['unit_price'],
      'The order contains an invalid price.',
    );
    return ProduceOrder(
      id: document.id,
      items: [
        MarketplaceCartItem(
          listing: listing,
          quantity: quantity,
          unitPrice: price,
          vendorUid: data['vendor_uid'] as String?,
          orderDocumentId: document.id,
          status: data['status'] as String? ?? 'pending_vendor_confirmation',
        ),
      ],
      buyerEmail: data['buyer_email'] as String? ?? '',
      createdAt: _dateFromValue(data['created_at']),
      totalAmount: _positiveInt(
        data['total'],
        'The order contains an invalid total.',
      ),
      status: data['status'] as String? ?? 'pending_vendor_confirmation',
      buyerUid: data['buyer_uid'] as String?,
    );
  }

  DocumentReference<Map<String, dynamic>> _userDocument(User user) =>
      _firestore.collection('users').doc(user.uid);

  Future<void> _writeVendorPublicProfile(MarketplaceAccount account) async {
    final reference = _firestore
        .collection('vendor_public_profiles')
        .doc(account.id);
    await reference.set(
      _vendorPublicProfileData(account),
      SetOptions(merge: true),
    );
  }

  VendorStoreProfile _vendorStoreProfileFromData(
    String id,
    Map<String, dynamic> data,
  ) {
    final normalizedData = Map<String, dynamic>.from(data);
    normalizedData['profile_photo_bytes'] = _profilePhotoBytesFromValue(
      normalizedData['profile_photo_bytes'],
    );
    return VendorStoreProfile.fromJson(id, normalizedData);
  }

  Uint8List? _profilePhotoBytesFromValue(Object? value) {
    if (value is Blob) return value.bytes;
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  VendorLocation _vendorLocationFor(MarketplaceAccount account) {
    final latitude = account.latitude;
    final longitude = account.longitude;
    if (latitude == null || longitude == null) {
      throw const MarketplaceApiException(
        'Save a valid vendor map pin before publishing your location.',
      );
    }
    final location = VendorLocation(
      id: account.id,
      name: account.companyName?.trim().isNotEmpty == true
          ? account.companyName!.trim()
          : account.fullName?.trim().isNotEmpty == true
          ? account.fullName!.trim()
          : 'Local vendor',
      businessType: account.businessType,
      address: account.addressLine1 ?? '',
      latitude: latitude,
      longitude: longitude,
    );
    return location;
  }

  Map<String, dynamic> _vendorLocationData(MarketplaceAccount account) {
    final location = _vendorLocationFor(account);
    return {
      'id': location.id,
      'name': location.name,
      'business_type': location.businessType,
      'address': location.address,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _vendorPublicProfileData(MarketplaceAccount account) => {
    'id': account.id,
    'store_name': account.companyName?.trim().isNotEmpty == true
        ? account.companyName!.trim()
        : account.fullName?.trim().isNotEmpty == true
        ? account.fullName!.trim()
        : 'Local vendor',
    'owner_name': account.fullName,
    'description': account.companyDescription,
    'business_type': account.businessType,
    'address': account.addressLine1,
    'zip_code': account.zipCode,
    'phone': account.phone,
    'latitude': account.latitude,
    'longitude': account.longitude,
    'profile_photo_url': account.profilePhotoUrl,
    'profile_photo_bytes': account.profilePhotoBytes == null
        ? null
        : Blob(account.profilePhotoBytes!),
    'updated_at': FieldValue.serverTimestamp(),
  };

  ProduceListing _withDistance(ProduceListing listing, double distanceKm) =>
      ProduceListing(
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
        distanceKm: distanceKm,
        imageUrl: listing.imageUrl,
        imageBytes: listing.imageBytes,
        imageFileName: listing.imageFileName,
        ownerEmail: listing.ownerEmail,
        ownerUid: listing.ownerUid,
        imageUrls: listing.imageUrls,
        videoUrls: listing.videoUrls,
        pendingMedia: listing.pendingMedia,
        latitude: listing.latitude,
        longitude: listing.longitude,
        postedAt: listing.postedAt,
        justPosted: listing.justPosted,
        description: listing.description,
        isMine: listing.isMine,
      );

  MarketplaceAccount _accountFromData(User user, Map<String, dynamic> data) {
    final role = data['role'];
    if (role != 'Buyer' && role != 'Vendor') {
      throw const FormatException('The Firebase account has an invalid role.');
    }
    return MarketplaceAccount(
      id: user.uid,
      role: role as String,
      email: user.email ?? data['email'] as String? ?? '',
      emailVerified: true,
      fullName: data['full_name'] as String?,
      companyName: data['company_name'] as String?,
      companyDescription: data['company_description'] as String?,
      addressLine1: data['address_line_1'] as String?,
      zipCode: data['zip_code'] as String?,
      phone: data['phone'] as String?,
      taxId: data['tax_id'] as String?,
      businessType: data['business_type'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      profilePhotoUrl: data['profile_photo_url'] as String?,
      profilePhotoBytes: _profilePhotoBytesFromValue(
        data['profile_photo_bytes'],
      ),
    );
  }

  MarketplaceAccount _accountFromCredentials(
    User user,
    MarketplaceCredentials credentials,
  ) => MarketplaceAccount(
    id: user.uid,
    role: credentials.role,
    email: user.email ?? credentials.email,
    emailVerified: true,
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

  Map<String, dynamic> _accountData(MarketplaceAccount account) => {
    'role': account.role,
    'email': account.email,
    'full_name': account.fullName,
    'company_name': account.companyName,
    'company_description': account.companyDescription,
    'address_line_1': account.addressLine1,
    'zip_code': account.zipCode,
    'phone': account.phone,
    'tax_id': account.taxId,
    'business_type': account.businessType,
    'latitude': account.latitude,
    'longitude': account.longitude,
    'profile_photo_url': account.profilePhotoUrl,
    'created_at': FieldValue.serverTimestamp(),
  };

  String _authErrorMessage(FirebaseAuthException error) => switch (error.code) {
    'email-already-in-use' => 'An account already exists for this email.',
    'invalid-email' => 'Enter a valid email address.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'The email or password is incorrect.',
    'weak-password' => 'Choose a stronger password.',
    'operation-not-allowed' =>
      'Enable Email/Password sign-in in Firebase Authentication settings.',
    'network-request-failed' =>
      'Could not reach Firebase. Check your internet connection.',
    'too-many-requests' => 'Too many attempts. Please try again later.',
    _ => error.message ?? 'Firebase Authentication failed (${error.code}).',
  };


}
