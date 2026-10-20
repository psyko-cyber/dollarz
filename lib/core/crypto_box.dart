import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Cifratura AES-256-GCM dei dati di Dollarz (a riposo, in sync e nei backup).
///
/// Formato: "DZ1" | nonce (12 byte) | testo cifrato | tag (16 byte).
/// GCM autentica i dati: una chiave sbagliata o un file alterato non si aprono.
class CryptoBox {
  static final _magic = ascii.encode('DZ1');
  static const _bigPayload = 96 * 1024;

  static bool isSealed(List<int> data) =>
      data.length >= 31 && data[0] == _magic[0] && data[1] == _magic[1] && data[2] == _magic[2];

  static Future<Uint8List> seal(List<int> key, List<int> plain) async {
    if (plain.length > _bigPayload) return Isolate.run(() => _seal(key, plain));
    return _seal(key, plain);
  }

  static Future<Uint8List> open(List<int> key, List<int> data) async {
    if (data.length > _bigPayload) return Isolate.run(() => _open(key, data));
    return _open(key, data);
  }

  static Future<Uint8List> sealString(List<int> key, String s) => seal(key, utf8.encode(s));

  static Future<String> openString(List<int> key, List<int> data) async => utf8.decode(await open(key, data));

  static Future<Uint8List> _seal(List<int> key, List<int> plain) async {
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(plain, secretKey: SecretKey(key), nonce: aes.newNonce());
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  static Future<Uint8List> _open(List<int> key, List<int> data) async {
    if (!isSealed(data)) throw const FormatException('Dati non cifrati da Dollarz');
    final aes = AesGcm.with256bits();
    final nonce = data.sublist(3, 15);
    final mac = Mac(data.sublist(data.length - 16));
    final cipher = data.sublist(15, data.length - 16);
    try {
      final plain = await aes.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: SecretKey(key));
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Chiave sbagliata o dati danneggiati');
    }
  }

  /// 32 byte casuali (chiave nuova).
  static Uint8List randomKey() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
  }

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// Chiave della sincronizzazione dal codice di abbinamento (già casuale e lungo).
  static Uint8List keyFromCode(String code) =>
      Uint8List.fromList(hash.sha256.convert(utf8.encode('dollarz-sync-v1:${code.toUpperCase()}')).bytes);

  /// Chiave da una password (backup, PIN): PBKDF2-HMAC-SHA256, in un isolate.
  static Future<Uint8List> keyFromPassword(String password, List<int> salt, {int iterations = 120000}) {
    return Isolate.run(() async {
      final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
      final k = await kdf.deriveKeyFromPassword(password: password, nonce: salt);
      return Uint8List.fromList(await k.extractBytes());
    });
  }

  static String sha256Hex(List<int> data) => hash.sha256.convert(data).toString();
}
