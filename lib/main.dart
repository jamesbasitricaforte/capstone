import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/firestore_image_compressor.dart';
import 'data/marketplace_repository.dart';
import 'data/firebase_marketplace_repository.dart';
import 'data/marketplace_service.dart';
import 'data/location_services.dart';
import 'data/nominatim_reverse_geocoder.dart';
import 'models/marketplace_messaging.dart';
import 'models/marketplace_purchase.dart';
import 'models/marketplace_trust.dart';
import 'models/produce_listing.dart';
import 'models/vendor_location.dart';
import 'models/vendor_store_profile.dart';
import 'widgets/desktop_phone_preview.dart';
import 'widgets/marketplace_messages_page.dart';
import 'widgets/profile_photo_avatar.dart';
import 'widgets/vendor_locations_page.dart';
import 'widgets/vendor_store_page.dart';

import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

import 'package:latlong2/latlong.dart';

const _forest = Color(0xFF245A40);
const _deepForest = Color(0xFF183F30);
const _leaf = Color(0xFF84966F);
const _cream = Color(0xFFF7F5EE);
const _paper = Color(0xFFFFFEFA);
const _ink = Color(0xFF29352D);
const _muted = Color(0xFF777D75);
const _line = Color(0xFFE5E5DC);
const _heroProduceImageAsset = 'assets/images/produce_market_hero.jpg';
const _homeBackgroundImageUrl =
    'https://images.unsplash.com/photo-1542838132-92c53300491e?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&q=85&w=2000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

MarketplaceRepository _defaultMarketplaceRepository() {
  return FirebaseMarketplaceRepository();
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.repository,
    this.deviceLocationService,
    this.reverseGeocoder,
  });

  final MarketplaceRepository? repository;
  final DeviceLocationService? deviceLocationService;
  final ReverseGeocoder? reverseGeocoder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Produce Connect',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          DesktopPhonePreview(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _cream,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: _forest,
              brightness: Brightness.light,
            ).copyWith(
              primary: _forest,
              secondary: _leaf,
              surface: _paper,
              onSurface: _ink,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _paper,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _paper,
          hintStyle: const TextStyle(color: _muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _forest, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _forest,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _paper,
          selectedColor: _forest,
          side: const BorderSide(color: _line),
          shape: const StadiumBorder(),
          labelStyle: const TextStyle(color: _ink),
          secondaryLabelStyle: const TextStyle(color: Colors.white),
        ),
      ),
      home: MarketplaceScreen(
        repository: repository ?? _defaultMarketplaceRepository(),
        deviceLocationService: deviceLocationService,
        reverseGeocoder: reverseGeocoder,
      ),
    );
  }
}

enum _Section { explore, nearby, cart, messages, Notification, profile }

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({
    super.key,
    required this.repository,
    this.deviceLocationService,
    this.reverseGeocoder,
  });

  static const Duration _verificationEmailCooldown = Duration(seconds: 60);

  static bool isVerificationEmailResendAllowed(
    DateTime? lastRequestAt, {
    DateTime? now,
  }) {
    final referenceNow = now ?? DateTime.now();
    if (lastRequestAt == null) return true;
    return referenceNow.difference(lastRequestAt) >= _verificationEmailCooldown;
  }

  final MarketplaceRepository repository;
  final DeviceLocationService? deviceLocationService;
  final ReverseGeocoder? reverseGeocoder;

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with WidgetsBindingObserver {

  late final MarketplaceRepository _service;
  late final DeviceLocationService _deviceLocationService;
  late final ReverseGeocoder _reverseGeocoder;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _savedListingIds = {};
  final List<MarketplaceNotification> _notifications = [];
  List<MarketplaceCartItem> _cartItems = [];
  List<ProduceReservation> _reservations = [];
  final Set<String> _cancellingReservationIds = {};
  List<ProduceOrder> _orders = [];
  final Set<String> _deletingBuyerOrderIds = {};
  List<ProduceOrder> _vendorOrders = [];
  List<MarketplaceConversation> _conversations = [];
  late final StreamSubscription<ProduceListing> _listingSubscription;
  late final StreamSubscription<String> _listingRemovalSubscription;
  late final StreamSubscription<MarketplaceNotification>
  _notificationSubscription;
  late final StreamSubscription<String> _notificationRemovalSubscription;
  List<ProduceListing> _listings = [];
  final Map<String, VendorStoreProfile> _vendorStoreProfiles = {};
  List<ProduceListing> _nearbyListings = [];
  LatLng? _nearbyLocation;
  bool _isLoading = true;
  bool _isLoadingNearby = false;
  bool _isLoadingVendorOrders = false;
  bool _isLoadingMessages = false;
  bool _isUpdatingProfilePhoto = false;
  Object? _loadError;
  Object? _nearbyError;
  Object? _vendorOrdersError;
  Object? _messagesError;
  String _query = '';
  String _category = 'All produce';
  bool _under50 = false;
  bool _availableOnly = true;
  bool _favoritesOnly = false;
  int? _maximumPrice;
  double? _maximumDistance;
  String _sortOrder = 'Recommended';
  String _vendorVerificationStatus = 'not_requested';
  VendorTrustSummary _vendorTrustSummary = const VendorTrustSummary(
    verificationStatus: 'not_requested',
    averageRating: 0,
    reviewCount: 0,
    reviews: [],
  );
  final Set<String> _reviewedPurchaseKeys = {};
  double _nearbyRadiusKm = 10;
  String _location = 'All locations';
  String? _signedInRole;
  String? _signedInEmail;
  String? _signedInUserId;
  MarketplaceAccount? _signedInAccount;
  MarketplaceAccount? _signedInVendorAccount;
  bool _isGuestBrowsing = false;
  _Section _section = _Section.explore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.repository;
    _deviceLocationService =
        widget.deviceLocationService ?? const GeolocatorDeviceLocationService();
    _reverseGeocoder = widget.reverseGeocoder ?? NominatimReverseGeocoder();
    _listingSubscription = _service.listingUpdates.listen(
      (listing) {
        if (!mounted) return;
        final visibleListing = _signedInRole == null
            ? _service.publicListing(listing)
            : listing;
        setState(() {
          _listings = [
            visibleListing,
            ..._listings.where((item) => item.id != visibleListing.id),
          ];
        });
        unawaited(_loadVendorStoreProfiles([visibleListing]));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _loadError = error;
          _isLoading = false;
        });
      },
    );
    _listingRemovalSubscription = _service.listingRemovals.listen((listingId) {
      if (!mounted) return;
      setState(() {
        _listings.removeWhere((listing) => listing.id == listingId);
        _nearbyListings.removeWhere((listing) => listing.id == listingId);
        _notifications.removeWhere(
          (notification) => notification.listing.id == listingId,
        );
      });
    });
    _notificationSubscription = _service.notificationUpdates.listen((
      notification,
    ) {
      if (!mounted) return;
      setState(() => _notifications.insert(0, notification));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${notification.title}: ${notification.message}'),
          ),
        );
    });
    _notificationRemovalSubscription = _service.notificationRemovals.listen((
      notificationId,
    ) {
      if (!mounted) return;
      setState(() {
        _notifications.removeWhere(
          (notification) => notification.id == notificationId,
        );
      });
    });
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listingSubscription.cancel();
    _listingRemovalSubscription.cancel();
    _notificationSubscription.cancel();
    _notificationRemovalSubscription.cancel();
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final account = await _service.restoreSession();
      if (!mounted) return;
      if (account != null) {
        setState(() {
          _signedInRole = account.role;
          _signedInEmail = account.email;
          _signedInUserId = account.id;
          _signedInAccount = account;
          _signedInVendorAccount = account.role == 'Vendor' ? account : null;
          if (account.role != 'Vendor') {
            _vendorVerificationStatus = 'not_requested';
          }
        });
      }
      await _loadListings();
      if (account != null && account.role == 'Buyer') {
        await _loadBuyerData();
      } else if (account != null && account.role == 'Vendor') {
        await _loadVendorOrders();
        await _loadVendorVerificationStatus();
      }
      if (account != null) await _loadConversations();
    } on MarketplaceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadListings() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final listings = _signedInRole == null
          ? await _service.loadPublicListings()
          : await _service.loadListings();
      final notifications = _signedInRole == null
          ? <MarketplaceNotification>[]
          : await _service.loadNotifications();
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _notifications
          ..clear()
          ..addAll(notifications);
        _isLoading = false;
      });
      unawaited(_loadVendorStoreProfiles(listings));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVendorStoreProfiles(
    Iterable<ProduceListing> listings,
  ) async {
    final vendorIds = listings.map(_vendorIdForListing).toSet().toList();
    if (vendorIds.isEmpty) return;
    try {
      final profiles = await Future.wait(
        vendorIds.map(_service.loadVendorStoreProfile),
      );
      if (!mounted) return;
      setState(() {
        for (var index = 0; index < vendorIds.length; index++) {
          final profile = profiles[index];
          if (profile == null) {
            _vendorStoreProfiles.remove(vendorIds[index]);
          } else {
            _vendorStoreProfiles[vendorIds[index]] = profile;
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load vendor profile pictures: $error'),
        ),
      );
    }
  }

  String _vendorIdForListing(ProduceListing listing) =>
      listing.ownerUid ?? listing.ownerEmail ?? listing.vendor;

  List<ProduceListing> get _visibleListings {
    final query = _query.trim().toLowerCase();
    final visible = _listings.where((listing) {
      final matchesQuery =
          query.isEmpty ||
          listing.name.toLowerCase().contains(query) ||
          listing.category.toLowerCase().contains(query) ||
          listing.vendor.toLowerCase().contains(query) ||
          listing.location.toLowerCase().contains(query);
      final matchesCategory =
          _category == 'All produce' ||
          (_category == 'Vegetables' && listing.category == 'Vegetables') ||
          (_category == 'Fruits' && listing.category == 'Fruits');
      final matchesLocation =
          _location == 'All locations' ||
          listing.location.toLowerCase().contains(_location.toLowerCase());
      final availableQuantity = _service.availableQuantity(listing);
      final distanceKm = _distanceToListing(listing);
      return matchesQuery &&
          matchesCategory &&
          matchesLocation &&
          (!_under50 || listing.price < 50) &&
          (_maximumPrice == null || listing.price <= _maximumPrice!) &&
          (!_availableOnly || availableQuantity > 0) &&
          (_maximumDistance == null ||
              (distanceKm != null && distanceKm <= _maximumDistance!)) &&
          (!_favoritesOnly || _savedListingIds.contains(listing.id));
    }).toList();
    switch (_sortOrder) {
      case 'Price: low to high':
        visible.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'Price: high to low':
        visible.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'Nearest first':
        visible.sort(
          (a, b) => (_distanceToListing(a) ?? double.infinity).compareTo(
            _distanceToListing(b) ?? double.infinity,
          ),
        );
        break;
    }
    return visible;
  }

  double? _distanceToListing(ProduceListing listing) {
    if (listing.distanceKm != null) return listing.distanceKm;
    final location = _nearbyLocation;
    final latitude = listing.latitude;
    final longitude = listing.longitude;
    if (location == null || latitude == null || longitude == null) return null;
    return const Distance().as(
      LengthUnit.Kilometer,
      location,
      LatLng(latitude, longitude),
    );
  }

  Future<void> _loadVendorVerificationStatus() async {
    final email = _signedInEmail;
    if (email == null || _signedInRole != 'Vendor') return;
    try {
      final trust = await _service.loadVendorTrust(email.toLowerCase());
      if (!mounted) return;
      setState(() {
        _vendorTrustSummary = trust;
        _vendorVerificationStatus = trust.verificationStatus;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load vendor feedback: $error')),
      );
    }
  }

  Future<void> _useCurrentLocationForNearby() async {
    setState(() {
      _nearbyError = null;
      _isLoadingNearby = true;
    });
    try {
      final location = await _deviceLocationService.currentLocation();
      if (!mounted) return;
      await _loadNearbyAt(location);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _nearbyError = error;
        _isLoadingNearby = false;
      });
    }
  }

  Future<void> _chooseNearbyMapLocation() async {
    final selection = await showDialog<MapLocationSelection>(
      context: context,
      builder: (context) => MapLocationPickerDialog(
        title: 'Choose a location for nearby produce',
        locationService: _deviceLocationService,
      ),
    );
    if (selection == null || !mounted) return;
    await _loadNearbyAt(selection.location);
  }

  Future<void> _loadNearbyAt(LatLng location) async {
    setState(() {
      _nearbyLocation = location;
      _nearbyError = null;
      _isLoadingNearby = true;
    });
    try {
      final listings = await _service.loadNearbyListings(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusKm: _nearbyRadiusKm,
      );
      if (!mounted) return;
      setState(() {
        _nearbyListings = listings;
        _isLoadingNearby = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _nearbyError = error;
        _isLoadingNearby = false;
      });
    }
  }

  Future<void> _openDeviceLocationSettings() async {
    final error = _nearbyError;
    try {
      final bool opened;
      if (error is DeviceLocationException &&
          error.issue == DeviceLocationIssue.servicesDisabled) {
        opened = await _deviceLocationService.openLocationSettings();
      } else {
        opened = await _deviceLocationService.openAppSettings();
      }
      if (!opened && mounted) {
        setState(
          () => _nearbyError = const DeviceLocationException(
            DeviceLocationIssue.unavailable,
            'Device settings could not be opened. Open location settings manually, then retry.',
          ),
        );
      }
    } catch (settingsError) {
      if (!mounted) return;
      setState(() => _nearbyError = settingsError);
    }
  }

  Future<void> _setSection(_Section section) async {
    if (_signedInRole == null &&
        section != _Section.explore &&
        section != _Section.nearby) {
      final action = switch (section) {
        _Section.cart => 'open your cart',
        _Section.messages => 'view your messages',
        _Section.Notification => 'view your Notification',
        _Section.profile => 'open your account',
        _ => 'continue',
      };
      if (!await _requestAccountAccess(action: action) || !mounted) return;
    }
    if (section == _Section.cart && _signedInRole != 'Buyer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The cart is available to buyer accounts.'),
        ),
      );
      return;
    }
    if (section == _Section.messages) {
      await _loadConversations();
    }
    setState(() => _section = section);
    if (section == _Section.profile && _signedInRole == 'Vendor') {
      await _loadVendorOrders();
    }
    if (section == _Section.Notification && _signedInRole != null) {
      try {
        final notifications = await _service.loadNotifications();
        if (!mounted) return;
        setState(() {
          _notifications
            ..clear()
            ..addAll(notifications);
        });
      } on MarketplaceApiException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh Notification: $error')),
        );
      }
    }
  }

  Future<bool> _showSignIn({
    String initialAccountType = 'Buyer',
    bool createAccount = false,
  }) async {
    final account = await showDialog<MarketplaceAccount>(
      context: context,
      builder: (context) => _SignInDialog(
        initialAccountType: initialAccountType,
        initialCreatingAccount: createAccount,
        deviceLocationService: _deviceLocationService,
        reverseGeocoder: _reverseGeocoder,
        onSubmit: _submitCredentials,
        onRequestPasswordReset: _service.requestPasswordReset,
      ),
    );
    if (account == null || !mounted) return false;
    setState(() {
      _signedInRole = account.role;
      _signedInEmail = account.email;
      _signedInUserId = account.id;
      _signedInAccount = account;
      _signedInVendorAccount = account.role == 'Vendor' ? account : null;
      _isGuestBrowsing = false;
      if (account.role != 'Buyer' && _section == _Section.cart) {
        _section = _Section.explore;
      }
    });
    if (account.role == 'Vendor') {
      await _loadVendorVerificationStatus();
    }
    await _loadListings();
    var accountDataLoaded = true;
    try {
      if (account.role == 'Buyer') {
        await _loadBuyerData();
      } else {
        setState(() {
          _savedListingIds.clear();
          _vendorVerificationStatus = 'not_requested';
          _cartItems = [];
          _reservations = [];
          _orders = [];
          _vendorOrders = [];
        });
        if (account.role == 'Vendor') {
          await _loadVendorOrders();
        }
      }
      await _loadConversations();
    } on MarketplaceApiException catch (error) {
      accountDataLoaded = false;
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signed in, but account data could not load: $error'),
        ),
      );
    }
    if (mounted && accountDataLoaded) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed in successfully.')));
    }
    return true;
  }

  Future<MarketplaceAccount> _submitCredentials(
    MarketplaceCredentials credentials,
    bool creatingAccount,
  ) async {
    return creatingAccount
        ? _service.register(credentials)
        : _service.signIn(credentials);
  }

  Future<void> _loadBuyerData() async {
    final cart = await _service.loadCart();
    final reservations = await _service.loadReservations();
    final orders = await _service.loadOrders();
    final favorites = await _service.loadFavorites();
    if (!mounted) return;
    setState(() {
      _cartItems = cart;
      _reservations = reservations;
      _orders = orders;
      _savedListingIds
        ..clear()
        ..addAll(favorites);
    });
  }

  Future<void> _deleteBuyerOrder(ProduceOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this order?'),
        content: const Text(
          'This removes the order from your buyer history. It does not cancel '
          'the purchase or restore the listing stock, and the vendor will keep '
          'their order record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingBuyerOrderIds.add(order.id));
    try {
      final deleted = await _service.deleteBuyerOrder(orderId: order.id);
      if (!mounted) return;
      if (!deleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This order is no longer available.')),
        );
        return;
      }
      final orders = await _service.loadOrders();
      if (!mounted) return;
      setState(() => _orders = orders);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order removed from your history.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove order: $error')));
    } finally {
      if (mounted) {
        setState(() => _deletingBuyerOrderIds.remove(order.id));
      }
    }
  }

  Future<void> _cancelReservation(ProduceReservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this reservation?'),
        content: Text(
          'Cancel ${reservation.quantity} ${reservation.listing.unit} of '
          '${reservation.listing.name}? The reserved quantity will return to '
          'the listing’s available stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep reservation'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel reservation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancellingReservationIds.add(reservation.id));
    try {
      final cancelled = await _service.cancelReservation(
        reservationId: reservation.id,
      );
      if (!mounted) return;
      setState(() {
        _reservations = _reservations
            .where((item) => item.id != reservation.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancelled
                ? 'Reservation cancelled and stock restored.'
                : 'This reservation is no longer active.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel reservation: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _cancellingReservationIds.remove(reservation.id));
      }
    }
  }

  Future<void> _loadVendorOrders() async {
    setState(() {
      _isLoadingVendorOrders = true;
      _vendorOrdersError = null;
    });
    try {
      final orders = await _service.loadVendorOrders();
      if (!mounted) return;
      setState(() {
        _vendorOrders = orders;
        _isLoadingVendorOrders = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _vendorOrdersError = error;
        _isLoadingVendorOrders = false;
      });
    }
  }

  Future<void> _loadConversations() async {
    if (_signedInRole == null) return;
    setState(() {
      _isLoadingMessages = true;
      _messagesError = null;
    });
    try {
      final conversations = await _service.loadConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoadingMessages = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messagesError = error;
        _isLoadingMessages = false;
      });
    }
  }

  Future<void> _openConversation(MarketplaceConversation conversation) async {
    final userId = _signedInUserId;
    if (userId == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => MarketplaceConversationDialog(
        repository: _service,
        conversation: conversation,
        currentUserId: userId,
      ),
    );
    if (mounted) await _loadConversations();
  }

  Future<void> _changeProfilePhoto() async {
    if (_isUpdatingProfilePhoto) return;
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final file = files.single;
      final imageBytes = await file.readAsBytes();
      if (imageBytes.isEmpty) {
        throw const FormatException('Choose a valid image.');
      }
      final compressedBytes = await compute(
        compressProfilePhotoForFirestore,
        imageBytes,
      );
      if (!mounted) return;
      setState(() => _isUpdatingProfilePhoto = true);

      final updatedAccount = await _service.updateProfilePhoto(
        imageBytes: compressedBytes,
        imageName: file.name,
      );
      if (!mounted) return;
      setState(() {
        _isUpdatingProfilePhoto = false;
        _signedInAccount = updatedAccount;
        if (updatedAccount.role == 'Vendor') {
          _signedInVendorAccount = updatedAccount;
        }
      });
      if (updatedAccount.role == 'Vendor') {
        unawaited(_loadVendorStoreProfiles(_listings));
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _isUpdatingProfilePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile photo: $error')),
      );
    }
  }

  Future<void> _startConversation({
    required String listingId,
    required String listingName,
    required String otherUserId,
    required String otherName,
    String? orderDocumentId,
  }) async {
    try {
      final conversation = await _service.openConversation(
        listingId: listingId,
        listingName: listingName,
        otherUserId: otherUserId,
        otherName: otherName,
        orderDocumentId: orderDocumentId,
      );
      if (!mounted) return;
      await _openConversation(conversation);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open conversation: $error')),
      );
    }
  }

  Future<void> _messageOrderParticipant(
    ProduceOrder order,
    MarketplaceCartItem item,
  ) async {
    final userIsBuyer = _signedInRole == 'Buyer';
    final otherUserId = userIsBuyer ? item.vendorUid : order.buyerUid;
    if (otherUserId == null || otherUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This older order does not have messaging details.'),
        ),
      );
      return;
    }
    await _startConversation(
      listingId: item.listing.id,
      listingName: item.listing.name,
      otherUserId: otherUserId,
      otherName: userIsBuyer ? item.listing.vendor : order.buyerEmail,
      orderDocumentId: item.orderDocumentId,
    );
  }

  Future<void> _updateVendorOrder(ProduceOrder order, String status) async {
    if (status == 'declined') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline this order?'),
          content: const Text(
            'The buyer will see the order as declined and the ordered quantity will be returned to your available stock.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Decline order'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      final updated = await _service.updateVendorOrder(
        orderId: order.id,
        status: status,
      );
      if (!mounted) return;
      if (!updated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This order is no longer available.')),
        );
        return;
      }
      await _loadVendorOrders();
      await _refreshInventory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Order approved.'
                : status == 'completed'
                ? 'Order marked completed.'
                : 'Order declined and stock restored.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update order: $error')));
    }
  }

  Future<void> _signOut() async {
    final signOut = _service.signOut();
    setState(() {
      _signedInRole = null;
      _signedInEmail = null;
      _signedInUserId = null;
      _signedInAccount = null;
      _signedInVendorAccount = null;
      _isGuestBrowsing = false;
      _cartItems = [];
      _reservations = [];
      _cancellingReservationIds.clear();
      _orders = [];
      _deletingBuyerOrderIds.clear();
      _vendorOrders = [];
      _conversations = [];
      _vendorOrdersError = null;
      _isLoadingVendorOrders = false;
      _savedListingIds.clear();
      _vendorVerificationStatus = 'not_requested';
      _section = _Section.explore;
    });

    Object? signOutError;
    try {
      await signOut;
    } on MarketplaceApiException catch (error) {
      signOutError = error;
    }
    if (!mounted) return;
    await _loadListings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          signOutError == null
              ? 'You have been signed out.'
              : 'Signed out locally, but the server sign-out failed: $signOutError',
        ),
      ),
    );
  }

  Future<void> _showNewListingForm() async {
    if (_signedInRole != 'Vendor') {
      final signedIn = await _showSignIn(initialAccountType: 'Vendor');
      if (!signedIn || !mounted || _signedInRole != 'Vendor') return;
    }
    final listing = await showDialog<ProduceListing>(
      context: context,
      builder: (context) => _NewListingDialog(
        vendorEmail: _signedInEmail!,
        vendorName: _signedInVendorAccount?.companyName ?? 'Your local farm',
        vendorAddress: _signedInVendorAccount?.addressLine1 ?? '',
        vendorLatitude: _signedInVendorAccount?.latitude,
        vendorLongitude: _signedInVendorAccount?.longitude,
      ),
    );
    if (listing == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final hasPhotos = listing.pendingMedia.any((media) => !media.isVideo);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 2),
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                hasPhotos
                    ? 'Uploading photos and saving listing...'
                    : 'Saving listing...',
              ),
            ],
          ),
        ),
      );
    try {
      await _service.addListing(listing);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      await _loadListings();
      if (!mounted) return;
      setState(() {
        _section = _Section.explore;
        _category = 'All produce';
        _under50 = false;
        _maximumPrice = null;
        _maximumDistance = null;
        _availableOnly = true;
        _favoritesOnly = false;
        _query = '';
        _searchController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing saved to Firebase.')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not save listing: $error')),
        );
    }
  }

  Future<void> _editVendorListing(ProduceListing listing) async {
    final updatedListing = await showDialog<ProduceListing>(
      context: context,
      builder: (context) => _EditListingDialog(listing: listing),
    );
    if (updatedListing == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final hasPhoto = updatedListing.pendingMedia.any((media) => !media.isVideo);
    if (hasPhoto) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(minutes: 2),
            content: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Uploading photo and updating listing...'),
              ],
            ),
          ),
        );
    }
    try {
      await _service.updateListing(updatedListing);
      if (hasPhoto) messenger.hideCurrentSnackBar();
      await _loadListings();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${listing.name} inventory updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      if (hasPhoto) messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update inventory: $error')),
      );
    }
  }

  Future<void> _requestVendorVerification() async {
    try {
      await _service.requestVendorVerification();
      if (!mounted) return;
      setState(() => _vendorVerificationStatus = 'pending');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification request saved on this device. It is not an official verification.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save verification request: $error')),
      );
    }
  }

  Future<void> _reportVendor(ProduceListing listing) async {
    if (!await _ensureBuyerAccess(action: 'report a vendor') || !mounted) {
      return;
    }
    final vendorId = listing.ownerEmail ?? listing.ownerUid;
    if (vendorId == null || vendorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This sample listing is not linked to a vendor account.',
          ),
        ),
      );
      return;
    }
    final report = await showDialog<_VendorReportDraft>(
      context: context,
      builder: (context) => const _VendorReportDialog(),
    );
    if (report == null || !mounted) return;
    try {
      await _service.reportVendor(
        vendorId: vendorId,
        reason: report.reason,
        details: report.details,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Report saved on this device only. It has not been sent to a review team.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save report: $error')));
    }
  }

  Future<void> _reviewVendor(
    ProduceOrder order,
    MarketplaceCartItem item,
  ) async {
    final vendorId = item.listing.ownerEmail ?? item.listing.ownerUid;
    if (vendorId == null || vendorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This purchase is not linked to a vendor account.'),
        ),
      );
      return;
    }
    final draft = await showDialog<_VendorReviewDraft>(
      context: context,
      builder: (context) =>
          _VendorReviewDialog(vendorName: item.listing.vendor),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.reviewVendor(
        vendorId: vendorId,
        orderId: order.id,
        rating: draft.rating,
        comment: draft.comment,
      );
      if (!mounted) return;
      setState(() {
        _reviewedPurchaseKeys.add(
          '${order.id}:${vendorId.trim().toLowerCase()}',
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks! Your verified purchase review was submitted.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save review: $error')));
    }
  }

  Future<VendorTrustSummary?> _reviewVendorStore(
    ProduceListing listing,
    _VendorReviewDraft draft,
  ) async {
    final vendorId = listing.ownerEmail ?? listing.ownerUid ?? listing.vendor;
    try {
      await _service.reviewVendor(
        vendorId: vendorId,
        rating: draft.rating,
        comment: draft.comment,
      );
      final summary = await _service.loadVendorTrust(vendorId);
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks! Your store feedback was saved. It is not a verified-purchase review.',
          ),
        ),
      );
      return summary;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save store feedback: $error')),
      );
      return null;
    }
  }

  Future<void> _deleteVendorListing(ProduceListing listing) async {
    if (_signedInRole != 'Vendor' || _signedInEmail == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in with a vendor account to delete listings.'),
          ),
        );
      }
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: Text(
          '${listing.name} will be removed from the marketplace and its new-listing alert will be withdrawn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep listing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9D4038),
            ),
            child: const Text('Delete listing'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    try {
      final removed = await _service.removeListing(listingId: listing.id);
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed ? '${listing.name} was deleted.' : 'This listing was not found in Firestore. The marketplace has been refreshed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete listing: $error')),
      );
    }
  }

  Future<void> _repostVendorListing(ProduceListing listing) async {
    if (_signedInRole != 'Vendor' || _signedInEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in with a vendor account to repost.'),
        ),
      );
      return;
    }
    try {
      final reposted = await _service.repostListing(listingId: listing.id);
      if (!mounted) return;
      if (!reposted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This listing is no longer available.')),
        );
        return;
      }
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${listing.name} was reposted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not repost listing: $error')),
      );
    }
  }

  void _showNotification() {
    if (_notifications.isNotEmpty) {
      final notification = _notifications.first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${notification.title}: ${notification.message}'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No new neighborhood notifications yet.')),
    );
  }

  Future<void> _showListingDetails(ProduceListing listing) async {
    final vendorId = listing.ownerEmail ?? listing.ownerUid ?? listing.vendor;
    late final VendorTrustSummary trust;
    try {
      trust = await _service.loadVendorTrust(vendorId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load vendor reviews: $error')),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ListingDetailsDialog(
        listing: listing,
        availableQuantity: _service.availableQuantity(listing),
        trustSummary: trust,
        canPurchase: _signedInRole != 'Vendor',
        canReviewStore: _signedInRole == 'Buyer',
        currentBuyerId: _signedInUserId,
        currentBuyerEmail: _signedInEmail,
        onReviewStore: _reviewVendorStore,
        onReport: () => _reportVendor(listing),
        onPickup: () {
          Navigator.of(context).pop();
          _showPickupMap(listing);
        },
        onContact: () {
          Navigator.of(context).pop();
          _contactVendor(listing);
        },
        onAddToCart: (quantity) => _addToCart(listing, quantity),
        onReserve: (quantity) => _reserveListing(listing, quantity),
        onBuyNow: (quantity) => _buyNow(listing, quantity),
      ),
    );
  }

  Future<void> _openVendorStore(ProduceListing listing) async {
    final vendorId = _vendorIdForListing(listing);
    try {
      final profile = await _service.loadVendorStoreProfile(vendorId);
      final listings = await _service.loadVendorListings(vendorId);
      if (!mounted) return;
      if (profile != null) {
        setState(() => _vendorStoreProfiles[vendorId] = profile);
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VendorStorePage(
            profile:
                profile ??
                VendorStoreProfile(
                  id: vendorId,
                  storeName: listing.vendor,
                  address: listing.location,
                  latitude: listing.latitude,
                  longitude: listing.longitude,
                ),
            listings: listings,
            onViewListing: _showListingDetails,
            onMessageVendor:
                _signedInRole == 'Buyer' &&
                    listing.ownerUid?.trim().isNotEmpty == true
                ? () => _contactVendor(listing)
                : null,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open this vendor store: $error')),
      );
    }
  }

  Future<void> _contactVendor(ProduceListing listing) async {
    if (!await _ensureBuyerAccess(action: 'message ${listing.vendor}')) return;
    if (!mounted) return;
    final vendorUid = listing.ownerUid;
    if (vendorUid == null || vendorUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Messaging is only available for listings linked to a vendor account.',
          ),
        ),
      );
      return;
    }
    await _startConversation(
      listingId: listing.id,
      listingName: listing.name,
      otherUserId: vendorUid,
      otherName: listing.vendor,
    );
  }

  Future<void> _refreshBuyerCart() async {
    if (_signedInRole != 'Buyer' || _signedInEmail == null) return;
    final cart = await _service.loadCart();
    if (!mounted) return;
    setState(() => _cartItems = cart);
  }

  Future<void> _refreshInventory() async {
    final listings = await _service.loadListings();
    if (!mounted) return;
    setState(() => _listings = listings);
  }

  Future<bool> _requestAccountAccess({
    required String action,
    bool buyerOnly = false,
  }) async {
    if (_signedInRole != null) {
      if (!buyerOnly || _signedInRole == 'Buyer') return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A buyer account is needed for this action.'),
        ),
      );
      return false;
    }

    final createAccount = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_outline, color: _forest),
        title: const Text('Join the neighborhood market'),
        content: Text('Sign in or create a free account to $action.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Not now'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Sign in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create account'),
          ),
        ],
      ),
    );
    if (createAccount == null || !mounted) return false;

    final signedIn = await _showSignIn(
      createAccount: createAccount,
      initialAccountType: 'Buyer',
    );
    if (!signedIn || !mounted) return false;
    if (buyerOnly && _signedInRole != 'Buyer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A buyer account is needed for this action.'),
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _ensureBuyerAccess({required String action}) async {
    if (_signedInRole == 'Buyer' && _signedInEmail != null) return true;
    return _requestAccountAccess(action: action, buyerOnly: true);
  }

  Future<void> _toggleSavedListing(ProduceListing listing) async {
    if (!await _ensureBuyerAccess(action: 'save a favorite')) return;
    final saved = !_savedListingIds.contains(listing.id);
    try {
      await _service.setFavorite(listingId: listing.id, saved: saved);
      if (!mounted) return;
      setState(() {
        if (saved) {
          _savedListingIds.add(listing.id);
        } else {
          _savedListingIds.remove(listing.id);
        }
      });
    } on MarketplaceApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favorite: $error')),
      );
    }
  }

  Future<void> _toggleFavoritesFilter() async {
    if (!_favoritesOnly &&
        !await _ensureBuyerAccess(action: 'filter by your saved favorites')) {
      return;
    }
    if (!mounted) return;
    setState(() => _favoritesOnly = !_favoritesOnly);
  }

  Future<bool> _addToCart(ProduceListing listing, int quantity) async {
    if (!await _ensureBuyerAccess(action: 'add produce to your cart')) {
      return false;
    }
    try {
      await _service.addToCart(listing: listing, quantity: quantity);
      await _refreshBuyerCart();
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$quantity added to your cart.')));
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add to cart: $error')));
      return false;
    }
  }

  Future<void> _reserveListing(ProduceListing listing, int quantity) async {
    if (!await _ensureBuyerAccess(action: 'reserve produce') || !mounted) {
      return;
    }
    try {
      final reservation = await _service.reserveListing(
        listing: listing,
        quantity: quantity,
      );
      await _refreshInventory();
      if (!mounted) return;
      final reservations = await _service.loadReservations();
      if (!mounted) return;
      setState(() => _reservations = reservations);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.event_available_outlined, color: _forest),
          title: const Text('Produce reserved'),
          content: Text(
            '${reservation.quantity} ${listing.unit} of ${listing.name} is reserved for you. '
            'Contact ${listing.vendor} to arrange pickup. Total: ₱${reservation.total}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reserve produce: $error')),
      );
    }
  }

  Future<void> _buyNow(ProduceListing listing, int quantity) async {
    if (!await _ensureBuyerAccess(action: 'place an order') || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm your purchase'),
        content: Text(
          '$quantity ${listing.unit} of ${listing.name}\n'
          'Pickup: ${listing.location}\n'
          'Total: ₱${listing.price * quantity}\n\n'
          'This records your order. Payment and pickup are arranged directly with the vendor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm purchase'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final order = await _service.buyListing(
        listing: listing,
        quantity: quantity,
      );
      await _refreshInventory();
      if (!mounted) return;
      final orders = await _service.loadOrders();
      if (!mounted) return;
      setState(() => _orders = orders);
      await _showOrderConfirmation(order);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete purchase: $error')),
      );
    }
  }

  Future<void> _updateCartQuantity(
    MarketplaceCartItem item,
    int quantity,
  ) async {
    final email = _signedInEmail;
    if (email == null || _signedInRole != 'Buyer') return;
    try {
      if (quantity < 1) {
        await _service.removeFromCart(listingId: item.listing.id);
      } else {
        await _service.updateCartQuantity(
          listingId: item.listing.id,
          quantity: quantity,
        );
      }
      await _refreshBuyerCart();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update cart: $error')));
    }
  }

  Future<void> _checkoutCart() async {
    if (!await _ensureBuyerAccess(action: 'place an order') ||
        !mounted ||
        _cartItems.isEmpty) {
      return;
    }
    final total = _cartItems.fold(0, (sum, item) => sum + item.subtotal);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Place your order?'),
        content: Text(
          '${_cartItems.length} produce item(s)\n'
          'Order total: ₱$total\n\n'
          'Payment and pickup are arranged directly with each vendor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep shopping'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Place order'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final order = await _service.checkoutCart();
      await _refreshBuyerCart();
      await _refreshInventory();
      if (!mounted) return;
      final orders = await _service.loadOrders();
      if (!mounted) return;
      setState(() => _orders = orders);
      await _showOrderConfirmation(order);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not place order: $error')));
    }
  }

  Future<void> _showOrderConfirmation(ProduceOrder order) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: _forest, size: 40),
        title: const Text('Order placed'),
        content: Text(
          'Order ${order.id.split('-').last} is confirmed. Total: ₱${order.total}.\n\n'
          'Arrange pickup and payment with the vendor(s) listed in your order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPickupMap(ProduceListing listing) async {
    try {
      final vendors = await _service.loadVendors();
      if (!mounted) return;

      VendorLocation? matchingVendor;
      for (final vendor in vendors) {
        final vendorName = vendor.name.toLowerCase();
        final listingVendor = listing.vendor.toLowerCase();
        final listingLocation = listing.location.toLowerCase();
        final vendorAddress = vendor.address.toLowerCase();
        final isMatch =
            vendorName == listingVendor ||
            listingLocation.contains(vendorAddress) ||
            vendorAddress.contains(listingLocation);
        if (isMatch) {
          matchingVendor = vendor;
          break;
        }
      }

      final exactListingLocation =
          listing.latitude != null && listing.longitude != null
          ? LatLng(listing.latitude!, listing.longitude!)
          : matchingVendor == null
          ? null
          : LatLng(matchingVendor.latitude, matchingVendor.longitude);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => VendorLocationsPage(
            repository: _service,
            isVendor: false,
            locationService: _deviceLocationService,
            reverseGeocoder: _reverseGeocoder,
            initialFocusLocation: exactListingLocation,
            initialVendorName:
                listing.latitude != null && listing.longitude != null
                ? null
                : matchingVendor?.name ?? listing.vendor,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open pickup map: $error')),
      );
    }
  }

  Future<void> _showMarketMap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => VendorLocationsPage(
          repository: _service,
          isVendor: _signedInRole == 'Vendor',
          locationService: _deviceLocationService,
          reverseGeocoder: _reverseGeocoder,
          currentVendor: _signedInVendorAccount,
          onLocationSaved: _updateVendorLocationInSession,
        ),
      ),
    );
  }

  void _updateVendorLocationInSession(VendorLocation location) {
    final account = _signedInVendorAccount;
    if (account == null) return;
    setState(() {
      _signedInVendorAccount = MarketplaceAccount(
        id: account.id,
        role: account.role,
        email: account.email,
        fullName: account.fullName,
        companyName: account.companyName,
        companyDescription: account.companyDescription,
        addressLine1: location.address,
        zipCode: account.zipCode,
        phone: account.phone,
        taxId: account.taxId,
        businessType: account.businessType,
        latitude: location.latitude,
        longitude: location.longitude,
        profilePhotoUrl: account.profilePhotoUrl,
        profilePhotoBytes: account.profilePhotoBytes,
      );
      _signedInAccount = _signedInVendorAccount;
    });
  }

  Future<void> _chooseLocation() async {
    final locations =
        _listings.map((listing) => listing.location).toSet().toList()..sort();
    locations.insert(0, 'All locations');
    final location = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Filter by listing location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ...locations.map(
              (value) => ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(value),
                trailing: value == _location
                    ? const Icon(Icons.check, color: _forest)
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
            ),
          ],
        ),
      ),
    );
    if (location != null && mounted) {
      setState(() => _location = location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final navigationSections = _signedInRole == 'Buyer'
        ? const [
            _Section.explore,
            _Section.nearby,
            _Section.messages,
            _Section.Notification,
            _Section.profile,
          ]
        : const [
            _Section.explore,
            _Section.nearby,
            _Section.messages,
            _Section.Notification,
            _Section.profile,
          ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _MarketplaceHeader(
              compact: isMobile,
              isVendor: _signedInRole == 'Vendor',
              isBuyer: _signedInRole == 'Buyer',
              isSignedIn: _signedInRole != null,
              signedInRole: _signedInRole,
              signedInAccount: _signedInAccount,
              cartItemCount: _cartItems.fold(
                0,
                (sum, item) => sum + item.quantity,
              ),
              onOpenCart: () => _setSection(_Section.cart),
              onNotifications: _showNotification,
              onPostProduce: _showNewListingForm,
              onSignIn: _signedInRole == null
                  ? () => _showSignIn()
                  : () => _setSection(_Section.profile),
            ),
            if (_isGuestBrowsing)
              _GuestBrowsingBanner(
                location: _location,
                onBackToWelcome: () => setState(() {
                  _isGuestBrowsing = false;
                }),
                onSignIn: () => _showSignIn(),
                onCreateAccount: () => _showSignIn(createAccount: true),
              ),
            Expanded(child: _buildSelectedSection()),
          ],
        ),
      ),
      bottomNavigationBar: isMobile && _signedInRole != null
          ? NavigationBar(
              selectedIndex: navigationSections
                  .indexOf(_section)
                  .clamp(0, navigationSections.length - 1),
              onDestinationSelected: (index) =>
                  _setSection(navigationSections[index]),
              destinations: navigationSections
                  .map(_navigationDestination)
                  .toList(),
            )
          : null,
    );
  }

  NavigationDestination _navigationDestination(_Section section) {
    return switch (section) {
      _Section.explore => const NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore),
        label: 'Explore',
      ),
      _Section.nearby => const NavigationDestination(
        icon: Icon(Icons.near_me_outlined),
        selectedIcon: Icon(Icons.near_me),
        label: 'Nearby',
      ),
      _Section.cart => const NavigationDestination(
        icon: Icon(Icons.shopping_cart_outlined),
        selectedIcon: Icon(Icons.shopping_cart),
        label: 'Cart',
      ),
      _Section.messages => const NavigationDestination(
        icon: Icon(Icons.forum_outlined),
        selectedIcon: Icon(Icons.forum),
        label: 'Messages',
      ),
      _Section.Notification => const NavigationDestination(
        icon: Icon(Icons.notifications_none),
        selectedIcon: Icon(Icons.notifications),
        label: 'Notification',
      ),
      _Section.profile => const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    };
  }

  Widget _buildSelectedSection() {
    if (_signedInRole == null && !_isGuestBrowsing) {
      return _GuestAccessPage(
        onCreateAccount: () => _showSignIn(createAccount: true),
        onSignIn: () => _showSignIn(),
        onBrowseAsGuest: () => setState(() {
          _isGuestBrowsing = true;
          _section = _Section.explore;
        }),
      );
    }
    if (_section == _Section.Notification) {
      return _NotificationPage(
        notifications: _notifications,
        onOpenListing: _showListingDetails,
      );
    }
    if (_section == _Section.messages) {
      return MarketplaceMessagesPage(
        conversations: _conversations,
        isLoading: _isLoadingMessages,
        error: _messagesError,
        onRefresh: _loadConversations,
        currentUserId: _signedInUserId ?? '',
        onOpenConversation: _openConversation,
      );
    }
    if (_section == _Section.cart) {
      if (_signedInRole != 'Buyer') {
        return const _BuyerOnlyMessage();
      }
      return _CartPage(
        items: _cartItems,
        availableQuantity: _service.availableQuantity,
        onQuantityChanged: _updateCartQuantity,
        onRemove: (item) => _updateCartQuantity(item, 0),
        onCheckout: _checkoutCart,
        onContinueShopping: () => _setSection(_Section.explore),
      );
    }
    if (_section == _Section.profile) {
      return _ProfilePage(
        signedInRole: _signedInRole,
        signedInEmail: _signedInEmail,
        account: _signedInAccount,
        onChangeProfilePhoto: _changeProfilePhoto,
        isUpdatingProfilePhoto: _isUpdatingProfilePhoto,
        vendorAccount: _signedInVendorAccount,
        ownListings: _signedInRole == 'Vendor'
            ? _listings
                  .where(
                    (listing) =>
                        listing.isMine || listing.ownerEmail == _signedInEmail,
                  )
                  .toList()
            : const [],
        isLoadingListings: _isLoading,
        listingsError: _loadError,
        onRetryListings: _loadListings,
        onSignIn: () => _showSignIn(),
        onVendorSignIn: () => _showSignIn(initialAccountType: 'Vendor'),
        onPostProduce: _showNewListingForm,
        onManageVendorLocation: _showMarketMap,
        onSignOut: _signOut,
        onDeleteListing: _deleteVendorListing,
        onRepostListing: _repostVendorListing,
        onEditListing: _editVendorListing,
        vendorVerificationStatus: _vendorVerificationStatus,
        vendorTrustSummary: _vendorTrustSummary,
        onRefreshVendorTrust: () {
          _loadVendorVerificationStatus();
        },
        onRequestVendorVerification: _requestVendorVerification,
        onBackToMarket: () => _setSection(_Section.explore),
        reservations: _reservations,
        cancellingReservationIds: _cancellingReservationIds,
        onCancelReservation: _cancelReservation,
        orders: _orders,
        deletingBuyerOrderIds: _deletingBuyerOrderIds,
        onDeleteBuyerOrder: _deleteBuyerOrder,
        onOpenMessages: () async {
          await _setSection(_Section.messages);
        },
        onMessageOrderParticipant: _messageOrderParticipant,
        onReviewVendor: _reviewVendor,
        reviewedPurchaseKeys: _reviewedPurchaseKeys,
        onUpdateVendorOrder: _updateVendorOrder,
        vendorOrders: _vendorOrders,
        isLoadingVendorOrders: _isLoadingVendorOrders,
        vendorOrdersError: _vendorOrdersError,
        onRefreshVendorOrders: _loadVendorOrders,
      );
    }
    if (_section == _Section.nearby) return _buildNearbyPage();
    return _buildExplorePage();
  }

  Widget _buildNearbyPage() {
    final location = _nearbyLocation;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NEARBY MARKET',
                style: TextStyle(
                  color: _leaf,
                  fontSize: 11,
                  letterSpacing: 1.7,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Available produce nearby',
                style: TextStyle(
                  color: _deepForest,
                  fontFamily: 'Georgia',
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use your location or choose a point on the map. We only show live listings with stock and vendor coordinates.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _isLoadingNearby
                        ? null
                        : _useCurrentLocationForNearby,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use my location'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoadingNearby
                        ? null
                        : _chooseNearbyMapLocation,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Choose on map'),
                  ),
                  TextButton(
                    onPressed: () => _setSection(_Section.explore),
                    child: const Text('Browse without distance sorting'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Search radius'),
                  const SizedBox(width: 12),
                  DropdownButton<double>(
                    value: _nearbyRadiusKm,
                    items: const [3.0, 10.0, 25.0, 50.0]
                        .map(
                          (radius) => DropdownMenuItem(
                            value: radius,
                            child: Text('${radius.toInt()} km'),
                          ),
                        )
                        .toList(),
                    onChanged: _isLoadingNearby
                        ? null
                        : (radius) {
                            if (radius == null) return;
                            setState(() => _nearbyRadiusKm = radius);
                            if (location != null) _loadNearbyAt(location);
                          },
                  ),
                  if (location != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nearby results centered on your current location',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
              if (_nearbyError != null)
                Card(
                  color: const Color(0xFFFFF1ED),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nearbyError is DeviceLocationException
                              ? 'Could not get device location: $_nearbyError'
                              : 'Nearby produce could not be loaded: $_nearbyError',
                          style: const TextStyle(color: Color(0xFF9D4038)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (_nearbyError is DeviceLocationException &&
                                (_nearbyError as DeviceLocationException)
                                    .canOpenSettings)
                              OutlinedButton.icon(
                                onPressed: _openDeviceLocationSettings,
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('Open settings'),
                              ),
                            TextButton.icon(
                              onPressed: _nearbyLocation == null
                                  ? _useCurrentLocationForNearby
                                  : () => _loadNearbyAt(_nearbyLocation!),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                            TextButton.icon(
                              onPressed: _chooseNearbyMapLocation,
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Choose on map'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isLoadingNearby)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: _forest),
                  ),
                )
              else if (_nearbyError == null && location == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'Your location is not requested until you choose “Use my location”.',
                    style: TextStyle(color: _muted),
                  ),
                )
              else if (_nearbyError == null && _nearbyListings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'No available listings with known vendor locations were found in this radius.',
                    style: TextStyle(color: _muted),
                  ),
                )
              else if (_nearbyError == null)
                ..._nearbyListings.map((listing) {
                  final vendorCanManage =
                      _signedInRole == 'Vendor' &&
                      (listing.isMine || listing.ownerEmail == _signedInEmail);
                  final vendorProfile =
                      _vendorStoreProfiles[_vendorIdForListing(listing)];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _ProduceCard(
                      listing: listing,
                      canDelete: _signedInRole == 'Vendor',
                      canRepost: vendorCanManage,
                      canSave:
                          _signedInRole == null || _signedInRole == 'Buyer',
                      isSaved: _savedListingIds.contains(listing.id),
                      onDelete: () => _deleteVendorListing(listing),
                      onRepost: () => _repostVendorListing(listing),
                      onToggleSaved: () => _toggleSavedListing(listing),
                      onView: () => _showListingDetails(listing),
                      onOpenVendorStore: () => _openVendorStore(listing),
                      vendorPhotoUrl: vendorProfile?.profilePhotoUrl,
                      vendorPhotoBytes: vendorProfile?.profilePhotoBytes,
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExplorePage() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _forest),
            SizedBox(height: 14),
            Text('Finding fresh produce near you…'),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42, color: _muted),
              const SizedBox(height: 12),
              const Text('We couldn’t load the market listings.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadListings,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _HeroSection(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeading(
                    eyebrow: 'EXPLORE THE MARKET',
                    title: _section == _Section.nearby
                        ? 'Fresh picks within 3 km'
                        : _location == 'All locations'
                        ? 'Fresh picks from local vendors'
                        : 'Fresh picks in $_location',
                    subtitle: 'Browse public listings, or choose a listing location to narrow results.',
                    action: OutlinedButton.icon(
                      onPressed: _showMarketMap,
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('View map'),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SearchAndLocation(
                    controller: _searchController,
                    location: _location,
                    onChanged: (value) => setState(() => _query = value),
                    onChooseLocation: _chooseLocation,
                  ),
                  const SizedBox(height: 18),
                  _buildFilters(),
                  const SizedBox(height: 24),
                  if (_visibleListings.isEmpty)
                    _EmptyListings(
                      onClear: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _category = 'All produce';
                          _under50 = false;
                          _maximumPrice = null;
                          _maximumDistance = null;
                          _availableOnly = true;
                          _favoritesOnly = false;
                          _sortOrder = 'Recommended';
                          _section = _Section.explore;
                        });
                      },
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 970
                            ? 3
                            : constraints.maxWidth >= 630
                            ? 2
                            : 1;
                        const gap = 20.0;
                        final width =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: _visibleListings.map((listing) {
                            final vendorProfile =
                                _vendorStoreProfiles[_vendorIdForListing(
                                  listing,
                                )];
                            return SizedBox(
                              width: width,
                              child: _ProduceCard(
                                listing: listing,
                                canDelete: _signedInRole == 'Vendor',
                                canRepost:
                                    _signedInRole == 'Vendor' &&
                                    (listing.isMine ||
                                        listing.ownerEmail == _signedInEmail),
                                canSave:
                                    _signedInRole == null ||
                                    _signedInRole == 'Buyer',
                                isSaved: _savedListingIds.contains(listing.id),
                                onDelete: () => _deleteVendorListing(listing),
                                onRepost: () => _repostVendorListing(listing),
                                onToggleSaved: () =>
                                    _toggleSavedListing(listing),
                                onView: () => _showListingDetails(listing),
                                onOpenVendorStore: () =>
                                    _openVendorStore(listing),
                                vendorPhotoUrl: vendorProfile?.profilePhotoUrl,
                                vendorPhotoBytes:
                                    vendorProfile?.profilePhotoBytes,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_signedInRole != 'Vendor')
          _VendorCallout(onStartSelling: _showNewListingForm),
        const _MarketplaceFooter(),
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _FilterChip(
          label: 'All produce',
          selected: _category == 'All produce',
          onSelected: () => setState(() => _category = 'All produce'),
        ),
        _FilterChip(
          label: 'Vegetables',
          selected: _category == 'Vegetables',
          onSelected: () => setState(() => _category = 'Vegetables'),
        ),
        _FilterChip(
          label: 'Fruits',
          selected: _category == 'Fruits',
          onSelected: () => setState(() => _category = 'Fruits'),
        ),
        _FilterChip(
          label: 'Under ₱50',
          selected: _under50,
          onSelected: () => setState(() => _under50 = !_under50),
        ),
        _FilterChip(
          label: _availableOnly ? 'Available only' : 'Include sold out',
          selected: _availableOnly,
          onSelected: () => setState(() => _availableOnly = !_availableOnly),
        ),
        _FilterChip(
          label: 'Saved favorites',
          selected: _favoritesOnly,
          onSelected: _toggleFavoritesFilter,
        ),
        _FilterDropdown<int>(
          label: 'Max price',
          value: _maximumPrice,
          options: const [
            (null, 'Any'),
            (50, '₱50'),
            (100, '₱100'),
            (200, '₱200'),
            (500, '₱500'),
          ],
          onChanged: (value) => setState(() => _maximumPrice = value),
        ),
        _FilterDropdown<double>(
          label: 'Distance',
          value: _maximumDistance,
          options: const [
            (null, 'Any'),
            (3.0, '3 km'),
            (10.0, '10 km'),
            (25.0, '25 km'),
            (50.0, '50 km'),
          ],
          onChanged: (value) => setState(() => _maximumDistance = value),
        ),
        _FilterDropdown<String>(
          label: 'Sort',
          value: _sortOrder,
          options: const [
            ('Recommended', 'Recommended'),
            ('Price: low to high', 'Price: low to high'),
            ('Price: high to low', 'Price: high to low'),
            ('Nearest first', 'Nearest first'),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sortOrder = value);
          },
        ),
        _FilterChip(
          label: 'Nearby',
          selected: false,
          onSelected: () => _setSection(_Section.nearby),
        ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<(T?, String)> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          items: options
              .map(
                (option) => DropdownMenuItem<T?>(
                  value: option.$1,
                  child: Text(option.$2, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

class _MarketplaceHeader extends StatelessWidget {
  const _MarketplaceHeader({
    required this.compact,
    required this.isVendor,
    required this.isBuyer,
    required this.isSignedIn,
    required this.signedInRole,
    required this.signedInAccount,
    required this.cartItemCount,
    required this.onOpenCart,
    required this.onNotifications,
    required this.onPostProduce,
    required this.onSignIn,
  });

  final bool compact;
  final bool isVendor;
  final bool isBuyer;
  final bool isSignedIn;
  final String? signedInRole;
  final MarketplaceAccount? signedInAccount;
  final int cartItemCount;
  final VoidCallback onOpenCart;
  final VoidCallback onNotifications;
  final VoidCallback onPostProduce;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _paper,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 24,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: _forest,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.eco_outlined,
                color: Color(0xFFDDEB78),
                size: 27,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Local Produce\n',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: 'Connect',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Georgia',
                        color: _deepForest,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSignedIn) ...[
                  if (isBuyer) ...[
                    IconButton(
                      tooltip: cartItemCount == 0
                          ? 'Shopping cart'
                          : 'Shopping cart ($cartItemCount items)',
                      onPressed: onOpenCart,
                      icon: Badge(
                        isLabelVisible: cartItemCount > 0,
                        label: Text('$cartItemCount'),
                        child: const Icon(Icons.shopping_cart_outlined),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: onNotifications,
                    icon: const Icon(Icons.notifications_none_outlined),
                  ),
                  const SizedBox(width: 8),
                ],
                if (isVendor) ...[
                  if (!compact)
                    FilledButton.icon(
                      onPressed: onPostProduce,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Post produce'),
                    )
                  else
                    IconButton.filled(
                      tooltip: 'Post produce',
                      onPressed: onPostProduce,
                      icon: const Icon(Icons.add),
                    ),
                  const SizedBox(width: 10),
                ],
                if (signedInRole != null)
                  Tooltip(
                    message: 'Account: $signedInRole',
                    child: InkWell(
                      onTap: onSignIn,
                      customBorder: const CircleBorder(),
                      child: ProfilePhotoAvatar(
                        radius: 23,
                        photoUrl: signedInAccount?.profilePhotoUrl,
                        photoBytes: signedInAccount?.profilePhotoBytes,
                        placeholderText: signedInRole == 'Vendor'
                            ? 'VE'
                            : 'BY',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _cream,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 50),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final copy = _heroCopy(context);
                final image = _heroImage(context);
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [copy, const SizedBox(height: 32), image],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 11, child: copy),
                    const SizedBox(width: 42),
                    Expanded(flex: 9, child: image),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroCopy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 38, height: 1, color: _leaf),
            const SizedBox(width: 12),
            const Text(
              'FRESH FROM YOUR NEIGHBORHOOD',
              style: TextStyle(
                color: _leaf,
                fontSize: 12,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text.rich(
          TextSpan(
            text: 'Good food grows\n',
            style: const TextStyle(
              color: _deepForest,
              fontFamily: 'Georgia',
              fontSize: 48,
              height: 1.08,
              letterSpacing: -1.9,
              fontWeight: FontWeight.w500,
            ),
            children: const [
              TextSpan(
                text: 'closer to home.',
                style: TextStyle(
                  color: _leaf,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Discover fresh fruits and vegetables from small local vendors near you. Better produce, fair prices, stronger communities.',
          style: TextStyle(fontSize: 16, color: _muted, height: 1.7),
        ),
      ],
    );
  }

  Widget _heroImage(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ProduceImage(
              assetPath: _heroProduceImageAsset,
              fallbackIcon: Icons.local_florist_outlined,
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: _paper.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wb_sunny_outlined, color: _forest, size: 20),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Explore local produce',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Browse vendor listings',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _paper.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Local marketplace',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchAndLocation extends StatelessWidget {
  const _SearchAndLocation({
    required this.controller,
    required this.location,
    required this.onChanged,
    required this.onChooseLocation,
  });

  final TextEditingController controller;
  final String location;
  final ValueChanged<String> onChanged;
  final VoidCallback onChooseLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 460;
          return Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Icon(Icons.search, color: _muted),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search tomatoes, mangoes, pechay...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
              Container(
                height: 44,
                width: 1,
                color: _line,
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              TextButton.icon(
                onPressed: onChooseLocation,
                icon: const Icon(Icons.location_on_outlined, size: 19),
                label: Text(compact ? location : location),
                style: TextButton.styleFrom(
                  foregroundColor: _muted,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: _leaf,
                fontSize: 11,
                letterSpacing: 1.7,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: _deepForest,
                fontFamily: 'Georgia',
                fontSize: 31,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: _muted)),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 16), action],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            action,
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      side: BorderSide(color: selected ? _forest : _line),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _ink,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      backgroundColor: _paper,
      selectedColor: _forest,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    );
  }
}

class _ProduceCard extends StatelessWidget {
  const _ProduceCard({
    required this.listing,
    required this.canDelete,
    required this.canRepost,
    required this.canSave,
    required this.isSaved,
    required this.onDelete,
    required this.onRepost,
    required this.onToggleSaved,
    required this.onView,
    required this.onOpenVendorStore,
    this.vendorPhotoUrl,
    this.vendorPhotoBytes,
  });

  final ProduceListing listing;
  final bool canDelete;
  final bool canRepost;
  final bool canSave;
  final bool isSaved;
  final VoidCallback onDelete;
  final VoidCallback onRepost;
  final VoidCallback onToggleSaved;
  final VoidCallback onView;
  final VoidCallback onOpenVendorStore;
  final String? vendorPhotoUrl;
  final Uint8List? vendorPhotoBytes;

  @override
  Widget build(BuildContext context) {
    final postedAtLabel = listing.postedAtLabel;
    return Card(
      color: _paper,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 205,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ProduceImage(
                  url: listing.imageUrl,
                  bytes: listing.imageBytes,
                  fallbackIcon: listing.category == 'Fruits'
                      ? Icons.apple
                      : Icons.eco_outlined,
                ),
                if (listing.justPosted)
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EFD9),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'JUST POSTED',
                        style: TextStyle(
                          color: _forest,
                          fontSize: 10,
                          letterSpacing: .7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canDelete)
                        Material(
                          color: _paper.withValues(alpha: .95),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Delete listing: ${listing.name}',
                            onPressed: onDelete,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFF9D4038),
                              size: 20,
                            ),
                          ),
                        ),
                      if (canDelete && canRepost) const SizedBox(width: 6),
                      if (canRepost)
                        Material(
                          color: _paper.withValues(alpha: .95),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Repost listing: ${listing.name}',
                            onPressed: onRepost,
                            icon: const Icon(
                              Icons.repeat,
                              color: _forest,
                              size: 20,
                            ),
                          ),
                        ),
                      if ((canDelete || canRepost) && canSave)
                        const SizedBox(width: 8),
                      if (canSave)
                        Material(
                          color: _paper.withValues(alpha: .95),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: isSaved
                                ? 'Remove saved listing'
                                : 'Save listing',
                            onPressed: onToggleSaved,
                            icon: Icon(
                              isSaved ? Icons.favorite : Icons.favorite_border,
                              color: isSaved
                                  ? const Color(0xFFB95F4D)
                                  : _forest,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            listing.category.toUpperCase(),
                            style: const TextStyle(
                              color: _leaf,
                              fontSize: 10,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            listing.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _deepForest,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(
                        text: listing.priceLabel,
                        style: const TextStyle(
                          color: _forest,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        children: [
                          TextSpan(
                            text: '/${listing.unit}',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${listing.quantity} ${listing.unit} available · ${listing.condition} · Available',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (postedAtLabel != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule, color: _muted, size: 13),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Posted $postedAtLabel',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 15),
                Semantics(
                  button: true,
                  label: 'Open ${listing.vendor} store',
                  child: InkWell(
                    onTap: onOpenVendorStore,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          if (vendorPhotoBytes?.isNotEmpty == true ||
                              vendorPhotoUrl?.trim().isNotEmpty == true)
                            ProfilePhotoAvatar(
                              radius: 17,
                              photoUrl: vendorPhotoUrl,
                              photoBytes: vendorPhotoBytes,
                              placeholderIcon: Icons.storefront_outlined,
                            )
                          else
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: const Color(0xFFE9EFE5),
                              child: Text(
                                listing.vendorInitials,
                                style: const TextStyle(
                                  color: _forest,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  listing.vendor,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                        listing.location,
                                        if (listing.distanceKm
                                            case final distance?)
                                          '${distance.toStringAsFixed(1)} km',
                                      ]
                                      .where((text) => text.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.storefront_outlined,
                            color: _forest,
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('View produce'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _forest,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProduceImage extends StatelessWidget {
  const _ProduceImage({
    this.url = '',
    this.bytes,
    this.assetPath,
    required this.fallbackIcon,
  });

  final String url;
  final Uint8List? bytes;
  final String? assetPath;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    if (assetPath case final path?) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _ImagePlaceholder(icon: fallbackIcon),
      );
    }
    if (bytes case final imageBytes?) {
      return Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _ImagePlaceholder(icon: fallbackIcon),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _ImagePlaceholder(icon: fallbackIcon),
    );
  }
}

class _ProducePhotoBanner extends StatelessWidget {
  const _ProducePhotoBanner({required this.height, required this.borderRadius});

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Fresh local produce from neighborhood farms',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _ProduceImage(
                assetPath: _heroProduceImageAsset,
                fallbackIcon: Icons.local_florist_outlined,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x990D2E20)],
                  ),
                ),
              ),
              const Positioned(
                left: 18,
                bottom: 16,
                child: Row(
                  children: [
                    Icon(
                      Icons.eco_outlined,
                      color: Color(0xFFDDEB78),
                      size: 19,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Fresh from local farms',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.icon = Icons.eco_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE9EFE5),
      alignment: Alignment.center,
      child: Icon(icon, size: 52, color: _leaf),
    );
  }
}

class _EmptyListings extends StatelessWidget {
  const _EmptyListings({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 46),
        child: Column(
          children: [
            const Icon(Icons.search_off, size: 42, color: _leaf),
            const SizedBox(height: 12),
            const Text(
              'No produce found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a different search or category.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

class _VendorInventoryMetric extends StatelessWidget {
  const _VendorInventoryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _forest,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

class _SectionHeadingText extends StatelessWidget {
  const _SectionHeadingText({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: _leaf,
            fontSize: 11,
            letterSpacing: 1.7,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: _deepForest,
            fontFamily: 'Georgia',
            fontSize: 29,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: _muted)),
      ],
    );
  }
}

class _VendorCallout extends StatelessWidget {
  const _VendorCallout({required this.onStartSelling});

  final VoidCallback onStartSelling;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _paper,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 46, 24, 46),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 650;
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FOR LOCAL VENDORS',
                      style: TextStyle(
                        color: _leaf,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Bring your local produce to nearby buyers.',
                      style: TextStyle(
                        color: _deepForest,
                        fontFamily: 'Georgia',
                        fontSize: 30,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Share your listings, manage available stock, and coordinate pickup with buyers.',
                      style: TextStyle(color: _muted, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
                final impact = Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF1E8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.eco_outlined, color: _forest, size: 28),
                      SizedBox(height: 20),
                      Text(
                        'Local marketplace',
                        style: TextStyle(
                          color: _forest,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Connect directly with nearby buyers and arrange pickup with each vendor.',
                        style: TextStyle(color: _muted),
                      ),
                    ],
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [copy, const SizedBox(height: 28), impact],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 6, child: copy),
                    const SizedBox(width: 60),
                    Expanded(flex: 4, child: impact),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketplaceFooter extends StatelessWidget {
  const _MarketplaceFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _deepForest,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: const Row(
            children: [
              Icon(Icons.eco_outlined, color: Color(0xFFDDEB78), size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Local Produce Connect · Fresh food. Fair trade. Stronger communities.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Text(
                '© 2025 Project RESCUE',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingDetailsDialog extends StatefulWidget {
  const _ListingDetailsDialog({
    required this.listing,
    required this.availableQuantity,
    required this.trustSummary,
    required this.canPurchase,
    required this.canReviewStore,
    required this.currentBuyerId,
    required this.currentBuyerEmail,
    required this.onReviewStore,
    required this.onReport,
    required this.onPickup,
    required this.onContact,
    required this.onAddToCart,
    required this.onReserve,
    required this.onBuyNow,
  });

  final ProduceListing listing;
  final int availableQuantity;
  final VendorTrustSummary trustSummary;
  final bool canPurchase;
  final bool canReviewStore;
  final String? currentBuyerId;
  final String? currentBuyerEmail;
  final Future<VendorTrustSummary?> Function(
    ProduceListing listing,
    _VendorReviewDraft draft,
  )
  onReviewStore;
  final VoidCallback onReport;
  final VoidCallback onPickup;
  final VoidCallback onContact;
  final Future<bool> Function(int quantity) onAddToCart;
  final Future<void> Function(int quantity) onReserve;
  final Future<void> Function(int quantity) onBuyNow;

  @override
  State<_ListingDetailsDialog> createState() => _ListingDetailsDialogState();
}

class _ListingDetailsDialogState extends State<_ListingDetailsDialog> {
  int _quantity = 1;
  late VendorTrustSummary _trustSummary;

  @override
  void initState() {
    super.initState();
    _trustSummary = widget.trustSummary;
  }

  Future<void> _reviewVendorStore() async {
    final draft = await showDialog<_VendorReviewDraft>(
      context: context,
      builder: (context) => _VendorReviewDialog(
        vendorName: widget.listing.vendor,
        isStoreFeedback: true,
      ),
    );
    if (draft == null || !mounted) return;
    final summary = await widget.onReviewStore(widget.listing, draft);
    if (summary != null && mounted) {
      setState(() => _trustSummary = summary);
    }
  }

  Future<void> _addToCart() async {
    final added = await widget.onAddToCart(_quantity);
    if (added && mounted) Navigator.of(context).pop();
  }

  Future<void> _openListingVideo(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this product video.')),
        );
      }
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open product video: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _paper,
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 800),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 220,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ListingMediaGallery(listing: widget.listing),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton.filledTonal(
                        tooltip: 'Close listing details',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.listing.category} · ${widget.availableQuantity > 0 ? 'AVAILABLE' : 'SOLD OUT'}',
                      style: const TextStyle(
                        color: _leaf,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.listing.name,
                      style: const TextStyle(
                        color: _deepForest,
                        fontFamily: 'Georgia',
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text.rich(
                      TextSpan(
                        text: widget.listing.priceLabel,
                        style: const TextStyle(
                          color: _forest,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        children: [
                          TextSpan(
                            text: '/${widget.listing.unit}',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _DetailFact(
                          label: 'AVAILABLE QUANTITY',
                          value:
                              '${widget.availableQuantity} ${widget.listing.unit}',
                        ),
                        _DetailFact(
                          label: 'PRODUCT CONDITION',
                          value: widget.listing.condition,
                        ),
                        _DetailFact(
                          label: 'LOCATION',
                          value: widget.listing.location,
                        ),
                        const _DetailFact(
                          label: 'AVAILABILITY',
                          value: 'Inventory tracked by the marketplace',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.listing.description.isEmpty
                          ? 'Posted by ${widget.listing.vendor}. Arrange final quantity and pickup with the vendor.'
                          : '${widget.listing.description} Posted by ${widget.listing.vendor}.',
                      style: const TextStyle(color: _muted, height: 1.55),
                    ),
                    if (widget.listing.videoUrls.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Product videos',
                        style: TextStyle(
                          color: _deepForest,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...widget.listing.videoUrls.asMap().entries.map(
                        (entry) => Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => _openListingVideo(entry.value),
                            icon: const Icon(Icons.play_circle_outline),
                            label: Text('Play video ${entry.key + 1}'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (widget.canPurchase && widget.availableQuantity > 0) ...[
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Quantity',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Decrease quantity',
                            onPressed: _quantity <= 1
                                ? null
                                : () => setState(() => _quantity--),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Increase quantity',
                            onPressed: _quantity >= widget.availableQuantity
                                ? null
                                : () => setState(() => _quantity++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          Text(
                            '₱${widget.listing.price * _quantity}',
                            style: const TextStyle(
                              color: _forest,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 430;
                          final addToCart = OutlinedButton.icon(
                            onPressed: _addToCart,
                            icon: const Icon(Icons.add_shopping_cart, size: 18),
                            label: const Text('Add to cart'),
                          );
                          final reserve = OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onReserve(_quantity);
                            },
                            icon: const Icon(
                              Icons.event_available_outlined,
                              size: 18,
                            ),
                            label: const Text('Reserve'),
                          );
                          final buyNow = FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onBuyNow(_quantity);
                            },
                            icon: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 18,
                            ),
                            label: const Text('Buy now'),
                          );
                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [addToCart, reserve, buyNow],
                            );
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [addToCart, reserve, buyNow],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ] else if (widget.canPurchase) ...[
                      const Text(
                        'This listing is sold out.',
                        style: TextStyle(color: Color(0xFF9D4038)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: widget.onPickup,
                          icon: const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                          ),
                          label: const Text('View pickup'),
                        ),
                        FilledButton.icon(
                          onPressed: widget.onContact,
                          icon: const Icon(Icons.chat_bubble_outline, size: 17),
                          label: const Text('Contact vendor'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFF4F6F0),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              color: _forest,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.trustSummary.verificationStatus ==
                                            'pending'
                                        ? 'Verification requested'
                                        : 'Not verified',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Customer feedback is shown below.',
                                    style: const TextStyle(color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.canPurchase)
                              TextButton(
                                onPressed: widget.onReport,
                                child: const Text('Report'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _VendorFeedbackPanel(
                      summary: _trustSummary,
                      canReview: widget.canReviewStore,
                      alreadySubmitted: _trustSummary.reviews.any(
                        (review) =>
                            !review.isVerifiedPurchase &&
                            (review.buyerUid == widget.currentBuyerId ||
                                review.buyerEmail == widget.currentBuyerEmail),
                      ),
                      onReview: _reviewVendorStore,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VendorFeedbackPanel extends StatelessWidget {
  const _VendorFeedbackPanel({
    required this.summary,
    this.canReview = false,
    this.alreadySubmitted = false,
    this.onReview,
    this.onRefresh,
  });

  final VendorTrustSummary summary;
  final bool canReview;
  final bool alreadySubmitted;
  final VoidCallback? onReview;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final reviews = summary.reviews;
    final breakdown = summary.ratingBreakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Vendor rating',
                style: TextStyle(
                  color: _deepForest,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh vendor ratings',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              summary.reviewCount == 0
                  ? '—'
                  : summary.averageRating.toStringAsFixed(1),
              style: const TextStyle(
                color: _deepForest,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(
                    5,
                    (index) => Icon(
                      index < summary.averageRating.round()
                          ? Icons.star
                          : Icons.star_border,
                      color: const Color(0xFFD59B2D),
                      size: 19,
                    ),
                  ),
                ),
                Text(
                  '${summary.reviewCount} customer review(s)',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...[5, 4, 3, 2, 1].map((rating) {
          final count = breakdown[rating] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '$rating star${rating == 1 ? '' : 's'}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: summary.reviewCount == 0
                        ? 0
                        : count / summary.reviewCount,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: _line,
                    color: const Color(0xFFD59B2D),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 18),
        const Text(
          'Customer reviews',
          style: TextStyle(
            color: _deepForest,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (reviews.isEmpty)
          const Text(
            'No customer ratings or feedback yet.',
            style: TextStyle(color: _muted),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index];
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F7F1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfilePhotoAvatar(
                          radius: 19,
                          photoUrl: review.buyerPhotoUrl,
                          photoBytes: review.buyerPhotoBytes,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                review.buyerName,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _reviewDateLabel(review.createdAt),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F0E7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            review.isVerifiedPurchase
                                ? 'Verified purchase'
                                : 'Store feedback',
                            style: const TextStyle(
                              color: _forest,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: List.generate(
                        5,
                        (index) => Icon(
                          index < review.rating
                              ? Icons.star
                              : Icons.star_border,
                          color: const Color(0xFFD59B2D),
                          size: 17,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      review.comment.isEmpty
                          ? 'No written feedback was provided.'
                          : review.comment,
                      style: const TextStyle(color: _ink, height: 1.4),
                    ),
                  ],
                ),
              );
            },
          ),
        if (canReview) ...[
          const SizedBox(height: 12),
          if (alreadySubmitted)
            const Chip(
              avatar: Icon(Icons.check_circle_outline, size: 16),
              label: Text('Your store feedback submitted'),
              visualDensity: VisualDensity.compact,
            )
          else if (onReview != null)
            OutlinedButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Rate this vendor store'),
            ),
        ],
      ],
    );
  }
}

String _reviewDateLabel(DateTime date) {
  final localDate = date.toLocal();
  return '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 195, maxWidth: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4EE),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 9,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ListingMediaGallery extends StatefulWidget {
  const _ListingMediaGallery({required this.listing});

  final ProduceListing listing;

  @override
  State<_ListingMediaGallery> createState() => _ListingMediaGalleryState();
}

class _ListingMediaGalleryState extends State<_ListingMediaGallery> {
  int _selectedImage = 0;

  List<ListingMediaAsset> get _localPhotos => widget.listing.pendingMedia
      .where((media) => !media.isVideo && media.bytes != null)
      .toList(growable: false);

  List<String> get _imageUrls {
    if (widget.listing.imageUrls.isNotEmpty) return widget.listing.imageUrls;
    return widget.listing.imageUrl.isEmpty
        ? const []
        : [widget.listing.imageUrl];
  }

  @override
  Widget build(BuildContext context) {
    final localPhotos = _localPhotos;
    final imageUrls = _imageUrls;
    final imageCount = localPhotos.isNotEmpty
        ? localPhotos.length
        : imageUrls.length;
    final selectedImage = _selectedImage < imageCount ? _selectedImage : 0;
    return ColoredBox(
      color: const Color(0xFFF3F4EE),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: _ProduceImage(
                url: localPhotos.isNotEmpty
                    ? ''
                    : imageUrls.isEmpty
                    ? ''
                    : imageUrls[selectedImage],
                bytes: localPhotos.isNotEmpty
                    ? localPhotos[selectedImage].bytes
                    : selectedImage == 0
                    ? widget.listing.imageBytes
                    : null,
                fallbackIcon: Icons.eco_outlined,
              ),
            ),
          ),
          if (imageCount > 1)
            SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: imageCount,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => setState(() => _selectedImage = index),
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selectedImage == index ? _forest : _line,
                          width: selectedImage == index ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: localPhotos.isNotEmpty
                          ? Image.memory(
                              localPhotos[index].bytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image_outlined),
                            )
                          : Image.network(
                              imageUrls[index],
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                  ? child
                                  : const Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _VendorReportDraft {
  const _VendorReportDraft({required this.reason, required this.details});

  final String reason;
  final String details;
}

class _VendorReportDialog extends StatefulWidget {
  const _VendorReportDialog();

  @override
  State<_VendorReportDialog> createState() => _VendorReportDialogState();
}

class _VendorReportDialogState extends State<_VendorReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _detailsController = TextEditingController();
  String _reason = 'Suspected scam';

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report this vendor'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This report is saved only on this device and will not be reviewed by a team.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items:
                const [
                  'Suspected scam',
                  'Misleading listing',
                  'Unsafe or inappropriate behavior',
                  'Other',
                ].map((reason) {
                  return DropdownMenuItem(value: reason, child: Text(reason));
                }).toList(),
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _detailsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _VendorReportDraft(
            reason: _reason,
            details: _detailsController.text.trim(),
          ),
        ),
        child: const Text('Save report'),
      ),
    ],
  );
}

class _VendorReviewDraft {
  const _VendorReviewDraft({required this.rating, required this.comment});

  final int rating;
  final String comment;
}

class _VendorReviewDialog extends StatefulWidget {
  const _VendorReviewDialog({
    required this.vendorName,
    this.isStoreFeedback = false,
  });

  final String vendorName;
  final bool isStoreFeedback;

  @override
  State<_VendorReviewDialog> createState() => _VendorReviewDialogState();
}

class _VendorReviewDialogState extends State<_VendorReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  int _rating = 0;
  String? _ratingError;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating == 0) {
      setState(() => _ratingError = 'Choose a star rating to continue.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _VendorReviewDraft(
        rating: _rating,
        comment: _commentController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Review ${widget.vendorName}'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isStoreFeedback
                    ? 'Share your experience with this vendor store. This feedback is not tied to a completed purchase.'
                    : 'Only completed purchases can be reviewed. Your purchase is verified when you submit.',
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => IconButton(
                    tooltip: 'Rate ${index + 1} stars',
                    onPressed: () => setState(() {
                      _rating = index + 1;
                      _ratingError = null;
                    }),
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFD59B2D),
                    ),
                  ),
                ),
              ),
              if (_ratingError != null)
                Text(
                  _ratingError!,
                  style: const TextStyle(
                    color: Color(0xFF9D4038),
                    fontSize: 12,
                  ),
                ),
              TextFormField(
                controller: _commentController,
                maxLength: 500,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message feedback',
                  hintText: 'Tell others about your experience',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please write a short review.'
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.send_outlined),
        label: Text(
          widget.isStoreFeedback ? 'Submit feedback' : 'Submit review',
        ),
      ),
    ],
  );
}

class _EditListingDialog extends StatefulWidget {
  const _EditListingDialog({required this.listing});

  final ProduceListing listing;

  @override
  State<_EditListingDialog> createState() => _EditListingDialogState();
}

class _EditListingDialogState extends State<_EditListingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _quantityController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _imageUrlController;
  late String _category;
  late bool _available;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.listing.name);
    _priceController = TextEditingController(
      text: widget.listing.price.toString(),
    );
    final quantity =
        int.tryParse(
          widget.listing.quantity.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
    _quantityController = TextEditingController(text: quantity.toString());
    _descriptionController = TextEditingController(
      text: widget.listing.description,
    );
    _imageUrlController = TextEditingController(text: widget.listing.imageUrl);
    _category = widget.listing.category == 'Fruits' ? 'Fruits' : 'Vegetables';
    _available = quantity > 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final original = widget.listing;
    Navigator.pop(
      context,
      ProduceListing(
        id: original.id,
        name: _nameController.text.trim(),
        category: _category,
        price: int.parse(_priceController.text.trim()),
        unit: original.unit,
        quantity: _available ? _quantityController.text.trim() : '0',
        condition: original.condition,
        vendor: original.vendor,
        vendorInitials: original.vendorInitials,
        location: original.location,
        distanceKm: original.distanceKm,
        imageUrl: _imageUrlController.text.trim(),
        ownerEmail: original.ownerEmail,
        ownerUid: original.ownerUid,
        imageUrls: _imageUrlController.text.trim().isEmpty
            ? const []
            : [_imageUrlController.text.trim()],
        videoUrls: original.videoUrls,
        latitude: original.latitude,
        longitude: original.longitude,
        postedAt: original.postedAt,
        justPosted: original.justPosted,
        description: _descriptionController.text.trim(),
        isMine: original.isMine,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Manage ${widget.listing.name}'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _imageUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Hosted product photo URL (optional)',
              hintText: 'https://example.com/photo.jpg',
              helperText: 'Use a publicly accessible HTTP or HTTPS image URL.',
            ),
            validator: (value) {
              final url = value?.trim() ?? '';
              return url.isNotEmpty && !isHostedMediaUrl(url)
                  ? 'Enter a valid public HTTP or HTTPS URL.'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Product name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a product name.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Price per ${widget.listing.unit} (₱)',
            ),
            validator: (value) {
              final price = int.tryParse(value?.trim() ?? '');
              return price == null || price <= 0
                  ? 'Enter a valid positive price.'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: const [
              DropdownMenuItem(value: 'Vegetables', child: Text('Vegetables')),
              DropdownMenuItem(value: 'Fruits', child: Text('Fruits')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Available for sale'),
            value: _available,
            onChanged: (value) => setState(() => _available = value),
          ),
          if (_available)
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Stock (${widget.listing.unit})',
              ),
              validator: (value) {
                final quantity = int.tryParse(value?.trim() ?? '');
                return quantity == null || quantity < 1
                    ? 'Enter at least 1 unit, or mark unavailable.'
                    : null;
              },
            ),
          const SizedBox(height: 8),
          const Text(
            'Updates sync to the marketplace when you are connected.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save changes')),
    ],
  );
}

class _NewListingDialog extends StatefulWidget {
  const _NewListingDialog({
    required this.vendorEmail,
    required this.vendorName,
    required this.vendorAddress,
    required this.vendorLatitude,
    required this.vendorLongitude,
  });

  final String vendorEmail;
  final String vendorName;
  final String vendorAddress;
  final double? vendorLatitude;
  final double? vendorLongitude;

  @override
  State<_NewListingDialog> createState() => _NewListingDialogState();
}

class _NewListingDialogState extends State<_NewListingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _hostedImageUrlController = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageFileName;
  String? _formError;
  String _condition = 'Fresh';
  String _unit = 'kg';

  @override
  void initState() {
    super.initState();
    _locationController.text = widget.vendorAddress;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _hostedImageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty) return;
      final file = result.single;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > maxFirestoreImageBytes) {
        if (mounted) {
          setState(() {
            _formError = bytes.isEmpty
                ? 'Choose a valid image.'
                : 'Choose an image file that is 5 MB or smaller.';
          });
        }
        return;
      }
      final compressedBytes = await compute(
        compressListingImageForFirestore,
        bytes,
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = compressedBytes;
        _imageFileName = file.name;
        _formError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _formError = 'Could not select image: $error');
      }
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (widget.vendorLatitude == null ||
        widget.vendorLongitude == null ||
        !widget.vendorLatitude!.isFinite ||
        !widget.vendorLongitude!.isFinite) {
      setState(
        () => _formError =
            'Save the exact vendor map pin from your profile before posting.',
      );
      return;
    }
    final name = _nameController.text.trim();
    final hostedImageUrl = _hostedImageUrlController.text.trim();
    final id = 'listing-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      ProduceListing(
        id: id,
        name: name,
        category: _isFruit(name) ? 'Fruits' : 'Vegetables',
        price: int.parse(_priceController.text.trim()),
        unit: _unit,
        quantity: _quantityController.text.trim(),
        condition: _condition,
        vendor: widget.vendorName,
        vendorInitials: widget.vendorName
            .trim()
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .take(2)
            .map((word) => word[0].toUpperCase())
            .join(),
        location: _locationController.text.trim(),
        ownerEmail: widget.vendorEmail,
        imageUrl: hostedImageUrl,
        imageBytes: _imageBytes,
        imageFileName: _imageFileName,
        imageUrls: hostedImageUrl.isEmpty ? const [] : [hostedImageUrl],
        latitude: widget.vendorLatitude,
        longitude: widget.vendorLongitude,
        postedAt: DateTime.now(),
        justPosted: true,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  bool _isFruit(String name) {
    const fruits = [
      'apple',
      'banana',
      'berry',
      'calamansi',
      'citrus',
      'fruit',
      'mango',
      'orange',
      'papaya',
      'pineapple',
    ];
    return fruits.any(name.toLowerCase().contains);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _paper,
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 570, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NEW LISTING',
                            style: TextStyle(
                              color: _leaf,
                              fontSize: 11,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Share your fresh produce',
                            style: TextStyle(
                              color: _deepForest,
                              fontFamily: 'Georgia',
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose an optional product photo from your device. The listing uses your saved vendor map pin and address.',
                  style: TextStyle(color: _muted),
                ),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _formError!,
                      style: const TextStyle(color: Color(0xFF9D4038)),
                    ),
                  ),
                const SizedBox(height: 20),
                _FormFieldLabel(
                  label: 'Hosted product photo URL (optional)',
                  child: TextFormField(
                    controller: _hostedImageUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/photo.jpg',
                      helperText:
                          'Use a publicly accessible HTTP or HTTPS image URL.',
                    ),
                    validator: (value) {
                      final url = value?.trim() ?? '';
                      return url.isNotEmpty && !isHostedMediaUrl(url)
                          ? 'Enter a valid public HTTP or HTTPS URL.'
                          : null;
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _FormFieldLabel(
                  label: 'Produce name',
                  child: TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Fresh Tomatoes',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a produce name'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                _FormFieldLabel(
                  label: 'Product photo (optional)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.upload_outlined),
                        label: Text(
                          _imageFileName == null
                              ? 'Choose image'
                              : 'Change image',
                        ),
                      ),
                      if (_imageBytes != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _imageBytes!,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _imageBytes = null;
                            _imageFileName = null;
                          }),
                          icon: const Icon(Icons.close),
                          label: const Text('Remove image'),
                        ),
                      ],
                      const Text(
                        'Photos up to 5 MB are optimized and saved in Firestore with the listing.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _FormFieldLabel(
                        label: 'Price (₱)',
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '40'),
                          validator: (value) {
                            final price = int.tryParse(value?.trim() ?? '');
                            return price == null || price <= 0
                                ? 'Enter a valid price'
                                : null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FormFieldLabel(
                        label: 'Available quantity',
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(hintText: '30'),
                          validator: (value) {
                            final quantity = int.tryParse(value?.trim() ?? '');
                            return quantity == null || quantity < 1
                                ? 'Enter a whole quantity greater than zero'
                                : null;
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _FormFieldLabel(
                        label: 'Condition',
                        child: DropdownButtonFormField<String>(
                          initialValue: _condition,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'Fresh',
                              child: Text('Fresh'),
                            ),
                            DropdownMenuItem(
                              value: 'Newly harvested',
                              child: Text('Newly harvested'),
                            ),
                            DropdownMenuItem(
                              value: 'Surplus',
                              child: Text('Surplus'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _condition = value ?? 'Fresh'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FormFieldLabel(
                        label: 'Selling unit',
                        child: DropdownButtonFormField<String>(
                          initialValue: _unit,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'kg', child: Text('kg')),
                            DropdownMenuItem(
                              value: 'bundle',
                              child: Text('bundle'),
                            ),
                            DropdownMenuItem(
                              value: 'dozen',
                              child: Text('dozen'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _unit = value ?? 'kg'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FormFieldLabel(
                  label: 'Pickup location (from vendor profile)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _locationController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          suffixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Set an address on your vendor profile'
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.vendorLatitude != null &&
                                widget.vendorLongitude != null
                            ? 'Map pin: ${widget.vendorLatitude!.toStringAsFixed(6)}, ${widget.vendorLongitude!.toStringAsFixed(6)}'
                            : 'No exact map pin saved. Set your location from your vendor profile before posting.',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormFieldLabel(
                  label: 'Product description',
                  child: TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          'Describe quality, harvest date, and pickup details',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('POST'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormFieldLabel extends StatelessWidget {
  const _FormFieldLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        child,
      ],
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({
    required this.initialAccountType,
    required this.onSubmit,
    required this.onRequestPasswordReset,
    required this.deviceLocationService,
    required this.reverseGeocoder,
    this.initialCreatingAccount = false,
  });

  final String initialAccountType;
  final bool initialCreatingAccount;
  final DeviceLocationService deviceLocationService;
  final ReverseGeocoder reverseGeocoder;
  final Future<MarketplaceAccount> Function(
    MarketplaceCredentials credentials,
    bool creatingAccount,
  )
  onSubmit;
  final Future<void> Function(String email) onRequestPasswordReset;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _businessTypeController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _phoneController = TextEditingController();
  late String _accountType = widget.initialAccountType;
  late bool _creatingAccount = widget.initialCreatingAccount;
  LatLng? _selectedVendorLocation;
  bool _isSubmitting = false;
  bool _showSuccess = false;
  String? _submitError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    _fullNameController.dispose();
    _companyNameController.dispose();
    _businessTypeController.dispose();
    _addressLine1Controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    if (_creatingAccount &&
        _accountType == 'Vendor' &&
        _selectedVendorLocation == null) {
      setState(() {
        _submitError = 'Please select a location on the map before continuing.';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final credentials = MarketplaceCredentials(
      role: _accountType,
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _creatingAccount && _accountType == 'Vendor'
          ? _fullNameController.text.trim()
          : null,
      passwordConfirmation: _creatingAccount && _accountType == 'Vendor'
          ? _passwordConfirmationController.text
          : null,
      companyName: _creatingAccount && _accountType == 'Vendor'
          ? _companyNameController.text.trim()
          : null,
      businessType: _creatingAccount && _accountType == 'Vendor'
          ? _businessTypeController.text.trim()
          : null,
      addressLine1: _creatingAccount && _accountType == 'Vendor'
          ? _addressLine1Controller.text.trim()
          : null,
      phone: _creatingAccount && _accountType == 'Vendor'
          ? _phoneController.text.trim()
          : null,
      latitude: _creatingAccount && _accountType == 'Vendor'
          ? _selectedVendorLocation?.latitude
          : null,
      longitude: _creatingAccount && _accountType == 'Vendor'
          ? _selectedVendorLocation?.longitude
          : null,
    );
    try {
      final account = await widget.onSubmit(credentials, _creatingAccount);
      if (!mounted) return;
      setState(() => _showSuccess = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pop(account);
    } on MarketplaceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = error.toString();
      });
    }
  }

  String? _requiredValidator(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label is required' : null;

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    return email.contains('@') && email.contains('.')
        ? null
        : 'Enter a valid email address';
  }

  String? _loginIdentifierValidator(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.contains('@')) return _emailValidator(identifier);
    return RegExp(r'^[a-zA-Z0-9_-]{3,50}$').hasMatch(identifier)
        ? null
        : 'Enter a valid email address or username (3–50 letters, numbers, _ or -)';
  }

  Future<void> _selectVendorLocation() async {
    final selection = await showDialog<MapLocationSelection>(
      context: context,
      builder: (context) => MapLocationPickerDialog(
        initialLocation: _selectedVendorLocation,
        locationService: widget.deviceLocationService,
        reverseGeocoder: widget.reverseGeocoder,
        resolveAddress: true,
        title: 'Choose your vendor location',
      ),
    );
    if (selection != null && mounted) {
      setState(() {
        _selectedVendorLocation = selection.location;
        if (selection.address?.isNotEmpty ?? false) {
          _addressLine1Controller.text = selection.address!;
        }
      });
    }
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return _FormFieldLabel(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        validator: validator,
      ),
    );
  }

  Widget _passwordField() {
    return _FormFieldLabel(
      label: 'Password',
      child: TextFormField(
        controller: _passwordController,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(hintText: 'At least 8 characters'),
        validator: (value) =>
            (value?.length ?? 0) < 8 ? 'Use at least 8 characters' : null,
      ),
    );
  }

  Widget _passwordConfirmationField() {
    return _FormFieldLabel(
      label: 'Confirm Password',
      child: TextFormField(
        controller: _passwordConfirmationController,
        obscureText: true,
        autofillHints: const [AutofillHints.newPassword],
        decoration: const InputDecoration(hintText: 'Re-enter your password'),
        validator: (value) =>
            value != _passwordController.text ? 'Passwords do not match' : null,
      ),
    );
  }

  Widget _loginIdentifierField({required String label}) {
    return _FormFieldLabel(
      label: label,
      child: TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.username, AutofillHints.email],
        decoration: const InputDecoration(
          hintText: 'Enter a username or email address',
        ),
        validator: _loginIdentifierValidator,
      ),
    );
  }

  Widget _accountTypeField() {
    return _FormFieldLabel(
      label: 'Account type',
      child: DropdownButtonFormField<String>(
        initialValue: _accountType,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'Buyer', child: Text('Buyer')),
          DropdownMenuItem(value: 'Vendor', child: Text('Vendor')),
        ],
        onChanged: _isSubmitting
            ? null
            : (value) => setState(() => _accountType = value ?? 'Buyer'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVendorRegistration = _creatingAccount && _accountType == 'Vendor';
    return Dialog(
      backgroundColor: _paper,
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isVendorRegistration ? 760 : 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProducePhotoBanner(
                  height: isVendorRegistration ? 130 : 150,
                  borderRadius: 16,
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Text(
                  'WELCOME TO THE MARKET',
                  style: TextStyle(
                    color: _leaf,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isVendorRegistration
                      ? 'Register your vendor account'
                      : _creatingAccount
                      ? 'Create your account'
                      : 'Sign in to Local Produce',
                  style: const TextStyle(
                    color: _deepForest,
                    fontFamily: 'Georgia',
                    fontSize: 27,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isVendorRegistration
                      ? 'Register your name and business to connect with buyers.'
                      : 'Sign in to save produce, receive neighborhood Notification, and connect with local vendors.',
                  style: const TextStyle(color: _muted, height: 1.5),
                ),
                const SizedBox(height: 20),
                if (isVendorRegistration) ...[
                  _textField(
                    label: 'Full Name *',
                    controller: _fullNameController,
                    hint: 'Enter your full name',
                    validator: (value) =>
                        _requiredValidator(value, 'Full name'),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    label: 'Contact Number *',
                    controller: _phoneController,
                    hint: 'Enter your contact number',
                    keyboardType: TextInputType.phone,
                    validator: (value) =>
                        _requiredValidator(value, 'Contact number'),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    label: 'Stall/Business Name *',
                    controller: _companyNameController,
                    hint: 'Enter your stall or business name',
                    validator: (value) =>
                        _requiredValidator(value, 'Stall/business name'),
                  ),
                  const SizedBox(height: 14),
                  _FormFieldLabel(
                    label: 'Business Type *',
                    child: DropdownButtonFormField<String>(
                      initialValue: _businessTypeController.text.isEmpty
                          ? null
                          : _businessTypeController.text,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'Select a business type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Vegetable Vendor',
                          child: Text('Vegetable Vendor'),
                        ),
                        DropdownMenuItem(
                          value: 'Fruit Vendor',
                          child: Text('Fruit Vendor'),
                        ),
                        DropdownMenuItem(value: 'Both', child: Text('Both')),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) =>
                                _businessTypeController.text = value ?? '',
                      validator: (value) =>
                          value == null ? 'Select a business type' : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    label: 'Market Address *',
                    controller: _addressLine1Controller,
                    hint: 'Enter the market address',
                    validator: (value) =>
                        _requiredValidator(value, 'Market address'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _selectVendorLocation,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      _selectedVendorLocation == null
                          ? 'Location Map * — Select a location using the map pin'
                          : 'Location selected',
                    ),
                  ),
                  if (_selectedVendorLocation == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Select a map location before continuing.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _loginIdentifierField(label: 'Username or Email *'),
                  const SizedBox(height: 14),
                  _passwordField(),
                  const SizedBox(height: 14),
                  _passwordConfirmationField(),
                ] else ...[
                  _loginIdentifierField(label: 'Username or Email'),
                  const SizedBox(height: 14),
                  _passwordField(),
                  if (!_creatingAccount) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (context) => _ForgotPasswordDialog(
                                  initialEmail: _emailController.text.trim(),
                                  onSubmit: widget.onRequestPasswordReset,
                                ),
                              ),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _accountTypeField(),
                ],
                const SizedBox(height: 18),
                if (_submitError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _submitError!,
                      style: const TextStyle(
                        color: Color(0xFF9D4038),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: _showSuccess
                          ? const Icon(
                              Icons.check_circle,
                              key: ValueKey('account-success'),
                              size: 20,
                            )
                          : _isSubmitting
                          ? const SizedBox(
                              key: ValueKey('account-progress'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.login,
                              key: ValueKey('account-login'),
                              size: 18,
                            ),
                    ),
                    label: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _showSuccess
                            ? 'You’re all set!'
                            : _isSubmitting
                            ? _creatingAccount
                                  ? 'Creating account…'
                                  : 'Signing in…'
                            : _creatingAccount
                            ? 'Create account'
                            : 'Sign in',
                        key: ValueKey(
                          'account-button-$_creatingAccount-$_isSubmitting-$_showSuccess',
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(
                            () => _creatingAccount = !_creatingAccount,
                          ),
                    child: Text(
                      _creatingAccount
                          ? 'Already have an account? Sign in'
                          : 'Create an account',
                    ),
                  ),
                ),
                const Text(
                  'Offline sign-in stores a password hash on this device. Accounts created offline stay on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.onSubmit,
  });

  final String initialEmail;
  final Future<void> Function(String email) onSubmit;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail.contains('@') ? widget.initialEmail : '',
  );
  bool _isSubmitting = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _message = null;
      _error = null;
    });
    try {
      await widget.onSubmit(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _message = 'If an account exists for that email, a password reset link has been sent. Check your inbox and spam folder.';
      });
    } on MarketplaceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset your password'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the email address on your account. We’ll send you a link to choose a new password.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.contains('@') && email.contains('.')
                      ? null
                      : 'Enter a valid email address';
                },
              ),
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(_message!, style: const TextStyle(color: _forest)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: Color(0xFF9D4038))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _isSubmitting || _message != null ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Send reset link'),
        ),
      ],
    );
  }
}

class _NotificationPage extends StatelessWidget {
  const _NotificationPage({
    required this.notifications,
    required this.onOpenListing,
  });

  final List<MarketplaceNotification> notifications;
  final ValueChanged<ProduceListing> onOpenListing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _SectionHeadingText(
              eyebrow: 'YOUR NEIGHBORHOOD',
              title: 'Notification',
              subtitle: 'Fresh updates from local vendors.',
            ),
            const SizedBox(height: 22),
            if (notifications.isNotEmpty)
              ...notifications.map(
                (notification) => Card(
                  color: _paper,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: _line),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE9EFE5),
                      child: Icon(Icons.eco_outlined, color: _forest),
                    ),
                    title: Text(
                      notification.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${notification.message} · ${notification.timeLabel}',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpenListing(notification.listing),
                  ),
                ),
              )
            else
              const Text(
                'You’re all caught up. Check back for fresh listings.',
              ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeBenefit extends StatelessWidget {
  const _WelcomeBenefit({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFE9EFE5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _forest, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _deepForest,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestAccessPage extends StatelessWidget {
  const _GuestAccessPage({
    required this.onCreateAccount,
    required this.onSignIn,
    required this.onBrowseAsGuest,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;
  final VoidCallback onBrowseAsGuest;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _cream,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            label: 'Fresh local produce fills the home page background',
            image: true,
            child: _ProduceImage(
              url: _homeBackgroundImageUrl,
              fallbackIcon: Icons.local_florist_outlined,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66F7F5EE),
                  Color(0x44F7F5EE),
                  Color(0x22F7F5EE),
                ],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              final short = constraints.maxHeight < 740;
              final cardPadding = compact ? 22.0 : 32.0;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 24,
                  vertical: short ? 12 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > (short ? 24 : 48)
                        ? constraints.maxHeight - (short ? 24 : 48)
                        : 0,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              alignment: Alignment.topCenter,
                              clipBehavior: Clip.none,
                              children: [
                                Card(
                                  color: _paper.withValues(alpha: .96),
                                  elevation: 8,
                                  shadowColor: _deepForest.withValues(
                                    alpha: .2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    side: BorderSide(
                                      color: _line.withValues(alpha: .9),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      cardPadding,
                                      short ? 50 : 56,
                                      cardPadding,
                                      short ? 16 : 24,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'FRESH FROM YOUR NEIGHBORHOOD',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _forest,
                                            fontSize: 11,
                                            letterSpacing: 1.6,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        SizedBox(height: short ? 8 : 12),
                                        Text(
                                          'Good food grows\ncloser to home.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _deepForest,
                                            fontSize: compact ? 29 : 36,
                                            height: 1.08,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          width: 160,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: _leaf,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: short ? 10 : 16),
                                        const Text(
                                          'Explore fresh local produce, compare prices, and learn about local vendors. Create an account only when you are ready to take action.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _muted,
                                            height: 1.5,
                                            fontSize: 15,
                                          ),
                                        ),
                                        SizedBox(height: short ? 16 : 24),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: _deepForest,
                                              side: const BorderSide(
                                                color: _forest,
                                                width: 1.3,
                                              ),
                                            ),
                                            onPressed: onBrowseAsGuest,
                                            icon: const Icon(
                                              Icons.storefront_outlined,
                                            ),
                                            label: const Text(
                                              'Browse as guest',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: _deepForest,
                                            ),
                                            onPressed: onCreateAccount,
                                            icon: const Icon(
                                              Icons.person_add_alt_1_outlined,
                                            ),
                                            label: const Text(
                                              'Create your account',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: _deepForest,
                                              side: const BorderSide(
                                                color: _forest,
                                                width: 1.3,
                                              ),
                                            ),
                                            onPressed: onSignIn,
                                            child: const Text('Sign in'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: -34,
                                  child: Container(
                                    width: 84,
                                    height: 84,
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: _paper,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFB6C75A),
                                        width: 2,
                                      ),
                                    ),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: _forest,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.eco_outlined,
                                        color: Color(0xFFDDEB78),
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: short ? 18 : 24),

                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, benefitConstraints) {
                                final benefits = [
                                  const _WelcomeBenefit(
                                    icon: Icons.shopping_basket_outlined,
                                    title: 'For buyers',
                                    description: 'Find fresh local goods, compare prices, and shop directly from nearby vendors.',
                                  ),
                                  const _WelcomeBenefit(
                                    icon: Icons.storefront_outlined,
                                    title: 'For vendors',
                                    description: 'Showcase your products, reach local buyers, and manage your listings in one place.',
                                  ),
                                ];
                                if (benefitConstraints.maxWidth >= 500) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: benefits[0]),
                                      const SizedBox(width: 12),
                                      Expanded(child: benefits[1]),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    benefits[0],
                                    const SizedBox(height: 10),
                                    benefits[1],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GuestBrowsingBanner extends StatelessWidget {
  const _GuestBrowsingBanner({
    required this.location,
    required this.onBackToWelcome,
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final String location;
  final VoidCallback onBackToWelcome;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _paper,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Back to welcome',
                  onPressed: onBackToWelcome,
                  icon: const Icon(Icons.arrow_back),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    'Browsing as guest · $location · device location is not used',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: onSignIn, child: const Text('Sign in')),
                TextButton(
                  onPressed: onCreateAccount,
                  child: const Text('Create account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyerOnlyMessage extends StatelessWidget {
  const _BuyerOnlyMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The shopping cart is available to buyer accounts. Switch to a buyer account to continue.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, height: 1.5),
        ),
      ),
    );
  }
}

class _CartPage extends StatelessWidget {
  const _CartPage({
    required this.items,
    required this.availableQuantity,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onCheckout,
    required this.onContinueShopping,
  });

  final List<MarketplaceCartItem> items;
  final int Function(ProduceListing listing) availableQuantity;
  final void Function(MarketplaceCartItem item, int quantity) onQuantityChanged;
  final ValueChanged<MarketplaceCartItem> onRemove;
  final VoidCallback onCheckout;
  final VoidCallback onContinueShopping;

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0, (sum, item) => sum + item.subtotal);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _SectionHeadingText(
              eyebrow: 'YOUR MARKET BAG',
              title: 'Shopping cart',
              subtitle: 'Review your produce before placing an order.',
            ),
            const SizedBox(height: 20),
            if (items.isEmpty)
              Card(
                color: _paper,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.shopping_cart_outlined,
                        color: _leaf,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your cart is empty',
                        style: TextStyle(
                          color: _deepForest,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Browse the market and add fresh produce to your cart.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onContinueShopping,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back to market'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              for (final item in items)
                Card(
                  color: _paper,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: _line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final quantityControls = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Decrease quantity',
                              onPressed: () =>
                                  onQuantityChanged(item, item.quantity - 1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Increase quantity',
                              onPressed:
                                  item.quantity >=
                                      availableQuantity(item.listing)
                                  ? null
                                  : () => onQuantityChanged(
                                      item,
                                      item.quantity + 1,
                                    ),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        );
                        final removeButton = IconButton(
                          tooltip: 'Remove ${item.listing.name}',
                          onPressed: () => onRemove(item),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFF9D4038),
                          ),
                        );
                        final productImage = ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 78,
                            height: 78,
                            child: _ProduceImage(
                              url: item.listing.imageUrl,
                              bytes: item.listing.imageBytes,
                              fallbackIcon: Icons.eco_outlined,
                            ),
                          ),
                        );
                        final productDescription = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.listing.name,
                              style: const TextStyle(
                                color: _deepForest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.listing.priceLabel}/${item.listing.unit} · ${item.listing.vendor}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                        if (constraints.maxWidth < 560) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  productImage,
                                  const SizedBox(width: 12),
                                  Expanded(child: productDescription),
                                  removeButton,
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '₱${item.subtotal}',
                                      style: const TextStyle(
                                        color: _forest,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  quantityControls,
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            productImage,
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  productDescription,
                                  const SizedBox(height: 5),
                                  Text(
                                    '₱${item.subtotal}',
                                    style: const TextStyle(
                                      color: _forest,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            removeButton,
                            quantityControls,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              Card(
                color: _paper,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Order total',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '₱$total',
                            style: const TextStyle(
                              color: _forest,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Payment and pickup are arranged directly with each vendor.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onCheckout,
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Checkout'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.signedInRole,
    required this.signedInEmail,
    required this.account,
    required this.onChangeProfilePhoto,
    required this.isUpdatingProfilePhoto,
    required this.vendorAccount,
    required this.ownListings,
    required this.isLoadingListings,
    required this.listingsError,
    required this.onRetryListings,
    required this.onSignIn,
    required this.onVendorSignIn,
    required this.onPostProduce,
    required this.onManageVendorLocation,
    required this.onSignOut,
    required this.onDeleteListing,
    required this.onRepostListing,
    required this.onEditListing,
    required this.vendorVerificationStatus,
    required this.vendorTrustSummary,
    required this.onRefreshVendorTrust,
    required this.onRequestVendorVerification,
    required this.onBackToMarket,
    required this.reservations,
    required this.cancellingReservationIds,
    required this.onCancelReservation,
    required this.orders,
    required this.deletingBuyerOrderIds,
    required this.onDeleteBuyerOrder,
    required this.onOpenMessages,
    required this.onMessageOrderParticipant,
    required this.onReviewVendor,
    required this.reviewedPurchaseKeys,
    required this.onUpdateVendorOrder,
    required this.vendorOrders,
    required this.isLoadingVendorOrders,
    required this.vendorOrdersError,
    required this.onRefreshVendorOrders,
  });

  final String? signedInRole;
  final String? signedInEmail;
  final MarketplaceAccount? account;
  final VoidCallback onChangeProfilePhoto;
  final bool isUpdatingProfilePhoto;
  final MarketplaceAccount? vendorAccount;
  final List<ProduceListing> ownListings;
  final bool isLoadingListings;
  final Object? listingsError;
  final VoidCallback onRetryListings;
  final VoidCallback onSignIn;
  final VoidCallback onVendorSignIn;
  final VoidCallback onPostProduce;
  final VoidCallback onManageVendorLocation;
  final VoidCallback onSignOut;
  final ValueChanged<ProduceListing> onDeleteListing;
  final ValueChanged<ProduceListing> onRepostListing;
  final ValueChanged<ProduceListing> onEditListing;
  final String vendorVerificationStatus;
  final VendorTrustSummary vendorTrustSummary;
  final VoidCallback onRefreshVendorTrust;
  final VoidCallback onRequestVendorVerification;
  final VoidCallback onBackToMarket;
  final List<ProduceReservation> reservations;
  final Set<String> cancellingReservationIds;
  final ValueChanged<ProduceReservation> onCancelReservation;
  final List<ProduceOrder> orders;
  final Set<String> deletingBuyerOrderIds;
  final ValueChanged<ProduceOrder> onDeleteBuyerOrder;
  final VoidCallback onOpenMessages;
  final Future<void> Function(ProduceOrder, MarketplaceCartItem)
  onMessageOrderParticipant;
  final Future<void> Function(ProduceOrder, MarketplaceCartItem) onReviewVendor;
  final Set<String> reviewedPurchaseKeys;
  final Future<void> Function(ProduceOrder, String) onUpdateVendorOrder;
  final List<ProduceOrder> vendorOrders;
  final bool isLoadingVendorOrders;
  final Object? vendorOrdersError;
  final VoidCallback onRefreshVendorOrders;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            color: _paper,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onBackToMarket,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back to market'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    children: [
                      ProfilePhotoAvatar(
                        radius: 38,
                        photoUrl: account?.profilePhotoUrl,
                        photoBytes: account?.profilePhotoBytes,
                        placeholderIcon: signedInRole == 'Vendor'
                            ? Icons.storefront_outlined
                            : Icons.person_outline,
                      ),
                      if (signedInRole != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Material(
                            color: _forest,
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: isUpdatingProfilePhoto
                                  ? null
                                  : onChangeProfilePhoto,
                              tooltip: isUpdatingProfilePhoto
                                  ? 'Saving profile photo'
                                  : 'Add or change profile photo',
                              icon: isUpdatingProfilePhoto
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (signedInRole != null)
                    TextButton.icon(
                      onPressed: isUpdatingProfilePhoto
                          ? null
                          : onChangeProfilePhoto,
                      icon: const Icon(Icons.upload_outlined),
                      label: Text(
                        isUpdatingProfilePhoto
                            ? 'Saving profile photo...'
                            : account?.profilePhotoUrl == null &&
                                  account?.profilePhotoBytes == null
                            ? 'Add profile photo'
                            : 'Change profile photo',
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    signedInRole == null
                        ? 'Join your local market'
                        : signedInRole == 'Vendor'
                        ? 'Store dashboard'
                        : 'Buyer account',
                    style: TextStyle(
                      color: _deepForest,
                      fontFamily: 'Georgia',
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    signedInRole == null
                        ? 'Sign in to save produce, get neighborhood Notification, and connect with vendors.'
                        : signedInEmail ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, height: 1.5),
                  ),
                  if (signedInRole != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFF4F6F0),
                      elevation: 0,
                      child: ListTile(
                        leading: Icon(
                          account?.emailVerified == true
                              ? Icons.verified_user_outlined
                              : Icons.mark_email_unread_outlined,
                          color: account?.emailVerified == true
                              ? _forest
                              : _muted,
                        ),
                        title: const Text('Email verification'),
                        subtitle: Text(
                          account?.emailVerified == true
                              ? 'Verified by Firebase Authentication'
                              : 'Not verified',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (signedInRole == 'Vendor') ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onPostProduce,
                        icon: const Icon(Icons.add),
                        label: const Text('Post produce'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onManageVendorLocation,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Manage map location'),
                      ),
                    ),
                  ] else if (signedInRole == null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onSignIn,
                        child: const Text('Sign in as a buyer'),
                      ),
                    ),
                    TextButton(
                      onPressed: onVendorSignIn,
                      child: const Text(
                        'I’m a vendor — sign in to post produce',
                      ),
                    ),
                  ],
                  if (signedInRole != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onOpenMessages,
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Messages'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: onSignOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ),
                  ],
                  if (signedInRole != null) ...[
                    const SizedBox(height: 14),
                    Card(
                      color: const Color(0xFFFFF8E8),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Account deletion',
                              style: TextStyle(
                                color: _deepForest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Secure deletion is not available yet. It will '
                              'require a trusted backend to remove your account '
                              'and related data completely.',
                              style: TextStyle(color: _muted, height: 1.4),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Planned: delete your listings and all '
                              'transaction records involving your account, '
                              'including the other participant’s history. '
                              'Hide chat history only for your account.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (signedInRole == 'Vendor' && vendorAccount != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFF4F6F0),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vendorAccount!.companyName ??
                                  vendorAccount!.fullName ??
                                  'Store profile',
                              style: const TextStyle(
                                color: _deepForest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (vendorAccount!.companyDescription
                                case final description?
                                when description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                            if (vendorAccount!.addressLine1 case final address?
                                when address.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Market address: $address'),
                            ],
                            if (vendorAccount!.phone case final phone?
                                when phone.isNotEmpty)
                              Text('Contact: $phone'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _VendorFeedbackPanel(
                      summary: vendorTrustSummary,
                      onRefresh: onRefreshVendorTrust,
                    ),
                    Card(
                      color: const Color(0xFFFFF8E8),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Vendor verification',
                              style: TextStyle(
                                color: _deepForest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              vendorVerificationStatus == 'pending'
                                  ? 'Request saved on this device. This is not official verification.'
                                  : 'Not verified. A local-only request cannot be reviewed by an admin.',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            if (vendorVerificationStatus != 'pending') ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: onRequestVendorVerification,
                                icon: const Icon(Icons.verified_user_outlined),
                                label: const Text('Request verification'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (signedInRole == 'Buyer') ...[
                    const Divider(height: 32),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'My reservations (${reservations.length})',
                        style: const TextStyle(
                          color: _deepForest,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (reservations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No reservations yet.',
                          style: TextStyle(color: _muted),
                        ),
                      )
                    else
                      ...reservations.map(
                        (reservation) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.event_available_outlined,
                            color: _forest,
                          ),
                          title: Text(
                            '${reservation.quantity} ${reservation.listing.unit} · ${reservation.listing.name}',
                          ),
                          subtitle: Text(
                            'Pickup: ${reservation.listing.location} · ₱${reservation.total}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Cancel reservation',
                            onPressed:
                                cancellingReservationIds.contains(
                                  reservation.id,
                                )
                                ? null
                                : () => onCancelReservation(reservation),
                            icon:
                                cancellingReservationIds.contains(
                                  reservation.id,
                                )
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.cancel_outlined,
                                    color: Color(0xFF9D4038),
                                  ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'My orders (${orders.length})',
                        style: const TextStyle(
                          color: _deepForest,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (orders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No purchases yet.',
                          style: TextStyle(color: _muted),
                        ),
                      )
                    else
                      ...orders.map(
                        (order) => Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.shopping_bag_outlined,
                                color: _forest,
                              ),
                              title: Text(
                                '${order.items.length} produce item(s) · ₱${order.total}',
                              ),
                              subtitle: Text(
                                '${order.createdAt.toLocal().toString().split('.').first}\n'
                                '${order.items.map((item) => '${item.listing.name}: ${item.status.isEmpty ? order.status : item.status}').join(', ')}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete order',
                                onPressed:
                                    deletingBuyerOrderIds.contains(order.id)
                                    ? null
                                    : () => onDeleteBuyerOrder(order),
                                icon: deletingBuyerOrderIds.contains(order.id)
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.delete_outline,
                                        color: Color(0xFF9D4038),
                                      ),
                              ),
                            ),
                            if (order.items.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 8,
                                  children: order.items.map((item) {
                                    final vendorId =
                                        item.listing.ownerEmail ??
                                        item.listing.ownerUid ??
                                        item.listing.vendor;
                                    final reviewKey =
                                        '${order.id}:${vendorId.toLowerCase()}';
                                    final isCompleted =
                                        item.status == 'completed' ||
                                        (item.status.isEmpty &&
                                            order.status == 'completed');
                                    return Wrap(
                                      spacing: 4,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              onMessageOrderParticipant(
                                                order,
                                                item,
                                              ),
                                          icon: const Icon(Icons.chat_outlined),
                                          label: Text(
                                            'Message ${item.listing.vendor}',
                                          ),
                                        ),
                                        if (isCompleted &&
                                            !reviewedPurchaseKeys.contains(
                                              reviewKey,
                                            ))
                                          TextButton.icon(
                                            onPressed: () =>
                                                onReviewVendor(order, item),
                                            icon: const Icon(
                                              Icons.star_outline,
                                            ),
                                            label: Text(
                                              'Review ${item.listing.vendor}',
                                            ),
                                          ),
                                        if (isCompleted &&
                                            reviewedPurchaseKeys.contains(
                                              reviewKey,
                                            ))
                                          const Chip(
                                            avatar: Icon(
                                              Icons.check_circle_outline,
                                              size: 16,
                                            ),
                                            label: Text('Reviewed'),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            const Divider(),
                          ],
                        ),
                      ),
                  ],
                  if (signedInRole == 'Vendor') ...[
                    const Divider(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Orders (${vendorOrders.length})',
                            style: const TextStyle(
                              color: _deepForest,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh orders',
                          onPressed: isLoadingVendorOrders
                              ? null
                              : onRefreshVendorOrders,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (isLoadingVendorOrders)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          children: [
                            LinearProgressIndicator(color: _forest),
                            SizedBox(height: 10),
                            Text(
                              'Loading customer orders…',
                              style: TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      )
                    else if (vendorOrdersError != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Could not load orders: $vendorOrdersError',
                            style: const TextStyle(color: Color(0xFF9D4038)),
                          ),
                          TextButton.icon(
                            onPressed: onRefreshVendorOrders,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      )
                    else if (vendorOrders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No customers have ordered your produce yet.',
                          style: TextStyle(color: _muted),
                        ),
                      )
                    else
                      ...vendorOrders.map(
                        (order) => Card(
                          color: const Color(0xFFF4F6F0),
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: _forest,
                                  ),
                                  title: Text(
                                    '${order.items.map((item) => '${item.quantity} ${item.listing.unit} ${item.listing.name}').join(', ')} · ₱${order.total}',
                                  ),
                                  subtitle: Text(
                                    'Buyer: ${order.buyerEmail}\n'
                                    '${order.status} · ${order.createdAt.toLocal().toString().split('.').first}',
                                  ),
                                  isThreeLine: true,
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: order.items.map((item) {
                                    return TextButton.icon(
                                      onPressed: () =>
                                          onMessageOrderParticipant(
                                            order,
                                            item,
                                          ),
                                      icon: const Icon(Icons.chat_outlined),
                                      label: const Text('Message buyer'),
                                    );
                                  }).toList(),
                                ),
                                if (order.status ==
                                    'pending_vendor_confirmation')
                                  OverflowBar(
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => onUpdateVendorOrder(
                                          order,
                                          'declined',
                                        ),
                                        child: const Text('Decline'),
                                      ),
                                      FilledButton.icon(
                                        onPressed: () => onUpdateVendorOrder(
                                          order,
                                          'approved',
                                        ),
                                        icon: const Icon(Icons.check),
                                        label: const Text('Approve'),
                                      ),
                                    ],
                                  ),
                                if (order.status == 'approved')
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => onUpdateVendorOrder(
                                        order,
                                        'completed',
                                      ),
                                      icon: const Icon(Icons.task_alt_outlined),
                                      label: const Text('Mark completed'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 32),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Store dashboard',
                        style: const TextStyle(
                          color: _deepForest,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoadingListings)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          children: [
                            LinearProgressIndicator(color: _forest),
                            SizedBox(height: 10),
                            Text(
                              'Loading your inventory…',
                              style: TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      )
                    else if (listingsError != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Could not load inventory: $listingsError',
                            style: const TextStyle(color: Color(0xFF9D4038)),
                          ),
                          TextButton.icon(
                            onPressed: onRetryListings,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      )
                    else ...[
                      Card(
                        color: const Color(0xFFF4F6F0),
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: _VendorInventoryMetric(
                                  label: 'Listings',
                                  value: '${ownListings.length}',
                                ),
                              ),
                              Expanded(
                                child: _VendorInventoryMetric(
                                  label: 'Units in stock',
                                  value:
                                      '${ownListings.fold<int>(0, (total, listing) => total + (int.tryParse(listing.quantity) ?? 0))}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'My listings (${ownListings.length})',
                          style: const TextStyle(
                            color: _deepForest,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (ownListings.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'You have not posted any produce yet.',
                            style: TextStyle(color: _muted),
                          ),
                        )
                      else
                        ...ownListings.map(
                          (listing) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFE9EFE5),
                              backgroundImage: listing.imageBytes == null
                                  ? null
                                  : MemoryImage(listing.imageBytes!),
                              child: listing.imageBytes == null
                                  ? const Icon(
                                      Icons.eco_outlined,
                                      color: _forest,
                                    )
                                  : null,
                            ),
                            title: Text(
                              listing.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${listing.priceLabel}/${listing.unit} · ${listing.inventoryLabel}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip:
                                      'Edit price and stock for ${listing.name}',
                                  onPressed: () => onEditListing(listing),
                                  color: _forest,
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Repost ${listing.name}',
                                  onPressed: () => onRepostListing(listing),
                                  color: _forest,
                                  icon: const Icon(Icons.repeat),
                                ),
                                IconButton(
                                  tooltip: 'Delete ${listing.name}',
                                  onPressed: () => onDeleteListing(listing),
                                  color: const Color(0xFF9D4038),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
