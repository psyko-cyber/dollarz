import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/crypto_box.dart';
import '../core/ids.dart';

/// Un record versionato. Ogni scrittura aggiorna [u] (timestamp ms) e [s]
/// (sequenza locale): la sincronizzazione usa [s] per sapere cosa inviare e
/// [u] + [v] per risolvere i conflitti (vince l'ultima modifica).
class Rec {
  final String id;
  Map<String, dynamic> d;
  int u;
  bool x;
  String v;
  int s;

  Rec(this.id, this.d, this.u, this.x, this.v, this.s);

  Map<String, dynamic> toJson() => {'id': id, 'd': d, 'u': u, 'x': x, 'v': v, 's': s};

  factory Rec.fromJson(Map m) => Rec(
        m['id'] as String,
        Map<String, dynamic>.from((m['d'] as Map?) ?? const {}),
        (m['u'] as num?)?.toInt() ?? 0,
        m['x'] == true,
        (m['v'] as String?) ?? '',
        (m['s'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> wire(String c) => {'c': c, 'id': id, 'd': x ? const {} : d, 'u': u, 'x': x, 'v': v};
}

/// Archivio locale a documenti, cifrato: una collezione = un file `.dz`
/// (AES-256-GCM con la chiave del dispositivo). Tutto resta in memoria e si
/// salva con debounce.
class Store extends ChangeNotifier {
  static const synced = [
    'profile', 'accounts', 'tx', 'cats', 'rules', 'sched', 'occ',
    'holdings', 'trades', 'assets', 'snaps', 'prices', 'consult', 'inbox', 'misc',
  ];

  late Directory root;
  late Directory dataDir;
  late List<int> _key;
  String deviceId = '';
  int seq = 0;

  /// Cresce a ogni modifica: serve a invalidare le cache derivate.
  int revision = 0;

  final _c = <String, Map<String, Rec>>{};
  final _dirty = <String>{};
  bool _metaDirty = false;
  Timer? _saveTimer;
  Future<void>? _saving;

  /// Chiamato dopo ogni modifica locale (non per quelle arrivate dalla sync).
  VoidCallback? onLocalChange;

  /// File che non si sono potuti aprire (chiave diversa o danneggiati).
  /// Finché non è vuoto non si scrive nulla su disco: i file restano intatti
  /// per un ripristino, finché l'utente non sceglie di ricominciare ([wipe]).
  final unreadable = <String>[];

  /// false nei test: niente salvataggi automatici con il timer.
  static bool autoSave = true;

  Future<void> init({Directory? dir, required List<int> key}) async {
    _key = key;
    root = dir ?? await getApplicationSupportDirectory();
    dataDir = Directory('${root.path}${Platform.pathSeparator}data')..createSync(recursive: true);
    final meta = await _readJson('_meta');
    deviceId = (meta?['deviceId'] as String?) ?? newId();
    seq = (meta?['seq'] as num?)?.toInt() ?? 0;
    for (final name in synced) {
      final j = await _readJson(name);
      if (j == null) continue;
      final m = <String, Rec>{};
      for (final r in (j['recs'] as List? ?? const [])) {
        final rec = Rec.fromJson(r as Map);
        m[rec.id] = rec;
        if (rec.s > seq) seq = rec.s;
      }
      _c[name] = m;
    }
    if (meta == null) {
      _metaDirty = true;
      _scheduleSave();
    }
  }

  /// true se non c'è ancora nessun dato (primo avvio).
  bool get isEmpty => synced.every((c) => count(c) == 0);

  // ------------------------------------------------------------ lettura

  Map<String, Rec> col(String c) => _c.putIfAbsent(c, () => <String, Rec>{});

  Iterable<Map<String, dynamic>> all(String c) => col(c).values.where((r) => !r.x).map((r) => r.d);

  Map<String, dynamic>? get(String c, String id) {
    final r = col(c)[id];
    return (r == null || r.x) ? null : r.d;
  }

  int count(String c) => col(c).values.where((r) => !r.x).length;

  // ------------------------------------------------------------ scrittura

  void put(String c, String id, Map<String, dynamic> data, {bool notify = true}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = col(c)[id];
    final u = (prev != null && prev.u >= now) ? prev.u + 1 : now;
    final d = Map<String, dynamic>.from(data)..['id'] = id;
    col(c)[id] = Rec(id, d, u, false, deviceId, ++seq);
    _changed(c, notify: notify);
  }

  void remove(String c, String id) {
    final prev = col(c)[id];
    if (prev == null || prev.x) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    col(c)[id] = Rec(id, {}, prev.u >= now ? prev.u + 1 : now, true, deviceId, ++seq);
    _changed(c);
  }

  /// Più scritture con una sola notifica.
  void batch(void Function() fn) {
    final was = _silent;
    _silent = true;
    if (!was) _touched = false;
    try {
      fn();
    } finally {
      _silent = was;
    }
    if (!was && _touched) {
      revision++;
      notifyListeners();
      onLocalChange?.call();
    }
  }

  bool _silent = false;
  bool _touched = false;

  void _changed(String c, {bool notify = true}) {
    _dirty.add(c);
    _metaDirty = true;
    _scheduleSave();
    if (_silent) {
      _touched = true;
      return;
    }
    revision++;
    if (notify) notifyListeners();
    onLocalChange?.call();
  }

  // ------------------------------------------------------------ sync

  /// Record modificati dopo la sequenza [since] (formato di rete).
  List<Map<String, dynamic>> changesSince(int since) {
    final out = <Map<String, dynamic>>[];
    for (final c in synced) {
      for (final r in col(c).values) {
        if (r.s > since) out.add(r.wire(c));
      }
    }
    return out;
  }

  /// Applica modifiche remote con "vince l'ultima". Ritorna quante hanno vinto.
  int applyRemote(List changes) {
    var n = 0;
    for (final w in changes) {
      if (w is! Map) continue;
      final c = w['c'];
      final id = w['id'];
      if (c is! String || id is! String || !synced.contains(c)) continue;
      final u = (w['u'] as num?)?.toInt() ?? 0;
      final v = (w['v'] as String?) ?? '';
      final cur = col(c)[id];
      if (cur != null) {
        if (u < cur.u) continue;
        if (u == cur.u && v.compareTo(cur.v) <= 0) continue;
      }
      final d = Map<String, dynamic>.from((w['d'] as Map?) ?? const {});
      col(c)[id] = Rec(id, d, u, w['x'] == true, v, ++seq);
      _dirty.add(c);
      n++;
    }
    if (n > 0) {
      _metaDirty = true;
      _scheduleSave();
      revision++;
      notifyListeners();
    }
    return n;
  }

  // ------------------------------------------------------------ backup

  Map<String, dynamic> exportAll() => {
        'app': 'dollarz',
        'format': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'changes': [
          for (final c in synced)
            for (final r in col(c).values)
              if (!r.x) r.wire(c),
        ],
      };

  int importAll(Map<String, dynamic> backup) {
    if (backup['app'] != 'dollarz') throw const FormatException('Il file non è un backup di Dollarz');
    return applyRemote((backup['changes'] as List?) ?? const []);
  }

  Future<void> wipe() async {
    _saveTimer?.cancel();
    await _saving;
    unreadable.clear();
    _c.clear();
    _dirty.clear();
    for (final f in dataDir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }
    seq = 0;
    deviceId = newId();
    _metaDirty = true;
    await flush();
    revision++;
    notifyListeners();
  }

  // ------------------------------------------------------------ persistenza

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (!autoSave || unreadable.isNotEmpty) return;
    _saveTimer = Timer(const Duration(milliseconds: 400), () => flush());
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    if (unreadable.isNotEmpty) return;
    // un salvataggio alla volta: il secondo aspetta il primo
    while (_saving != null) {
      await _saving;
    }
    final f = _flush();
    _saving = f;
    try {
      await f;
    } finally {
      _saving = null;
    }
  }

  Future<void> _flush() async {
    final dirty = _dirty.toList();
    _dirty.clear();
    for (final c in dirty) {
      final recs = col(c).values.map((r) => r.toJson()).toList();
      await _writeJson(c, {'recs': recs});
    }
    if (_metaDirty) {
      _metaDirty = false;
      await _writeJson('_meta', {'deviceId': deviceId, 'seq': seq});
    }
  }

  File _file(String name) => File('${dataDir.path}${Platform.pathSeparator}$name.dz');

  Future<Map<String, dynamic>?> _readJson(String name) async {
    var existed = false;
    for (final f in [_file(name), File('${_file(name).path}.bak')]) {
      try {
        if (!f.existsSync()) continue;
        existed = true;
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        final txt = await CryptoBox.openString(_key, bytes);
        return Map<String, dynamic>.from(jsonDecode(txt) as Map);
      } catch (e) {
        debugPrint('Store: file $name illeggibile ($e), provo il backup');
      }
    }
    if (existed) unreadable.add(name);
    return null;
  }

  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    final target = _file(name);
    final tmp = File('${target.path}.tmp');
    final sealed = await CryptoBox.sealString(_key, jsonEncode(data));
    await tmp.writeAsBytes(sealed, flush: true);
    final bak = File('${target.path}.bak');
    try {
      if (target.existsSync()) {
        if (bak.existsSync()) bak.deleteSync();
        target.renameSync(bak.path);
      }
    } catch (_) {}
    await _replace(tmp, target);
  }

  Future<void> _replace(File from, File to) async {
    try {
      await from.rename(to.path);
    } catch (_) {
      if (to.existsSync()) to.deleteSync();
      await from.rename(to.path);
    }
  }
}
