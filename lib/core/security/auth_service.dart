import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';
import 'secure_key_storage.dart';

/// Silent Authentication Service:
/// - Strictly NO login / password / sign-up screen exists anywhere
/// - Silently creates or restores a Firebase Anonymous Auth session
/// - Includes transparent offline fallback with hardware-persisted device ID
class AuthService {
  static const _uuid = Uuid();

  /// Silently get or create this device's unique identifier
  static Future<String> getOrCreateDeviceUid() async {
    // 1. Check local secure storage first
    var deviceUid = await SecureKeyStorage.getMyDeviceId();
    if (deviceUid != null && deviceUid.isNotEmpty) {
      return deviceUid;
    }

    // 2. Try Firebase Anonymous Auth if Firebase is initialized
    try {
      if (Firebase.apps.isNotEmpty) {
        final auth = FirebaseAuth.instance;
        User? user = auth.currentUser;
        if (user == null) {
          final cred = await auth.signInAnonymously();
          user = cred.user;
        }
        if (user != null) {
          deviceUid = user.uid;
          await SecureKeyStorage.saveMyDeviceId(deviceUid);
          return deviceUid;
        }
      }
    } catch (_) {
      // Firebase not configured yet or offline, proceed to secure local UUID
    }

    // 3. Fallback: Generate cryptographic device UID & store in secure keystore
    deviceUid = 'dev_${_uuid.v4().replaceAll('-', '').substring(0, 16)}';
    await SecureKeyStorage.saveMyDeviceId(deviceUid);
    return deviceUid;
  }
}
