import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/location_services.dart';
import '../data/marketplace_repository.dart';
import '../models/vendor_location.dart';
import 'vendor_map_view.dart';

const _forest = Color(0xFF245A40);
const _paper = Color(0xFFFFFEFA);
const _muted = Color(0xFF777D75);
const _line = Color(0xFFE5E5DC);

class VendorLocationsPage extends StatefulWidget {
  const VendorLocationsPage({
    super.key,
    required this.repository,
    required this.isVendor,
    this.locationService,
    this.reverseGeocoder,
    this.currentVendor,
    this.onLocationSaved,
    this.initialFocusLocation,
    this.initialVendorName,
  });

  final MarketplaceRepository repository;
  final bool isVendor;
  final DeviceLocationService? locationService;
  final ReverseGeocoder? reverseGeocoder;
  final MarketplaceAccount? currentVendor;
  final ValueChanged<VendorLocation>? onLocationSaved;
  final LatLng? initialFocusLocation;
  final String? initialVendorName;

  @override
  State<VendorLocationsPage> createState() => _VendorLocationsPageState();
}

class _VendorLocationsPageState extends State<VendorLocationsPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  List<VendorLocation> _vendors = [];
  VendorLocation? _selectedVendor;
  LatLng? _selectedLocation;
  LatLng? _buyerLocation;
  String? _selectedAddress;
  String _query = '';
  Object? _loadError;
  Object? _locationError;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    final vendor = widget.currentVendor;
    if (vendor?.latitude != null && vendor?.longitude != null) {
      _selectedLocation = LatLng(vendor!.latitude!, vendor.longitude!);
    }
    if (widget.initialFocusLocation != null) {
      _selectedLocation = widget.initialFocusLocation;
      _buyerLocation = widget.initialFocusLocation;
    }
    _refreshVendors();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DeviceLocationService get _locationService =>
      widget.locationService ?? const GeolocatorDeviceLocationService();

  ReverseGeocoder get _reverseGeocoder =>
      widget.reverseGeocoder ?? widget.repository;

  List<VendorLocation> get _filteredVendors {
    final query = _query.trim().toLowerCase();
    final vendors = _vendors.where((vendor) {
      return query.isEmpty ||
          vendor.name.toLowerCase().contains(query) ||
          vendor.address.toLowerCase().contains(query) ||
          (vendor.businessType?.toLowerCase().contains(query) ?? false);
    }).toList();
    final buyerLocation = _buyerLocation;
    if (!widget.isVendor && buyerLocation != null) {
      final distance = const Distance();
      vendors.sort(
        (first, second) => distance
            .as(
              LengthUnit.Kilometer,
              buyerLocation,
              LatLng(first.latitude, first.longitude),
            )
            .compareTo(
              distance.as(
                LengthUnit.Kilometer,
                buyerLocation,
                LatLng(second.latitude, second.longitude),
              ),
            ),
      );
    }
    return vendors;
  }

  Future<void> _refreshVendors() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final vendors = await widget.repository.loadVendors();
      if (!mounted) return;
      setState(() {
        _vendors = vendors;
        _isLoading = false;
        _selectedVendor = null;
      });
      if (widget.initialVendorName != null) {
        for (final vendor in vendors) {
          if (vendor.name == widget.initialVendorName) {
            setState(() {
              _selectedVendor = vendor;
              _selectedLocation = LatLng(vendor.latitude, vendor.longitude);
              _buyerLocation = LatLng(vendor.latitude, vendor.longitude);
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _mapController.move(
                LatLng(vendor.latitude, vendor.longitude),
                14,
              );
            });
            return;
          }
        }
      }
      if (widget.initialFocusLocation != null) {
        final focusLocation = widget.initialFocusLocation!;
        setState(() {
          _selectedLocation = focusLocation;
          _buyerLocation = focusLocation;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.move(focusLocation, 14);
        });
        return;
      }
      if (vendors.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.fitCamera(
            CameraFit.coordinates(
              coordinates: vendors
                  .map((vendor) => LatLng(vendor.latitude, vendor.longitude))
                  .toList(),
              padding: const EdgeInsets.all(48),
              maxZoom: 12,
            ),
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveLocation() async {
    final location = _selectedLocation;
    if (location == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final vendor = await widget.repository.updateVendorLocation(
        latitude: location.latitude,
        longitude: location.longitude,
        addressLine1: _selectedAddress,
      );
      if (!mounted) return;
      widget.onLocationSaved?.call(vendor);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your vendor map location was saved.')),
      );
      await _refreshVendors();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your location: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_isGettingLocation) return;
    setState(() {
      _isGettingLocation = true;
      _locationError = null;
    });
    try {
      final location = await _locationService.currentLocation();
      if (!mounted) return;
      setState(() {
        _selectedLocation = location;
        _buyerLocation = widget.isVendor ? _buyerLocation : location;
        _selectedVendor = null;
      });
      if (widget.isVendor) {
        try {
          final address = await _reverseGeocoder.addressFor(location);
          if (mounted) setState(() => _selectedAddress = address);
        } catch (error) {
          if (mounted) setState(() => _locationError = error);
        }
      }
      _mapController.move(location, 14);
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationError = error);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _chooseBuyerLocation() async {
    final selection = await showDialog<MapLocationSelection>(
      context: context,
      builder: (context) =>
          MapLocationPickerDialog(locationService: _locationService),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _buyerLocation = selection.location;
      _selectedVendor = null;
    });
    _mapController.move(selection.location, 12);
  }

  Future<void> _openLocationSettings() async {
    final error = _locationError;
    final service = _locationService;
    try {
      final bool opened;
      if (error is DeviceLocationException &&
          error.issue == DeviceLocationIssue.servicesDisabled) {
        opened = await service.openLocationSettings();
      } else {
        opened = await service.openAppSettings();
      }
      if (!opened && mounted) {
        setState(
          () => _locationError = const DeviceLocationException(
            DeviceLocationIssue.unavailable,
            'Device settings could not be opened. Open location settings manually, then retry.',
          ),
        );
      }
    } catch (settingsError) {
      if (!mounted) return;
      setState(() => _locationError = settingsError);
    }
  }

  void _selectVendor(VendorLocation vendor) {
    setState(() => _selectedVendor = vendor);
    _mapController.move(LatLng(vendor.latitude, vendor.longitude), 14);
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _filteredVendors;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RESCUE — Vendor Locations',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh vendor locations',
            onPressed: _isLoading ? null : _refreshVendors,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshVendors,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (widget.isVendor)
              _LocationSelectionNotice(
                hasLocation: widget.currentVendor?.latitude != null,
                isSaving: _isSaving,
                canSave: _selectedLocation != null,
                isGettingLocation: _isGettingLocation,
                selectedAddress: _selectedAddress,
                locationError: _locationError,
                onUseCurrentLocation: _useCurrentLocation,
                onOpenSettings: _openLocationSettings,
                onSave: _saveLocation,
              )
            else
              _MapDescription(
                location: _buyerLocation,
                isGettingLocation: _isGettingLocation,
                locationError: _locationError,
                onUseCurrentLocation: _useCurrentLocation,
                onChooseMap: _chooseBuyerLocation,
                onOpenSettings: _openLocationSettings,
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: MediaQuery.sizeOf(context).height < 700 ? 310 : 400,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: VendorMapView(
                  mapController: _mapController,
                  vendors: vendors,
                  selectedLocation: _selectedLocation,
                  onLocationSelected: widget.isVendor
                      ? (location) {
                          setState(() {
                            _selectedLocation = location;
                            _selectedVendor = null;
                            _selectedAddress = null;
                          });
                        }
                      : null,
                  onVendorSelected: _selectVendor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'The starting map view is an area reference, not a vendor location.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator(color: _forest)),
            ],
            if (_loadError != null)
              _MapMessage(
                icon: Icons.cloud_off_outlined,
                message: 'Vendor locations could not be loaded: $_loadError',
                action: TextButton.icon(
                  onPressed: _refreshVendors,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              )
            else if (!_isLoading && _vendors.isEmpty)
              const _MapMessage(
                icon: Icons.location_searching,
                message: 'No vendors have registered their locations yet. Check back after a vendor shares a map location.',
              )
            else if (!_isLoading) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _query = value;
                    _selectedVendor = null;
                  });
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search vendor, business type, or address',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _selectedVendor = null;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: _paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _line),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (vendors.isEmpty)
                const _MapMessage(
                  icon: Icons.search_off,
                  message: 'No vendor locations match your search.',
                )
              else ...[
                Text(
                  '${vendors.length} vendor location${vendors.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: _forest,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ...vendors.map(
                  (vendor) => Card(
                    color: _paper,
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: _line),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE9EFE5),
                        child: Icon(Icons.storefront_outlined, color: _forest),
                      ),
                      title: Text(
                        vendor.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if (vendor.businessType?.isNotEmpty ?? false)
                            vendor.businessType!,
                          if (vendor.address.isNotEmpty) vendor.address,
                        ].join(' · '),
                      ),
                      trailing: _buyerLocation == null
                          ? const Icon(Icons.near_me_outlined)
                          : Text(
                              '${const Distance().as(LengthUnit.Kilometer, _buyerLocation!, LatLng(vendor.latitude, vendor.longitude)).toStringAsFixed(1)} km',
                              style: const TextStyle(
                                color: _forest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      selected: _selectedVendor?.id == vendor.id,
                      onTap: () => _selectVendor(vendor),
                    ),
                  ),
                ),
              ],
            ],
            if (_selectedVendor != null)
              Card(
                color: const Color(0xFFE9EFE5),
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: _forest),
                  title: Text(_selectedVendor!.name),
                  subtitle: Text(
                    [
                      if (_selectedVendor!.businessType?.isNotEmpty ?? false)
                        _selectedVendor!.businessType!,
                      if (_selectedVendor!.address.isNotEmpty)
                        _selectedVendor!.address,
                    ].join(' · '),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MapLocationSelection {
  const MapLocationSelection({required this.location, this.address});

  final LatLng location;
  final String? address;
}

class MapLocationPickerDialog extends StatefulWidget {
  const MapLocationPickerDialog({
    super.key,
    this.initialLocation,
    this.locationService,
    this.reverseGeocoder,
    this.resolveAddress = false,
    this.title = 'Choose a map location',
  });

  final LatLng? initialLocation;
  final DeviceLocationService? locationService;
  final ReverseGeocoder? reverseGeocoder;
  final bool resolveAddress;
  final String title;

  @override
  State<MapLocationPickerDialog> createState() =>
      _MapLocationPickerDialogState();
}

class _MapLocationPickerDialogState extends State<MapLocationPickerDialog> {
  final MapController _mapController = MapController();
  final TextEditingController _addressController = TextEditingController();
  LatLng? _selectedLocation;
  String? _selectedAddress;
  Object? _locationError;
  Object? _addressError;
  bool _isGettingLocation = false;
  bool _isResolvingAddress = false;
  bool _hasEditedAddress = false;
  int _addressLookupRequest = 0;

  DeviceLocationService get _locationService =>
      widget.locationService ?? const GeolocatorDeviceLocationService();

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _locationError = null;
      _addressError = null;
    });
    try {
      final location = await _locationService.currentLocation();
      if (!mounted) return;
      final shouldResolveAddress =
          widget.resolveAddress && widget.reverseGeocoder != null;
      setState(() {
        _selectedLocation = location;
        _selectedAddress = null;
        _addressController.clear();
        _hasEditedAddress = false;
        _isResolvingAddress = shouldResolveAddress;
      });
      _mapController.move(location, 14);
      if (shouldResolveAddress) {
        unawaited(_resolveAddress(location));
      }
    } catch (error) {
      if (mounted) setState(() => _locationError = error);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _resolveAddress(LatLng location) async {
    final request = ++_addressLookupRequest;
    try {
      final address = await widget.reverseGeocoder!.addressFor(location);
      if (!mounted || request != _addressLookupRequest) return;
      setState(() {
        if (!_hasEditedAddress) {
          _selectedAddress = address;
          _addressController.text = address ?? '';
        }
        _addressError = null;
      });
    } catch (error) {
      if (!mounted || request != _addressLookupRequest) return;
      setState(() => _addressError = error);
    } finally {
      if (mounted && request == _addressLookupRequest) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  Future<void> _openLocationSettings() async {
    final error = _locationError;
    try {
      final bool opened;
      if (error is DeviceLocationException &&
          error.issue == DeviceLocationIssue.servicesDisabled) {
        opened = await _locationService.openLocationSettings();
      } else {
        opened = await _locationService.openAppSettings();
      }
      if (!opened && mounted) {
        setState(
          () => _locationError = const DeviceLocationException(
            DeviceLocationIssue.unavailable,
            'Device settings could not be opened. Open location settings manually, then retry.',
          ),
        );
      }
    } catch (settingsError) {
      if (mounted) setState(() => _locationError = settingsError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.32)
        .clamp(180.0, 340.0)
        .toDouble();
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width * 0.6)
            .clamp(0.0, 500.0)
            .toDouble(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use your current location or tap the map to choose a point. Location access is requested only when you choose the GPS button.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isGettingLocation ? null : _useCurrentLocation,
                icon: _isGettingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _isGettingLocation
                      ? 'Finding location…'
                      : 'Use my current location',
                ),
              ),
            ),
            if (_locationError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Location unavailable: $_locationError',
                style: const TextStyle(color: Color(0xFF9D4038)),
              ),
              if (_locationError is DeviceLocationException &&
                  (_locationError as DeviceLocationException).canOpenSettings)
                TextButton.icon(
                  onPressed: _openLocationSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open location settings'),
                ),
            ],
            if (_isResolvingAddress) ...[
              const SizedBox(height: 8),
              const Text(
                'Looking up the street address…',
                style: TextStyle(color: _muted),
              ),
            ],
            if (_addressError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Address lookup failed. Check your internet connection or enter the market address manually; the selected GPS location is still available.',
                style: const TextStyle(color: Color(0xFF9D4038)),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: mapHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: VendorMapView(
                  mapController: _mapController,
                  vendors: const [],
                  showVendorMarkers: false,
                  selectedLocation: _selectedLocation,
                  onLocationSelected: (location) => setState(() {
                    _addressLookupRequest++;
                    _selectedLocation = location;
                    _selectedAddress = null;
                    _addressController.clear();
                    _hasEditedAddress = false;
                    _locationError = null;
                    _addressError = null;
                    _isResolvingAddress = false;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedLocation == null
                  ? 'No location selected'
                  : 'Location selected',
              style: const TextStyle(color: _forest),
            ),
            if (widget.resolveAddress) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                minLines: 1,
                maxLines: 2,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Business address',
                  hintText: 'Enter your barangay, purok, or street',
                  helperText: 'Map suggestions may be approximate. Verify or edit the address before continuing.',
                  alignLabelWithHint: true,
                ),
                onChanged: (value) {
                  _hasEditedAddress = true;
                  _selectedAddress = value.trim().isEmpty ? null : value.trim();
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selectedLocation == null || _isResolvingAddress
              ? null
              : () => Navigator.of(context).pop(
                  MapLocationSelection(
                    location: _selectedLocation!,
                    address: _selectedAddress,
                  ),
                ),
          child: const Text('Use this location'),
        ),
      ],
    );
  }
}

class _LocationSelectionNotice extends StatelessWidget {
  const _LocationSelectionNotice({
    required this.hasLocation,
    required this.isSaving,
    required this.canSave,
    required this.isGettingLocation,
    required this.selectedAddress,
    required this.locationError,
    required this.onUseCurrentLocation,
    required this.onOpenSettings,
    required this.onSave,
  });

  final bool hasLocation;
  final bool isSaving;
  final bool canSave;
  final bool isGettingLocation;
  final String? selectedAddress;
  final Object? locationError;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onOpenSettings;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFE9EFE5),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasLocation
                  ? 'Update your public map pin'
                  : 'Add your business to the map',
              style: const TextStyle(
                color: _forest,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use GPS or tap the map to select your business location, then confirm and save. Your business address is shown to map visitors.',
              style: TextStyle(color: _muted),
            ),
            if (selectedAddress != null) ...[
              const SizedBox(height: 6),
              Text('Address found: $selectedAddress'),
            ],
            if (locationError != null) ...[
              const SizedBox(height: 6),
              Text(
                'Location detail: $locationError',
                style: const TextStyle(color: Color(0xFF9D4038)),
              ),
              if (locationError is DeviceLocationException &&
                  (locationError as DeviceLocationException).canOpenSettings)
                TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open location settings'),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: isGettingLocation ? null : onUseCurrentLocation,
                  icon: isGettingLocation
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    isGettingLocation ? 'Finding location…' : 'Use GPS',
                  ),
                ),
                FilledButton.icon(
                  onPressed: canSave && !isSaving ? onSave : null,
                  icon: isSaving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(isSaving ? 'Saving…' : 'Save my location'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapDescription extends StatelessWidget {
  const _MapDescription({
    required this.location,
    required this.isGettingLocation,
    required this.locationError,
    required this.onUseCurrentLocation,
    required this.onChooseMap,
    required this.onOpenSettings,
  });

  final LatLng? location;
  final bool isGettingLocation;
  final Object? locationError;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onChooseMap;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFE9EFE5),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sort vendors by distance',
              style: TextStyle(color: _forest, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              location == null
                  ? 'Share your location or choose a point on the map. You can also browse without distance sorting.'
                  : 'Vendors are sorted by distance from your selected point.',
              style: const TextStyle(color: _muted),
            ),
            if (locationError != null) ...[
              const SizedBox(height: 6),
              Text(
                '$locationError',
                style: const TextStyle(color: Color(0xFF9D4038)),
              ),
              if (locationError is DeviceLocationException &&
                  (locationError as DeviceLocationException).canOpenSettings)
                TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open location settings'),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: isGettingLocation ? null : onUseCurrentLocation,
                  icon: isGettingLocation
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    isGettingLocation ? 'Finding…' : 'Use my location',
                  ),
                ),
                TextButton.icon(
                  onPressed: onChooseMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Choose on map'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _paper,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: _forest),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: _muted)),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
