import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_image_compressor.dart';
import '../models/produce_listing.dart';

class FirebaseListingService {
  FirebaseListingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _listings =>
      _db.collection('listings');

  Future<void> addListing(ProduceListing listing) async {
    final user = await _requireVendor();
    if (listing.price <= 0 || listing.name.trim().isEmpty) {
      throw ArgumentError('A listing needs a name and a positive price.');
    }
    _rejectLocalMedia(listing);
    final imageBytes = listing.imageBytes;
    final imageChunks = imageBytes == null
        ? const <Uint8List>[]
        : splitFirestoreImageBytes(imageBytes);
    final imageUrls = _imageUrlsFor(listing);
    _validateMediaUrls(imageUrls, listing.videoUrls);

    final availability = _available(listing.quantity);
    final reference = _listings.doc(listing.id);
    final batch = _db.batch()
      ..set(reference, {
        'id': listing.id,
        'owner_uid': user.uid,
        'vendor_uid': user.uid,
        'vendor': listing.vendor,
        'vendor_initials': listing.vendorInitials,
        'name': listing.name,
        'category': listing.category,
        'description': listing.description,
        'price': listing.price,
        'unit': listing.unit,
        'quantity': listing.quantity,
        'availability': availability,
        'status': availability ? 'active' : 'sold_out',
        'condition': listing.condition,
        'location': listing.location,
        'image_url': imageUrls.isEmpty ? '' : imageUrls.first,
        'image_urls': imageUrls,
        'image_chunk_count': imageChunks.length,
        'image_size_bytes': imageBytes?.length ?? 0,
        'video_urls': listing.videoUrls,
        'latitude': listing.latitude,
        'longitude': listing.longitude,
        'posted_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'just_posted': true,
      });
    for (var index = 0; index < imageChunks.length; index++) {
      batch.set(
        reference.collection('image_chunks').doc('$index'),
        {'index': index, 'bytes': Blob(imageChunks[index])},
      );
    }
    await batch.commit();
  }

  Future<List<ProduceListing>> loadListings() async {
    final snapshot = await _listings
        .orderBy('posted_at', descending: true)
        .get();
    return Future.wait(snapshot.docs.map(listingFromDocument));
  }

  Future<List<ProduceListing>> loadPublicListings() async => loadListings();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchListings() =>
      _listings.orderBy('posted_at', descending: true).snapshots();

  Future<void> updateListing(ProduceListing listing) async {
    final user = await _requireVendor();
    if (listing.name.trim().isEmpty || listing.price <= 0) {
      throw ArgumentError('A listing needs a name and a positive price.');
    }
    _rejectLocalMedia(listing);
    final imageUrls = _imageUrlsFor(listing);
    _validateMediaUrls(imageUrls, listing.videoUrls);
    final reference = _listings.doc(listing.id);
    final snapshot = await reference.get();
    _requireOwner(snapshot, user);
    final availability = _available(listing.quantity);
    final updates = <String, Object?>{
      'name': listing.name,
      'price': listing.price,
      'quantity': listing.quantity,
      'availability': availability,
      'status': availability ? 'active' : 'sold_out',
      'category': listing.category,
      'description': listing.description,
      'image_url': imageUrls.isEmpty ? '' : imageUrls.first,
      'image_urls': imageUrls,
      'just_posted': listing.justPosted,
      'updated_at': FieldValue.serverTimestamp(),
    };
    final batch = _db.batch();
    if (imageUrls.isNotEmpty) {
      final chunks = await reference.collection('image_chunks').get();
      for (final chunk in chunks.docs) {
        batch.delete(chunk.reference);
      }
      updates
        ..['image_bytes'] = FieldValue.delete()
        ..['image_chunk_count'] = 0
        ..['image_size_bytes'] = 0;
    }
    batch.update(reference, updates);
    await batch.commit();
  }

  Future<bool> repostListing({required String listingId}) async {
    final user = await _requireVendor();
    final reference = _listings.doc(listingId);
    final snapshot = await reference.get();
    if (!snapshot.exists) return false;
    _requireOwner(snapshot, user);
    await reference.update({
      'just_posted': true,
      'posted_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return true;
  }

  Future<bool> deleteListing(String listingId) async {
    final user = await _requireVendor();
    final reference = _listings.doc(listingId);
    final snapshot = await reference.get();
    if (!snapshot.exists) return false;
    _requireOwner(snapshot, user);
    final chunks = await reference.collection('image_chunks').get();
    final batch = _db.batch();
    for (final chunk in chunks.docs) {
      batch.delete(chunk.reference);
    }
    batch.delete(reference);
    await batch.commit();
    return true;
  }

  Future<ProduceListing> listingFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
    if (data == null) {
      throw StateError('The listing document has no data.');
    }
    data['id'] = document.id;
    data.remove('owner_email');
    final chunkCount = data['image_chunk_count'];
    if (chunkCount != null &&
        (chunkCount is! int ||
            chunkCount < 0 ||
            chunkCount > maxFirestoreImageChunkCount)) {
      throw FormatException(
        'Listing ${document.id} has invalid image chunk metadata.',
      );
    }
    if (chunkCount is int && chunkCount > 0) {
      final chunks = await document.reference
          .collection('image_chunks')
          .orderBy('index')
          .get();
      if (chunks.docs.length != chunkCount) {
        throw StateError('Listing ${document.id} has an incomplete image.');
      }
      final builder = BytesBuilder(copy: false);
      var totalBytes = 0;
      for (var index = 0; index < chunks.docs.length; index++) {
        final chunkDocument = chunks.docs[index];
        final chunk = chunkDocument.data();
        final bytes = chunk['bytes'];
        if (chunkDocument.id != '$index' ||
            chunk['index'] != index ||
            bytes is! Blob ||
            bytes.bytes.isEmpty ||
            bytes.bytes.length > maxFirestoreImageChunkBytes) {
          throw FormatException('Listing ${document.id} has invalid image data.');
        }
        builder.add(bytes.bytes);
        totalBytes += bytes.bytes.length;
      }
      if (totalBytes != data['image_size_bytes'] ||
          totalBytes > maxFirestoreImageBytes) {
        throw FormatException('Listing ${document.id} has an invalid image size.');
      }
      data['image_bytes'] = builder.takeBytes();
    } else {
      if (chunkCount == 0 && data['image_size_bytes'] != 0) {
        throw FormatException('Listing ${document.id} has an invalid image size.');
      }
      final imageBytes = data['image_bytes'];
      if (imageBytes is Blob) data['image_bytes'] = imageBytes.bytes;
    }
    final postedAt = data['posted_at'];
    if (postedAt is Timestamp) data['posted_at'] = postedAt.toDate();
    data['is_mine'] = data['owner_uid'] == _auth.currentUser?.uid;
    return ProduceListing.fromJson(data);
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in with Firebase before managing listings.');
    }
    return user;
  }

  Future<User> _requireVendor() async {
    final user = _requireUser();
    final profile = await _db.collection('users').doc(user.uid).get();
    if (profile.data()?['role'] != 'Vendor') {
      throw StateError('Only vendor accounts can manage listings.');
    }
    return user;
  }

  void _rejectLocalMedia(ProduceListing listing) {
    if (listing.pendingMedia.isNotEmpty) {
      throw ArgumentError(
        'Local photos and videos are not uploaded. Use publicly hosted URLs instead.',
      );
    }
  }

  List<String> _imageUrlsFor(ProduceListing listing) {
    final primaryUrl = listing.imageUrl.trim();
    if (primaryUrl.isNotEmpty) return [primaryUrl];
    return listing.imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  void _validateMediaUrls(List<String> imageUrls, List<String> videoUrls) {
    if ([...imageUrls, ...videoUrls].any((url) => !isHostedMediaUrl(url))) {
      throw ArgumentError(
        'Use publicly accessible HTTPS URLs for listing media.',
      );
    }
  }

  bool _available(String quantity) {
    final parsed = int.tryParse(quantity.trim());
    if (parsed == null || parsed < 0) {
      throw ArgumentError('Quantity must be a non-negative whole number.');
    }
    return parsed > 0;
  }

  void _requireOwner(
    DocumentSnapshot<Map<String, dynamic>> document,
    User user,
  ) {
    if (!document.exists || document.data()?['owner_uid'] != user.uid) {
      throw StateError('You can only manage your own listings.');
    }
  }
}
