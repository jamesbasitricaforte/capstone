import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:project_rescue/data/firestore_image_compressor.dart';
import 'package:project_rescue/models/produce_listing.dart';

void main() {
  test('hosted image URLs must use HTTPS and include a host', () {
    expect(isHostedMediaUrl('https://images.example.test/photo.jpg'), isTrue);
    expect(isHostedMediaUrl(''), isFalse);
    expect(isHostedMediaUrl('http://images.example.test/photo.jpg'), isFalse);
    expect(isHostedMediaUrl('file:///photo.jpg'), isFalse);
    expect(isHostedMediaUrl('https://'), isFalse);
  });

  test('Firestore image bytes are restored when reading a listing', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final listing = ProduceListing.fromJson({
      'id': 'listing-1',
      'name': 'Tomatoes',
      'category': 'Vegetables',
      'price': 40,
      'unit': 'kg',
      'quantity': '2',
      'condition': 'Fresh',
      'vendor': 'Local farm',
      'vendor_initials': 'LF',
      'location': 'Town',
      'image_url': '',
      'image_bytes': bytes,
    });

    expect(listing.imageBytes, orderedEquals(bytes));
  });

  test('selected images are compressed under the Firestore size limit', () {
    final source = img.Image(width: 1400, height: 1000);
    var seed = 7;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        seed = (seed * 1664525 + 1013904223) & 0x7fffffff;
        source.setPixelRgb(
          x,
          y,
          seed & 0xff,
          (seed >> 8) & 0xff,
          (seed >> 16) & 0xff,
        );
      }
    }

    final input = Uint8List.fromList(img.encodePng(source));
    final compressed = compressListingImageForFirestore(input);

    expect(compressed.length, lessThanOrEqualTo(maxFirestoreImageBytes));
    expect(img.decodeImage(compressed), isNotNull);
  });

  test('profile photos are compressed to fit in a Firestore user document', () {
    final source = img.Image(width: 1000, height: 1000);
    var seed = 7;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        seed = (seed * 1664525 + 1013904223) & 0x7fffffff;
        source.setPixelRgb(
          x,
          y,
          seed & 0xff,
          (seed >> 8) & 0xff,
          (seed >> 16) & 0xff,
        );
      }
    }

    final input = Uint8List.fromList(img.encodePng(source));
    final compressed = compressProfilePhotoForFirestore(input);

    expect(compressed.length, lessThanOrEqualTo(maxFirestoreProfilePhotoBytes));
    expect(img.decodeImage(compressed), isNotNull);
  });

  test('Firestore image chunks stay within size and preserve their order', () {
    final input = Uint8List(maxFirestoreImageBytes);
    input[0] = 17;
    input[maxFirestoreImageChunkBytes] = 29;
    input[maxFirestoreImageBytes - 1] = 43;

    final chunks = splitFirestoreImageBytes(input);

    expect(chunks, hasLength(maxFirestoreImageChunkCount));
    expect(
      chunks.map((chunk) => chunk.length),
      everyElement(maxFirestoreImageChunkBytes),
    );
    expect(chunks.first.first, 17);
    expect(chunks[1].first, 29);
    expect(chunks.last.last, 43);
    expect(
      () => splitFirestoreImageBytes(Uint8List(maxFirestoreImageBytes + 1)),
      throwsArgumentError,
    );
  });
}
