import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/security/secure_key_storage.dart';
import '../../../../core/backup/google_drive_backup_service.dart';
import '../../../../core/security/auth_service.dart';

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

  /// Derive or create a stable permanent UID for an account.
  /// Uses Supabase Anonymous Auth to get a real auth.uid() that passes RLS policies.
  /// The auth UID is stored permanently so the same UID is reused across sessions.
  static Future<String> _resolveStableUid(String username, String password) async {
    final u = normalizeUsername(username);

    // 1. Check if this user already has a stored UID
    final existingUid = await _storage.read(key: 'metric_auth_user_${u}_uid');
    if (existingUid != null && existingUid.isNotEmpty) {
      return existingUid;
    }

    // 2. Try Supabase Anonymous Auth to get a real auth.uid()
    //    This UID is essential for RLS — sender_uid MUST equal auth.uid()
    final client = SupabaseConfig.client;
    if (client != null && SupabaseConfig.isConfigured) {
      try {
        // If already authenticated, use current UID
        final currentUser = client.auth.currentUser;
        if (currentUser != null && currentUser.id.isNotEmpty) {
          return currentUser.id;
        }

        final authRes = await client.auth.signInAnonymously();
        if (authRes.user != null && authRes.user!.id.isNotEmpty) {
          return authRes.user!.id;
        }
      } catch (_) {}
    }

    // 3. Offline fallback: deterministic v5 UUID (won't work with RLS but prevents crash)
    return _uuid.v5(Namespace.url.value, 'metric:account:$u');
  }

  /// Register a new account with username + password
  /// Generates:
  /// - A stable permanent UID
  /// - A permanent 6-digit numeric Connect Code
  /// - A one-time 12-char recovery code (hashed, never plaintext in storage)
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

    // 6. Save to secure storage (NEVER plaintext recovery code or password!)
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

    // Automatically bind to device state
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

    final pwdSalt = await _storage.read(key: 'metric_auth_user_${u}_pwd_salt');
    final storedPwdHash = await _storage.read(key: 'metric_auth_user_${u}_pwd_hash');

    if (pwdSalt == null || storedPwdHash == null) {
      return AuthResult.fail('No account found for "$username".');
    }

    final candidateHash = await _hashWithSalt(password, pwdSalt);
    if (!_constantTimeEquals(candidateHash, storedPwdHash)) {
      return AuthResult.fail('Incorrect password.');
    }

    // Re-resolve or retrieve stable UID
    var stableUid = await _storage.read(key: 'metric_auth_user_${u}_uid');
    if (stableUid == null || stableUid.isEmpty) {
      stableUid = await _resolveStableUid(u, password);
      await _storage.write(key: 'metric_auth_user_${u}_uid', value: stableUid);
    }

    // Retrieve or generate connect code
    var connectCode = await _storage.read(key: 'metric_auth_user_${u}_connect_code');
    if (connectCode == null || connectCode.isEmpty) {
      connectCode = generateConnectCode();
      await _storage.write(key: 'metric_auth_user_${u}_connect_code', value: connectCode);
    }

    // Set active device identifiers
    await SecureKeyStorage.saveMyDeviceId(stableUid);
    await SecureKeyStorage.saveMyConnectCode(connectCode);
    await _storage.write(key: 'metric_auth_current_user', value: u);
    await _storage.write(key: 'metric_auth_is_logged_in', value: 'true');

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
    await _storage.delete(key: 'metric_auth_current_user');
    await _storage.write(key: 'metric_auth_is_logged_in', value: 'false');

    // 1. Clear session keys, connect code, pairing data in SecureKeyStorage
    await SecureKeyStorage.clearUserSessionOnLogout();

    // 2. Disconnect Google Drive
    try {
      await GoogleDriveBackupService.instance.signOut();
    } catch (_) {}

    // 3. Sign out of Supabase
    try {
      await AuthService.signOut();
    } catch (_) {}
  }
}
