import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:metric/core/security/signal_crypto.dart';
import 'package:metric/core/security/secure_key_storage.dart';

void main() {
  test('X25519 and Ed25519 key generation and signature verification', () async {
    final x25519 = X25519();
    final ed25519 = Ed25519();

    // Generate Identity KeyPair (X25519)
    final identityKeyPair = await x25519.newKeyPair();
    final identityPub = await identityKeyPair.extractPublicKey();

    // Generate Signing KeyPair (Ed25519)
    final signingKeyPair = await ed25519.newKeyPair();
    final signingPub = await signingKeyPair.extractPublicKey();

    // Generate Signed Prekey (X25519)
    final signedPrekeyPair = await x25519.newKeyPair();
    final signedPrekeyPub = await signedPrekeyPair.extractPublicKey();

    // Sign the signed prekey with the signing key
    final signature = await ed25519.sign(
      signedPrekeyPub.bytes,
      keyPair: signingKeyPair,
    );

    // Verify signature
    final isValid = await ed25519.verify(
      signedPrekeyPub.bytes,
      signature: signature,
    );

    expect(isValid, isTrue);

    // Generate One-Time Prekey
    final opk = await x25519.newKeyPair();
    final opkPub = await opk.extractPublicKey();

    expect(identityPub.bytes.length, 32);
    expect(signingPub.bytes.length, 32);
    expect(signedPrekeyPub.bytes.length, 32);
    expect(opkPub.bytes.length, 32);
  });

  test('PublicKeyBundle JSON serialization and deserialization', () {
    const bundle = PublicKeyBundle(
      identityKeyHex: 'aabbcc112233',
      signingKeyHex: '445566778899',
      signedPrekeyHex: '112233445566',
      signedPrekeyId: 1,
      signedPrekeySignatureHex: 'deadbeefcafe',
      oneTimePrekeyHex: '998877665544',
      oneTimePrekeyId: 1,
      timestamp: 1740000000000,
    );

    final json = bundle.toJson();
    expect(json['identity_key'], 'aabbcc112233');
    expect(json['signing_key'], '445566778899');
    expect(json['signed_prekey'], '112233445566');
    expect(json['signed_prekey_id'], 1);
    expect(json['signed_prekey_signature'], 'deadbeefcafe');
    expect(json['one_time_prekey'], '998877665544');
    expect(json['one_time_prekey_id'], 1);
    expect(json['timestamp'], 1740000000000);

    final restored = PublicKeyBundle.fromJson(json);
    expect(restored.identityKeyHex, bundle.identityKeyHex);
    expect(restored.signingKeyHex, bundle.signingKeyHex);
    expect(restored.signedPrekeyHex, bundle.signedPrekeyHex);
    expect(restored.signedPrekeyId, bundle.signedPrekeyId);
    expect(restored.signedPrekeySignatureHex, bundle.signedPrekeySignatureHex);
    expect(restored.oneTimePrekeyHex, bundle.oneTimePrekeyHex);
    expect(restored.oneTimePrekeyId, bundle.oneTimePrekeyId);
    expect(restored.timestamp, bundle.timestamp);
  });

  test('12-digit Safety Number is identical regardless of which device computes it', () async {
    const keyA = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    const keyB = 'f9e8d7c6b5a403122130495867768594f9e8d7c6b5a403122130495867768594';

    // Device A computes safety number passing (keyA, keyB)
    final safetyNumberOnA = await SignalCryptoService.computeSafetyNumber(keyA, keyB);

    // Device B computes safety number passing (keyB, keyA)
    final safetyNumberOnB = await SignalCryptoService.computeSafetyNumber(keyB, keyA);

    expect(safetyNumberOnA, equals(safetyNumberOnB));
    expect(safetyNumberOnA.length, 14); // 12 digits + 2 spaces: "XXXX XXXX XXXX"
    expect(RegExp(r'^\d{4} \d{4} \d{4}$').hasMatch(safetyNumberOnA), isTrue);
  });

  test('EncryptedMessageEnvelope parses recipient_uid correctly', () {
    final map = {
      'id': 'msg-123',
      'sender_uid': 'sender-abc',
      'recipient_uid': 'receiver-xyz',
      'ephemeral_key': 'ephkey123',
      'counter': 1,
      'iv': 'iv123',
      'ciphertext': 'cipher123',
      'mac': 'mac123',
      'timestamp': 12345678,
    };
    final envelope = EncryptedMessageEnvelope.fromMap(map);
    expect(envelope.senderUid, 'sender-abc');
    expect(envelope.receiverUid, 'receiver-xyz');
  });

  test('SecureKeyStorage default passcode and verification', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final defaultPass = await SecureKeyStorage.getPasscode();
    expect(defaultPass, '1234');
    expect(await SecureKeyStorage.verifyPasscode('1234'), isTrue);
    expect(await SecureKeyStorage.verifyPasscode('9999'), isFalse);

    await SecureKeyStorage.setPasscode('4321');
    expect(await SecureKeyStorage.getPasscode(), '4321');
    expect(await SecureKeyStorage.verifyPasscode('4321'), isTrue);
    expect(await SecureKeyStorage.verifyPasscode('1234'), isFalse);
  });

  test('SecureKeyStorage secret knock sequence defaults and customization', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final defaultSeq = await SecureKeyStorage.getSecretKnockSequence();
    expect(defaultSeq, ['length', 'length', 'pressure']);

    await SecureKeyStorage.setSecretKnockSequence(['mass', 'temperature', 'speed']);
    final customSeq = await SecureKeyStorage.getSecretKnockSequence();
    expect(customSeq, ['mass', 'temperature', 'speed']);
  });
}
