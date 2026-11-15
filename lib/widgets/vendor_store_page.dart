import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/produce_listing.dart';
import '../models/vendor_location.dart';
import '../models/vendor_store_profile.dart';
import 'profile_photo_avatar.dart';
import 'vendor_map_view.dart';

class VendorStorePage extends StatefulWidget {
  const VendorStorePage({
    super.key,
    required this.profile,
    required this.listings,
    required this.onViewListing,
    this.onMessageVendor,
  });

  final VendorStoreProfile profile;
  final List<ProduceListing> listings;
  final ValueChanged<ProduceListing> onViewListing;
  final VoidCallback? onMessageVendor;

  @override
  State<VendorStorePage> createState() => _VendorStorePageState();
}

class _VendorStorePageState extends State<VendorStorePage> {
  final MapController _mapController = MapController();

  VendorLocation? get _location {
    final latitude = widget.profile.latitude;
    final longitude = widget.profile.longitude;
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return VendorLocation(
      id: widget.profile.id,
      name: widget.profile.storeName,
      address: widget.profile.address ?? '',
      businessType: widget.profile.businessType,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final location = _location;
    return Scaffold(
      appBar: AppBar(title: Text(profile.storeName)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProfilePhotoAvatar(
                        radius: 27,
                        photoUrl: profile.profilePhotoUrl,
                        photoBytes: profile.profilePhotoBytes,
                        placeholderIcon: Icons.storefront_outlined,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.storeName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (_hasText(profile.businessType))
                              Text(
                                profile.businessType!,
                                style: const TextStyle(
                                  color: Color(0xFF777D75),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.onMessageVendor != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onMessageVendor,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Message vendor'),
                      ),
                    ),
                  ],
                  if (_hasText(profile.description)) ...[
                    const SizedBox(height: 18),
                    Text(
                      profile.description!,
                      style: const TextStyle(height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _detail('Store owner', profile.ownerName),
                  _detail('Contact number', profile.phone),
                  _detail('Address', profile.address),
                  _detail('ZIP code', profile.zipCode),
                  if (location != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 220,
                        child: VendorMapView(
                          mapController: _mapController,
                          vendors: [location],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Location: ${location.latitude.toStringAsFixed(5)}, '
                      '${location.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: Color(0xFF777D75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Products from this store',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (widget.listings.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Text(
                  'This store has no available products right now.',
                  style: TextStyle(color: Color(0xFF777D75)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverList.separated(
                itemCount: widget.listings.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final listing = widget.listings[index];
                  return _StoreListingTile(
                    listing: listing,
                    onTap: () => widget.onViewListing(listing),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(String label, String? value) {
    if (!_hasText(value)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF777D75)),
            ),
          ),
          Expanded(
            child: Text(
              value!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasText(String? value) => value?.trim().isNotEmpty == true;
}

class _StoreListingTile extends StatelessWidget {
  const _StoreListingTile({required this.listing, required this.onTap});

  final ProduceListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quantity = int.tryParse(listing.quantity) ?? 0;
    final postedAtLabel = listing.postedAtLabel;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 112,
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: double.infinity,
                child: _listingImage(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        listing.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${listing.priceLabel}/${listing.unit}',
                        style: const TextStyle(
                          color: Color(0xFF245A40),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        quantity > 0
                            ? '${listing.quantity} ${listing.unit} available'
                            : 'Currently unavailable',
                        style: const TextStyle(
                          color: Color(0xFF777D75),
                          fontSize: 12,
                        ),
                      ),
                      if (postedAtLabel != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Posted $postedAtLabel',
                          style: const TextStyle(
                            color: Color(0xFF777D75),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_right, color: Color(0xFF777D75)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listingImage() {
    final bytes = listing.imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
      );
    }
    if (listing.imageUrl.isNotEmpty) {
      return Image.network(
        listing.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() => const ColoredBox(
    color: Color(0xFFE9EFE5),
    child: Center(
      child: Icon(Icons.eco_outlined, color: Color(0xFF84966F), size: 32),
    ),
  );
}
