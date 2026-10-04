import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class EncryptedMediaPayload {
  final Uint8List ciphertext;
  final String keyHex;
  final String ivHex;
  final String macHex;
  final int originalSize;

  const EncryptedMediaPayload({
    required this.ciphertext,
    required this.keyHex,
    required this.ivHex,
    required this.macHex,
    required this.originalSize,
  });
}

/// AES-256-GCM encryption service used for secure vault database backup payloads
class MediaCryptoService {

  /// Encrypt arbitrary bytes using AES-256-GCM on a background isolate
  static Future<EncryptedMediaPayload> encryptMediaBytes(Uint8List rawBytes) async {
    return compute(_encryptWorker, rawBytes);
  }

  /// Decrypt bytes using AES-256-GCM on a background isolate
  static Future<Uint8List> decryptMediaBytes(
    Uint8List ciphertext, {
    required String keyHex,
    required String ivHex,
    required String macHex,
  }) async {
    return compute(_decryptWorker, {
      'ciphertext': ciphertext,
      'keyHex': keyHex,
      'ivHex': ivHex,
      'macHex': macHex,
    });
  }

  /// Get the app's private sandboxed directory
  static Future<Directory> getSandboxMediaDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docsDir.path, 'vault_storage'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  /// Save bytes into private app sandbox
  static Future<String> saveToSandbox(Uint8List decryptedBytes, String filename) async {
    final dir = await getSandboxMediaDirectory();
    final filePath = p.join(dir.path, filename);
    final file = File(filePath);
    await file.writeAsBytes(decryptedBytes, flush: true);
    return filePath;
  }

  /// Delete a file from sandbox
  static Future<void> deleteFromSandbox(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Helper: Hex encoding
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Helper: Hex decoding
  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

Future<EncryptedMediaPayload> _encryptWorker(Uint8List rawBytes) async {
  final random = Random.secure();
  final keyBytes = Uint8List(32);
  final ivBytes = Uint8List(12);
  for (int i = 0; i < 32; i++) {
    keyBytes[i] = random.nextInt(256);
  }
  for (int i = 0; i < 12; i++) {
    ivBytes[i] = random.nextInt(256);
  }

  final secretKey = SecretKey(keyBytes);
  final aesGcm = AesGcm.with256bits();
  final secretBox = await aesGcm.encrypt(
    rawBytes,
    secretKey: secretKey,
    nonce: ivBytes,
  );

  return EncryptedMediaPayload(
    ciphertext: Uint8List.fromList(secretBox.cipherText),
    keyHex: MediaCryptoService._bytesToHex(keyBytes),
    ivHex: MediaCryptoService._bytesToHex(ivBytes),
    macHex: MediaCryptoService._bytesToHex(secretBox.mac.bytes),
    originalSize: rawBytes.length,
  );
}

Future<Uint8List> _decryptWorker(Map<String, dynamic> params) async {
  final ciphertext = params['ciphertext'] as Uint8List;
  final keyHex = params['keyHex'] as String;
  final ivHex = params['ivHex'] as String;
  final macHex = params['macHex'] as String;

  final keyBytes = MediaCryptoService._hexToBytes(keyHex);
  final ivBytes = MediaCryptoService._hexToBytes(ivHex);
  final macBytes = MediaCryptoService._hexToBytes(macHex);

  final secretKey = SecretKey(keyBytes);
  final secretBox = SecretBox(
    ciphertext,
    nonce: ivBytes,
    mac: Mac(macBytes),
  );

  final aesGcm = AesGcm.with256bits();
  final decrypted = await aesGcm.decrypt(
    secretBox,
    secretKey: secretKey,
  );

  return Uint8List.fromList(decrypted);
}
