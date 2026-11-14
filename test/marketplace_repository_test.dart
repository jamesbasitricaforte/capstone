import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_rescue/data/marketplace_repository.dart';
import 'package:project_rescue/models/produce_listing.dart';

void main() {
  test('demo accounts and sample listings work without a server', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);

    final account = await repository.signInDemo('Buyer');
    final listings = await repository.loadPublicListings();

    expect(account.role, 'Buyer');
    expect(listings, isNotEmpty);
  });

  test('local account registration keeps the supplied profile', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);

    final account = await repository.register(
      const MarketplaceCredentials(
        email: 'vendor@example.test',
        password: 'local-password',
        role: 'Vendor',
        fullName: 'Sample Vendor',
        companyName: 'Green Basket',
      ),
    );

    expect(account.email, 'vendor@example.test');
    expect(account.role, 'Vendor');
    expect(account.fullName, 'Sample Vendor');
    expect(account.companyName, 'Green Basket');
  });

  test('buyers can cancel reservations and restore listing stock', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'reservation-buyer@example.test',
        password: 'local-password',
        role: 'Buyer',
      ),
    );
    const listing = ProduceListing(
      id: 'reservation-cancel-listing',
      name: 'Fresh Okra',
      category: 'Vegetables',
      price: 42,
      unit: 'kg',
      quantity: '5',
      condition: 'Fresh',
      vendor: 'Green Basket',
      vendorInitials: 'GB',
      location: 'Market Road',
      imageUrl: '',
    );
    await repository.addListing(listing);

    final reservation = await repository.reserveListing(
      listing: listing,
      quantity: 2,
    );
    expect(repository.availableQuantity(listing), 3);

    await repository.register(
      const MarketplaceCredentials(
        email: 'another-buyer@example.test',
        password: 'local-password',
        role: 'Buyer',
      ),
    );
    expect(
      await repository.cancelReservation(reservationId: reservation.id),
      isFalse,
    );
    expect(repository.availableQuantity(listing), 3);

    await repository.signIn(
      const MarketplaceCredentials(
        email: 'reservation-buyer@example.test',
        password: 'local-password',
        role: 'Buyer',
      ),
    );
    expect(
      await repository.cancelReservation(reservationId: reservation.id),
      isTrue,
    );
    expect(repository.availableQuantity(listing), 5);
    expect(await repository.loadReservations(), isEmpty);
    expect(
      await repository.cancelReservation(reservationId: reservation.id),
      isFalse,
    );
  });

  test(
    'vendor storefront returns public details and that vendor listings',
    () async {
      final repository = InMemoryMarketplaceRepository();
      addTearDown(repository.dispose);
      final account = await repository.register(
        const MarketplaceCredentials(
          email: 'storefront@example.test',
          password: 'local-password',
          role: 'Vendor',
          fullName: 'Sample Owner',
          companyName: 'Green Basket',
          companyDescription: 'Fresh produce from our family farm.',
          addressLine1: 'Market Road',
          zipCode: '1000',
          phone: '09171234567',
          taxId: 'private-tax-id',
        ),
      );
      const listing = ProduceListing(
        id: 'storefront-listing',
        name: 'Fresh Okra',
        category: 'Vegetables',
        price: 42,
        unit: 'kg',
        quantity: '5',
        condition: 'Fresh',
        vendor: 'Green Basket',
        vendorInitials: 'GB',
        location: 'Market Road',
        imageUrl: '',
        ownerEmail: 'storefront@example.test',
      );
      const soldOutListing = ProduceListing(
        id: 'storefront-sold-out-listing',
        name: 'Sold-out Tomatoes',
        category: 'Vegetables',
        price: 42,
        unit: 'kg',
        quantity: '0',
        condition: 'Fresh',
        vendor: 'Green Basket',
        vendorInitials: 'GB',
        location: 'Market Road',
        imageUrl: '',
        ownerEmail: 'storefront@example.test',
      );
      await repository.addListing(listing);
      await repository.addListing(soldOutListing);

      final profile = await repository.loadVendorStoreProfile(account.id);
      final listings = await repository.loadVendorListings(account.id);

      expect(profile?.storeName, 'Green Basket');
      expect(profile?.ownerName, 'Sample Owner');
      expect(profile?.description, 'Fresh produce from our family farm.');
      expect(profile?.phone, '09171234567');
      expect(profile?.zipCode, '1000');
      expect(
        listings.map((item) => item.id),
        containsAll([listing.id, soldOutListing.id]),
      );
    },
  );

  test('a vendor account cannot sign in with the buyer account type', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'vendor-role@example.test',
        password: 'local-password',
        role: 'Vendor',
      ),
    );
    await repository.signOut();

    await expectLater(
      repository.signIn(
        const MarketplaceCredentials(
          email: 'vendor-role@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      ),
      throwsA(isA<MarketplaceApiException>()),
    );
    expect(await repository.restoreSession(), isNull);
  });

  test('accounts can update their profile photo', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'photo@example.test',
        password: 'local-password',
        role: 'Buyer',
      ),
    );
    final imageBytes = Uint8List.fromList([1, 2, 3]);

    final updatedAccount = await repository.updateProfilePhoto(
      imageBytes: imageBytes,
      imageName: 'profile.png',
    );

    expect(updatedAccount.profilePhotoBytes, imageBytes);
  });

  test('vendor storefront profile exposes its uploaded photo', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    final account = await repository.register(
      const MarketplaceCredentials(
        email: 'vendor-photo@example.test',
        password: 'local-password',
        role: 'Vendor',
        companyName: 'Photo Store',
      ),
    );
    final imageBytes = Uint8List.fromList([1, 2, 3]);
    await repository.updateProfilePhoto(
      imageBytes: imageBytes,
      imageName: 'vendor.png',
    );

    final profile = await repository.loadVendorStoreProfile(account.id);

    expect(profile?.profilePhotoBytes, imageBytes);
  });

  test('accounts can save and clear a hosted profile photo URL', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'hosted-photo@example.test',
        password: 'local-password',
        role: 'Buyer',
      ),
    );

    await expectLater(
      repository.updateProfilePhotoUrl(photoUrl: 'file:///profile.jpg'),
      throwsA(isA<MarketplaceApiException>()),
    );
    final updatedAccount = await repository.updateProfilePhotoUrl(
      photoUrl: 'https://images.example.test/profile.jpg',
    );
    expect(
      updatedAccount.profilePhotoUrl,
      'https://images.example.test/profile.jpg',
    );

    final clearedAccount = await repository.updateProfilePhotoUrl(photoUrl: '');
    expect(clearedAccount.profilePhotoUrl, isNull);
  });

  test('vendors can repost their own listing without changing stock', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'vendor@example.test',
        password: 'local-password',
        role: 'Vendor',
      ),
    );
    const listing = ProduceListing(
      id: 'vendor-listing',
      name: 'Tomatoes',
      category: 'Vegetables',
      price: 40,
      unit: 'kg',
      quantity: '12',
      condition: 'Fresh',
      vendor: 'Green Basket',
      vendorInitials: 'GB',
      location: 'Market Road',
      imageUrl: 'https://example.test/tomato.jpg',
      imageUrls: ['https://example.test/tomato.jpg'],
      videoUrls: ['https://example.test/tomato.mp4'],
      ownerEmail: 'vendor@example.test',
      latitude: 14.6,
      longitude: 120.98,
    );

    await repository.addListing(listing);
    expect(await repository.repostListing(listingId: listing.id), isTrue);

    final reposted = (await repository.loadListings()).first;
    expect(reposted.id, listing.id);
    expect(reposted.quantity, '12');
    expect(reposted.imageUrls, listing.imageUrls);
    expect(reposted.videoUrls, listing.videoUrls);
    expect(reposted.latitude, listing.latitude);
    expect(reposted.longitude, listing.longitude);
    expect(reposted.justPosted, isTrue);
    expect(reposted.postedAt, isNotNull);
  });

  test('vendors can update listing price and available stock', () async {
    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'inventory@example.test',
        password: 'local-password',
        role: 'Vendor',
      ),
    );
    const listing = ProduceListing(
      id: 'editable-listing',
      name: 'Fresh Okra',
      category: 'Vegetables',
      price: 35,
      unit: 'kg',
      quantity: '8',
      condition: 'Fresh',
      vendor: 'Green Basket',
      vendorInitials: 'GB',
      location: 'Market Road',
      imageUrl: '',
      ownerEmail: 'inventory@example.test',
    );
    await repository.addListing(listing);

    await repository.updateListing(
      const ProduceListing(
        id: 'editable-listing',
        name: 'Fresh Okra',
        category: 'Vegetables',
        price: 42,
        unit: 'kg',
        quantity: '5',
        condition: 'Fresh',
        vendor: 'Green Basket',
        vendorInitials: 'GB',
        location: 'Market Road',
        imageUrl: '',
        ownerEmail: 'inventory@example.test',
      ),
    );

    final updated = (await repository.loadListings()).singleWhere(
      (item) => item.id == listing.id,
    );
    expect(updated.price, 42);
    expect(updated.quantity, '5');
    expect(repository.availableQuantity(updated), 5);
  });

  test(
    'favorites persist for the account and verification stays pending',
    () async {
      final buyer = InMemoryMarketplaceRepository();
      final vendor = InMemoryMarketplaceRepository();
      addTearDown(buyer.dispose);
      addTearDown(vendor.dispose);
      await buyer.register(
        const MarketplaceCredentials(
          email: 'favorite-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      );
      await buyer.setFavorite(listingId: 'tomatoes', saved: true);
      expect(await buyer.loadFavorites(), contains('tomatoes'));

      await vendor.register(
        const MarketplaceCredentials(
          email: 'verification-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      await vendor.requestVendorVerification();
      final trust = await vendor.loadVendorTrust(
        'verification-vendor@example.test',
      );
      expect(trust.verificationStatus, 'pending');
      expect(trust.reviewCount, 0);
    },
  );

  test(
    'vendor reviews require a completed purchase and are single-use',
    () async {
      final vendor = InMemoryMarketplaceRepository();
      final buyer = InMemoryMarketplaceRepository();
      final otherBuyer = InMemoryMarketplaceRepository();
      addTearDown(vendor.dispose);
      addTearDown(buyer.dispose);
      addTearDown(otherBuyer.dispose);
      await vendor.register(
        const MarketplaceCredentials(
          email: 'review-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      const listing = ProduceListing(
        id: 'review-listing',
        name: 'Fresh Peppers',
        category: 'Vegetables',
        price: 45,
        unit: 'kg',
        quantity: '6',
        condition: 'Fresh',
        vendor: 'Pepper Farm',
        vendorInitials: 'PF',
        location: 'Market Road',
        imageUrl: '',
        ownerEmail: 'review-vendor@example.test',
      );
      await vendor.addListing(listing);
      await buyer.register(
        const MarketplaceCredentials(
          email: 'review-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
          fullName: 'Sample Customer',
        ),
      );
      final profilePhoto = Uint8List.fromList([4, 5, 6]);
      await buyer.updateProfilePhoto(
        imageBytes: profilePhoto,
        imageName: 'customer.png',
      );
      final order = await buyer.buyListing(listing: listing, quantity: 1);
      await expectLater(
        buyer.reviewVendor(
          vendorId: 'review-vendor@example.test',
          orderId: order.id,
          rating: 5,
          comment: 'Great produce',
        ),
        throwsA(isA<MarketplaceApiException>()),
      );

      await vendor.updateVendorOrder(orderId: order.id, status: 'approved');
      await vendor.updateVendorOrder(orderId: order.id, status: 'completed');
      await expectLater(
        buyer.reviewVendor(
          vendorId: 'review-vendor@example.test',
          orderId: order.id,
          rating: 5,
          comment: '  ',
        ),
        throwsA(isA<MarketplaceApiException>()),
      );
      await expectLater(
        buyer.reviewVendor(
          vendorId: 'another-vendor@example.test',
          orderId: order.id,
          rating: 5,
          comment: 'Wrong vendor',
        ),
        throwsA(isA<MarketplaceApiException>()),
      );
      await expectLater(
        buyer.reviewVendor(
          vendorId: 'review-vendor@example.test',
          orderId: order.id,
          rating: 6,
          comment: 'Invalid rating',
        ),
        throwsA(isA<MarketplaceApiException>()),
      );
      await otherBuyer.register(
        const MarketplaceCredentials(
          email: 'review-other-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      );
      await expectLater(
        otherBuyer.reviewVendor(
          vendorId: 'review-vendor@example.test',
          orderId: order.id,
          rating: 5,
          comment: 'Not my transaction',
        ),
        throwsA(isA<MarketplaceApiException>()),
      );
      await buyer.reviewVendor(
        vendorId: 'review-vendor@example.test',
        orderId: order.id,
        rating: 4,
        comment: 'Great produce',
      );
      await otherBuyer.buyListing(listing: listing, quantity: 1);
      final secondOrder = (await otherBuyer.loadOrders()).single;
      await vendor.updateVendorOrder(
        orderId: secondOrder.id,
        status: 'approved',
      );
      await vendor.updateVendorOrder(
        orderId: secondOrder.id,
        status: 'completed',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await otherBuyer.reviewVendor(
        vendorId: 'review-vendor@example.test',
        orderId: secondOrder.id,
        rating: 5,
        comment: 'Fresh and carefully packed',
      );
      final trust = await otherBuyer.loadVendorTrust(
        'REVIEW-VENDOR@example.test',
      );
      expect(trust.averageRating, 4.5);
      expect(trust.reviewCount, 2);
      expect(trust.ratingBreakdown, {1: 0, 2: 0, 3: 0, 4: 1, 5: 1});
      expect(trust.reviews.first.orderId, secondOrder.id);
      expect(trust.reviews.first.buyerName, 'Marketplace customer');
      expect(trust.reviews.first.isVerifiedPurchase, isTrue);
      expect(trust.reviews.last.buyerName, 'Sample Customer');
      expect(trust.reviews.last.buyerUid, 'review-buyer@example.test');
      expect(trust.reviews.last.buyerPhotoBytes, profilePhoto);
      await expectLater(
        buyer.reviewVendor(
          vendorId: 'review-vendor@example.test',
          orderId: order.id,
          rating: 5,
          comment: 'Duplicate',
        ),
        throwsA(isA<MarketplaceApiException>()),
      );
    },
  );

  test('buyers can leave one unverified store rating and feedback', () async {
    final buyer = InMemoryMarketplaceRepository();
    addTearDown(buyer.dispose);
    await buyer.register(
      const MarketplaceCredentials(
        email: 'store-feedback-buyer@example.test',
        password: 'local-password',
        role: 'Buyer',
        fullName: 'Sample Customer',
      ),
    );

    await buyer.reviewVendor(
      vendorId: 'store-feedback-vendor@example.test',
      rating: 4,
      comment: 'Friendly vendor and fresh produce.',
    );

    final trust = await buyer.loadVendorTrust(
      'store-feedback-vendor@example.test',
    );
    expect(trust.averageRating, 4);
    expect(trust.reviewCount, 1);
    expect(trust.reviews.single.orderId, isNull);
    expect(trust.reviews.single.isVerifiedPurchase, isFalse);
    expect(trust.reviews.single.buyerUid, 'store-feedback-buyer@example.test');
    expect(trust.reviews.single.comment, 'Friendly vendor and fresh produce.');
    await expectLater(
      buyer.reviewVendor(
        vendorId: 'store-feedback-vendor@example.test',
        rating: 5,
        comment: 'A second store rating.',
      ),
      throwsA(isA<MarketplaceApiException>()),
    );
  });

  test(
    'buyers can hide their order without removing the vendor order',
    () async {
      final repository = InMemoryMarketplaceRepository();
      addTearDown(repository.dispose);
      await repository.register(
        const MarketplaceCredentials(
          email: 'order-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      const listing = ProduceListing(
        id: 'order-history-listing',
        name: 'Fresh Tomatoes',
        category: 'Vegetables',
        price: 40,
        unit: 'kg',
        quantity: '5',
        condition: 'Fresh',
        vendor: 'Green Basket',
        vendorInitials: 'GB',
        location: 'Market Road',
        imageUrl: '',
        ownerEmail: 'order-vendor@example.test',
      );
      await repository.addListing(listing);

      await repository.register(
        const MarketplaceCredentials(
          email: 'order-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      );
      final order = await repository.buyListing(listing: listing, quantity: 1);
      expect(await repository.deleteBuyerOrder(orderId: order.id), isTrue);
      expect(await repository.loadOrders(), isEmpty);
      expect(await repository.deleteBuyerOrder(orderId: order.id), isFalse);

      await repository.signIn(
        const MarketplaceCredentials(
          email: 'order-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      expect(await repository.loadVendorOrders(), hasLength(1));
    },
  );

  test(
    'vendors can decline an order and restore the available stock',
    () async {
      final vendor = InMemoryMarketplaceRepository();
      final buyer = InMemoryMarketplaceRepository();
      addTearDown(vendor.dispose);
      addTearDown(buyer.dispose);
      await vendor.register(
        const MarketplaceCredentials(
          email: 'approval-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      const listing = ProduceListing(
        id: 'approval-listing',
        name: 'Fresh Tomatoes',
        category: 'Vegetables',
        price: 40,
        unit: 'kg',
        quantity: '8',
        condition: 'Fresh',
        vendor: 'Green Basket',
        vendorInitials: 'GB',
        location: 'Market Road',
        imageUrl: '',
        ownerEmail: 'approval-vendor@example.test',
      );
      await vendor.addListing(listing);
      await buyer.register(
        const MarketplaceCredentials(
          email: 'approval-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      );
      final order = await buyer.buyListing(listing: listing, quantity: 3);
      expect(order.status, 'pending_vendor_confirmation');
      expect(buyer.availableQuantity(listing), 5);

      await vendor.signIn(
        const MarketplaceCredentials(
          email: 'approval-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      expect(
        await vendor.updateVendorOrder(orderId: order.id, status: 'declined'),
        isTrue,
      );
      expect(vendor.availableQuantity(listing), 8);
      expect((await vendor.loadVendorOrders()).single.status, 'declined');
      expect(
        await vendor.updateVendorOrder(orderId: order.id, status: 'approved'),
        isFalse,
      );

      await buyer.signIn(
        const MarketplaceCredentials(
          email: 'approval-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      );
      expect((await buyer.loadOrders()).single.items.single.status, 'declined');
    },
  );

  test(
    'chat image messages can be deleted from only one participant view',
    () async {
      final vendor = InMemoryMarketplaceRepository();
      final buyer = InMemoryMarketplaceRepository();
      addTearDown(vendor.dispose);
      addTearDown(buyer.dispose);
      final registeredVendor = await vendor.register(
        const MarketplaceCredentials(
          email: 'chat-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      final vendorPhoto = Uint8List.fromList([7, 8, 9]);
      final vendorAccount = await vendor.updateProfilePhoto(
        imageBytes: vendorPhoto,
        imageName: 'vendor.png',
      );
      expect(vendorAccount.id, registeredVendor.id);
      await buyer.register(
        const MarketplaceCredentials(
          email: 'chat-buyer@example.test',
          password: 'local-password',
          role: 'Buyer',
        ),
      );
      final buyerPhoto = Uint8List.fromList([1, 2, 3]);
      final buyerAccount = await buyer.updateProfilePhoto(
        imageBytes: buyerPhoto,
        imageName: 'buyer.jpg',
      );
      final conversation = await buyer.openConversation(
        listingId: 'chat-listing',
        listingName: 'Fresh Tomatoes',
        otherUserId: vendorAccount.id,
        otherName: 'Green Basket',
      );
      expect(conversation.buyerPhotoBytes, buyerPhoto);
      await buyer.sendMessage(
        conversationId: conversation.id,
        text: 'Is this available?',
        imageBytes: Uint8List.fromList([1, 2, 3]),
        imageName: 'produce.jpg',
      );
      final originalMessage =
          (await buyer.watchMessages(conversation.id).first).single;
      expect(originalMessage.imageBytes, [1, 2, 3]);

      await buyer.deleteMessageForMe(
        conversationId: conversation.id,
        messageId: originalMessage.id,
      );
      expect(await buyer.watchMessages(conversation.id).first, isEmpty);

      await vendor.signIn(
        const MarketplaceCredentials(
          email: 'chat-vendor@example.test',
          password: 'local-password',
          role: 'Vendor',
        ),
      );
      final vendorConversation = await vendor.openConversation(
        listingId: 'chat-listing',
        listingName: 'Fresh Tomatoes',
        otherUserId: buyerAccount.id,
        otherName: buyerAccount.email,
      );
      expect(vendorConversation.vendorPhotoBytes, vendorPhoto);
      expect(vendorConversation.buyerPhotoBytes, buyerPhoto);
      expect(
        (await vendor.watchMessages(conversation.id).first).single.text,
        'Is this available?',
      );
      expect(
        (await vendor.loadConversations()).single.buyerUid,
        buyerAccount.id,
      );
    },
  );
}
