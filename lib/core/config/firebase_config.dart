import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

class FirebaseConfig {
  static bool _isInitialized = false;

  static bool get isConfigured => _isInitialized;

  static FirebaseFirestore? get firestore {
    if (!_isInitialized) return null;
    return FirebaseFirestore.instance;
  }

  static FirebaseAuth? get auth {
    if (!_isInitialized) return null;
    return FirebaseAuth.instance;
  }

  /// Initialize Firebase app with error handling
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (Firebase.apps.isNotEmpty) {
        _isInitialized = true;
        _configureFirestoreSettings();
        return;
      }

      try {
        // Try initializing with platform options
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        _isInitialized = true;
      } catch (e) {
        // Fallback to default native configuration (google-services.json)
        try {
          await Firebase.initializeApp();
          _isInitialized = true;
        } catch (inner) {
          if (kDebugMode) {
            debugPrint('[FirebaseConfig] Native initialize fallback error: $inner');
          }
          // If already exists or error, mark if apps are present
          _isInitialized = Firebase.apps.isNotEmpty;
        }
      }

      if (_isInitialized) {
        _configureFirestoreSettings();
        if (kDebugMode) {
          debugPrint('[FirebaseConfig] Firebase successfully initialized on Spark plan.');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseConfig] Firebase initialization notice: $e');
      }
    }
  }

  static void _configureFirestoreSettings() {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {}
  }
}
