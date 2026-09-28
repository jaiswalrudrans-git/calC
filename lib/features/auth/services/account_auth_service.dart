import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/firebase_config.dart';
import '../../../../core/security/secure_key_storage.dart';
import '../../../../core/backup/google_drive_backup_service.dart';
import '../../messenger/models/chat_contact.dart';

/// Result object returned by AccountAuthService operations
class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? recoveryCode; // Plaintext recovery code (ONLY returned once upon registration or reset)
  final String? connectCode;  // Permanent 6-digit numeric connect code
  final String? uid;          // Permanent stable UID for this account
  final bool isLockedOut;
  final int lockoutSeconds;

  const AuthResult({
    required this.success,
    this.errorMessage,
    this.recoveryCode,
    this.connectCode,
    this.uid,
    this.isLockedOut = false,
    this.lockoutSeconds = 0,
  });

  factory AuthResult.ok({
    String? recoveryCode,
    String? connectCode,
    String? uid,
  }) =>
      AuthResult(
        success: true,
        recoveryCode: recoveryCode,
        connectCode: connectCode,
        uid: uid,
      );

  factory AuthResult.fail(
    String message, {
    bool isLockedOut = false,
    int lockoutSeconds = 0,
  }) =>
      AuthResult(
        success: false,
        errorMessage: message,
        isLockedOut: isLockedOut,
        lockoutSeconds: lockoutSeconds,
      );
}

/// Service managing username/password credentials, stable permanent UIDs,
/// 6-digit permanent connect codes, and zero-knowledge recovery codes.
/// - NO anonymous authentication exists
/// - Every account has a permanent, stable UID mapped from username (under the hood: username@metricapp.local)
/// - Recovery codes and passwords are ALWAYS salted and hashed with SHA-256
/// - Plaintext recovery codes are NEVER persisted, NEVER logged, and only shown ONCE
/// - Brute-force protection: Rate limiting on recovery attempts (5 attempts -> 60s lockout)
class AccountAuthService {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    aOptions: AndroidOptions(
      resetOnError: false,
    ),
  );

  static final _sha256 = Sha256();
  static final _random = Random.secure();
  static const _uuid = Uuid();

  // Rate Limiting Constants
  static const int maxFailedAttempts = 5;
  static const int lockoutDurationSeconds = 60;

  // In-memory / secure rate-limiting tracking
  static final Map<String, int> _failedAttempts = {};
  static final Map<String, DateTime> _lockoutUntil = {};

  // Characters used for 12-char recovery code (unambiguous alphanumeric, excluding 0, O, 1, I)
  static const String _recoveryCharset = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// Normalize username for consistent storage indexing
  static String normalizeUsername(String username) => username.trim().toLowerCase();

  /// Normalize recovery code: remove hyphens, whitespace, uppercase
  static String normalizeRecoveryCode(String code) {
    return code.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();
  }

  /// Generate a cryptographically random 12-character recovery code formatted as XXXX-XXXX-XXXX
  static String generateRecoveryCode() {
    final chars = List.generate(
      12,
      (_) => _recoveryCharset[_random.nextInt(_recoveryCharset.length)],
    );
    return '${chars.sublist(0, 4).join()}-${chars.sublist(4, 8).join()}-${chars.sublist(8, 12).join()}';
  }

  /// Generate a permanent 6-digit numeric connect code formatted as XXX-XXX (e.g. 839-201)
  static String generateConnectCode() {
    final number = 100000 + _random.nextInt(900000);
    final str = number.toString();
    return '${str.substring(0, 3)}-${str.substring(3, 6)}';
  }

  /// Generate a 16-byte random cryptographic salt as hex
  static String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hash input string with given salt using SHA-256
  static Future<String> _hashWithSalt(String input, String saltHex) async {
    final combined = utf8.encode('$saltHex:$input');
    final hash = await _sha256.hash(combined);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Constant-time string comparison to prevent timing attacks
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Check remaining lockout seconds for a given username
  static int getRemainingLockoutSeconds(String rawUsername) {
    final u = normalizeUsername(rawUsername);
    final lockout = _lockoutUntil[u];
    if (lockout == null) return 0;
    final now = DateTime.now();
    if (now.isBefore(lockout)) {
      return lockout.difference(now).inSeconds;
    }
    // Lockout expired
    _lockoutUntil.remove(u);
    _failedAttempts[u] = 0;
    return 0;
  }

  /// Derive a stable, permanent, globally unique UID for an account.
  /// Uses a deterministic UUIDv5 namespace keyed by normalized username.
  /// Guarantees that every account has a distinct, immutable UID that never collides.
  static Future<String> _resolveStableUid(String username, [String? password]) async {
    final u = normalizeUsername(username);
    final deterministicUid = _uuid.v5(Namespace.url.value, 'metric:account:$u');
    await _storage.write(key: 'metric_auth_user_${u}_uid', value: deterministicUid);
    return deterministicUid;
  }

  /// Register a new account with username + password
  /// Generates:
  /// - A stable permanent UID
  /// - A permanent 6-digit numeric Connect Code
  /// - A one-time 12-char recovery code (hashed, never plaintext in storage)
  /// - Stores credentials and public profile on Firebase Spark (Cloud Firestore)
  static Future<AuthResult> register({
    required String username,
    required String password,
  }) async {
    final u = normalizeUsername(username);

    if (u.length < 3) {
      return AuthResult.fail('Username must be at least 3 characters long.');
    }
    if (password.length < 6) {
      return AuthResult.fail('Password must be at least 6 characters long.');
    }

    final existingSalt = await _storage.read(key: 'metric_auth_user_${u}_pwd_salt');
    if (existingSalt != null) {
      return AuthResult.fail('Username "$username" is already registered. Please sign in or choose another.');
    }

    // Check Cloud Firestore to ensure username is globally unique on Firebase
    final firestore = FirebaseConfig.firestore;
    if (firestore != null) {
      try {
        final existingRemote = await firestore
            .collection('users')
            .where('username', isEqualTo: u)
            .limit(1)
            .get();
        if (existingRemote.docs.isNotEmpty) {
          return AuthResult.fail('Username "$username" is already taken. Please choose another.');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[AccountAuthService] Firestore username check notice: $e');
      }
    }

    // 1. Resolve stable permanent UID
    final stableUid = await _resolveStableUid(u, password);

    // 2. Generate permanent 6-digit numeric Connect Code
    final connectCode = generateConnectCode();

    // 3. Generate one-time recovery code
    final plainRecoveryCode = generateRecoveryCode();
    final normalizedRecoveryCode = normalizeRecoveryCode(plainRecoveryCode);

    // 4. Hash Password
    final pwdSalt = _generateSalt();
    final pwdHash = await _hashWithSalt(password, pwdSalt);

    // 5. Hash Recovery Code (same salted SHA-256 approach)
    final recoverySalt = _generateSalt();
    final recoveryHash = await _hashWithSalt(normalizedRecoveryCode, recoverySalt);

    // 6. Save to local secure storage
    await _storage.write(key: 'metric_auth_user_${u}_uid', value: stableUid);
    await _storage.write(key: 'metric_auth_user_${u}_connect_code', value: connectCode);
    await _storage.write(key: 'metric_auth_user_${u}_pwd_salt', value: pwdSalt);
    await _storage.write(key: 'metric_auth_user_${u}_pwd_hash', value: pwdHash);
    await _storage.write(key: 'metric_auth_user_${u}_recovery_salt', value: recoverySalt);
    await _storage.write(key: 'metric_auth_user_${u}_recovery_hash', value: recoveryHash);
    await _storage.write(key: 'metric_auth_user_${u}_created_at', value: DateTime.now().toIso8601String());

    // Update list of registered users
    final allUsersRaw = await _storage.read(key: 'metric_auth_all_usernames') ?? '';
    final userList = allUsersRaw.split(',').where((s) => s.isNotEmpty).toSet();
    userList.add(u);
    await _storage.write(key: 'metric_auth_all_usernames', value: userList.join(','));

    // 7. Store user credentials and connect code mapping on Firebase Cloud Firestore
    if (firestore != null) {
      try {
        await firestore.collection('users').doc(stableUid).set({
          'uid': stableUid,
          'username': u,
          'connect_code': connectCode,
          'pwd_salt': pwdSalt,
          'pwd_hash': pwdHash,
          'recovery_salt': recoverySalt,
          'recovery_hash': recoveryHash,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'contacts': [],
        }, SetOptions(merge: true));

        final cleanCode = connectCode.replaceAll(RegExp(r'[^0-9]'), '');
        await firestore.collection('connect_codes').doc(cleanCode).set({
          'uid': stableUid,
          'username': u,
          'connect_code': connectCode,
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[AccountAuthService] Firestore register notice: $e');
      }
    }

    // Clear previous user's contacts and bind new user's credentials
    await SecureKeyStorage.saveContacts([]);
    await SecureKeyStorage.saveMyDeviceId(stableUid);
    await SecureKeyStorage.saveMyConnectCode(connectCode);
    await _storage.write(key: 'metric_auth_current_user', value: u);
    await _storage.write(key: 'metric_auth_is_logged_in', value: 'true');

    return AuthResult.ok(
      recoveryCode: plainRecoveryCode,
      connectCode: connectCode,
      uid: stableUid,
    );
  }

  /// Verify login credentials (username + password)
  /// Reconnects the exact same stable UID and Connect Code!
  static Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final u = normalizeUsername(username);

    var pwdSalt = await _storage.read(key: 'metric_auth_user_${u}_pwd_salt');
    var storedPwdHash = await _storage.read(key: 'metric_auth_user_${u}_pwd_hash');
    var stableUid = await _storage.read(key: 'metric_auth_user_${u}_uid');
    var connectCode = await _storage.read(key: 'metric_auth_user_${u}_connect_code');

    // If credentials are not cached locally, query Firebase Cloud Firestore
    if (pwdSalt == null || storedPwdHash == null) {
      final firestore = FirebaseConfig.firestore;
      if (firestore != null) {
        try {
          final query = await firestore
              .collection('users')
              .where('username', isEqualTo: u)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            final data = query.docs.first.data();
            pwdSalt = data['pwd_salt'] as String?;
            storedPwdHash = data['pwd_hash'] as String?;
            stableUid = data['uid'] as String?;
            connectCode = data['connect_code'] as String?;
            final recoverySalt = data['recovery_salt'] as String?;
            final recoveryHash = data['recovery_hash'] as String?;

            if (pwdSalt != null && storedPwdHash != null) {
              await _storage.write(key: 'metric_auth_user_${u}_pwd_salt', value: pwdSalt);
              await _storage.write(key: 'metric_auth_user_${u}_pwd_hash', value: storedPwdHash);
              if (stableUid != null) await _storage.write(key: 'metric_auth_user_${u}_uid', value: stableUid);
              if (connectCode != null) await _storage.write(key: 'metric_auth_user_${u}_connect_code', value: connectCode);
              if (recoverySalt != null) await _storage.write(key: 'metric_auth_user_${u}_recovery_salt', value: recoverySalt);
              if (recoveryHash != null) await _storage.write(key: 'metric_auth_user_${u}_recovery_hash', value: recoveryHash);

              // Restore contacts list from Firestore (capped at 5)
              final rawContacts = data['contacts'] as List<dynamic>?;
              if (rawContacts != null) {
                final contacts = rawContacts
                    .map((item) => ChatContact.fromMap(item as Map<String, dynamic>))
                    .toList();
                await SecureKeyStorage.saveContacts(contacts);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AccountAuthService] Firestore login query notice: $e');
        }
      }
    }

    if (pwdSalt == null || storedPwdHash == null) {
      return AuthResult.fail('No account found for "$username".');
    }

    final candidateHash = await _hashWithSalt(password, pwdSalt);
    if (!_constantTimeEquals(candidateHash, storedPwdHash)) {
      return AuthResult.fail('Incorrect password.');
    }

    // Enforce distinct deterministic permanent UID for this username
    stableUid = await _resolveStableUid(u, password);
    await _storage.write(key: 'metric_auth_user_${u}_uid', value: stableUid);

    // Retrieve or generate connect code
    if (connectCode == null || connectCode.isEmpty) {
      connectCode = generateConnectCode();
      await _storage.write(key: 'metric_auth_user_${u}_connect_code', value: connectCode);
    }

    // Restore contacts specific to this user account
    final userContactsJson = await _storage.read(key: 'metric_contacts_$u');
    if (userContactsJson != null && userContactsJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(userContactsJson);
        final contacts = list.map((item) => ChatContact.fromMap(item as Map<String, dynamic>)).toList();
        await SecureKeyStorage.saveContacts(contacts);
      } catch (_) {
        await SecureKeyStorage.saveContacts([]);
      }
    } else {
      await SecureKeyStorage.saveContacts([]);
    }

    // Set active device identifiers
    await SecureKeyStorage.saveMyDeviceId(stableUid);
    await SecureKeyStorage.saveMyConnectCode(connectCode);
    await _storage.write(key: 'metric_auth_current_user', value: u);
    await _storage.write(key: 'metric_auth_is_logged_in', value: 'true');

    // Sync connect code to Firestore for pairing
    final firestore = FirebaseConfig.firestore;
    if (firestore != null) {
      try {
        final cleanCode = connectCode.replaceAll(RegExp(r'[^0-9]'), '');
        await firestore.collection('connect_codes').doc(cleanCode).set({
          'uid': stableUid,
          'username': u,
          'connect_code': connectCode,
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    return AuthResult.ok(
      connectCode: connectCode,
      uid: stableUid,
    );
  }

  /// Verify recovery code for a user with brute-force rate-limiting
  static Future<AuthResult> verifyRecoveryCode({
    required String username,
    required String recoveryCode,
  }) async {
    final u = normalizeUsername(username);

    // 1. Check rate limit / lockout
    final remainingLockout = getRemainingLockoutSeconds(u);
    if (remainingLockout > 0) {
      return AuthResult.fail(
        'Too many failed recovery attempts. Locked out for ${remainingLockout}s.',
        isLockedOut: true,
        lockoutSeconds: remainingLockout,
      );
    }

    final recoverySalt = await _storage.read(key: 'metric_auth_user_${u}_recovery_salt');
    final storedRecoveryHash = await _storage.read(key: 'metric_auth_user_${u}_recovery_hash');

    if (recoverySalt == null || storedRecoveryHash == null) {
      return AuthResult.fail('Account "$username" not found.');
    }

    final normalized = normalizeRecoveryCode(recoveryCode);
    final candidateHash = await _hashWithSalt(normalized, recoverySalt);

    if (!_constantTimeEquals(candidateHash, storedRecoveryHash)) {
      // Record failure for rate limiting
      final attempts = (_failedAttempts[u] ?? 0) + 1;
      _failedAttempts[u] = attempts;

      if (attempts >= maxFailedAttempts) {
        _lockoutUntil[u] = DateTime.now().add(const Duration(seconds: lockoutDurationSeconds));
        return AuthResult.fail(
          'Maximum attempts reached. Locked out for ${lockoutDurationSeconds}s.',
          isLockedOut: true,
          lockoutSeconds: lockoutDurationSeconds,
        );
      }

      final remainingAttempts = maxFailedAttempts - attempts;
      return AuthResult.fail(
        'Invalid recovery code. ($remainingAttempts attempt${remainingAttempts == 1 ? '' : 's'} remaining before lockout)',
        isLockedOut: false,
        lockoutSeconds: 0,
      );
    }

    // Success -> reset failure counter
    _failedAttempts[u] = 0;
    _lockoutUntil.remove(u);

    return AuthResult.ok();
  }

  /// Reset password using recovery code verification.
  /// Preserves the stable permanent UID and permanent Connect Code!
  static Future<AuthResult> resetPassword({
    required String username,
    required String recoveryCode,
    required String newPassword,
    bool generateNewRecoveryCode = true,
  }) async {
    final u = normalizeUsername(username);

    // 1. Verify recovery code with rate-limiting check
    final verifyRes = await verifyRecoveryCode(
      username: username,
      recoveryCode: recoveryCode,
    );
    if (!verifyRes.success) {
      return verifyRes;
    }

    if (newPassword.length < 6) {
      return AuthResult.fail('New password must be at least 6 characters long.');
    }

    // 2. Hash and update new password
    final newPwdSalt = _generateSalt();
    final newPwdHash = await _hashWithSalt(newPassword, newPwdSalt);

    await _storage.write(key: 'metric_auth_user_${u}_pwd_salt', value: newPwdSalt);
    await _storage.write(key: 'metric_auth_user_${u}_pwd_hash', value: newPwdHash);

    // 3. Optionally generate and hash new recovery code (replacing the old one)
    String? newPlainCode;
    if (generateNewRecoveryCode) {
      newPlainCode = generateRecoveryCode();
      final normalizedNewCode = normalizeRecoveryCode(newPlainCode);
      final newRecoverySalt = _generateSalt();
      final newRecoveryHash = await _hashWithSalt(normalizedNewCode, newRecoverySalt);

      await _storage.write(key: 'metric_auth_user_${u}_recovery_salt', value: newRecoverySalt);
      await _storage.write(key: 'metric_auth_user_${u}_recovery_hash', value: newRecoveryHash);
    }

    final firestore = FirebaseConfig.firestore;
    final stableUid = await _storage.read(key: 'metric_auth_user_${u}_uid');
    if (firestore != null && stableUid != null) {
      try {
        final updateData = <String, dynamic>{
          'pwd_salt': newPwdSalt,
          'pwd_hash': newPwdHash,
        };
        if (newPlainCode != null) {
          updateData['recovery_salt'] = await _storage.read(key: 'metric_auth_user_${u}_recovery_salt');
          updateData['recovery_hash'] = await _storage.read(key: 'metric_auth_user_${u}_recovery_hash');
        }
        await firestore.collection('users').doc(stableUid).update(updateData);
      } catch (_) {}
    }

    return AuthResult.ok(recoveryCode: newPlainCode);
  }

  /// Get current user's Connect Code — guaranteed to return a valid 6-digit code
  static Future<String> getCurrentConnectCode() async {
    // 1. Try SecureKeyStorage
    var code = await SecureKeyStorage.getMyConnectCode();
    if (code != null && code.isNotEmpty) {
      return code;
    }

    // 2. Try User account storage
    final u = await getCurrentUsername();
    if (u != null && u.isNotEmpty) {
      code = await _storage.read(key: 'metric_auth_user_${u}_connect_code');
      if (code != null && code.isNotEmpty) {
        await SecureKeyStorage.saveMyConnectCode(code);
        return code;
      }

      // Generate, save, and bind
      code = generateConnectCode();
      await _storage.write(key: 'metric_auth_user_${u}_connect_code', value: code);
      await SecureKeyStorage.saveMyConnectCode(code);
      return code;
    }

    // 3. Fallback: generate and persist for this device
    code = generateConnectCode();
    await SecureKeyStorage.saveMyConnectCode(code);
    return code;
  }

  /// Get current user's permanent UID
  static Future<String?> getCurrentUserUid() async {
    return await SecureKeyStorage.getMyDeviceId();
  }

  /// Get current username
  static Future<String?> getCurrentUsername() async {
    return await _storage.read(key: 'metric_auth_current_user');
  }

  /// Check if user is currently logged in
  static Future<bool> isLoggedIn() async {
    final status = await _storage.read(key: 'metric_auth_is_logged_in');
    return status == 'true';
  }

  /// Log out current user and clear all session data, connect code, drive tokens, and cloud auth
  static Future<void> logout() async {
    // 1. Save contacts for the current user before wiping session
    final u = await getCurrentUsername();
    if (u != null && u.isNotEmpty) {
      final contacts = await SecureKeyStorage.getContacts();
      await _storage.write(
        key: 'metric_contacts_$u',
        value: jsonEncode(contacts.map((c) => c.toMap()).toList()),
      );
    }

    await _storage.delete(key: 'metric_auth_current_user');
    await _storage.write(key: 'metric_auth_is_logged_in', value: 'false');

    // 2. Clear session keys, connect code, contacts, and pairing data in SecureKeyStorage
    await SecureKeyStorage.clearUserSessionOnLogout();

    // 3. Disconnect Google Drive
    try {
      await GoogleDriveBackupService.instance.signOut();
    } catch (_) {}

    // 4. Sign out of Firebase Auth
    try {
      await FirebaseConfig.auth?.signOut();
    } catch (_) {}
  }
}
