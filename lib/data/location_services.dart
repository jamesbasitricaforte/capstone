import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const osmTileUrl = String.fromEnvironment(
  'OSM_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);
const osmTileUserAgentPackage = String.fromEnvironment(
  'OSM_USER_AGENT_PACKAGE',
  defaultValue: 'com.example.project_rescue',
);

enum DeviceLocationIssue {
  servicesDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.issue, this.message);

  final DeviceLocationIssue issue;
  final String message;

  bool get canOpenSettings =>
      issue == DeviceLocationIssue.servicesDisabled ||
      issue == DeviceLocationIssue.permissionPermanentlyDenied;

  @override
  String toString() => message;
}

abstract interface class DeviceLocationService {
  Future<LatLng> currentLocation();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorDeviceLocationService implements DeviceLocationService {
  const GeolocatorDeviceLocationService();

  @override
  Future<LatLng> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        DeviceLocationIssue.servicesDisabled,
        'Location services are turned off. Enable them and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        DeviceLocationIssue.permissionPermanentlyDenied,
        'Location permission is blocked. Allow location access in app settings, then retry.',
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const DeviceLocationException(
        DeviceLocationIssue.permissionDenied,
        'Location permission was denied. Allow it to find nearby produce, or choose a map location instead.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 30),
        ),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude < -90 ||
          position.latitude > 90 ||
          position.longitude < -180 ||
          position.longitude > 180) {
        throw const DeviceLocationException(
          DeviceLocationIssue.unavailable,
          'The device returned invalid GPS coordinates. Try again or choose a map location.',
        );
      }
      return LatLng(position.latitude, position.longitude);
    } on LocationServiceDisabledException {
      throw const DeviceLocationException(
        DeviceLocationIssue.servicesDisabled,
        'Location services are turned off. Enable them and try again.',
      );
    } on TimeoutException {
      throw const DeviceLocationException(
        DeviceLocationIssue.unavailable,
        'The device could not determine your location in time. Try again or choose a map location.',
      );
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

abstract interface class ReverseGeocoder {
  Future<String?> addressFor(LatLng location);
}
