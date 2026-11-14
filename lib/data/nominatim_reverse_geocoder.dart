import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'location_services.dart';

class NominatimReverseGeocoder implements ReverseGeocoder {
  NominatimReverseGeocoder([this._client]);

  static const _requestInterval = Duration(seconds: 1);
  static const _requestTimeout = Duration(seconds: 10);
  static const _addressFields = [
    'road',
    'pedestrian',
    'footway',
    'residential',
    'neighbourhood',
    'suburb',
    'city_district',
    'city',
    'town',
    'village',
    'municipality',
    'county',
    'state',
  ];

  final http.Client? _client;
  DateTime _nextRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<String?> addressFor(LatLng location) async {
    await _waitForRateLimit();

    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '${location.latitude}',
      'lon': '${location.longitude}',
      'addressdetails': '1',
      'zoom': '18',
    });
    final headers = <String, String>{'Accept': 'application/json'};
    if (!kIsWeb) {
      headers['User-Agent'] = 'ProjectRescue/1.0 (com.example.project_rescue)';
    }

    final response =
        await (_client?.get(uri, headers: headers) ??
                http.get(uri, headers: headers))
            .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Address lookup failed with HTTP ${response.statusCode}.',
        uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Address lookup returned invalid data.');
    }
    final address = decoded['address'];
    if (address is! Map<String, dynamic>) return null;

    final parts = <String>[];
    for (final field in _addressFields) {
      final value = address[field];
      if (value is! String || value.trim().isEmpty) continue;
      final part = value.trim();
      if (!parts.any(
        (existing) => existing.toLowerCase() == part.toLowerCase(),
      )) {
        parts.add(part);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<void> _waitForRateLimit() async {
    final now = DateTime.now();
    if (_nextRequestAt.isAfter(now)) {
      await Future<void>.delayed(_nextRequestAt.difference(now));
    }
    _nextRequestAt = DateTime.now().add(_requestInterval);
  }
}
