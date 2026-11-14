import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/location_services.dart';
import '../models/vendor_location.dart';

const _defaultMapLatitudeValue = String.fromEnvironment(
  'MAP_DEFAULT_LATITUDE',
  defaultValue: '14.5995',
);
const _defaultMapLongitudeValue = String.fromEnvironment(
  'MAP_DEFAULT_LONGITUDE',
  defaultValue: '120.9842',
);
final _defaultMapLatitude =
    double.tryParse(_defaultMapLatitudeValue) ?? 14.5995;
final _defaultMapLongitude =
    double.tryParse(_defaultMapLongitudeValue) ?? 120.9842;

LatLng get rescueDefaultMapCenter {
  if (!_defaultMapLatitude.isFinite ||
      _defaultMapLatitude < -90 ||
      _defaultMapLatitude > 90 ||
      !_defaultMapLongitude.isFinite ||
      _defaultMapLongitude < -180 ||
      _defaultMapLongitude > 180) {
    return const LatLng(14.5995, 120.9842);
  }
  return LatLng(_defaultMapLatitude, _defaultMapLongitude);
}

class VendorMapView extends StatelessWidget {
  const VendorMapView({
    super.key,
    required this.mapController,
    required this.vendors,
    this.selectedLocation,
    this.onLocationSelected,
    this.onVendorSelected,
    this.showVendorMarkers = true,
  });

  final MapController mapController;
  final List<VendorLocation> vendors;
  final LatLng? selectedLocation;
  final ValueChanged<LatLng>? onLocationSelected;
  final ValueChanged<VendorLocation>? onVendorSelected;
  final bool showVendorMarkers;

  @override
  Widget build(BuildContext context) {
    final mapCenter = selectedLocation != null
        ? selectedLocation!
        : vendors.isNotEmpty
        ? LatLng(vendors.first.latitude, vendors.first.longitude)
        : rescueDefaultMapCenter;

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: mapCenter,
        initialZoom: selectedLocation != null
            ? 14
            : vendors.isNotEmpty
            ? 11
            : 6,
        minZoom: 3,
        maxZoom: 18,
        onTap: onLocationSelected == null
            ? null
            : (tapPosition, point) => onLocationSelected!(point),
      ),
      children: [
        TileLayer(
          urlTemplate: osmTileUrl,
          userAgentPackageName: osmTileUserAgentPackage,
          maxZoom: 19,
        ),
        if (showVendorMarkers)
          MarkerLayer(
            markers: vendors.map((vendor) {
              return Marker(
                point: LatLng(vendor.latitude, vendor.longitude),
                width: 44,
                height: 48,
                child: Semantics(
                  button: onVendorSelected != null,
                  label: 'Vendor ${vendor.name}',
                  child: GestureDetector(
                    onTap: onVendorSelected == null
                        ? null
                        : () => onVendorSelected!(vendor),
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFF245A40),
                      size: 42,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        if (selectedLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: selectedLocation!,
                width: 48,
                height: 54,
                child: const Icon(
                  Icons.place,
                  color: Color(0xFFC65339),
                  size: 48,
                ),
              ),
            ],
          ),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomRight,
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: _openOpenStreetMapCopyright,
            ),
          ],
        ),
      ],
    );
  }

  void _openOpenStreetMapCopyright() {
    unawaited(launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')));
  }
}
