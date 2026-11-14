import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const maxFirestoreImageBytes = 5 * 1000 * 1000;
const maxFirestoreImageChunkBytes = 625 * 1000;
const maxFirestoreImageChunkCount = 8;
const maxFirestoreProfilePhotoBytes = 716800;

Uint8List compressListingImageForFirestore(Uint8List bytes) {
  return _compressImageForFirestore(
    bytes,
    maxBytes: maxFirestoreImageBytes,
    failureMessage: 'The selected photo could not be reduced for Firestore.',
  );
}

Uint8List compressProfilePhotoForFirestore(Uint8List bytes) {
  return _compressImageForFirestore(
    bytes,
    maxBytes: maxFirestoreProfilePhotoBytes,
    failureMessage:
        'The profile photo could not be reduced to fit in Firestore.',
  );
}

Uint8List _compressImageForFirestore(
  Uint8List bytes, {
  required int maxBytes,
  required String failureMessage,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('This image format is not supported.');
  }

  var image = decoded;
  final largestDimension = math.max(image.width, image.height);
  if (largestDimension > 1280) {
    final scale = 1280 / largestDimension;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }

  for (var quality = 85; quality >= 45; quality -= 10) {
    final compressed = Uint8List.fromList(
      img.encodeJpg(image, quality: quality),
    );
    if (compressed.length <= maxBytes) return compressed;
  }

  while (math.max(image.width, image.height) > 320) {
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * 0.8).round()).toInt(),
      height: math.max(1, (image.height * 0.8).round()).toInt(),
    );
    for (var quality = 75; quality >= 45; quality -= 10) {
      final compressed = Uint8List.fromList(
        img.encodeJpg(image, quality: quality),
      );
      if (compressed.length <= maxBytes) return compressed;
    }
  }

  throw StateError(failureMessage);
}

List<Uint8List> splitFirestoreImageBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError('Choose a valid image.');
  }
  if (bytes.length > maxFirestoreImageBytes) {
    throw ArgumentError('The product photo must be 5 MB or smaller.');
  }
  final chunkCount =
      (bytes.length + maxFirestoreImageChunkBytes - 1) ~/
      maxFirestoreImageChunkBytes;
  if (chunkCount > maxFirestoreImageChunkCount) {
    throw ArgumentError('The product photo needs too many Firestore chunks.');
  }
  return List<Uint8List>.generate(
    chunkCount,
    (index) {
      final start = index * maxFirestoreImageChunkBytes;
      final end = math
          .min(start + maxFirestoreImageChunkBytes, bytes.length)
          .toInt();
      return Uint8List.sublistView(bytes, start, end);
    },
    growable: false,
  );
}
