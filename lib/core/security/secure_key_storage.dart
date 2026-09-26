import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure hardware-backed key storage
/// - iOS: Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly (never synced to iCloud)
/// - Android: Android Keystore with EncryptedSharedPreferences (StrongBox hardware backed where supported)
class SecureKeyStorage {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    aOptions: AndroidOptions(
      resetOnError: false,
    ),
  );

  // Key identifiers
  static const _kIdentityPrivateKey = 'metric_identity_private_key';
  static const _kIdentityPublicKey = 'metric_identity_public_key';
  static const _kRootKey = 'metric_ratchet_root_key';
  static const _kSendChainKey = 'metric_ratchet_send_chain_key';
  static const _kRecvChainKey = 'metric_ratchet_recv_chain_key';
  static const _kRemoteIdentityPublicKey = 'metric_remote_identity_public_key';
  static const _kPairedUid = 'metric_paired_device_uid';
  static const _kMyDeviceId = 'metric_my_device_uid';
  static const _kPairingComplete = 'metric_is_paired';
  static const _kBiometricsEnabled = 'metric_biometrics_enabled';
  static const _kAutoLockSeconds = 'metric_auto_lock_seconds';
  static const _kDisappearingTimerSeconds = 'metric_disappearing_timer_seconds';
  static const _kSecretKnockSequence = 'metric_secret_knock_sequence';

  // Identity Keys
  static Future<void> saveIdentityKeyPair({
    required String privateKeyHex,
    required String publicKeyHex,
  }) async {
    await _storage.write(key: _kIdentityPrivateKey, value: privateKeyHex);
    await _storage.write(key: _kIdentityPublicKey, value: publicKeyHex);
  }

  static Future<String?> getIdentityPrivateKey() =>
      _storage.read(key: _kIdentityPrivateKey);

  static Future<String?> getIdentityPublicKey() =>
      _storage.read(key: _kIdentityPublicKey);

  // Paired Peer Info
  static Future<void> savePairedPeer({
    required String peerUid,
    required String peerPublicKeyHex,
  }) async {
    await _storage.write(key: _kPairedUid, value: peerUid);
    await _storage.write(key: _kRemoteIdentityPublicKey, value: peerPublicKeyHex);
    await _storage.write(key: _kPairingComplete, value: 'true');
  }

  static Future<String?> getPairedUid() => _storage.read(key: _kPairedUid);

  static Future<String?> getRemoteIdentityPublicKey() =>
      _storage.read(key: _kRemoteIdentityPublicKey);

  static Future<bool> isPaired() async {
    final value = await _storage.read(key: _kPairingComplete);
    return value == 'true';
  }

  // Ratchet State Keys
  static Future<void> saveRatchetKeys({
    required String rootKeyHex,
    required String sendChainKeyHex,
    required String recvChainKeyHex,
  }) async {
    await _storage.write(key: _kRootKey, value: rootKeyHex);
    await _storage.write(key: _kSendChainKey, value: sendChainKeyHex);
    await _storage.write(key: _kRecvChainKey, value: recvChainKeyHex);
  }

  static Future<String?> getRootKey() => _storage.read(key: _kRootKey);
  static Future<String?> getSendChainKey() => _storage.read(key: _kSendChainKey);
  static Future<String?> getRecvChainKey() => _storage.read(key: _kRecvChainKey);

  // Device UID
  static Future<void> saveMyDeviceId(String uid) =>
      _storage.write(key: _kMyDeviceId, value: uid);

  static Future<String?> getMyDeviceId() => _storage.read(key: _kMyDeviceId);

  // Security Preferences
  static Future<bool> isBiometricsEnabled() async {
    final value = await _storage.read(key: _kBiometricsEnabled);
    return value != 'false'; // Enabled by default
  }

  static Future<void> setBiometricsEnabled(bool enabled) =>
      _storage.write(key: _kBiometricsEnabled, value: enabled.toString());

  static Future<int> getAutoLockSeconds() async {
    final value = await _storage.read(key: _kAutoLockSeconds);
    return value != null ? int.tryParse(value) ?? 30 : 30; // 30s default
  }

  static Future<void> setAutoLockSeconds(int seconds) =>
      _storage.write(key: _kAutoLockSeconds, value: seconds.toString());

  static Future<int> getDisappearingTimerSeconds() async {
    final value = await _storage.read(key: _kDisappearingTimerSeconds);
    return value != null ? int.tryParse(value) ?? 0 : 0; // 0 = off
  }

  static Future<void> setDisappearingTimerSeconds(int seconds) =>
      _storage.write(key: _kDisappearingTimerSeconds, value: seconds.toString());

  // Secret Knock Combination
  static Future<List<String>> getSecretKnockSequence() async {
    final value = await _storage.read(key: _kSecretKnockSequence);
    if (value != null && value.isNotEmpty) {
      final list = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    // Default secret sequence requested by user: Length -> Length -> Pressure
    return ['length', 'length', 'pressure'];
  }

  static Future<void> setSecretKnockSequence(List<String> sequence) =>
      _storage.write(key: _kSecretKnockSequence, value: sequence.join(','));

  // Wipe all keys (nuclear reset)
  static Future<void> clearAll() => _storage.deleteAll();
}
