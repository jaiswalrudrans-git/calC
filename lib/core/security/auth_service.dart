import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';
import 'secure_key_storage.dart';

/// Silent Authentication Service:
/// - Strictly NO login / password / sign-up screen exists anywhere
/// - Silently creates or restores a Supabase Anonymous Auth session
/// - Hardware-persisted device UID in secure storage
class AuthService {
  static const _uuid = Uuid();

  /// Silently get or create this device's unique identifier via Supabase Anonymous Auth
  static Future<String> getOrCreateDeviceUid() async {
    // 1. Check local secure storage first
    var deviceUid = await SecureKeyStorage.getMyDeviceId();

    // 2. Try Supabase Anonymous Auth if Supabase client is available
    final client = SupabaseConfig.client;
    if (client != null) {
      try {
        final currentUser = client.auth.currentUser;
        if (currentUser != null && currentUser.id.isNotEmpty) {
          deviceUid = currentUser.id;
          await SecureKeyStorage.saveMyDeviceId(deviceUid);
          return deviceUid;
        }

        // Silent anonymous sign-in
        final authResponse = await client.auth.signInAnonymously();
        if (authResponse.user != null) {
          deviceUid = authResponse.user!.id;
          await SecureKeyStorage.saveMyDeviceId(deviceUid);
          if (kDebugMode) {
            debugPrint('[AuthService] Supabase Anonymous Auth succeeded. UID: $deviceUid');
          }
          return deviceUid;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AuthService] Supabase Anonymous Auth notice: $e');
        }
      }
    }

    if (deviceUid != null && deviceUid.isNotEmpty) {
      return deviceUid;
    }

    // 3. Fallback: Generate cryptographic device UUID & store in secure keystore
    deviceUid = _uuid.v4();
    await SecureKeyStorage.saveMyDeviceId(deviceUid);
    return deviceUid;
  }
}
