import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/crypto_box.dart';
import '../core/fmt.dart';
import '../core/ids.dart';
import '../data/app_state.dart';

/// Backup cifrato con una password scelta dall'utente.
/// Formato: "DZB1" | sale (16 byte) | dati cifrati (AES-256-GCM).
class Backup {
  static final _magic = ascii.encode('DZB1');

  static Future<Uint8List> build(AppState app, List<int> key, List<int> salt) async {
    await app.store.flush();
    final sealed = await CryptoBox.sealString(key, jsonEncode(app.store.exportAll()));
    return (BytesBuilder(copy: false)
          ..add(_magic)
          ..add(salt)
          ..add(sealed))
        .toBytes();
  }

  static bool looksLike(List<int> b) => b.length > 40 && b[0] == _magic[0] && b[1] == _magic[1] && b[2] == _magic[2] && b[3] == _magic[3];

  /// Apre un backup: ritorna i dati o lancia FormatException (password sbagliata, file non valido).
  static Future<Map<String, dynamic>> open(List<int> bytes, String password) async {
    if (!looksLike(bytes)) throw const FormatException('Il file non è un backup di Dollarz.');
    final salt = bytes.sublist(4, 20);
    final key = await CryptoBox.keyFromPassword(password, salt);
    try {
      final txt = await CryptoBox.openString(key, bytes.sublist(20));
      return Map<String, dynamic>.from(jsonDecode(txt) as Map);
    } on FormatException {
      throw const FormatException('Password sbagliata o file danneggiato.');
    }
  }

  static String fileName() => 'dollarz-backup-${todayKey()}.dzb';

  /// Esporta: sul PC si sceglie dove salvare, sul telefono si condivide.
  static Future<String?> export(AppState app, String password) async {
    final salt = CryptoBox.randomBytes(16);
    final key = await CryptoBox.keyFromPassword(password, salt);
    final data = await build(app, key, salt);
    final name = fileName();
    if (isDesktop) {
      final loc = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [XTypeGroup(label: 'Backup Dollarz', extensions: ['dzb'])],
        confirmButtonText: 'Salva',
      );
      if (loc == null) return null;
      await File(loc.path).writeAsBytes(data, flush: true);
      return loc.path;
    }
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(data, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/octet-stream')], subject: 'Backup Dollarz'));
    return 'condivisione';
  }

  static Future<Uint8List?> pick() async {
    final x = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Backup Dollarz', extensions: ['dzb'], mimeTypes: ['application/octet-stream']),
    ]);
    return x == null ? null : await x.readAsBytes();
  }

  /// Unisce il backup ai dati attuali (vince la modifica più recente). Ritorna i record importati.
  static Future<int> restore(AppState app, List<int> bytes, String password) async {
    final data = await open(bytes, password);
    return app.store.importAll(data);
  }

  // ---------------------------------------------------------------- copia automatica sul PC

  static Future<Directory> autoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}Dollarz backup');
  }

  /// Una copia al giorno in Documenti\Dollarz backup (le ultime 14), se è stata scelta una password.
  static Future<void> autoBackup(AppState app) async {
    if (!isDesktop) return;
    final k = app.prefs.get<String>('backupKey'), s = app.prefs.get<String>('backupSalt');
    if (k == null || s == null || app.store.isEmpty) return;
    final dir = await autoDir();
    final f = File('${dir.path}${Platform.pathSeparator}${fileName()}');
    if (f.existsSync()) return;
    await dir.create(recursive: true);
    await f.writeAsBytes(await build(app, base64.decode(k), base64.decode(s)), flush: true);
    final old = dir.listSync().whereType<File>().where((x) => x.path.endsWith('.dzb')).toList()..sort((a, b) => b.path.compareTo(a.path));
    for (final x in old.skip(14)) {
      try {
        x.deleteSync();
      } catch (_) {}
    }
  }

  /// Imposta (o toglie, con null) la password della copia automatica.
  static Future<void> setAutoPassword(AppState app, String? password) async {
    if (password == null) {
      app.prefs.set('backupKey', null);
      app.prefs.set('backupSalt', null);
      return;
    }
    final salt = CryptoBox.randomBytes(16);
    final key = await CryptoBox.keyFromPassword(password, salt);
    app.prefs.set('backupSalt', base64.encode(salt));
    app.prefs.set('backupKey', base64.encode(key));
  }

  static bool autoOn(AppState app) => app.prefs.get<String>('backupKey') != null;
}

// ------------------------------------------------------------------ CSV dei movimenti

String _cell(Object? v) {
  final s = v == null ? '' : v.toString();
  if (s.contains(';') || s.contains('"') || s.contains('\n')) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String movementsCsv(AppState app) {
  final b = StringBuffer('﻿');
  b.writeln(['data', 'conto', 'importo', 'valuta', 'categoria', 'descrizione', 'note'].join(';'));
  for (final t in app.txs.reversed) {
    final a = app.account(t.accountId);
    b.writeln([
      t.date,
      a?.name ?? '',
      fDec(t.amount / 100, 2).replaceAll('.', ''),
      a?.currency ?? 'EUR',
      app.cat(t.catId)?.name ?? '',
      t.desc,
      t.note,
    ].map(_cell).join(';'));
  }
  return b.toString();
}

Future<String?> exportMovementsCsv(AppState app) async {
  final data = movementsCsv(app);
  final name = 'dollarz-movimenti-${todayKey()}.csv';
  if (isDesktop) {
    final loc = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
      confirmButtonText: 'Salva',
    );
    if (loc == null) return null;
    await File(loc.path).writeAsString(data, encoding: utf8);
    return loc.path;
  }
  final tmp = await getTemporaryDirectory();
  final f = File('${tmp.path}${Platform.pathSeparator}$name');
  await f.writeAsString(data, encoding: utf8);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], subject: 'Movimenti Dollarz'));
  return 'condivisione';
}
