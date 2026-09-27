import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:metric/core/database/local_cache.dart';
import 'package:metric/core/security/media_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Media Messaging Flow Tests (Step 3)', () {
    test('Encrypted media envelope pack and unpack round-trip', () async {
      // 1. Raw synthetic photo bytes
      final rawPhotoBytes = Uint8List.fromList(List.generate(256, (i) => (i * 7) % 256));

      // 2. Encrypt media payload using AES-256-GCM
      final encryptedMedia = await MediaCryptoService.encryptMediaBytes(rawPhotoBytes);

      // 3. Assemble JSON envelope payload
      final envelopeJson = jsonEncode({
        'type': 'media',
        'media_type': 'image',
        'file_name': 'vault_photo.jpg',
        'file_size': rawPhotoBytes.length,
        'caption': 'Encrypted image test',
        'key_hex': encryptedMedia.keyHex,
        'iv_hex': encryptedMedia.ivHex,
        'mac_hex': encryptedMedia.macHex,
        'data_base64': base64Encode(encryptedMedia.ciphertext),
      });

      // 4. Verify envelope payload parsing
      final decoded = jsonDecode(envelopeJson) as Map<String, dynamic>;
      expect(decoded['type'], equals('media'));
      expect(decoded['media_type'], equals('image'));
      expect(decoded['file_name'], equals('vault_photo.jpg'));
      expect(decoded['caption'], equals('Encrypted image test'));

      // 5. Decrypt media payload
      final recoveredCiphertext = base64Decode(decoded['data_base64'] as String);
      final decryptedBytes = await MediaCryptoService.decryptMediaBytes(
        recoveredCiphertext,
        keyHex: decoded['key_hex'] as String,
        ivHex: decoded['iv_hex'] as String,
        macHex: decoded['mac_hex'] as String,
      );

      expect(decryptedBytes, equals(rawPhotoBytes));
    });

    test('LocalChatMessage correctly persists media metadata', () {
      final msg = LocalChatMessage(
        id: 'media_test_001',
        senderUid: 'sender_abc',
        receiverUid: 'receiver_xyz',
        text: 'vault_photo.jpg',
        timestamp: 1727438400000,
        isMe: true,
        status: 'sent',
        mediaType: 'image',
        localPath: '/sandboxed/vault_media/media_test_001_vault_photo.jpg',
        mediaSize: 1048576, // 1 MB
        duration: null,
      );

      final map = msg.toMap();
      expect(map['mediaType'], equals('image'));
      expect(map['localPath'], equals('/sandboxed/vault_media/media_test_001_vault_photo.jpg'));
      expect(map['mediaSize'], equals(1048576));
      expect(map['duration'], isNull);

      final fromMap = LocalChatMessage.fromMap(map);
      expect(fromMap.id, equals(msg.id));
      expect(fromMap.mediaType, equals('image'));
      expect(fromMap.localPath, equals(msg.localPath));
      expect(fromMap.mediaSize, equals(1048576));
    });

    test('Voice note metadata correctly serialized and deserialized', () {
      final voiceMsg = LocalChatMessage(
        id: 'voice_test_002',
        senderUid: 'sender_abc',
        receiverUid: 'receiver_xyz',
        text: 'voice_12345.m4a',
        timestamp: 1727438405000,
        isMe: false,
        status: 'delivered',
        mediaType: 'voice',
        localPath: '/sandboxed/vault_media/voice_test_002_voice_12345.m4a',
        mediaSize: 32768,
        duration: 14,
      );

      final map = voiceMsg.toMap();
      expect(map['mediaType'], equals('voice'));
      expect(map['duration'], equals(14));

      final restored = LocalChatMessage.fromMap(map);
      expect(restored.mediaType, equals('voice'));
      expect(restored.duration, equals(14));
      expect(restored.status, equals('delivered'));
    });
  });
}
