import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/firebase_config.dart';
import 'secure_key_storage.dart';

/// Authentication Service for Metric using Firebase Spark
class AuthService {
  /// Ensure Firebase is authenticated and return the current UID.
  static Future<String?> ensureFirebaseAuth() async {
    final auth = FirebaseConfig.auth;
    if (auth == null) return null;

    // 1. Check if already authenticated
    final currentUser = auth.currentUser;
    if (currentUser != null && currentUser.uid.isNotEmpty) {
      return currentUser.uid;
    }

    // 2. Sign in anonymously to get an auth session
    try {
      final authRes = await auth.signInAnonymously();
      if (authRes.user != null && authRes.user!.uid.isNotEmpty) {
        return authRes.user!.uid;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] Anonymous auth error: $e');
    }

    return null;
  }

  /// Get the current logged-in user's stable UID.
  static Future<String?> getCurrentUid() async {
    // 1. Check local secure storage first (fastest path)
    final localUid = await SecureKeyStorage.getMyDeviceId();
    if (localUid != null && localUid.isNotEmpty) {
      final auth = FirebaseConfig.auth;
      if (auth != null && auth.currentUser == null) {
        try {
          await auth.signInAnonymously();
        } catch (_) {}
      }
      return localUid;
    }

    // 2. No local UID stored — get one from Firebase auth
    final authUid = await ensureFirebaseAuth();
    if (authUid != null && authUid.isNotEmpty) {
      await SecureKeyStorage.saveMyDeviceId(authUid);
      return authUid;
    }

    return null;
  }

  /// Returns the current stable UID, ensuring non-null fallback.
  static Future<String> getOrCreateDeviceUid() async {
    final uid = await getCurrentUid();
    if (uid != null && uid.isNotEmpty) return uid;

    final generated = const Uuid().v4();
    await SecureKeyStorage.saveMyDeviceId(generated);
    return generated;
  }

  /// Sign out current account
  static Future<void> signOut() async {
    try {
      final auth = FirebaseConfig.auth;
      if (auth != null) {
        await auth.signOut();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthService] Sign out notice: $e');
      }
    }
  }
}
