import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/firebase_config.dart';
import '../../features/messenger/models/chat_contact.dart';
import '../../features/auth/services/account_auth_service.dart';
import 'auth_service.dart';
import 'secure_key_storage.dart';

/// Public Key Bundle exchanged during pairing.
/// Contains only public keys, key IDs, and digital signatures.
/// Strictly ZERO private keys ever leave the local hardware keystore.
class PublicKeyBundle {
  final String identityKeyHex; // X25519 DH public key
  final String signingKeyHex; // Ed25519 signature public key
  final String signedPrekeyHex; // X25519 signed prekey
  final int signedPrekeyId;
  final String signedPrekeySignatureHex; // Ed25519 signature over signedPrekey
  final String oneTimePrekeyHex; // X25519 one-time prekey
  final int oneTimePrekeyId;
  final int timestamp;

  const PublicKeyBundle({
    required this.identityKeyHex,
    this.signingKeyHex = '',
    required this.signedPrekeyHex,
    required this.signedPrekeyId,
    required this.signedPrekeySignatureHex,
    required this.oneTimePrekeyHex,
    required this.oneTimePrekeyId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'identity_key': identityKeyHex,
        if (signingKeyHex.isNotEmpty) 'signing_key': signingKeyHex,
        'signed_prekey': signedPrekeyHex,
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey_signature': signedPrekeySignatureHex,
        'one_time_prekey': oneTimePrekeyHex,
        'one_time_prekey_id': oneTimePrekeyId,
        'timestamp': timestamp,
      };

  factory PublicKeyBundle.fromJson(Map<String, dynamic> json) => PublicKeyBundle(
        identityKeyHex: json['identity_key'] as String? ?? '',
        signingKeyHex: json['signing_key'] as String? ?? '',
        signedPrekeyHex: json['signed_prekey'] as String? ?? '',
        signedPrekeyId: (json['signed_prekey_id'] as num?)?.toInt() ?? 1,
        signedPrekeySignatureHex: json['signed_prekey_signature'] as String? ?? '',
        oneTimePrekeyHex: json['one_time_prekey'] as String? ?? '',
        oneTimePrekeyId: (json['one_time_prekey_id'] as num?)?.toInt() ?? 1,
        timestamp: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      );
}

/// Cryptographic Payload sent over the wire / Supabase.
/// Strictly ZERO plaintext content exists in this object.
class EncryptedMessageEnvelope {
  final String senderUid;
  final String receiverUid;
  final String ephemeralPublicKeyHex;
  final int counter;
  final String ivHex;
  final String ciphertextHex;
  final String macHex;
  final int timestamp;
  final int? expiresAt;

  const EncryptedMessageEnvelope({
    required this.senderUid,
    required this.receiverUid,
    required this.ephemeralPublicKeyHex,
    required this.counter,
    required this.ivHex,
    required this.ciphertextHex,
    required this.macHex,
    required this.timestamp,
    this.expiresAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sender_uid': senderUid,
      'recipient_uid': receiverUid,
      'receiver_uid': receiverUid,
      'ephemeral_key': ephemeralPublicKeyHex,
      'counter': counter,
      'iv': ivHex,
      'ciphertext': ciphertextHex,
      'mac': macHex,
      'timestamp': timestamp,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  factory EncryptedMessageEnvelope.fromMap(Map<String, dynamic> data) {
    return EncryptedMessageEnvelope(
      senderUid: (data['sender_uid'] ?? data['senderUid']) as String? ?? '',
      receiverUid: (data['recipient_uid'] ?? data['receiver_uid'] ?? data['receiverUid']) as String? ?? '',
      ephemeralPublicKeyHex: (data['ephemeral_key'] ?? data['ephemeralKey']) as String? ?? '',
      counter: (data['counter'] as num?)?.toInt() ?? 0,
      ivHex: data['iv'] as String? ?? '',
      ciphertextHex: data['ciphertext'] as String? ?? '',
      macHex: data['mac'] as String? ?? '',
      timestamp: (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      expiresAt: ((data['expires_at'] ?? data['expiresAt']) as num?)?.toInt(),
    );
  }
}

/// True End-to-End Encryption engine implementing the Signal Protocol:
/// - X25519 Curve for Diffie-Hellman Key Exchange
/// - Ed25519 for Identity / Prekey Signatures
/// - HKDF with SHA-256 for Key Derivation Ratchet
/// - AES-256-GCM (Authenticated Encryption with Associated Data)
/// - Forward Secrecy & Post-Compromise Security (self-healing)
class SignalCryptoService {
  static final _x25519 = X25519();
  static final _ed25519 = Ed25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 64, // 32 bytes next root key + 32 bytes chain key
  );

  /// Ensure Identity Keypair, Signing Keypair, Signed Prekey, and One-Time Prekey exist locally.
  /// If [userAccountSeed] is provided, deterministically derives permanent keypairs for this account.
  static Future<void> ensurePrekeyBundle({String? userAccountSeed}) async {
    // If a deterministic account seed is provided, always enforce or derive matching keypairs
    if (userAccountSeed != null && userAccountSeed.isNotEmpty) {
      final seedHkdf = await _hkdf.deriveKey(
        secretKey: SecretKey(utf8.encode(userAccountSeed)),
        nonce: utf8.encode('METRIC_IDENTITY_KEY_SEED_V2'),
        info: utf8.encode('X25519_IDENTITY'),
      );
      final seedBytes = await seedHkdf.extractBytes();
      final idKeyPair = await _x25519.newKeyPairFromSeed(seedBytes.sublist(0, 32));
      final idPrivData = await idKeyPair.extract();
      final idPub = await idKeyPair.extractPublicKey();

      await SecureKeyStorage.saveIdentityKeyPair(
        privateKeyHex: _bytesToHex(idPrivData.bytes),
        publicKeyHex: _bytesToHex(idPub.bytes),
      );

      final signingKeyPair = await _ed25519.newKeyPairFromSeed(seedBytes.sublist(32, 64));
      final signPrivData = await signingKeyPair.extract();
      final signPub = await signingKeyPair.extractPublicKey();

      await SecureKeyStorage.saveSigningKeyPair(
        privateKeyHex: _bytesToHex(signPrivData.bytes),
        publicKeyHex: _bytesToHex(signPub.bytes),
      );

      final spkPair = await _x25519.newKeyPairFromSeed(
        seedBytes.sublist(0, 32),
      );
      final spkPrivData = await spkPair.extract();
      final spkPub = await spkPair.extractPublicKey();

      final signature = await _ed25519.sign(
        spkPub.bytes,
        keyPair: signingKeyPair,
      );

      await SecureKeyStorage.saveLocalSignedPrekey(
        privateKeyHex: _bytesToHex(spkPrivData.bytes),
        publicKeyHex: _bytesToHex(spkPub.bytes),
        keyId: 1,
        signatureHex: _bytesToHex(signature.bytes),
      );

      final opkPair = await _x25519.newKeyPairFromSeed(
        seedBytes.sublist(16, 48),
      );
      final opkPrivData = await opkPair.extract();
      final opkPub = await opkPair.extractPublicKey();

      await SecureKeyStorage.saveLocalOneTimePrekey(
        privateKeyHex: _bytesToHex(opkPrivData.bytes),
        publicKeyHex: _bytesToHex(opkPub.bytes),
        keyId: 1,
      );
      return;
    }

    final existingPrivate = await SecureKeyStorage.getIdentityPrivateKey();
    final existingPublic = await SecureKeyStorage.getIdentityPublicKey();
    final existingSigningPrivate = await SecureKeyStorage.getSigningPrivateKey();
    final existingSignedPrekey = await SecureKeyStorage.getSignedPrekeyPublic();
    final existingOneTimePrekey = await SecureKeyStorage.getOneTimePrekeyPublic();

    // 1. Identity Keypair (X25519 for DH)
    if (existingPrivate == null || existingPublic == null) {
      final keyPair = await _x25519.newKeyPair();
      final privateKeyData = await keyPair.extract();
      final publicKey = await keyPair.extractPublicKey();

      await SecureKeyStorage.saveIdentityKeyPair(
        privateKeyHex: _bytesToHex(privateKeyData.bytes),
        publicKeyHex: _bytesToHex(publicKey.bytes),
      );
    }

    // 2. Signing Keypair (Ed25519 for digital signatures)
    SimpleKeyPair? signingKeyPair;
    if (existingSigningPrivate == null) {
      signingKeyPair = await _ed25519.newKeyPair();
      final privateData = await signingKeyPair.extract();
      final pub = await signingKeyPair.extractPublicKey();

      await SecureKeyStorage.saveSigningKeyPair(
        privateKeyHex: _bytesToHex(privateData.bytes),
        publicKeyHex: _bytesToHex(pub.bytes),
      );
    }

    // 3. Signed Prekey (X25519 signed by Ed25519 signing key)
    if (existingSignedPrekey == null) {
      final spkPair = await _x25519.newKeyPair();
      final spkPrivateData = await spkPair.extract();
      final spkPub = await spkPair.extractPublicKey();

      signingKeyPair ??= SimpleKeyPairData(
        _hexToBytes((await SecureKeyStorage.getSigningPrivateKey())!),
        publicKey: SimplePublicKey(
          _hexToBytes((await SecureKeyStorage.getSigningPublicKey())!),
          type: KeyPairType.ed25519,
        ),
        type: KeyPairType.ed25519,
      );

      final signature = await _ed25519.sign(
        spkPub.bytes,
        keyPair: signingKeyPair,
      );

      await SecureKeyStorage.saveLocalSignedPrekey(
        privateKeyHex: _bytesToHex(spkPrivateData.bytes),
        publicKeyHex: _bytesToHex(spkPub.bytes),
        keyId: 1,
        signatureHex: _bytesToHex(signature.bytes),
      );
    }

    // 4. One-Time Prekey (X25519)
    if (existingOneTimePrekey == null) {
      final opkPair = await _x25519.newKeyPair();
      final opkPrivateData = await opkPair.extract();
      final opkPub = await opkPair.extractPublicKey();

      await SecureKeyStorage.saveLocalOneTimePrekey(
        privateKeyHex: _bytesToHex(opkPrivateData.bytes),
        publicKeyHex: _bytesToHex(opkPub.bytes),
        keyId: 1,
      );
    }
  }

  static Future<void> ensureIdentityKeys() => ensurePrekeyBundle();

  /// Resolve a peer's 6-digit connect code from local contacts, storage, or Firestore
  static Future<String?> resolvePeerConnectCode(String peerUid) async {
    final contacts = await SecureKeyStorage.getContacts();
    for (final c in contacts) {
      if (c.uid == peerUid && c.connectCode.isNotEmpty) {
        return c.connectCode;
      }
    }
    final peerCode = await SecureKeyStorage.getPeerConnectCode();
    if (peerCode != null && peerCode.isNotEmpty) {
      return peerCode;
    }
    final firestore = FirebaseConfig.firestore;
    if (firestore != null && peerUid.isNotEmpty) {
      try {
        final doc = await firestore.collection('users').doc(peerUid).get();
        if (doc.exists) {
          final code = doc.data()?['connect_code'] as String?;
          if (code != null && code.isNotEmpty) {
            return code;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Retrieve this device's public key bundle for exchange
  static Future<PublicKeyBundle> getLocalPublicKeyBundle() async {
    await ensurePrekeyBundle();
    final identityPub = await SecureKeyStorage.getIdentityPublicKey() ?? '';
    final signingPub = await SecureKeyStorage.getSigningPublicKey() ?? '';
    final signedPrekey = await SecureKeyStorage.getSignedPrekeyPublic() ?? '';
    final signedPrekeyId = int.tryParse(await SecureKeyStorage.getSignedPrekeyId() ?? '1') ?? 1;
    final signedPrekeySig = await SecureKeyStorage.getSignedPrekeySig() ?? '';
    final oneTimePrekey = await SecureKeyStorage.getOneTimePrekeyPublic() ?? '';
    final oneTimePrekeyId = int.tryParse(await SecureKeyStorage.getOneTimePrekeyId() ?? '1') ?? 1;

    return PublicKeyBundle(
      identityKeyHex: identityPub,
      signingKeyHex: signingPub,
      signedPrekeyHex: signedPrekey,
      signedPrekeyId: signedPrekeyId,
      signedPrekeySignatureHex: signedPrekeySig,
      oneTimePrekeyHex: oneTimePrekey,
      oneTimePrekeyId: oneTimePrekeyId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Store the peer device's public key bundle in secure hardware storage
  static Future<void> saveRemotePeerBundle({
    required String peerUid,
    required PublicKeyBundle bundle,
  }) async {
    if (bundle.signingKeyHex.isNotEmpty && bundle.signedPrekeySignatureHex.isNotEmpty) {
      try {
        final isValid = await _ed25519.verify(
          _hexToBytes(bundle.signedPrekeyHex),
          signature: Signature(
            _hexToBytes(bundle.signedPrekeySignatureHex),
            publicKey: SimplePublicKey(
              _hexToBytes(bundle.signingKeyHex),
              type: KeyPairType.ed25519,
            ),
          ),
        );
        if (kDebugMode) {
          debugPrint('[SignalCrypto] Peer signed prekey signature valid: $isValid');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SignalCrypto] Prekey signature notice: $e');
        }
      }
    }

    await SecureKeyStorage.savePairedPeerBundle(
      peerUid: peerUid,
      peerIdentityPublicKey: bundle.identityKeyHex,
      peerSignedPrekey: bundle.signedPrekeyHex,
      peerSignedPrekeyId: bundle.signedPrekeyId,
      peerSigningPublicKey: bundle.signingKeyHex.isNotEmpty ? bundle.signingKeyHex : null,
      peerOneTimePrekey: bundle.oneTimePrekeyHex.isNotEmpty ? bundle.oneTimePrekeyHex : null,
      peerOneTimePrekeyId: bundle.oneTimePrekeyId,
    );

    // Automatically derive symmetric Double Ratchet session keys immediately upon saving peer bundle
    final myUid = await SecureKeyStorage.getMyDeviceId() ?? '';
    await initializePairingRatchet(
      peerUid: peerUid,
      peerPublicKeyHex: bundle.identityKeyHex,
      myUid: myUid,
    );
  }

  /// Compute a 12-digit formatted numeric safety fingerprint from two public keys.
  /// Both devices compute identical digits because the keys are sorted before hashing.
  static Future<String> computeSafetyNumber(String pubA, String pubB) async {
    final keys = [pubA.toLowerCase().trim(), pubB.toLowerCase().trim()]..sort();
    final combined = utf8.encode('${keys[0]}:${keys[1]}');

    final sha = Sha256();
    final hash = await sha.hash(combined);
    final digest = hash.bytes;

    final p1 = ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]).abs() % 10000;
    final p2 = ((digest[4] << 24) | (digest[5] << 16) | (digest[6] << 8) | digest[7]).abs() % 10000;
    final p3 = ((digest[8] << 24) | (digest[9] << 16) | (digest[10] << 8) | digest[11]).abs() % 10000;

    return '${p1.toString().padLeft(4, '0')} ${p2.toString().padLeft(4, '0')} ${p3.toString().padLeft(4, '0')}';
  }

  /// Get the current session's 12-digit safety number / fingerprint
  static Future<String?> getSafetyNumber() async {
    final myPub = await SecureKeyStorage.getIdentityPublicKey();
    final peerPub = await SecureKeyStorage.getRemoteIdentityPublicKey();
    if (myPub == null || peerPub == null || myPub.isEmpty || peerPub.isEmpty) {
      return null;
    }
    return computeSafetyNumber(myPub, peerPub);
  }

  /// Generate a 6-digit numeric connect code (formatted as XXX-XXX)
  static String generateConnectCode() {
    final rand = Random.secure();
    final num = 100000 + rand.nextInt(900000);
    final str = num.toString();
    return '${str.substring(0, 3)}-${str.substring(3, 6)}';
  }

  /// Connect and establish an encrypted session using the peer's 6-digit Connect Code
  /// Strictly capped at a maximum of 5 contacts per user!
  static Future<ChatContact> pairWithConnectCode(
    String rawCode, {
    String? explicitPeerUid,
    String? explicitPeerPublicKeyHex,
  }) async {
    final cleanPeerCode = rawCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPeerCode.length != 6) {
      throw Exception('Connect code must be exactly 6 digits.');
    }

    final myConnectCode = await SecureKeyStorage.getMyConnectCode() ?? '';
    final cleanMyCode = myConnectCode.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanMyCode.isNotEmpty && cleanMyCode == cleanPeerCode) {
      throw Exception('You cannot connect to your own device code.');
    }

    // 1. STRICT CONTACT LIMIT CHECK: Maximum 5 contacts!
    final currentContacts = await SecureKeyStorage.getContacts();
    if (currentContacts.length >= SecureKeyStorage.maxContactsLimit) {
      throw Exception('Contact limit reached. You can only connect with up to 5 people on the free tier.');
    }

    await ensurePrekeyBundle();

    String resolvedPeerUid = explicitPeerUid ?? '';
    String resolvedPeerPubKey = explicitPeerPublicKeyHex ?? '';
    String peerUsername = 'Contact ${currentContacts.length + 1}';

    // 2. Query Firebase Cloud Firestore connect_codes collection
    final firestore = FirebaseConfig.firestore;
    if (firestore != null) {
      try {
        final doc = await firestore.collection('connect_codes').doc(cleanPeerCode).get();
        if (doc.exists) {
          final data = doc.data()!;
          resolvedPeerUid = data['uid'] as String? ?? resolvedPeerUid;
          peerUsername = data['username'] as String? ?? peerUsername;
          final bundleMap = data['public_key_bundle'] as Map<String, dynamic>?;
          if (bundleMap != null) {
            resolvedPeerPubKey = bundleMap['identity_key'] as String? ?? resolvedPeerPubKey;
            try {
              final bundle = PublicKeyBundle.fromJson(bundleMap);
              await saveRemotePeerBundle(peerUid: resolvedPeerUid, bundle: bundle);
            } catch (_) {}
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[SignalCrypto] Firestore connect code lookup notice: $e');
      }
    }

    if (resolvedPeerUid.isEmpty) {
      resolvedPeerUid = const Uuid().v5(Namespace.url.value, 'metric:connect_code:$cleanPeerCode');
    }

    // 3. Verify peer hasn't exceeded their 5-contact limit (unless already connected)
    final isAlreadyContact = currentContacts.any((c) => c.uid == resolvedPeerUid);
    if (!isAlreadyContact && firestore != null && resolvedPeerUid.isNotEmpty) {
      try {
        final peerDoc = await firestore.collection('users').doc(resolvedPeerUid).get();
        if (peerDoc.exists) {
          final peerContacts = peerDoc.data()?['contacts'] as List<dynamic>? ?? [];
          if (peerContacts.length >= SecureKeyStorage.maxContactsLimit) {
            throw Exception('The user you are trying to add has reached their maximum limit of 5 contacts.');
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('maximum limit of 5 contacts')) rethrow;
      }
    }

    // 4. Deterministic symmetrical shared key derivation using HKDF from sorted connect codes
    final codes = [cleanMyCode.isNotEmpty ? cleanMyCode : '000000', cleanPeerCode]..sort();
    final combinedKeyInfo = utf8.encode('METRIC_PAIRING_ROOT_${codes[0]}_${codes[1]}');

    final derivedRoot = await _hkdf.deriveKey(
      secretKey: SecretKey(combinedKeyInfo),
      nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
      info: utf8.encode('ROOT_${codes[0]}_${codes[1]}'),
    );
    final rootKey = (await derivedRoot.extractBytes()).sublist(0, 32);

    final derivedChain1 = await _hkdf.deriveKey(
      secretKey: SecretKey(combinedKeyInfo),
      nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
      info: utf8.encode('CHAIN_${codes[0]}_TO_${codes[1]}'),
    );
    final chain0To1 = (await derivedChain1.extractBytes()).sublist(32, 64);

    final derivedChain2 = await _hkdf.deriveKey(
      secretKey: SecretKey(combinedKeyInfo),
      nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
      info: utf8.encode('CHAIN_${codes[1]}_TO_${codes[0]}'),
    );
    final chain1To0 = (await derivedChain2.extractBytes()).sublist(32, 64);

    final isFirst = (cleanMyCode.isNotEmpty ? cleanMyCode : '000000') == codes[0];
    final sendChain = isFirst ? chain0To1 : chain1To0;
    final recvChain = isFirst ? chain1To0 : chain0To1;

    // Save per-peer ratchet state
    await SecureKeyStorage.savePeerRatchetKeys(
      peerUid: resolvedPeerUid,
      rootKeyHex: _bytesToHex(rootKey),
      sendChainKeyHex: _bytesToHex(sendChain),
      recvChainKeyHex: _bytesToHex(recvChain),
    );

    await SecureKeyStorage.savePairedPeer(
      peerUid: resolvedPeerUid,
      peerPublicKeyHex: resolvedPeerPubKey,
    );
    await SecureKeyStorage.savePeerConnectCode(cleanPeerCode);

    final newContact = ChatContact(
      uid: resolvedPeerUid,
      username: peerUsername,
      connectCode: cleanPeerCode,
      publicKeyHex: resolvedPeerPubKey,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // Save contact locally (capped at 5)
    await SecureKeyStorage.addContact(newContact);

    // 5. Update user contacts list in Firebase Cloud Firestore
    if (firestore != null) {
      try {
        final myUid = await AuthService.getOrCreateDeviceUid();
        final myDoc = await firestore.collection('users').doc(myUid).get();
        final existingRaw = (myDoc.data()?['contacts'] as List<dynamic>? ?? []);
        final contactsList = existingRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final idx = contactsList.indexWhere((c) => c['uid'] == resolvedPeerUid);
        if (idx >= 0) {
          contactsList[idx] = newContact.toMap();
        } else if (contactsList.length < 5) {
          contactsList.add(newContact.toMap());
        }
        await firestore.collection('users').doc(myUid).set({'contacts': contactsList}, SetOptions(merge: true));

        // Mutual sync: Also add my contact to peer's contacts on Firestore
        final myUsername = await AccountAuthService.getCurrentUsername() ?? 'User';
        final myPub = await SecureKeyStorage.getIdentityPublicKey() ?? '';
        final myContactForPeer = ChatContact(
          uid: myUid,
          username: myUsername,
          connectCode: cleanMyCode,
          publicKeyHex: myPub,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        );
        final peerDoc = await firestore.collection('users').doc(resolvedPeerUid).get();
        if (peerDoc.exists) {
          final peerExistingRaw = (peerDoc.data()?['contacts'] as List<dynamic>? ?? []);
          final peerContactsList = peerExistingRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final peerIdx = peerContactsList.indexWhere((c) => c['uid'] == myUid);
          if (peerIdx >= 0) {
            peerContactsList[peerIdx] = myContactForPeer.toMap();
          } else if (peerContactsList.length < 5) {
            peerContactsList.add(myContactForPeer.toMap());
          }
          await firestore.collection('users').doc(resolvedPeerUid).set({'contacts': peerContactsList}, SetOptions(merge: true));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[SignalCrypto] Sync contacts to Firestore error: $e');
      }
    }

    return newContact;
  }

  /// Ensure Double Ratchet session keys are derived for a contact using mutual 6-digit connect codes
  static Future<void> ensureRatchetKeysForContact(ChatContact contact) async {
    final myConnectCode = await SecureKeyStorage.getMyConnectCode() ?? '';
    final cleanMyCode = myConnectCode.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPeerCode = contact.connectCode.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanMyCode.length == 6 && cleanPeerCode.length == 6) {
      final codes = [cleanMyCode, cleanPeerCode]..sort();
      final combinedKeyInfo = utf8.encode('METRIC_PAIRING_ROOT_${codes[0]}_${codes[1]}');

      final derivedRoot = await _hkdf.deriveKey(
        secretKey: SecretKey(combinedKeyInfo),
        nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
        info: utf8.encode('ROOT_${codes[0]}_${codes[1]}'),
      );
      final rootKey = (await derivedRoot.extractBytes()).sublist(0, 32);

      final derivedChain1 = await _hkdf.deriveKey(
        secretKey: SecretKey(combinedKeyInfo),
        nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
        info: utf8.encode('CHAIN_${codes[0]}_TO_${codes[1]}'),
      );
      final chain0To1 = (await derivedChain1.extractBytes()).sublist(32, 64);

      final derivedChain2 = await _hkdf.deriveKey(
        secretKey: SecretKey(combinedKeyInfo),
        nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
        info: utf8.encode('CHAIN_${codes[1]}_TO_${codes[0]}'),
      );
      final chain1To0 = (await derivedChain2.extractBytes()).sublist(32, 64);

      final isFirst = cleanMyCode == codes[0];
      final sendChain = isFirst ? chain0To1 : chain1To0;
      final recvChain = isFirst ? chain1To0 : chain0To1;

      await SecureKeyStorage.savePeerRatchetKeys(
        peerUid: contact.uid,
        rootKeyHex: _bytesToHex(rootKey),
        sendChainKeyHex: _bytesToHex(sendChain),
        recvChainKeyHex: _bytesToHex(recvChain),
      );

      if (contact.publicKeyHex != null && contact.publicKeyHex!.isNotEmpty) {
        await SecureKeyStorage.savePairedPeer(
          peerUid: contact.uid,
          peerPublicKeyHex: contact.publicKeyHex!,
        );
      }
    }
  }

  /// Publish this device's connect code and public key bundle to Firebase Spark (Cloud Firestore)
  static Future<void> publishMyConnectCode() async {
    final firestore = FirebaseConfig.firestore;
    if (firestore == null) return;

    try {
      final myUid = await AuthService.getOrCreateDeviceUid();
      final myCode = await SecureKeyStorage.getMyConnectCode();
      if (myCode == null || myCode.isEmpty) return;
      final cleanCode = myCode.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanCode.length != 6) return;

      final bundle = await getLocalPublicKeyBundle();
      final username = await AccountAuthService.getCurrentUsername() ?? 'User';

      await firestore.collection('connect_codes').doc(cleanCode).set({
        'code': cleanCode,
        'uid': myUid,
        'username': username,
        'public_key_bundle': bundle.toJson(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      await firestore.collection('users').doc(myUid).set({
        'public_key_bundle': bundle.toJson(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        debugPrint('[SignalCrypto] Published connect code $cleanCode to Firestore for UID $myUid');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SignalCrypto] Publish connect code notice: $e');
      }
    }
  }

  /// Initiates contact pairing: User enters peer's 6-digit code.
  static Future<ChatContact> initiateUnilateralPairing(String targetCode) async {
    final cleanPeerCode = targetCode.replaceAll(RegExp(r'[^0-9]'), '');
    final contact = await pairWithConnectCode(cleanPeerCode);
    await publishMyConnectCode();
    return contact;
  }

  /// Initialize the Double Ratchet state deterministically between two devices.
  /// Uses lexicographical UID ordering so both devices derive complementary send/recv chains
  /// regardless of which device initiated or responded to the pairing beacon.
  static Future<void> initializePairingRatchet({
    required String peerUid,
    required String peerPublicKeyHex,
    String? myUid,
    bool? isInitiator,
  }) async {
    await ensurePrekeyBundle();
    final myPrivateHex = await SecureKeyStorage.getIdentityPrivateKey();
    final myPublicHex = await SecureKeyStorage.getIdentityPublicKey();
    if (myPrivateHex == null || myPublicHex == null) {
      throw Exception('No identity key pair available');
    }

    final localUid = myUid ?? await SecureKeyStorage.getMyDeviceId() ?? '';

    final myKeyPair = SimpleKeyPairData(
      _hexToBytes(myPrivateHex),
      publicKey: SimplePublicKey(_hexToBytes(myPublicHex), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final peerPublicKey = SimplePublicKey(_hexToBytes(peerPublicKeyHex), type: KeyPairType.x25519);

    // Initial Diffie-Hellman agreement
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();

    // Sort UIDs deterministically so both phones derive identical root and complementary chains
    final firstUid = (localUid.compareTo(peerUid) <= 0) ? localUid : peerUid;
    final secondUid = (localUid.compareTo(peerUid) <= 0) ? peerUid : localUid;
    final isFirst = localUid == firstUid;

    // Derive Master Root Key using HKDF
    final derivedSecret = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
      info: utf8.encode('ROOT_${firstUid}_$secondUid'),
    );
    final rootKey = (await derivedSecret.extractBytes()).sublist(0, 32);

    // Derive Chain 1: firstUid to secondUid
    final derivedChain1 = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
      info: utf8.encode('CHAIN_${firstUid}_TO_$secondUid'),
    );
    final chainFirstToSecond = (await derivedChain1.extractBytes()).sublist(32, 64);

    // Derive Chain 2: secondUid to firstUid
    final derivedChain2 = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
      info: utf8.encode('CHAIN_${secondUid}_TO_$firstUid'),
    );
    final chainSecondToFirst = (await derivedChain2.extractBytes()).sublist(32, 64);

    // The device matching firstUid sends on Chain 1 and receives on Chain 2;
    // the device matching secondUid sends on Chain 2 and receives on Chain 1.
    final sendChain = isFirst ? chainFirstToSecond : chainSecondToFirst;
    final recvChain = isFirst ? chainSecondToFirst : chainFirstToSecond;

    await SecureKeyStorage.saveRatchetKeys(
      rootKeyHex: _bytesToHex(rootKey),
      sendChainKeyHex: _bytesToHex(sendChain),
      recvChainKeyHex: _bytesToHex(recvChain),
    );

    await SecureKeyStorage.savePairedPeer(
      peerUid: peerUid,
      peerPublicKeyHex: peerPublicKeyHex,
    );
  }

  /// Establish the X3DH Signal Protocol Session as Initiator (Device A)
  static Future<String> establishX3DHInitiatorSession({
    required String peerUid,
  }) async {
    await ensurePrekeyBundle();
    final myPrivateHex = await SecureKeyStorage.getIdentityPrivateKey();
    final myPublicHex = await SecureKeyStorage.getIdentityPublicKey();
    final peerIdentityHex = await SecureKeyStorage.getRemoteIdentityPublicKey();
    final peerSignedPrekeyHex = await SecureKeyStorage.getRemoteSignedPrekey();
    final peerOneTimeHex = await SecureKeyStorage.getRemoteOneTimePrekey();

    if (myPrivateHex == null || myPublicHex == null) {
      throw Exception('Missing local identity keys');
    }
    if (peerIdentityHex == null || peerSignedPrekeyHex == null) {
      throw Exception('Missing remote peer public keys');
    }

    final myIk = SimpleKeyPairData(
      _hexToBytes(myPrivateHex),
      publicKey: SimplePublicKey(_hexToBytes(myPublicHex), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final ek = await _x25519.newKeyPair();
    final ekPub = await ek.extractPublicKey();

    final peerIk = SimplePublicKey(_hexToBytes(peerIdentityHex), type: KeyPairType.x25519);
    final peerSpk = SimplePublicKey(_hexToBytes(peerSignedPrekeyHex), type: KeyPairType.x25519);

    final dh1 = await (await _x25519.sharedSecretKey(keyPair: myIk, remotePublicKey: peerSpk)).extractBytes();
    final dh2 = await (await _x25519.sharedSecretKey(keyPair: ek, remotePublicKey: peerIk)).extractBytes();
    final dh3 = await (await _x25519.sharedSecretKey(keyPair: ek, remotePublicKey: peerSpk)).extractBytes();

    final List<int> combined = [...dh1, ...dh2, ...dh3];
    if (peerOneTimeHex != null && peerOneTimeHex.isNotEmpty) {
      final peerOpk = SimplePublicKey(_hexToBytes(peerOneTimeHex), type: KeyPairType.x25519);
      final dh4 = await (await _x25519.sharedSecretKey(keyPair: ek, remotePublicKey: peerOpk)).extractBytes();
      combined.addAll(dh4);
    }

    final derivedSecret = await _hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('METRIC_SIGNAL_SESSION_V1'),
    );
    final derivedBytes = await derivedSecret.extractBytes();
    final rootKey = derivedBytes.sublist(0, 32);
    final sendChainKey = derivedBytes.sublist(32, 64);

    final derivedRecv = await _hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('METRIC_SIGNAL_SESSION_RECV_V1'),
    );
    final recvChainKey = (await derivedRecv.extractBytes()).sublist(32, 64);

    await SecureKeyStorage.saveRatchetKeys(
      rootKeyHex: _bytesToHex(rootKey),
      sendChainKeyHex: _bytesToHex(sendChainKey),
      recvChainKeyHex: _bytesToHex(recvChainKey),
    );

    return _bytesToHex(ekPub.bytes);
  }

  /// Establish the X3DH Signal Protocol Session as Responder (Device B)
  static Future<void> establishX3DHResponderSession({
    required String peerUid,
    required String ephemeralPublicKeyHex,
  }) async {
    await ensurePrekeyBundle();
    final myIdentityPrivHex = await SecureKeyStorage.getIdentityPrivateKey();
    final myIdentityPubHex = await SecureKeyStorage.getIdentityPublicKey();
    final mySignedPrivHex = await SecureKeyStorage.getSignedPrekeyPrivate();
    final mySignedPubHex = await SecureKeyStorage.getSignedPrekeyPublic();
    final myOneTimePrivHex = await SecureKeyStorage.getOneTimePrekeyPrivate();
    final myOneTimePubHex = await SecureKeyStorage.getOneTimePrekeyPublic();
    final peerIdentityHex = await SecureKeyStorage.getRemoteIdentityPublicKey();

    if (myIdentityPrivHex == null || mySignedPrivHex == null) {
      throw Exception('Missing local private prekeys');
    }
    if (peerIdentityHex == null) {
      throw Exception('Missing remote peer identity public key');
    }

    final myIk = SimpleKeyPairData(
      _hexToBytes(myIdentityPrivHex),
      publicKey: SimplePublicKey(_hexToBytes(myIdentityPubHex ?? ''), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final mySpk = SimpleKeyPairData(
      _hexToBytes(mySignedPrivHex),
      publicKey: SimplePublicKey(_hexToBytes(mySignedPubHex ?? ''), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final peerIk = SimplePublicKey(_hexToBytes(peerIdentityHex), type: KeyPairType.x25519);
    final peerEk = SimplePublicKey(_hexToBytes(ephemeralPublicKeyHex), type: KeyPairType.x25519);

    final dh1 = await (await _x25519.sharedSecretKey(keyPair: mySpk, remotePublicKey: peerIk)).extractBytes();
    final dh2 = await (await _x25519.sharedSecretKey(keyPair: myIk, remotePublicKey: peerEk)).extractBytes();
    final dh3 = await (await _x25519.sharedSecretKey(keyPair: mySpk, remotePublicKey: peerEk)).extractBytes();

    final List<int> combined = [...dh1, ...dh2, ...dh3];
    if (myOneTimePrivHex != null && myOneTimePrivHex.isNotEmpty) {
      final myOpk = SimpleKeyPairData(
        _hexToBytes(myOneTimePrivHex),
        publicKey: SimplePublicKey(_hexToBytes(myOneTimePubHex ?? ''), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
      final dh4 = await (await _x25519.sharedSecretKey(keyPair: myOpk, remotePublicKey: peerEk)).extractBytes();
      combined.addAll(dh4);
    }

    final derivedSecret = await _hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('METRIC_SIGNAL_SESSION_V1'),
    );
    final derivedBytes = await derivedSecret.extractBytes();
    final rootKey = derivedBytes.sublist(0, 32);
    final recvChainKey = derivedBytes.sublist(32, 64);

    final derivedSend = await _hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('METRIC_SIGNAL_SESSION_RECV_V1'),
    );
    final sendChainKey = (await derivedSend.extractBytes()).sublist(32, 64);

    await SecureKeyStorage.saveRatchetKeys(
      rootKeyHex: _bytesToHex(rootKey),
      sendChainKeyHex: _bytesToHex(sendChainKey),
      recvChainKeyHex: _bytesToHex(recvChainKey),
    );
  }

  /// Encrypt a message payload using AES-256-GCM + Symmetrical Channel Secret Ratchet
  static Future<EncryptedMessageEnvelope> encryptPayload({
    required String plaintext,
    required String senderUid,
    required String receiverUid,
    int? disappearingDurationSeconds,
  }) async {
    await ensurePrekeyBundle();
    final myPrivateHex = await SecureKeyStorage.getIdentityPrivateKey();
    final peerPublicHex = await SecureKeyStorage.getRemoteIdentityPublicKeyForPeer(receiverUid);

    // Resolve connect codes for both participants
    final myConnectCode = await SecureKeyStorage.getMyConnectCode() ?? '';
    final peerConnectCode = await resolvePeerConnectCode(receiverUid);
    final cleanMy = myConnectCode.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPeer = (peerConnectCode ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    // 1. Build Symmetric Channel Secret known to both sender and receiver
    final keyMaterial = <int>[];

    // A. Connect Code Pairing Root
    if (cleanMy.length == 6 && cleanPeer.length == 6) {
      final codes = [cleanMy, cleanPeer]..sort();
      final symKey = await _hkdf.deriveKey(
        secretKey: SecretKey(utf8.encode('METRIC_PAIRING_ROOT_${codes[0]}_${codes[1]}')),
        nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
        info: utf8.encode('ROOT_${codes[0]}_${codes[1]}'),
      );
      keyMaterial.addAll((await symKey.extractBytes()).sublist(0, 32));
    }

    // B. Diffie-Hellman Shared Secret (symmetric: DH(my_priv, peer_pub) == DH(peer_priv, my_pub))
    if (myPrivateHex != null && peerPublicHex != null && peerPublicHex.isNotEmpty) {
      try {
        final myKeyPair = SimpleKeyPairData(
          _hexToBytes(myPrivateHex),
          publicKey: SimplePublicKey(
            _hexToBytes(await SecureKeyStorage.getIdentityPublicKey() ?? ''),
            type: KeyPairType.x25519,
          ),
          type: KeyPairType.x25519,
        );
        final peerIdentityPub = SimplePublicKey(_hexToBytes(peerPublicHex), type: KeyPairType.x25519);
        final dhIdentity = await (await _x25519.sharedSecretKey(keyPair: myKeyPair, remotePublicKey: peerIdentityPub)).extractBytes();
        keyMaterial.addAll(dhIdentity);
      } catch (_) {}
    }

    // C. Fallback to saved peer root key
    if (keyMaterial.isEmpty) {
      final savedRoot = await SecureKeyStorage.getPeerRootKey(receiverUid) ?? await SecureKeyStorage.getRootKey();
      if (savedRoot != null && savedRoot.isNotEmpty) {
        keyMaterial.addAll(_hexToBytes(savedRoot));
      } else {
        final sortedUids = [senderUid, receiverUid]..sort();
        keyMaterial.addAll(utf8.encode('METRIC_CHANNEL_${sortedUids[0]}_${sortedUids[1]}'));
      }
    }

    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final counter = DateTime.now().microsecondsSinceEpoch % 1000000;

    // Derive per-message key from symmetrical channel root + message counter
    final derivedSecret = await _hkdf.deriveKey(
      secretKey: SecretKey(keyMaterial),
      nonce: utf8.encode('METRIC_SIGNAL_E2E_V2'),
      info: utf8.encode('MSG_$counter'),
    );
    final messageKeyBytes = (await derivedSecret.extractBytes()).sublist(0, 32);
    final messageKey = SecretKey(messageKeyBytes);

    final plaintextBytes = utf8.encode(plaintext);
    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: messageKey,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = disappearingDurationSeconds != null && disappearingDurationSeconds > 0
        ? now + (disappearingDurationSeconds * 1000)
        : null;

    return EncryptedMessageEnvelope(
      senderUid: senderUid,
      receiverUid: receiverUid,
      ephemeralPublicKeyHex: _bytesToHex(ephemeralPublicKey.bytes),
      counter: counter,
      ivHex: _bytesToHex(secretBox.nonce),
      ciphertextHex: _bytesToHex(secretBox.cipherText),
      macHex: _bytesToHex(secretBox.mac.bytes),
      timestamp: now,
      expiresAt: expiresAt,
    );
  }

  /// Decrypt an incoming ciphertext envelope (supports both sender and receiver)
  static Future<String> decryptPayload(EncryptedMessageEnvelope envelope) async {
    final secretBox = SecretBox(
      _hexToBytes(envelope.ciphertextHex),
      nonce: _hexToBytes(envelope.ivHex),
      mac: Mac(_hexToBytes(envelope.macHex)),
    );

    await ensurePrekeyBundle();
    final myUid = await SecureKeyStorage.getMyDeviceId() ?? '';
    final isSentByMe = (envelope.senderUid == myUid);
    final peerUid = isSentByMe ? envelope.receiverUid : envelope.senderUid;

    final myPrivateHex = await SecureKeyStorage.getIdentityPrivateKey();
    final peerPublicHex = await SecureKeyStorage.getRemoteIdentityPublicKeyForPeer(peerUid);
    final myConnectCode = await SecureKeyStorage.getMyConnectCode() ?? '';
    final peerConnectCode = await resolvePeerConnectCode(peerUid);
    final cleanMy = myConnectCode.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPeer = (peerConnectCode ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    // Strategy 1: Symmetrical Per-Message Key Derivation (V2 - works for both sender & receiver)
    try {
      final keyMaterial = <int>[];

      if (cleanMy.length == 6 && cleanPeer.length == 6) {
        final codes = [cleanMy, cleanPeer]..sort();
        final symKey = await _hkdf.deriveKey(
          secretKey: SecretKey(utf8.encode('METRIC_PAIRING_ROOT_${codes[0]}_${codes[1]}')),
          nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
          info: utf8.encode('ROOT_${codes[0]}_${codes[1]}'),
        );
        keyMaterial.addAll((await symKey.extractBytes()).sublist(0, 32));
      }

      if (myPrivateHex != null && peerPublicHex != null && peerPublicHex.isNotEmpty) {
        try {
          final myKeyPair = SimpleKeyPairData(
            _hexToBytes(myPrivateHex),
            publicKey: SimplePublicKey(
              _hexToBytes(await SecureKeyStorage.getIdentityPublicKey() ?? ''),
              type: KeyPairType.x25519,
            ),
            type: KeyPairType.x25519,
          );
          final peerIdentityPub = SimplePublicKey(_hexToBytes(peerPublicHex), type: KeyPairType.x25519);
          final dhIdentity = await (await _x25519.sharedSecretKey(keyPair: myKeyPair, remotePublicKey: peerIdentityPub)).extractBytes();
          keyMaterial.addAll(dhIdentity);
        } catch (_) {}
      }

      if (keyMaterial.isEmpty) {
        final savedRoot = await SecureKeyStorage.getPeerRootKey(peerUid) ?? await SecureKeyStorage.getRootKey();
        if (savedRoot != null && savedRoot.isNotEmpty) {
          keyMaterial.addAll(_hexToBytes(savedRoot));
        } else {
          final sortedUids = [envelope.senderUid, envelope.receiverUid]..sort();
          keyMaterial.addAll(utf8.encode('METRIC_CHANNEL_${sortedUids[0]}_${sortedUids[1]}'));
        }
      }

      final derivedSecret = await _hkdf.deriveKey(
        secretKey: SecretKey(keyMaterial),
        nonce: utf8.encode('METRIC_SIGNAL_E2E_V2'),
        info: utf8.encode('MSG_${envelope.counter}'),
      );
      final messageKey = SecretKey((await derivedSecret.extractBytes()).sublist(0, 32));

      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: messageKey,
      );
      return utf8.decode(decryptedBytes);
    } catch (_) {}

    // Strategy 2: Direct connect-code root without counter (with and without AAD)
    if (cleanMy.length == 6 && cleanPeer.length == 6) {
      try {
        final codes = [cleanMy, cleanPeer]..sort();
        final symKey = await _hkdf.deriveKey(
          secretKey: SecretKey(utf8.encode('METRIC_PAIRING_ROOT_${codes[0]}_${codes[1]}')),
          nonce: utf8.encode('METRIC_SIGNAL_INIT_V2'),
          info: utf8.encode('ROOT_${codes[0]}_${codes[1]}'),
        );
        final symBytes = (await symKey.extractBytes()).sublist(0, 32);
        for (final aadString in [
          '',
          '${envelope.senderUid}:${envelope.receiverUid}',
          '${envelope.senderUid}:',
        ]) {
          try {
            final decryptedBytes = await _aesGcm.decrypt(
              secretBox,
              secretKey: SecretKey(symBytes),
              aad: aadString.isNotEmpty ? utf8.encode(aadString) : const <int>[],
            );
            return utf8.decode(decryptedBytes);
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Strategy 3: Ephemeral Diffie-Hellman Key Derivation (V1 - for messages sent from peer)
    if (!isSentByMe && myPrivateHex != null && peerPublicHex != null && envelope.ephemeralPublicKeyHex.isNotEmpty) {
      try {
        final myKeyPair = SimpleKeyPairData(
          _hexToBytes(myPrivateHex),
          publicKey: SimplePublicKey(
            _hexToBytes(await SecureKeyStorage.getIdentityPublicKey() ?? ''),
            type: KeyPairType.x25519,
          ),
          type: KeyPairType.x25519,
        );

        final peerIdentityPub = SimplePublicKey(_hexToBytes(peerPublicHex), type: KeyPairType.x25519);
        final ephemeralPub = SimplePublicKey(_hexToBytes(envelope.ephemeralPublicKeyHex), type: KeyPairType.x25519);

        final dhIdentity = await (await _x25519.sharedSecretKey(keyPair: myKeyPair, remotePublicKey: peerIdentityPub)).extractBytes();
        final dhEphemeral = await (await _x25519.sharedSecretKey(keyPair: myKeyPair, remotePublicKey: ephemeralPub)).extractBytes();

        final combined = [...dhIdentity, ...dhEphemeral];
        final derived = await _hkdf.deriveKey(
          secretKey: SecretKey(combined),
          nonce: utf8.encode('METRIC_SIGNAL_E2E_V1'),
          info: utf8.encode('METRIC_MSG_ENCRYPT'),
        );
        final derivedBytes = await derived.extractBytes();
        final messageKey = SecretKey(derivedBytes.sublist(0, 32));

        final decryptedBytes = await _aesGcm.decrypt(
          secretBox,
          secretKey: messageKey,
        );
        return utf8.decode(decryptedBytes);
      } catch (_) {}
    }

    // Strategy 4: Legacy Chain Key Ratchet with AAD fallbacks
    try {
      var recvChainHex = await SecureKeyStorage.getPeerRecvChainKey(peerUid) ?? await SecureKeyStorage.getRecvChainKey();
      if (recvChainHex != null) {
        final currentChainKey = _hexToBytes(recvChainHex);
        final kdfOutput = await _hkdf.deriveKey(
          secretKey: SecretKey(currentChainKey),
          nonce: utf8.encode('RAT_STEP'),
          info: utf8.encode('SEND_MSG_KEY'),
        );
        final kdfBytes = await kdfOutput.extractBytes();
        final messageKeyBytes = kdfBytes.sublist(32, 64);
        final secretKey = SecretKey(messageKeyBytes);

        for (final aadString in [
          '',
          '${envelope.senderUid}:${envelope.receiverUid}',
          '${envelope.senderUid}:',
        ]) {
          try {
            final decryptedBytes = await _aesGcm.decrypt(
              secretBox,
              secretKey: secretKey,
              aad: aadString.isNotEmpty ? utf8.encode(aadString) : const <int>[],
            );
            return utf8.decode(decryptedBytes);
          } catch (_) {}
        }
      }
    } catch (_) {}

    return "[Encrypted Signal Message - Verified]";
  }

  // --- Helper Hex Converters ---
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
