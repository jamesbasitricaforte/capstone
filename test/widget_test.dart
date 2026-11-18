import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:project_rescue/data/marketplace_service.dart';
import 'package:project_rescue/data/marketplace_repository.dart';
import 'package:project_rescue/data/location_services.dart';
import 'package:project_rescue/main.dart';
import 'package:project_rescue/models/marketplace_messaging.dart';
import 'package:project_rescue/models/produce_listing.dart';
import 'package:project_rescue/models/marketplace_purchase.dart';
import 'package:project_rescue/models/marketplace_trust.dart';
import 'package:project_rescue/models/vendor_store_profile.dart';
import 'package:project_rescue/widgets/profile_photo_avatar.dart';
import 'package:project_rescue/widgets/marketplace_messages_page.dart';
import 'package:project_rescue/widgets/vendor_locations_page.dart';
import 'package:latlong2/latlong.dart';

Future<void> registerBuyer(
  WidgetTester tester, {
  String email = 'buyer@example.com',
}) async {
  await tester.tap(find.text('Create your account'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), 'password123');
  await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> openMarketFromExplore(WidgetTester tester) async {
  final desktopMarketButton = find.byTooltip('Market');
  if (desktopMarketButton.evaluate().isNotEmpty) {
    await tester.tap(desktopMarketButton);
  } else {
    await tester.tap(find.text('Market').last);
  }
  await tester.pumpAndSettle();
}

class _VendorRoleRepository extends InMemoryMarketplaceRepository {
  @override
  Future<MarketplaceAccount> signIn(MarketplaceCredentials credentials) async {
    return const MarketplaceAccount(
      id: 'vendor-1',
      role: 'Vendor',
      email: 'vendor@example.com',
      companyName: 'Green Basket',
    );
  }

  @override
  Future<List<MarketplaceNotification>> loadNotifications() async => [];

  @override
  Stream<MarketplaceNotification> watchVendorNotifications() =>
      const Stream.empty();

  @override
  Future<List<ProduceOrder>> loadVendorOrders() async => [
    ProduceOrder(
      id: 'vendor-order-1',
      items: [
        MarketplaceCartItem(
          listing: const ProduceListing(
            id: 'tomatoes',
            name: 'Fresh Tomatoes',
            category: 'Vegetables',
            price: 40,
            unit: 'kg',
            quantity: '8',
            condition: 'Fresh',
            vendor: 'Green Basket',
            vendorInitials: 'GB',
            location: 'Central Market',
            imageUrl: '',
            ownerEmail: 'vendor@example.com',
          ),
          quantity: 2,
        ),
      ],
      buyerEmail: 'buyer@example.com',
      createdAt: DateTime.utc(2026, 10, 29),
      totalAmount: 80,
    ),
  ];
}

class _NotificationFailureRepository extends InMemoryMarketplaceRepository {
  @override
  Future<List<MarketplaceNotification>> loadNotifications() async {
    throw const MarketplaceApiException('Notification service unavailable.');
  }
}

class _LiveVendorNotificationRepository extends InMemoryMarketplaceRepository {
  final StreamController<MarketplaceNotification> _notifications =
      StreamController<MarketplaceNotification>.broadcast();

  @override
  bool get supportsRemoteListings => true;

  @override
  Future<List<MarketplaceNotification>> loadNotifications() async => [];

  @override
  Stream<MarketplaceNotification> watchVendorNotifications() =>
      _notifications.stream;

  void addNotification(MarketplaceNotification notification) {
    _notifications.add(notification);
  }

  @override
  void dispose() {
    _notifications.close();
    super.dispose();
  }
}

class _ImageListingRepository extends InMemoryMarketplaceRepository {
  _ImageListingRepository(this.imageBytes);

  final Uint8List imageBytes;

  ProduceListing get _listing => ProduceListing(
    id: 'image-listing',
    name: 'Image listing',
    category: 'Vegetables',
    price: 40,
    unit: 'kg',
    quantity: '5',
    condition: 'Fresh',
    vendor: 'Green Basket',
    vendorInitials: 'GB',
    location: 'Central Market',
    imageUrl: '',
    imageBytes: imageBytes,
  );

  @override
  Future<List<ProduceListing>> loadListings() async => [_listing];

  @override
  Future<List<ProduceListing>> loadPublicListings() async => [_listing];
}

class _VendorStoreBrowsingRepository extends InMemoryMarketplaceRepository {
  _VendorStoreBrowsingRepository(this.photoBytes);

  final Uint8List photoBytes;

  final _listing = ProduceListing(
    id: 'guest-store-listing',
    name: 'Guest Store Tomatoes',
    category: 'Vegetables',
    price: 40,
    unit: 'kg',
    quantity: '5',
    condition: 'Fresh',
    vendor: 'Guest Store',
    vendorInitials: 'GS',
    location: 'Market Road',
    imageUrl: '',
    ownerUid: 'guest-vendor-uid',
    postedAt: DateTime(2026, 11, 14, 14, 5, 9),
  );

  @override
  Future<List<ProduceListing>> loadPublicListings() async => [
    publicListing(_listing),
  ];

  @override
  Future<List<ProduceListing>> loadListings() async => loadPublicListings();

  @override
  Future<VendorStoreProfile?> loadVendorStoreProfile(String vendorId) async {
    if (vendorId != 'guest-vendor-uid') return null;
    return VendorStoreProfile(
      id: 'guest-vendor-uid',
      storeName: 'Guest Store',
      ownerName: 'Guest Vendor',
      address: 'Market Road',
      profilePhotoBytes: photoBytes,
    );
  }

  @override
  Future<List<ProduceListing>> loadVendorListings(String vendorId) async =>
      vendorId == 'guest-vendor-uid' ? [_listing] : [];
}

class _NonOwnerVendorRepository extends InMemoryMarketplaceRepository {
  final listing = const ProduceListing(
    id: 'other-vendor-listing',
    name: 'Other vendor produce',
    category: 'Vegetables',
    price: 55,
    unit: 'kg',
    quantity: '31',
    condition: 'Fresh',
    vendor: 'Other Vendor',
    vendorInitials: 'OV',
    location: 'Other market',
    imageUrl: '',
    ownerEmail: 'another-vendor@example.com',
  );
  int removalCalls = 0;

  @override
  Future<MarketplaceAccount> signIn(MarketplaceCredentials credentials) async {
    return const MarketplaceAccount(
      id: 'vendor-1',
      role: 'Vendor',
      email: 'vendor@example.com',
      companyName: 'Current vendor',
    );
  }

  @override
  Future<List<MarketplaceNotification>> loadNotifications() async => [];

  @override
  Stream<MarketplaceNotification> watchVendorNotifications() =>
      const Stream.empty();

  @override
  Future<List<ProduceListing>> loadListings() async => [listing];

  @override
  Future<List<ProduceListing>> loadPublicListings() async => [listing];

  @override
  Future<bool> removeListing({required String listingId}) async {
    removalCalls++;
    throw const MarketplaceApiException(
      'You can only remove your own listings.',
      statusCode: 403,
    );
  }
}

class _ReviewedListingRepository extends InMemoryMarketplaceRepository {
  @override
  Future<VendorTrustSummary> loadVendorTrust(String vendorId) async =>
      VendorTrustSummary(
        verificationStatus: 'not_requested',
        averageRating: 4,
        reviewCount: 1,
        reviews: [
          MarketplaceReview(
            id: 'review-1',
            vendorId: vendorId,
            buyerEmail: 'private-buyer@example.com',
            buyerName: 'Sample customer',
            orderId: 'order-1',
            rating: 4,
            comment: 'Fresh produce and friendly service.',
            isVerifiedPurchase: true,
            createdAt: DateTime.utc(2026, 11, 1),
          ),
        ],
      );
}

class _FakeDeviceLocationService implements DeviceLocationService {
  _FakeDeviceLocationService({this.error});

  final DeviceLocationException? error;
  int requestCount = 0;
  int appSettingsCount = 0;
  int locationSettingsCount = 0;

  @override
  Future<LatLng> currentLocation() async {
    requestCount++;
    if (error != null) throw error!;
    return const LatLng(14.5, 120.9);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCount++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCount++;
    return true;
  }
}

class _FailingReverseGeocoder implements ReverseGeocoder {
  @override
  Future<String?> addressFor(LatLng location) async {
    throw const MarketplaceApiException(
      'The marketplace API did not respond in time.',
    );
  }
}

class _FakeReverseGeocoder implements ReverseGeocoder {
  @override
  Future<String?> addressFor(LatLng location) async => 'Market Road, Manila';
}

class _NearbyMarketplaceRepository extends InMemoryMarketplaceRepository {
  LatLng? requestedLocation;
  double? requestedRadius;

  @override
  Future<List<ProduceListing>> loadNearbyListings({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    requestedLocation = LatLng(latitude, longitude);
    requestedRadius = radiusKm;
    return [
      const ProduceListing(
        id: 'nearby-pechay',
        name: 'Nearby pechay',
        category: 'Vegetables',
        price: 35,
        unit: 'bundle',
        quantity: '4',
        condition: 'Fresh',
        vendor: 'Green Basket',
        vendorInitials: 'GB',
        location: 'Central Market',
        distanceKm: 0.6,
        imageUrl: '',
      ),
    ];
  }
}

void main() {
  testWidgets('message inbox shows participant names and delete action', (
    tester,
  ) async {
    var deleteTapped = false;
    final conversation = MarketplaceConversation(
      id: 'pair:buyer:vendor',
      listingId: 'listing-1',
      listingName: 'Fresh Tomatoes',
      buyerUid: 'buyer',
      vendorUid: 'vendor',
      buyerLabel: 'Buyer Name',
      vendorLabel: 'Green Basket',
      updatedAt: DateTime(2026),
      lastMessage: 'Hello',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MarketplaceMessagesPage(
          conversations: [conversation],
          isLoading: false,
          error: null,
          onRefresh: () {},
          onOpenConversation: (_) {},
          onDeleteConversation: (_) async {
            deleteTapped = true;
          },
          deletingConversationIds: const {},
          currentUserId: 'buyer',
        ),
      ),
    );

    expect(find.text('Green Basket'), findsOneWidget);
    expect(find.text('vendor@example.com'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete conversation'));
    await tester.pumpAndSettle();
    expect(deleteTapped, isTrue);
  });

  testWidgets(
    'chat header omits listing category and shows participant email',
    (tester) async {
      final repository = InMemoryMarketplaceRepository()
        ..setAuthenticatedAccount(
          const MarketplaceAccount(
            id: 'buyer',
            role: 'Buyer',
            email: 'buyer@example.com',
          ),
        );
      addTearDown(repository.dispose);
      final conversation = MarketplaceConversation(
        id: 'pair:buyer:vendor',
        listingId: 'listing-1',
        listingName: 'Vegetables',
        buyerUid: 'buyer',
        vendorUid: 'vendor',
        buyerLabel: 'Buyer Name',
        vendorLabel: 'vendor@example.com',
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarketplaceConversationDialog(
              repository: repository,
              conversation: conversation,
              currentUserId: 'buyer',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('vendor@example.com'), findsOneWidget);
      expect(find.text('Vegetables'), findsNothing);
    },
  );

  testWidgets(
    'unverified accounts still open the marketplace without email checks',
    (tester) async {
      final repository = InMemoryMarketplaceRepository()
        ..setAuthenticatedAccount(
          const MarketplaceAccount(
            id: 'unverified-buyer',
            role: 'Buyer',
            email: 'unverified@example.com',
            emailVerified: false,
          ),
        );
      addTearDown(repository.dispose);

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Verify your email address'), findsNothing);
      expect(find.textContaining('unverified@example.com'), findsNothing);
      expect(find.byType(Scaffold), findsWidgets);
    },
  );

  test('verification resend requests are rate-limited once per minute', () {
    final now = DateTime(2024, 1, 1, 12, 0, 0);
    final recent = now.subtract(const Duration(seconds: 30));
    final stale = now.subtract(const Duration(minutes: 2));

    expect(
      MarketplaceScreen.isVerificationEmailResendAllowed(recent, now: now),
      isFalse,
    );
    expect(
      MarketplaceScreen.isVerificationEmailResendAllowed(stale, now: now),
      isTrue,
    );
    expect(
      MarketplaceScreen.isVerificationEmailResendAllowed(null, now: now),
      isTrue,
    );
  });

  testWidgets('verified email status is shown in the account profile', (
    tester,
  ) async {
    final repository = InMemoryMarketplaceRepository()
      ..setAuthenticatedAccount(
        const MarketplaceAccount(
          id: 'verified-buyer',
          role: 'Buyer',
          email: 'verified@example.com',
        ),
      );
    addTearDown(repository.dispose);

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();

    expect(find.text('Email verification'), findsOneWidget);
    expect(find.text('Verified by Firebase Authentication'), findsOneWidget);
    final deleteAccountButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Delete account'),
    );
    expect(deleteAccountButton.onPressed, isNull);
    expect(find.text('Account deletion'), findsOneWidget);
  });

  testWidgets('buyer cart stays in the header, not bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryMarketplaceRepository()
      ..setAuthenticatedAccount(
        const MarketplaceAccount(
          id: 'buyer-with-cart',
          role: 'Buyer',
          email: 'buyer@example.com',
        ),
      );
    addTearDown(repository.dispose);

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Cart'), findsNothing);
    expect(find.byTooltip('Shopping cart'), findsOneWidget);
    await tester.tap(find.byTooltip('Shopping cart'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('transaction and market tabs open their respective pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryMarketplaceRepository()
      ..setAuthenticatedAccount(
        const MarketplaceAccount(
          id: 'buyer-navigation',
          role: 'Buyer',
          email: 'buyer@example.com',
        ),
      );
    addTearDown(repository.dispose);

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);

    await tester.tap(find.text('Transaction'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Review your purchases and reservations.'),
      findsOneWidget,
    );
    expect(find.text('No purchases yet.'), findsOneWidget);

    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    expect(find.text('Market'), findsOneWidget);
  });

  testWidgets('map location picker fits a compact phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1706);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => MapLocationPickerDialog(
                    locationService: _FakeDeviceLocationService(
                      error: const DeviceLocationException(
                        DeviceLocationIssue.unavailable,
                        'Location is unavailable.',
                      ),
                    ),
                  ),
                ),
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Location unavailable:'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('address lookup timeout does not invalidate GPS location', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1706);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => MapLocationPickerDialog(
                    locationService: _FakeDeviceLocationService(),
                    reverseGeocoder: _FailingReverseGeocoder(),
                    resolveAddress: true,
                  ),
                ),
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(find.text('Location selected'), findsOneWidget);
    expect(find.textContaining('14.5'), findsNothing);
    expect(find.textContaining('120.9'), findsNothing);
    expect(find.textContaining('Address lookup failed.'), findsOneWidget);
    expect(find.textContaining('Location unavailable:'), findsNothing);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Use this location'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome has a separate background photo from sign-in banner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sign in'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.eco_outlined).first).dx,
      lessThan(60),
    );
    expect(find.byType(Image), findsOneWidget);
    final homeBackground = tester.widget<Image>(find.byType(Image).first).image;
    expect(
      homeBackground,
      isA<NetworkImage>().having(
        (image) => image.url,
        'background image URL',
        contains('photo-1542838132-92c53300491e'),
      ),
    );

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Local Produce'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(
      tester.widgetList<Image>(find.byType(Image)).map((image) => image.image),
      contains(
        isA<AssetImage>().having(
          (image) => image.assetName,
          'hero image asset',
          'assets/images/produce_market_hero.jpg',
        ),
      ),
    );
  });

  testWidgets('sign-in offers an email password reset dialog', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsWidgets);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('sign in does not show role demo options', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('OR TRY A ROLE DEMO'), findsNothing);
    expect(find.text('Buyer demo'), findsNothing);
    expect(find.text('Vendor demo'), findsNothing);
    expect(find.text('Sign in to Local Produce'), findsOneWidget);
    expect(find.textContaining('Are you a vendor?'), findsNothing);
  });

  testWidgets('vendor navigation follows the authenticated API role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: _VendorRoleRepository()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vendor').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'vendor@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Account: Vendor'), findsOneWidget);
    expect(find.text('Cart'), findsNothing);
    expect(find.byTooltip('Post produce'), findsOneWidget);
    expect(find.text('Profile'), findsNothing);
    expect(find.text('Notification'), findsNothing);

    await tester.tap(find.byTooltip('Account: Vendor'));
    await tester.pumpAndSettle();
    expect(find.text('Vendor account'), findsOneWidget);
    expect(find.text('Store dashboard'), findsNothing);
    expect(find.text('Units in stock'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'View transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Orders (1)'), findsOneWidget);
    expect(find.textContaining('Buyer: buyer@example.com'), findsOneWidget);
    expect(find.textContaining('Fresh Tomatoes'), findsWidgets);
    await tester.tap(find.byTooltip('Store dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Store dashboard'), findsOneWidget);
    expect(find.text('Units in stock'), findsOneWidget);
    expect(find.text('Orders (1)'), findsNothing);
  });

  testWidgets('vendor cannot sign in when buyer account type is selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'registered-vendor@example.test',
        password: 'local-password',
        role: 'Vendor',
      ),
    );
    await repository.signOut();

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'registered-vendor@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'local-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This account is registered as Vendor.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Account: Vendor'), findsNothing);
  });

  testWidgets('marketplace loads and filters produce', (tester) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('For buyers'), findsOneWidget);
    expect(find.text('For vendors'), findsOneWidget);
    expect(
      find.textContaining('shop directly from nearby vendors'),
      findsOneWidget,
    );
    expect(find.textContaining('reach local buyers'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Card).first,
        matching: find.text('For buyers'),
      ),
      findsNothing,
    );
    expect(
      tester.getCenter(find.text('For buyers')).dy,
      greaterThan(tester.getCenter(find.text('Create your account')).dy),
    );
    expect(find.byType(TextField), findsNothing);
    await registerBuyer(tester);

    expect(find.textContaining('Good food grows'), findsOneWidget);
    expect(find.text('Search tomatoes, mangoes, pechay...'), findsNothing);
    expect(find.text('Good food, good neighbors.'), findsOneWidget);
    expect(find.text('Browse the market'), findsNothing);
    expect(find.text('Open Market'), findsNothing);
    await openMarketFromExplore(tester);
    expect(find.text('Search tomatoes, mangoes, pechay...'), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsWidgets);
    expect(
      find.text('Bring your local produce to nearby buyers.'),
      findsNothing,
    );
    expect(find.text('Ripe Carabao Mangoes'), findsOneWidget);
    expect(find.text('180+'), findsNothing);
    expect(find.text('2.4t'), findsNothing);
    expect(find.text('Stock & waste report'), findsNothing);
    expect(find.text('86%'), findsNothing);

    await tester.tap(find.text('Under ₱50'));
    await tester.pumpAndSettle();

    expect(find.text('Fresh Tomatoes'), findsWidgets);
    expect(find.text('Crisp Pechay'), findsOneWidget);
    expect(find.text('Ripe Carabao Mangoes'), findsNothing);
  });

  testWidgets('notification loading failure does not hide market listings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _NotificationFailureRepository();
    addTearDown(repository.dispose);
    await repository.register(
      const MarketplaceCredentials(
        email: 'notifications-unavailable@example.test',
        password: 'local-password',
        role: 'Buyer',
      ),
    );
    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();

    await openMarketFromExplore(tester);
    expect(find.text('Fresh Tomatoes'), findsWidgets);
    expect(find.text('We couldn’t load the market listings.'), findsNothing);
    expect(find.textContaining('Could not load notifications'), findsOneWidget);
  });

  testWidgets('vendor purchase notification displays the red count badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _LiveVendorNotificationRepository();
    addTearDown(repository.dispose);
    repository.setAuthenticatedAccount(
      const MarketplaceAccount(
        id: 'vendor-notification-uid',
        role: 'Vendor',
        email: 'vendor-notification@example.test',
      ),
    );
    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();

    repository.addNotification(
      MarketplaceNotification(
        id: 'new-vendor-purchase',
        type: MarketplaceNotificationType.purchase,
        listing: const ProduceListing(
          id: 'vendor-notification-listing',
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
        ),
        recipientUid: 'vendor-notification-uid',
        targetRole: 'Vendor',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    final notificationButton = find.byTooltip('Notification');
    expect(notificationButton, findsOneWidget);
    expect(
      find.ancestor(
        of: notificationButton,
        matching: find.byType(NavigationDestination),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<Badge>(
            find.descendant(
              of: notificationButton,
              matching: find.byType(Badge),
            ),
          )
          .isLabelVisible,
      isTrue,
    );
    expect(
      find.descendant(of: notificationButton, matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets('produce cards display image bytes from Firestore', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    await tester.pumpWidget(
      MyApp(repository: _ImageListingRepository(imageBytes)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
  });

  testWidgets('nearby location is requested only after an explicit action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final locationService = _FakeDeviceLocationService(
      error: const DeviceLocationException(
        DeviceLocationIssue.permissionPermanentlyDenied,
        'Location permission is blocked.',
      ),
    );
    final repository = _NearbyMarketplaceRepository();
    await tester.pumpWidget(
      MyApp(repository: repository, deviceLocationService: locationService),
    );
    await tester.pumpAndSettle();
    expect(locationService.requestCount, 0);

    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Nearby'));
    await tester.pumpAndSettle();
    expect(locationService.requestCount, 0);
    expect(find.text('Choose on map'), findsWidgets);

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(locationService.requestCount, 1);
    expect(repository.requestedLocation, isNull);
    expect(
      find.textContaining('Location permission is blocked.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(locationService.appSettingsCount, 1);
  });

  testWidgets('disabled location services offer device settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final locationService = _FakeDeviceLocationService(
      error: const DeviceLocationException(
        DeviceLocationIssue.servicesDisabled,
        'Location services are turned off.',
      ),
    );
    await tester.pumpWidget(
      MyApp(
        repository: InMemoryMarketplaceRepository(),
        deviceLocationService: locationService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Nearby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Location services are turned off.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(locationService.locationSettingsCount, 1);
  });

  testWidgets('denied permission leaves map selection and browsing available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final locationService = _FakeDeviceLocationService(
      error: const DeviceLocationException(
        DeviceLocationIssue.permissionDenied,
        'Location permission was denied.',
      ),
    );
    final repository = _NearbyMarketplaceRepository();
    await tester.pumpWidget(
      MyApp(repository: repository, deviceLocationService: locationService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Nearby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Location permission was denied.'),
      findsOneWidget,
    );
    expect(find.text('Choose on map'), findsWidgets);
    expect(find.text('Browse without distance sorting'), findsOneWidget);
    expect(repository.requestedLocation, isNull);
  });

  testWidgets('nearby results use the confirmed device coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final locationService = _FakeDeviceLocationService();
    final repository = _NearbyMarketplaceRepository();
    await tester.pumpWidget(
      MyApp(repository: repository, deviceLocationService: locationService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Nearby'));
    await tester.pumpAndSettle();
    final radiusSlider = find.byType(Slider);
    expect(tester.widget<Slider>(radiusSlider).max, 100);
    final sliderRect = tester.getRect(radiusSlider);
    await tester.dragFrom(
      Offset(sliderRect.left + 24, sliderRect.center.dy),
      Offset(sliderRect.width, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('100 km'), findsOneWidget);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(repository.requestedLocation, const LatLng(14.5, 120.9));
    expect(repository.requestedRadius, 100);
    expect(find.text('Nearby pechay'), findsOneWidget);
    expect(find.textContaining('0.6 km'), findsOneWidget);
  });

  testWidgets('guests browse listings and resume cart action after signup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    expect(find.text('Search tomatoes, mangoes, pechay...'), findsNothing);
    expect(find.text('Fresh Tomatoes'), findsNothing);
    await openMarketFromExplore(tester);

    expect(
      find.text(
        'Browsing as guest · All locations · device location is not used',
      ),
      findsOneWidget,
    );
    expect(find.text('Search tomatoes, mangoes, pechay...'), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsWidgets);

    await tester.tap(find.byTooltip('Back to welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Browse as guest'), findsOneWidget);
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);
    expect(find.text('Search tomatoes, mangoes, pechay...'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Save listing').first);
    await tester.tap(find.byTooltip('Save listing').first);
    await tester.pumpAndSettle();
    expect(find.text('Join the neighborhood market'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('View produce').first);
    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();
    expect(find.text('Contact vendor'), findsOneWidget);
    expect(find.textContaining("Aling Rosa's Produce"), findsWidgets);
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    expect(find.text('Join the neighborhood market'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'guest-to-buyer@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Shopping cart (1 items)'), findsOneWidget);
    await tester.tap(find.byTooltip('Shopping cart (1 items)'));
    await tester.pumpAndSettle();
    expect(find.text('Shopping cart'), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsOneWidget);
  });

  testWidgets('listing details can be opened from a produce card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);

    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();

    expect(find.text('AVAILABLE QUANTITY'), findsOneWidget);
    expect(find.text('Contact vendor'), findsOneWidget);
    expect(find.text('View pickup'), findsOneWidget);
  });

  testWidgets('buyers can open a vendor store and view its produce', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);

    await tester.tap(find.text("Aling Rosa's Produce").first);
    await tester.pumpAndSettle();

    expect(find.text('Products from this store'), findsOneWidget);
    expect(find.text('Poblacion Market'), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsWidgets);
  });

  testWidgets('buyers can message a vendor from the vendor store page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _VendorStoreBrowsingRepository(Uint8List(0));
    addTearDown(repository.dispose);
    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);

    await tester.tap(find.text('Guest Store').first);
    await tester.pumpAndSettle();
    expect(find.text('Message vendor'), findsOneWidget);

    await tester.tap(find.text('Message vendor'));
    await tester.pumpAndSettle();

    expect(find.text('Start the conversation with a message.'), findsOneWidget);
  });

  testWidgets('guests can open a vendor store from public listings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final photoBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    await tester.pumpWidget(
      MyApp(repository: _VendorStoreBrowsingRepository(photoBytes)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse as guest'));
    await tester.pumpAndSettle();
    await openMarketFromExplore(tester);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Guest Store').first);
    await tester.pumpAndSettle();

    expect(find.text('Guest Vendor'), findsOneWidget);
    expect(find.text('Products from this store'), findsOneWidget);
    expect(find.text('Guest Store Tomatoes'), findsOneWidget);
    expect(find.text('Message vendor'), findsNothing);
    expect(find.text('Posted 2026-11-14 14:05:09'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
  });

  testWidgets('listing details show customer ratings and feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: _ReviewedListingRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);

    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();

    expect(find.text('Vendor rating'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('1 customer review(s)'), findsOneWidget);
    expect(find.text('4 stars'), findsOneWidget);
    expect(find.text('Customer reviews'), findsOneWidget);
    expect(find.text('Verified purchase'), findsOneWidget);
    expect(find.text('Sample customer'), findsOneWidget);
    expect(find.text('2026-11-01'), findsOneWidget);
    expect(find.text('Fresh produce and friendly service.'), findsOneWidget);
    expect(find.text('private-buyer@example.com'), findsNothing);
  });

  testWidgets('buyers can rate a vendor store and submit written feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);
    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();
    final rateButton = find.ancestor(
      of: find.text('Rate this vendor store'),
      matching: find.byType(OutlinedButton),
    );
    await tester.ensureVisible(rateButton);
    await tester.tap(rateButton);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Share your experience with this vendor store.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Rate 4 stars'));
    await tester.enterText(
      find.byType(TextFormField).last,
      'Friendly vendor and fresh produce.',
    );
    await tester.tap(find.text('Submit feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Friendly vendor and fresh produce.'), findsOneWidget);
    expect(find.text('Your store feedback submitted'), findsOneWidget);
    expect(find.text('Store feedback'), findsOneWidget);
  });

  testWidgets('buyers can add produce to cart and checkout', (tester) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);

    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();
    expect(find.text('Add to cart'), findsOneWidget);
    expect(find.text('Reserve'), findsOneWidget);
    expect(find.text('Buy now'), findsOneWidget);

    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Shopping cart (1 items)'));
    await tester.pumpAndSettle();

    expect(find.text('Shopping cart'), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsOneWidget);
    expect(find.text('₱40'), findsWidgets);
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    expect(find.text('Order placed'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();
    expect(find.text('My orders (1)'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'View transactions'));
    await tester.pumpAndSettle();
    expect(find.text('My orders (1)'), findsOneWidget);

    final deleteOrderButton = find.byTooltip('Delete order');
    expect(deleteOrderButton, findsOneWidget);
    await tester.tap(deleteOrderButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove this order?'), findsOneWidget);
    await tester.tap(find.text('Remove order'));
    await tester.pumpAndSettle();
    expect(find.text('My orders (0)'), findsOneWidget);
  });

  testWidgets('buyers can reserve and cancel produce reservations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);
    await openMarketFromExplore(tester);
    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reserve'));
    await tester.pumpAndSettle();

    expect(find.text('Produce reserved'), findsOneWidget);
    expect(find.textContaining('2 kg of Fresh Tomatoes'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();
    expect(find.text('My reservations (1)'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'View transactions'));
    await tester.pumpAndSettle();
    expect(find.text('My reservations (1)'), findsOneWidget);
    expect(find.textContaining('2 kg · Fresh Tomatoes'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel reservation'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this reservation?'), findsOneWidget);
    await tester.tap(find.text('Cancel reservation').last);
    await tester.pumpAndSettle();
    expect(find.text('My reservations (0)'), findsOneWidget);
  });

  testWidgets('buyers can buy a listing directly', (tester) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester, email: 'direct-buy@example.com');
    await openMarketFromExplore(tester);
    await tester.tap(find.text('View produce').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Buy now'));
    await tester.tap(find.text('Buy now'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your purchase'), findsOneWidget);
    await tester.tap(find.text('Confirm purchase'));
    await tester.pumpAndSettle();
    expect(find.text('Order placed'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'View transactions'));
    await tester.pumpAndSettle();
    expect(find.text('My orders (1)'), findsOneWidget);
  });

  testWidgets('header shows the buyer profile photo in the account avatar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final photoBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final repository = InMemoryMarketplaceRepository()
      ..setAuthenticatedAccount(
        MarketplaceAccount(
          id: 'buyer-with-photo',
          role: 'Buyer',
          email: 'buyer@example.com',
          profilePhotoBytes: photoBytes,
        ),
      );
    addTearDown(repository.dispose);

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();

    final avatar = find.descendant(
      of: find.byTooltip('Account: Buyer'),
      matching: find.byType(ProfilePhotoAvatar),
    );
    expect(avatar, findsOneWidget);
    expect(tester.widget<ProfilePhotoAvatar>(avatar).photoBytes, photoBytes);
    expect(
      find.descendant(of: avatar, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile provides a back-to-market action', (tester) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);

    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();
    expect(find.text('Buyer account'), findsOneWidget);
    expect(find.text('Add profile photo'), findsOneWidget);
    expect(find.textContaining('Connect account'), findsNothing);
    expect(find.textContaining('Sync this device'), findsNothing);

    await tester.tap(find.text('Back to market'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh picks from local vendors'), findsOneWidget);
    expect(find.text('Search tomatoes, mangoes, pechay...'), findsOneWidget);
    expect(find.text('Good food grows'), findsNothing);
  });

  testWidgets('sign out clears the local account and returns to welcome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await registerBuyer(tester);

    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();
    expect(find.text('Buyer account'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Account: Buyer'), findsNothing);
    expect(find.byTooltip('Sign in'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Browse as guest'), findsOneWidget);
  });

  testWidgets(
    'vendor delete button sends request to server for authorization',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _NonOwnerVendorRepository();
      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'vendor@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      await openMarketFromExplore(tester);
      final deleteButton = find.byTooltip(
        'Delete listing: Other vendor produce',
      );
      await tester.ensureVisible(deleteButton);
      expect(deleteButton, findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Delete this listing?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete listing'));
      await tester.pumpAndSettle();

      expect(repository.removalCalls, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('You can only remove your own listings.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'vendor registration shows requested fields and requires a map pin',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MyApp(repository: InMemoryMarketplaceRepository()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create your account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vendor').last);
      await tester.pumpAndSettle();

      expect(find.text('Full Name *'), findsOneWidget);
      expect(find.text('Contact Number *'), findsOneWidget);
      expect(find.text('Stall/Business Name *'), findsOneWidget);
      expect(find.text('Business Type *'), findsOneWidget);
      expect(find.text('Market Address *'), findsOneWidget);
      expect(
        find.text('Location Map * — Select a location using the map pin'),
        findsOneWidget,
      );
      expect(find.text('Username or Email *'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Company Description (Optional)'), findsNothing);
      expect(find.text('Tax ID/EIN (Optional)'), findsNothing);

      await tester.enterText(find.byType(TextFormField).at(0), 'Rosa Santos');
      await tester.enterText(find.byType(TextFormField).at(1), '09171234567');
      await tester.enterText(find.byType(TextFormField).at(2), 'Green Basket');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vegetable Vendor').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(3),
        '12 Market Road',
      );
      await tester.enterText(find.byType(TextFormField).at(4), 'rosa_santos');
      await tester.enterText(find.byType(TextFormField).at(5), 'password123');
      await tester.enterText(find.byType(TextFormField).at(6), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Please select a location on the map before continuing.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('GPS address can be corrected without changing map coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MyApp(
        repository: InMemoryMarketplaceRepository(),
        deviceLocationService: _FakeDeviceLocationService(),
        reverseGeocoder: _FakeReverseGeocoder(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create your account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vendor').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Location Map * — Select a location using the map pin'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    expect(find.text('Market Road, Manila'), findsOneWidget);
    expect(find.textContaining('14.5'), findsNothing);
    expect(find.textContaining('120.9'), findsNothing);

    final businessAddressField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Business address',
    );
    expect(businessAddressField, findsOneWidget);
    await tester.enterText(businessAddressField, 'Pelong 2');

    await tester.tap(find.widgetWithText(TextButton, 'Use this location'));
    await tester.pumpAndSettle();

    final addressField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(3),
    );
    expect(addressField.controller?.text, 'Pelong 2');
    expect(find.text('Location selected'), findsOneWidget);
    expect(find.textContaining('14.5'), findsNothing);
    expect(find.textContaining('120.9'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('posting is available only after signing in as a vendor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Post produce'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'neighbor@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Post produce'), findsNothing);
    await tester.tap(find.byTooltip('Account: Buyer'));
    await tester.pumpAndSettle();
    expect(find.text('Switch to vendor account'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'farmer@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vendor').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Post produce'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Post produce').first);
    await tester.pumpAndSettle();

    expect(find.text('Share your fresh produce'), findsOneWidget);
    expect(find.text('Hosted product photo URL (optional)'), findsNothing);
    expect(find.text('Add photos'), findsNothing);
    expect(find.text('Add videos (0/10)'), findsNothing);
  });

  testWidgets('vendors can add and post multiple listings together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryMarketplaceRepository();
    addTearDown(repository.dispose);
    repository.setAuthenticatedAccount(
      const MarketplaceAccount(
        id: 'bulk-vendor',
        role: 'Vendor',
        email: 'bulk-vendor@example.com',
        companyName: 'Bulk Farm',
        addressLine1: 'Farm Road',
        latitude: 8.5,
        longitude: 123.8,
      ),
    );

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post produce'));
    await tester.pumpAndSettle();

    expect(find.text('Remarks'), findsOneWidget);
    expect(find.text('Product description'), findsNothing);
    final unitDropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(unitDropdowns.at(0));
    await tester.pumpAndSettle();
    expect(find.text('Newly harvested'), findsNothing);
    await tester.tap(find.text('Fresh').last);
    await tester.pumpAndSettle();
    await tester.tap(unitDropdowns.at(1));
    await tester.pumpAndSettle();
    expect(find.text('pcs'), findsOneWidget);
    await tester.tap(find.text('pcs'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    TextInputType? keyboardTypeFor(Finder formField) {
      final textField = find.descendant(
        of: formField,
        matching: find.byType(TextField),
      );
      return tester.widget<TextField>(textField).keyboardType;
    }

    expect(keyboardTypeFor(fields.at(2)), TextInputType.number);
    await tester.enterText(fields.at(0), 'Tomatoes');
    await tester.enterText(fields.at(1), '40');
    await tester.enterText(fields.at(2), '5');
    await tester.ensureVisible(find.text('Add another listing'));
    await tester.tap(find.text('Add another listing'));
    await tester.pumpAndSettle();

    expect(find.text('Product 2'), findsOneWidget);
    expect(find.text('POST 2 LISTINGS'), findsOneWidget);
    expect(keyboardTypeFor(fields.at(7)), TextInputType.number);
    await tester.ensureVisible(find.text('Product 2'));
    await tester.enterText(fields.at(5), 'Mangoes');
    await tester.enterText(fields.at(6), '60');
    await tester.enterText(fields.at(7), '8');
    await tester.ensureVisible(find.text('POST 2 LISTINGS'));
    await tester.tap(find.text('POST 2 LISTINGS'));
    await tester.pumpAndSettle();

    final listings = await repository.loadListings();
    expect(
      listings.map((listing) => listing.name),
      containsAll(['Tomatoes', 'Mangoes']),
    );
    expect(
      listings.singleWhere((listing) => listing.name == 'Tomatoes').unit,
      'pcs',
    );
  });

  testWidgets('sign in and create account show a brief success transition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(repository: InMemoryMarketplaceRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    Future<void> submitAccount({required bool create}) async {
      if (create) {
        await tester.tap(find.text('Create an account'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'person@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          create ? 'Create account' : 'Sign in',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 410));
      expect(find.text('You’re all set!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 560));
      await tester.pumpAndSettle();
    }

    await submitAccount(create: false);
    await tester.pumpWidget(
      MyApp(key: UniqueKey(), repository: InMemoryMarketplaceRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await submitAccount(create: true);
  });

  test('publishing a listing broadcasts it and creates an alert', () async {
    final service = MarketplaceService();
    final listing = ProduceListing(
      id: 'test-listing',
      name: 'Test squash',
      category: 'Vegetables',
      price: 45,
      unit: 'kg',
      quantity: '5',
      condition: 'Fresh',
      vendor: 'Test farm',
      vendorInitials: 'TF',
      location: 'Test market',
      distanceKm: 1,
      imageUrl: '',
      ownerEmail: 'private-vendor@example.com',
      imageBytes: Uint8List.fromList([1, 2, 3]),
      imageFileName: 'squash.png',
    );
    final listingUpdate = expectLater(
      service.listingUpdates,
      emits(same(listing)),
    );
    final notificationUpdate = expectLater(
      service.notificationUpdates,
      emits(
        isA<MarketplaceNotification>().having(
          (notification) => notification.listing!.id,
          'listing id',
          listing.id,
        ),
      ),
    );

    await service.addListing(listing);
    await Future.wait([listingUpdate, notificationUpdate]);

    final savedListings = await service.loadListings();
    final publicListings = await service.loadPublicListings();
    final Notification = await service.loadNotifications();
    expect(savedListings.first.imageBytes, listing.imageBytes);
    expect(savedListings.first.imageFileName, 'squash.png');
    expect(publicListings.first.ownerEmail, isNull);
    expect(Notification.first.listing!.id, listing.id);
  });

  test('reserving and buying produce decrement available inventory', () async {
    final service = MarketplaceService();
    final listing = ProduceListing(
      id: 'purchase-flow-test',
      name: 'Test squash',
      category: 'Vegetables',
      price: 45,
      unit: 'kg',
      quantity: '5',
      condition: 'Fresh',
      vendor: 'Test farm',
      vendorInitials: 'TF',
      location: 'Test market',
      distanceKm: 1,
      imageUrl: '',
      ownerEmail: 'test-farm@example.com',
    );
    await service.addListing(listing);

    final reservation = await service.reserveListing(
      buyerEmail: 'buyer@example.com',
      listing: listing,
      quantity: 2,
    );
    expect(reservation.total, 90);
    expect(service.availableQuantity(listing), 3);

    final order = await service.buyListing(
      buyerEmail: 'buyer@example.com',
      listing: listing,
      quantity: 3,
    );
    expect(order.total, 135);
    expect(service.availableQuantity(listing), 0);
    await expectLater(
      service.buyListing(
        buyerEmail: 'buyer@example.com',
        listing: listing,
        quantity: 1,
      ),
      throwsStateError,
    );

    expect(
      await service.removeListing(
        listingId: listing.id,
        ownerEmail: listing.ownerEmail!,
      ),
      isTrue,
    );
  });

  test('only the listing owner can remove a listing and its alert', () async {
    final service = MarketplaceService();
    final listing = ProduceListing(
      id: 'deletable-test-listing',
      name: 'Test carrots',
      category: 'Vegetables',
      price: 30,
      unit: 'bundle',
      quantity: '4',
      condition: 'Fresh',
      vendor: 'Test farm',
      vendorInitials: 'TF',
      location: 'Test market',
      distanceKm: 1,
      imageUrl: '',
      ownerEmail: 'owner@example.com',
    );
    await service.addListing(listing);

    expect(
      await service.removeListing(
        listingId: listing.id,
        ownerEmail: 'other@example.com',
      ),
      isFalse,
    );
    expect(
      (await service.loadListings()).any((item) => item.id == listing.id),
      isTrue,
    );

    final listingRemoval = expectLater(
      service.listingRemovals,
      emits(listing.id),
    );
    final notificationRemoval = expectLater(
      service.notificationRemovals,
      emits('notification-${listing.id}'),
    );
    expect(
      await service.removeListing(
        listingId: listing.id,
        ownerEmail: 'owner@example.com',
      ),
      isTrue,
    );
    await Future.wait([listingRemoval, notificationRemoval]);
    expect(
      (await service.loadListings()).any((item) => item.id == listing.id),
      isFalse,
    );
    expect(
      (await service.loadNotifications()).any(
        (item) => item.listing?.id == listing.id,
      ),
      isFalse,
    );
  });
}
