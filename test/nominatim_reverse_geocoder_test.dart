import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:project_rescue/data/nominatim_reverse_geocoder.dart';

void main() {
  test(
    'returns a readable address without house number or coordinates',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'nominatim.openstreetmap.org');
        expect(request.url.path, '/reverse');
        expect(request.url.queryParameters['lat'], '14.5');
        expect(request.url.queryParameters['lon'], '120.9');
        expect(request.headers['user-agent'], contains('ProjectRescue'));
        return http.Response('''
        {
          "address": {
            "house_number": "123",
            "road": "Market Road",
            "suburb": "Barangay San Isidro",
            "city": "Manila",
            "postcode": "1000"
          }
        }
        ''', 200);
      });

      final geocoder = NominatimReverseGeocoder(client);
      final address = await geocoder.addressFor(const LatLng(14.5, 120.9));

      expect(address, 'Market Road, Barangay San Isidro, Manila');
    },
  );

  test('reports failed geocoding responses explicitly', () async {
    final client = MockClient(
      (_) async => http.Response('Service unavailable', 503),
    );
    final geocoder = NominatimReverseGeocoder(client);

    await expectLater(
      geocoder.addressFor(const LatLng(14.5, 120.9)),
      throwsA(
        isA<http.ClientException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 503'),
        ),
      ),
    );
  });
}
