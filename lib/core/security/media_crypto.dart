import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
  static final _aesGcm = AesGcm.with256bits();
  static final _random = Random.secure();

  /// Encrypt arbitrary bytes using AES-256-GCM with a newly generated ephemeral key
  static Future<EncryptedMediaPayload> encryptMediaBytes(Uint8List rawBytes) async {
    // 1. Generate 256-bit AES key & 12-byte IV
    final keyBytes = Uint8List(32);
    final ivBytes = Uint8List(12);
    for (int i = 0; i < 32; i++) {
      keyBytes[i] = _random.nextInt(256);
    }
    for (int i = 0; i < 12; i++) {
      ivBytes[i] = _random.nextInt(256);
    }

    final secretKey = SecretKey(keyBytes);

    // 2. Encrypt with AES-GCM
    final secretBox = await _aesGcm.encrypt(
      rawBytes,
      secretKey: secretKey,
      nonce: ivBytes,
    );

    return EncryptedMediaPayload(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      keyHex: _bytesToHex(keyBytes),
      ivHex: _bytesToHex(ivBytes),
      macHex: _bytesToHex(secretBox.mac.bytes),
      originalSize: rawBytes.length,
    );
  }

  /// Decrypt bytes using AES-256-GCM
  static Future<Uint8List> decryptMediaBytes(
    Uint8List ciphertext, {
    required String keyHex,
    required String ivHex,
    required String macHex,
  }) async {
    final keyBytes = _hexToBytes(keyHex);
    final ivBytes = _hexToBytes(ivHex);
    final macBytes = _hexToBytes(macHex);

    final secretKey = SecretKey(keyBytes);
    final secretBox = SecretBox(
      ciphertext,
      nonce: ivBytes,
      mac: Mac(macBytes),
    );

    final decrypted = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
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
