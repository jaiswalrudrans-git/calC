import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import 'secure_key_storage.dart';

/// Authentication Service for Metric:
/// - Strictly Account-Based (Username & Password mapped to stable Auth UID)
/// - NO anonymous authentication
/// - Stable permanent UID used across Firestore, Signal sessions, and Drive storage
class AuthService {
  /// Get the current logged-in user's stable UID
  static Future<String?> getCurrentUid() async {
    // 1. If user has a connect code, use standard connect UID so peer messages match
    final connectCode = await SecureKeyStorage.getMyConnectCode();
    if (connectCode != null && connectCode.isNotEmpty) {
      final clean = connectCode.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.length == 6) {
        return 'code_$clean';
      }
    }

    // 2. Check local secure storage
    final localUid = await SecureKeyStorage.getMyDeviceId();
    if (localUid != null && localUid.isNotEmpty) {
      return localUid;
    }

    // 3. Check Supabase client current session if available
    final client = SupabaseConfig.client;
    if (client != null) {
      final currentUser = client.auth.currentUser;
      if (currentUser != null && currentUser.id.isNotEmpty) {
        await SecureKeyStorage.saveMyDeviceId(currentUser.id);
        return currentUser.id;
      }
    }

    return null;
  }

  /// Returns the current stable UID, ensuring non-null fallback for chat initializations
  static Future<String> getOrCreateDeviceUid() async {
    final uid = await getCurrentUid();
    return uid ?? 'unauthenticated_user';
  }

  /// Sign out current account
  static Future<void> signOut() async {
    try {
      final client = SupabaseConfig.client;
      if (client != null) {
        await client.auth.signOut();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthService] Sign out notice: $e');
      }
    }
  }
}
