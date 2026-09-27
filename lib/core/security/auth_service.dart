import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';
import 'secure_key_storage.dart';

/// Authentication Service for Metric:
/// - Uses Supabase Anonymous Auth to get a stable, RLS-compatible auth UID
/// - The Supabase auth.uid() is used as the device UID everywhere
/// - This ensures sender_uid == auth.uid() so RLS policies pass
/// - NO email/password auth (Supabase rejects .local domains)
class AuthService {
  /// Ensure the Supabase client is authenticated and auth.uid() matches our device UID.
  /// If the device already has a persisted UID, re-authenticate anonymously if needed.
  /// Returns the Supabase auth UID.
  static Future<String?> ensureSupabaseAuth() async {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return null;

    // 1. Check if already authenticated
    final currentUser = client.auth.currentUser;
    if (currentUser != null && currentUser.id.isNotEmpty) {
      return currentUser.id;
    }

    // 2. Sign in anonymously to get a fresh auth session
    try {
      final authRes = await client.auth.signInAnonymously();
      if (authRes.user != null && authRes.user!.id.isNotEmpty) {
        return authRes.user!.id;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] Anonymous auth error: $e');
    }

    return null;
  }

  /// Get the current logged-in user's stable UID (RFC-4122 compliant UUID).
  /// Priority: Supabase auth UID > Local storage > null
  static Future<String?> getCurrentUid() async {
    // 1. Check local secure storage first (fastest path)
    final localUid = await SecureKeyStorage.getMyDeviceId();
    if (localUid != null && _isValidUuid(localUid)) {
      // Verify Supabase auth session is active with this UID
      final client = SupabaseConfig.client;
      if (client != null && SupabaseConfig.isConfigured) {
        final currentUser = client.auth.currentUser;
        if (currentUser != null && currentUser.id == localUid) {
          return localUid; // Already authenticated with matching UID
        }
        // Auth session expired or UID mismatch — try re-authenticating
        try {
          final authRes = await client.auth.signInAnonymously();
          final authUid = authRes.user?.id;
          if (authUid != null && authUid.isNotEmpty) {
            // If we get a NEW anonymous UID that doesn't match our stored one,
            // we need to keep our stored UID for pairing consistency but update
            // the pairing_exchange table with the new auth UID mapping.
            // For now, use the anonymous UID as our device UID.
            if (authUid != localUid) {
              // First login with new anonymous session - update device UID
              if (kDebugMode) {
                debugPrint('[AuthService] Auth UID changed: $localUid -> $authUid');
              }
              await SecureKeyStorage.saveMyDeviceId(authUid);
              return authUid;
            }
            return localUid;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AuthService] Re-auth error: $e');
        }
      }
      return localUid;
    }

    // 2. No local UID stored — get one from Supabase anonymous auth
    final authUid = await ensureSupabaseAuth();
    if (authUid != null && authUid.isNotEmpty) {
      await SecureKeyStorage.saveMyDeviceId(authUid);
      return authUid;
    }

    return null;
  }

  /// Returns the current stable UID, ensuring non-null fallback for chat initializations.
  /// CRITICAL: This UID MUST match Supabase auth.uid() for RLS to pass on message inserts.
  static Future<String> getOrCreateDeviceUid() async {
    final uid = await getCurrentUid();
    if (uid != null && uid.isNotEmpty) return uid;

    // Last resort fallback: generate a UUID (won't work with RLS but prevents crash)
    final generated = const Uuid().v4();
    await SecureKeyStorage.saveMyDeviceId(generated);
    return generated;
  }

  /// Ensure Supabase auth session is alive and auth.uid() matches the given sender UID.
  /// Call this BEFORE any Supabase insert/update that involves RLS.
  /// Returns true if auth.uid() matches senderUid.
  static Future<bool> ensureAuthMatchesSender(String senderUid) async {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return false;

    final currentUser = client.auth.currentUser;
    if (currentUser != null && currentUser.id == senderUid) {
      return true; // Already authenticated with matching UID
    }

    // Sign in anonymously — the new session may not match senderUid.
    // This is OK because we'll update senderUid to match auth.uid().
    try {
      final authRes = await client.auth.signInAnonymously();
      final authUid = authRes.user?.id;
      if (authUid != null && authUid == senderUid) {
        return true;
      }
      // UID mismatch: update the stored device UID to match auth
      if (authUid != null && authUid.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[AuthService] Auth UID mismatch: sender=$senderUid, auth=$authUid');
        }
        return false; // Caller should update sender_uid to auth.uid()
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] ensureAuthMatchesSender error: $e');
    }

    return false;
  }

  static bool _isValidUuid(String str) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(str);
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
