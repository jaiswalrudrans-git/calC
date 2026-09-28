import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:metric/core/security/media_crypto.dart';

void main() {
  test('MediaCryptoService encrypts and decrypts database/payload bytes accurately', () async {
    final original = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));

    final encrypted = await MediaCryptoService.encryptMediaBytes(original);

    expect(encrypted.ciphertext.length, original.length);
    expect(encrypted.keyHex.length, 64); // 32 bytes hex
    expect(encrypted.ivHex.length, 24); // 12 bytes hex
    expect(encrypted.macHex.length, 32); // 16 bytes hex

    final decrypted = await MediaCryptoService.decryptMediaBytes(
      encrypted.ciphertext,
      keyHex: encrypted.keyHex,
      ivHex: encrypted.ivHex,
      macHex: encrypted.macHex,
    );

    expect(decrypted, equals(original));
  });
}
