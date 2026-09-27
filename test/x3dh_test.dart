import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('X3DH Initiator and Responder derive identical master secret and chain keys', () async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

    // --- Device A (Initiator) Key Generation ---
    final ikA = await x25519.newKeyPair();
    final ikAPub = await ikA.extractPublicKey();

    // --- Device B (Responder) Key Generation ---
    final ikB = await x25519.newKeyPair();
    final ikBPub = await ikB.extractPublicKey();

    final spkB = await x25519.newKeyPair();
    final spkBPub = await spkB.extractPublicKey();

    final opkB = await x25519.newKeyPair();
    final opkBPub = await opkB.extractPublicKey();

    // --- Initiator (Device A) runs X3DH ---
    final ekA = await x25519.newKeyPair();
    final ekAPub = await ekA.extractPublicKey();

    final dh1A = await (await x25519.sharedSecretKey(keyPair: ikA, remotePublicKey: spkBPub)).extractBytes();
    final dh2A = await (await x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: ikBPub)).extractBytes();
    final dh3A = await (await x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: spkBPub)).extractBytes();
    final dh4A = await (await x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: opkBPub)).extractBytes();

    final combinedA = [...dh1A, ...dh2A, ...dh3A, ...dh4A];

    final derivedA = await hkdf.deriveKey(
      secretKey: SecretKey(combinedA),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('METRIC_SIGNAL_SESSION_V1'),
    );
    final masterSecretA = await derivedA.extractBytes();

    // --- Responder (Device B) runs X3DH upon receiving EK_A ---
    final dh1B = await (await x25519.sharedSecretKey(keyPair: spkB, remotePublicKey: ikAPub)).extractBytes();
    final dh2B = await (await x25519.sharedSecretKey(keyPair: ikB, remotePublicKey: ekAPub)).extractBytes();
    final dh3B = await (await x25519.sharedSecretKey(keyPair: spkB, remotePublicKey: ekAPub)).extractBytes();
    final dh4B = await (await x25519.sharedSecretKey(keyPair: opkB, remotePublicKey: ekAPub)).extractBytes();

    final combinedB = [...dh1B, ...dh2B, ...dh3B, ...dh4B];

    final derivedB = await hkdf.deriveKey(
      secretKey: SecretKey(combinedB),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('METRIC_SIGNAL_SESSION_V1'),
    );
    final masterSecretB = await derivedB.extractBytes();

    expect(masterSecretA, equals(masterSecretB));
  });

  test('Round-trip encryption on Device A and decryption on Device B via X3DH session', () async {
    final x25519 = X25519();
    final aesGcm = AesGcm.with256bits();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

    final ikA = await x25519.newKeyPair();
    final ikAPub = await ikA.extractPublicKey();

    final ikB = await x25519.newKeyPair();
    final ikBPub = await ikB.extractPublicKey();
    final spkB = await x25519.newKeyPair();
    final spkBPub = await spkB.extractPublicKey();

    // Device A initiates X3DH session
    final ekA = await x25519.newKeyPair();
    final ekAPub = await ekA.extractPublicKey();

    final dh1A = await (await x25519.sharedSecretKey(keyPair: ikA, remotePublicKey: spkBPub)).extractBytes();
    final dh2A = await (await x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: ikBPub)).extractBytes();
    final dh3A = await (await x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: spkBPub)).extractBytes();

    final combinedA = [...dh1A, ...dh2A, ...dh3A];
    final derivedSecretA = await hkdf.deriveKey(
      secretKey: SecretKey(combinedA),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('INITIATOR_TO_RESPONDER'),
    );
    final derivedBytesA = await derivedSecretA.extractBytes();
    final encKeyA = SecretKey(derivedBytesA.sublist(0, 32));

    // Device A encrypts a hardcoded test string
    const hardcodedString = "METRIC_E2E_VERIFICATION_STRING_778899";
    final secretBox = await aesGcm.encrypt(
      utf8.encode(hardcodedString),
      secretKey: encKeyA,
      aad: utf8.encode('devA_uid:devB_uid'),
    );

    // CIPHERTEXT ONLY exists in transit:
    final ciphertextBytes = secretBox.cipherText;
    final nonce = secretBox.nonce;
    final mac = secretBox.mac;
    final ephemeralPubBytes = ekAPub.bytes;

    // --- Device B receives the ciphertext envelope ---
    // Device B completes X3DH using received ephemeral public key
    final remoteEkA = SimplePublicKey(ephemeralPubBytes, type: KeyPairType.x25519);
    final dh1B = await (await x25519.sharedSecretKey(keyPair: spkB, remotePublicKey: ikAPub)).extractBytes();
    final dh2B = await (await x25519.sharedSecretKey(keyPair: ikB, remotePublicKey: remoteEkA)).extractBytes();
    final dh3B = await (await x25519.sharedSecretKey(keyPair: spkB, remotePublicKey: remoteEkA)).extractBytes();

    final combinedB = [...dh1B, ...dh2B, ...dh3B];
    final derivedSecretB = await hkdf.deriveKey(
      secretKey: SecretKey(combinedB),
      nonce: utf8.encode('METRIC_X3DH_SALT_V1'),
      info: utf8.encode('INITIATOR_TO_RESPONDER'),
    );
    final derivedBytesB = await derivedSecretB.extractBytes();
    final decKeyB = SecretKey(derivedBytesB.sublist(0, 32));

    // Device B decrypts ciphertext
    final decryptedBytes = await aesGcm.decrypt(
      SecretBox(ciphertextBytes, nonce: nonce, mac: mac),
      secretKey: decKeyB,
      aad: utf8.encode('devA_uid:devB_uid'),
    );
    final decryptedString = utf8.decode(decryptedBytes);

    expect(decryptedString, equals(hardcodedString));
  });
}
