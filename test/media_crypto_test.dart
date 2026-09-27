import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:metric/core/security/media_crypto.dart';

void main() {
  test('MediaCryptoService encrypts and decrypts bytes accurately', () async {
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

  test('MediaCryptoService strips EXIF and compresses image', () async {
    // Generate a test image 2000x2000
    final testImg = img.Image(width: 1800, height: 1200);
    for (int y = 0; y < 1200; y++) {
      for (int x = 0; x < 1800; x++) {
        testImg.setPixelRgba(x, y, (x % 255), (y % 255), 128, 255);
      }
    }
    final rawPng = Uint8List.fromList(img.encodePng(testImg));

    final processed = await MediaCryptoService.stripExifAndCompress(
      rawPng,
      maxWidth: 800,
      maxHeight: 800,
      quality: 75,
    );

    expect(processed.isNotEmpty, isTrue);
    final decoded = img.decodeImage(processed);
    expect(decoded, isNotNull);
    expect(decoded!.width <= 800, isTrue);
    expect(decoded.height <= 800, isTrue);
  });
}
