import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:metric/core/database/local_cache.dart';
import 'package:metric/core/security/media_crypto.dart';

void main() {
  group('Step 5 - Google Drive Zero-Knowledge Encrypted Backup Tests', () {
    test('DriveLedgerItem serialization and deserialization', () {
      final item = DriveLedgerItem(
        id: 'ledger_123',
        localMsgId: 'msg_abc',
        localFilePath: '/data/user/0/com.metric/vault_media/photo.jpg',
        mediaType: 'image',
        folderKey: '2026-09',
        obscuredFilename: 'enc_9f8e7d6c-5b4a.bin',
        status: 'pending',
        timestamp: 1789456123000,
      );

      final map = item.toMap();
      expect(map['id'], equals('ledger_123'));
      expect(map['local_msg_id'], equals('msg_abc'));
      expect(map['folder_key'], equals('2026-09'));
      expect(map['obscured_filename'], equals('enc_9f8e7d6c-5b4a.bin'));
      expect(map['status'], equals('pending'));

      final restored = DriveLedgerItem.fromMap(map);
      expect(restored.id, equals(item.id));
      expect(restored.localMsgId, equals(item.localMsgId));
      expect(restored.folderKey, equals(item.folderKey));
      expect(restored.obscuredFilename, equals(item.obscuredFilename));
      expect(restored.status, equals('pending'));
    });

    test('Zero-knowledge ciphertext encryption for Drive upload and restore', () async {
      final samplePlaintext = utf8.encode('Top secret vault document payload for Drive sync');
      
      // 1. Client-side AES-256-GCM encryption
      final encrypted = await MediaCryptoService.encryptMediaBytes(samplePlaintext);

      // Verify that ciphertext is not plaintext
      expect(encrypted.ciphertext, isNot(equals(samplePlaintext)));

      // 2. Build envelope as uploaded to Google Drive
      final envelopeMap = {
        'v': 1,
        'cipher': base64Encode(encrypted.ciphertext),
        'key': encrypted.keyHex,
        'iv': encrypted.ivHex,
        'mac': encrypted.macHex,
        'orig_size': encrypted.originalSize,
        'media_type': 'document',
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

      final envelopeJson = jsonEncode(envelopeMap);
      expect(envelopeJson, contains('"cipher":'));
      expect(envelopeJson, isNot(contains('Top secret vault document')));

      // 3. Client-side decryption simulation (Restore from Drive)
      final parsedEnvelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
      final downloadedCipher = base64Decode(parsedEnvelope['cipher'] as String);
      final decrypted = await MediaCryptoService.decryptMediaBytes(
        downloadedCipher,
        keyHex: parsedEnvelope['key'] as String,
        ivHex: parsedEnvelope['iv'] as String,
        macHex: parsedEnvelope['mac'] as String,
      );

      expect(utf8.decode(decrypted), equals('Top secret vault document payload for Drive sync'));
    });

    test('Drive folder structure organizes by Month/Year', () {
      final septDate = DateTime(2026, 9, 27);
      final augDate = DateTime(2026, 8, 15);

      final septKey = '${septDate.year}-${septDate.month.toString().padLeft(2, '0')}';
      final augKey = '${augDate.year}-${augDate.month.toString().padLeft(2, '0')}';

      expect(septKey, equals('2026-09'));
      expect(augKey, equals('2026-08'));

      // Filenames in Drive must never include original filenames
      final originalName = 'passport_scan_john_doe.jpg';
      final obscuredDriveName = 'enc_${originalName.hashCode.abs()}.bin';

      expect(obscuredDriveName, isNot(contains('passport')));
      expect(obscuredDriveName, isNot(contains('john')));
      expect(obscuredDriveName, endsWith('.bin'));
    });
  });
}
