import 'package:flutter/foundation.dart';
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

  static const _kIdentityPrivateKey = 'metric_identity_private_key';
  static const _kIdentityPublicKey = 'metric_identity_public_key';

  static const _kSigningPrivateKey = 'metric_signing_private_key';
  static const _kSigningPublicKey = 'metric_signing_public_key';

  static const _kSignedPrekeyPrivate = 'metric_signed_prekey_private';
  static const _kSignedPrekeyPublic = 'metric_signed_prekey_public';
  static const _kSignedPrekeyId = 'metric_signed_prekey_id';
  static const _kSignedPrekeySig = 'metric_signed_prekey_sig';

  static const _kOneTimePrekeyPrivate = 'metric_onetime_prekey_private';
  static const _kOneTimePrekeyPublic = 'metric_onetime_prekey_public';
  static const _kOneTimePrekeyId = 'metric_onetime_prekey_id';

  static const _kRootKey = 'metric_ratchet_root_key';
  static const _kSendChainKey = 'metric_ratchet_send_chain_key';
  static const _kRecvChainKey = 'metric_ratchet_recv_chain_key';

  // Remote/Peer Info
  static const _kPairedUid = 'metric_paired_device_uid';
  static const _kRemoteIdentityPublicKey = 'metric_remote_identity_public_key';
  static const _kRemoteSigningPublicKey = 'metric_remote_signing_public_key';
  static const _kRemoteSignedPrekey = 'metric_remote_signed_prekey';
  static const _kRemoteSignedPrekeyId = 'metric_remote_signed_prekey_id';
  static const _kRemoteOneTimePrekey = 'metric_remote_onetime_prekey';
  static const _kRemoteOneTimePrekeyId = 'metric_remote_onetime_prekey_id';

  static const _kMyDeviceId = 'metric_my_device_uid';
  static const _kPairingComplete = 'metric_is_paired';
  static const _kBiometricsEnabled = 'metric_biometrics_enabled';
  static const _kAutoLockSeconds = 'metric_auto_lock_seconds';
  static const _kDisappearingTimerSeconds = 'metric_disappearing_timer_seconds';
  static const _kSecretKnockSequence = 'metric_secret_knock_sequence';
  static const _kSafetyNumberVerified = 'metric_safety_number_verified';
  static const _kPasscode = 'metric_vault_passcode';

  // Google Drive Cloud Backup (Owner Only)
  static const _kIsOwnerDevice = 'metric_is_owner_device';
  static const _kHasPromptedDriveAuth = 'metric_has_prompted_drive_auth';
  static const _kLastDriveSyncTime = 'metric_last_drive_sync_time';
  static const _kDriveAccountEmail = 'metric_drive_account_email';
  static const _kDriveRootFolderId = 'metric_drive_root_folder_id';
  static const _kDriveBackupEnabled = 'metric_drive_backup_enabled';

  // --- Local Identity Keys ---
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

  // --- Local Ed25519 Signing Keys ---
  static Future<void> saveSigningKeyPair({
    required String privateKeyHex,
    required String publicKeyHex,
  }) async {
    await _storage.write(key: _kSigningPrivateKey, value: privateKeyHex);
    await _storage.write(key: _kSigningPublicKey, value: publicKeyHex);
  }

  static Future<String?> getSigningPrivateKey() =>
      _storage.read(key: _kSigningPrivateKey);

  static Future<String?> getSigningPublicKey() =>
      _storage.read(key: _kSigningPublicKey);

  // --- Local Prekeys ---
  static Future<void> saveLocalSignedPrekey({
    required String privateKeyHex,
    required String publicKeyHex,
    required int keyId,
    required String signatureHex,
  }) async {
    await _storage.write(key: _kSignedPrekeyPrivate, value: privateKeyHex);
    await _storage.write(key: _kSignedPrekeyPublic, value: publicKeyHex);
    await _storage.write(key: _kSignedPrekeyId, value: keyId.toString());
    await _storage.write(key: _kSignedPrekeySig, value: signatureHex);
  }

  static Future<String?> getSignedPrekeyPrivate() =>
      _storage.read(key: _kSignedPrekeyPrivate);
  static Future<String?> getSignedPrekeyPublic() =>
      _storage.read(key: _kSignedPrekeyPublic);
  static Future<String?> getSignedPrekeyId() =>
      _storage.read(key: _kSignedPrekeyId);
  static Future<String?> getSignedPrekeySig() =>
      _storage.read(key: _kSignedPrekeySig);

  static Future<void> saveLocalOneTimePrekey({
    required String privateKeyHex,
    required String publicKeyHex,
    required int keyId,
  }) async {
    await _storage.write(key: _kOneTimePrekeyPrivate, value: privateKeyHex);
    await _storage.write(key: _kOneTimePrekeyPublic, value: publicKeyHex);
    await _storage.write(key: _kOneTimePrekeyId, value: keyId.toString());
  }

  static Future<String?> getOneTimePrekeyPrivate() =>
      _storage.read(key: _kOneTimePrekeyPrivate);
  static Future<String?> getOneTimePrekeyPublic() =>
      _storage.read(key: _kOneTimePrekeyPublic);
  static Future<String?> getOneTimePrekeyId() =>
      _storage.read(key: _kOneTimePrekeyId);

  // --- Paired Peer Bundle Info ---
  static Future<void> savePairedPeerBundle({
    required String peerUid,
    required String peerIdentityPublicKey,
    required String peerSignedPrekey,
    required int peerSignedPrekeyId,
    String? peerSigningPublicKey,
    String? peerOneTimePrekey,
    int? peerOneTimePrekeyId,
  }) async {
    await _storage.write(key: _kPairedUid, value: peerUid);
    await _storage.write(key: _kRemoteIdentityPublicKey, value: peerIdentityPublicKey);
    await _storage.write(key: _kRemoteSignedPrekey, value: peerSignedPrekey);
    await _storage.write(key: _kRemoteSignedPrekeyId, value: peerSignedPrekeyId.toString());
    if (peerSigningPublicKey != null) {
      await _storage.write(key: _kRemoteSigningPublicKey, value: peerSigningPublicKey);
    }
    if (peerOneTimePrekey != null) {
      await _storage.write(key: _kRemoteOneTimePrekey, value: peerOneTimePrekey);
    }
    if (peerOneTimePrekeyId != null) {
      await _storage.write(key: _kRemoteOneTimePrekeyId, value: peerOneTimePrekeyId.toString());
    }
    await _storage.write(key: _kPairingComplete, value: 'true');
  }

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
  static Future<String?> getRemoteSigningPublicKey() =>
      _storage.read(key: _kRemoteSigningPublicKey);
  static Future<String?> getRemoteSignedPrekey() =>
      _storage.read(key: _kRemoteSignedPrekey);
  static Future<String?> getRemoteOneTimePrekey() =>
      _storage.read(key: _kRemoteOneTimePrekey);

  static Future<bool> isPaired() async {
    final value = await _storage.read(key: _kPairingComplete);
    return value == 'true';
  }

  // --- Ratchet State Keys ---
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

  // --- Device UID ---
  static Future<void> saveMyDeviceId(String uid) =>
      _storage.write(key: _kMyDeviceId, value: uid);

  static Future<String?> getMyDeviceId() => _storage.read(key: _kMyDeviceId);

  // --- Security Preferences ---
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

  // --- Secret Knock Combination ---
  static Future<List<String>> getSecretKnockSequence() async {
    final value = await _storage.read(key: _kSecretKnockSequence);
    if (value != null && value.isNotEmpty) {
      final list = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    // Default secret sequence: Length -> Length -> Pressure
    return ['length', 'length', 'pressure'];
  }

  static Future<void> setSecretKnockSequence(List<String> sequence) =>
      _storage.write(key: _kSecretKnockSequence, value: sequence.join(','));

  // --- Safety Number Verification ---
  static Future<bool> isSafetyNumberVerified() async {
    final value = await _storage.read(key: _kSafetyNumberVerified);
    return value == 'true';
  }

  static Future<void> setSafetyNumberVerified(bool verified) =>
      _storage.write(key: _kSafetyNumberVerified, value: verified.toString());

  // --- Vault Passcode ---
  static const _kDefaultPasscode = '1234';

  static Future<String> getPasscode() async {
    final value = await _storage.read(key: _kPasscode);
    return value ?? _kDefaultPasscode;
  }

  static Future<void> setPasscode(String newPasscode) =>
      _storage.write(key: _kPasscode, value: newPasscode);

  static Future<bool> verifyPasscode(String entered) async {
    final current = await getPasscode();
    return current == entered.trim();
  }

  static Future<bool> hasCustomPasscode() async {
    final value = await _storage.read(key: _kPasscode);
    return value != null && value.isNotEmpty;
  }

  // --- Debug Confirmation ---
  /// Debug-only check to log that both devices' public keys and UIDs are present
  static Future<Map<String, dynamic>> printDebugPairingStatus() async {
    final myUid = await getMyDeviceId();
    final myPub = await getIdentityPublicKey();
    final mySignedPub = await getSignedPrekeyPublic();
    final peerUid = await getPairedUid();
    final peerPub = await getRemoteIdentityPublicKey();
    final peerSigned = await getRemoteSignedPrekey();
    final paired = await isPaired();

    if (kDebugMode) {
      debugPrint('=====================================================');
      debugPrint('[METRIC DEBUG] SECURE STORAGE PAIRING VERIFICATION:');
      debugPrint('  My UID:             $myUid');
      debugPrint('  My Identity Public: ${myPub != null ? "${myPub.substring(0, 16)}..." : "MISSING"}');
      debugPrint('  My Signed Prekey:   ${mySignedPub != null ? "${mySignedPub.substring(0, 16)}..." : "MISSING"}');
      debugPrint('  Peer UID:           $peerUid');
      debugPrint('  Peer Identity Pub:  ${peerPub != null ? "${peerPub.substring(0, 16)}..." : "MISSING"}');
      debugPrint('  Peer Signed Prekey: ${peerSigned != null ? "${peerSigned.substring(0, 16)}..." : "MISSING"}');
      debugPrint('  Paired Status:      $paired');
      debugPrint('=====================================================');
    }

    return {
      'myUid': myUid,
      'myPublicKey': myPub,
      'peerUid': peerUid,
      'peerPublicKey': peerPub,
      'peerSignedPrekey': peerSigned,
      'isPaired': paired,
    };
  }

  // --- Google Drive Backup Accessors ---
  static Future<bool> isOwnerDevice() async {
    final val = await _storage.read(key: _kIsOwnerDevice);
    if (val == null) return true; // Default to owner device
    return val == 'true';
  }

  static Future<void> setIsOwnerDevice(bool isOwner) =>
      _storage.write(key: _kIsOwnerDevice, value: isOwner.toString());

  static Future<bool> hasPromptedDriveAuth() async {
    final val = await _storage.read(key: _kHasPromptedDriveAuth);
    return val == 'true';
  }

  static Future<void> setHasPromptedDriveAuth(bool prompted) =>
      _storage.write(key: _kHasPromptedDriveAuth, value: prompted.toString());

  static Future<String?> getDriveAccountEmail() =>
      _storage.read(key: _kDriveAccountEmail);

  static Future<void> setDriveAccountEmail(String? email) async {
    if (email == null) {
      await _storage.delete(key: _kDriveAccountEmail);
    } else {
      await _storage.write(key: _kDriveAccountEmail, value: email);
    }
  }

  static Future<int?> getLastDriveSyncTime() async {
    final val = await _storage.read(key: _kLastDriveSyncTime);
    return val != null ? int.tryParse(val) : null;
  }

  static Future<void> setLastDriveSyncTime(int timestamp) =>
      _storage.write(key: _kLastDriveSyncTime, value: timestamp.toString());

  static Future<String?> getDriveRootFolderId() =>
      _storage.read(key: _kDriveRootFolderId);

  static Future<void> setDriveRootFolderId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _kDriveRootFolderId);
    } else {
      await _storage.write(key: _kDriveRootFolderId, value: id);
    }
  }

  static Future<bool> isDriveBackupEnabled() async {
    final val = await _storage.read(key: _kDriveBackupEnabled);
    return val == 'true';
  }

  static Future<void> setDriveBackupEnabled(bool enabled) =>
      _storage.write(key: _kDriveBackupEnabled, value: enabled.toString());

  // Wipe all keys (nuclear reset)
  static Future<void> clearAll() => _storage.deleteAll();
}
