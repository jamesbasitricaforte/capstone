import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirebaseTest {
  static Future<void> testConnection() async {
    try {
      await FirebaseFirestore.instance
          .collection('connection_test')
          .doc('flutter_test')
          .set({
            'message': 'PROJECT_RECUE connected!',
            'status': 'success',
            'createdAt': FieldValue.serverTimestamp(),
          });

      debugPrint('FIREBASE CONNECTION SUCCESSFUL!');
    } catch (e) {
      debugPrint('FIREBASE CONNECTION ERROR: $e');
      rethrow;
    }
  }
}
