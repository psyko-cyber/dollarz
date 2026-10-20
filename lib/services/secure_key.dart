import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/crypto_box.dart';

/// Chiave dei dati del dispositivo, nel portachiavi del sistema
/// (Android Keystore; su Windows protetta da DPAPI).
class SecureKey {
  static const _name = 'dollarz.dataKey.v1';

  // resetOnError: false. Se il portachiavi dà errore NON va svuotato: perderemmo la chiave e i dati.
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  /// Ritorna (chiave, appena creata). Lancia se il portachiavi non risponde:
  /// meglio fermarsi che creare una chiave nuova sopra dati esistenti.
  static Future<(List<int>, bool)> load() async {
    final v = await _storage.read(key: _name);
    if (v != null && v.isNotEmpty) return (base64.decode(v), false);
    final k = CryptoBox.randomKey();
    final enc = base64.encode(k);
    await _storage.write(key: _name, value: enc);
    if (await _storage.read(key: _name) != enc) throw StateError('Il portachiavi del sistema non salva la chiave.');
    return (k, true);
  }

  /// Solo per "ricomincia da zero" quando i dati non si possono più aprire.
  static Future<List<int>> replace() async {
    final k = CryptoBox.randomKey();
    await _storage.write(key: _name, value: base64.encode(k));
    return k;
  }
}
