import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/crypto_box.dart';
import '../core/ids.dart';

/// Impostazioni del singolo dispositivo (NON sincronizzate), cifrate come i dati:
/// PIN, chiave Gemini, abbinamento Wi-Fi, notifiche banca, avvio automatico…
class LocalPrefs extends ChangeNotifier {
  late File _file;
  late List<int> _key;
  Map<String, dynamic> _m = {};
  Timer? _timer;

  /// false nei test: niente salvataggi automatici con il timer.
  static bool autoSave = true;

  Future<void> init(Directory root, List<int> key) async {
    _key = key;
    _file = File('${root.path}${Platform.pathSeparator}local.dz');
    try {
      if (_file.existsSync()) {
        _m = Map<String, dynamic>.from(jsonDecode(await CryptoBox.openString(_key, await _file.readAsBytes())) as Map);
      }
    } catch (e) {
      debugPrint('LocalPrefs illeggibili: $e');
      _m = {};
    }
  }

  T? get<T>(String k) => _m[k] as T?;

  void set(String k, Object? v) {
    if (v == null) {
      _m.remove(k);
    } else {
      _m[k] = v;
    }
    _timer?.cancel();
    if (autoSave) _timer = Timer(const Duration(milliseconds: 250), flush);
    notifyListeners();
  }

  Future<void> flush() async {
    _timer?.cancel();
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsBytes(await CryptoBox.sealString(_key, jsonEncode(_m)), flush: true);
      if (_file.existsSync()) _file.deleteSync();
      tmp.renameSync(_file.path);
    } catch (e) {
      debugPrint('LocalPrefs: salvataggio fallito $e');
    }
  }

  // ---------------------------------------------------------------- blocco
  String? get pinHash => get<String>('pinHash');
  String? get pinSalt => get<String>('pinSalt');
  void setPin(String hash, String salt) {
    set('pinSalt', salt);
    set('pinHash', hash);
  }

  bool get hasPin => pinHash != null;
  bool get bioOn => get<bool>('bioOn') ?? false;
  set bioOn(bool v) => set('bioOn', v);

  /// Minuti in background prima di richiedere lo sblocco (0 = subito).
  int get lockAfterMin => get<int>('lockAfter') ?? 2;
  set lockAfterMin(int v) => set('lockAfter', v);
  int get failCount => get<int>('failCount') ?? 0;
  set failCount(int v) => set('failCount', v);
  int get lockedUntil => get<int>('lockedUntil') ?? 0;
  set lockedUntil(int v) => set('lockedUntil', v);

  /// Android: niente screenshot e anteprima nascosta nelle app recenti (spenta di base).
  bool get secureScreen => get<bool>('secureScreen') ?? false;
  set secureScreen(bool v) => set('secureScreen', v);

  /// Importi nascosti in home (per quando c'è gente intorno).
  bool get hideAmounts => get<bool>('hideAmounts') ?? false;
  set hideAmounts(bool v) => set('hideAmounts', v);

  // ---------------------------------------------------------------- Gemini
  String get geminiKey => get<String>('geminiKey') ?? '';
  set geminiKey(String v) => set('geminiKey', v.trim().isEmpty ? null : v.trim());
  String get geminiModel => get<String>('geminiModel') ?? 'gemini-flash-latest';
  set geminiModel(String v) => set('geminiModel', v.trim().isEmpty ? null : v.trim());

  // ---------------------------------------------------------------- sync (client)
  /// {hosts: [..], port: 47820, key: '...', name: 'PC', serverId}
  Map<String, dynamic>? get pairing => (get<Map>('pairing'))?.cast<String, dynamic>();
  set pairing(Map<String, dynamic>? v) => set('pairing', v);
  int get lastServerSeq => get<int>('lastServerSeq') ?? 0;
  set lastServerSeq(int v) => set('lastServerSeq', v);
  int get lastPushedSeq => get<int>('lastPushedSeq') ?? 0;
  set lastPushedSeq(int v) => set('lastPushedSeq', v);
  int get lastSyncAt => get<int>('lastSyncAt') ?? 0;
  set lastSyncAt(int v) => set('lastSyncAt', v);

  // ---------------------------------------------------------------- sync (server PC)
  /// Sul PC il server di sincronizzazione è attivo di default.
  bool get serverEnabled => get<bool>('serverEnabled') ?? isDesktop;
  set serverEnabled(bool v) => set('serverEnabled', v);
  String? get serverKey => get<String>('serverKey');
  set serverKey(String? v) => set('serverKey', v);

  /// Dispositivi che si sono sincronizzati: {id: {name, at}}
  Map<String, dynamic> get peers => (get<Map>('peers') ?? {}).cast<String, dynamic>();
  set peers(Map<String, dynamic> v) => set('peers', v);

  // ---------------------------------------------------------------- notifiche banca (Android)
  bool get bankNotifOn => get<bool>('bankNotifOn') ?? false;
  set bankNotifOn(bool v) => set('bankNotifOn', v);

  /// App in più da ascoltare (nomi di pacchetto), oltre a Revolut, Fineco e Trade Republic.
  List<String> get bankApps => (get<List>('bankApps') ?? const []).cast<String>();
  set bankApps(List<String> v) => set('bankApps', v);

  /// Impronte delle notifiche già lette (per non creare doppioni).
  List<String> get notifSeen => (get<List>('notifSeen') ?? const []).cast<String>();
  set notifSeen(List<String> v) => set('notifSeen', v.length > 400 ? v.sublist(v.length - 400) : v);

  /// Notifiche ricevute di recente (testo grezzo, solo su questo telefono): per controllare i parser.
  List<Map<String, dynamic>> get notifLog => (get<List>('notifLog') ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  set notifLog(List<Map<String, dynamic>> v) => set('notifLog', v.length > 60 ? v.sublist(v.length - 60) : v);

  // ---------------------------------------------------------------- desktop
  bool get trayEnabled => get<bool>('tray') ?? true;
  set trayEnabled(bool v) => set('tray', v);
  bool get closeHintShown => get<bool>('closeHint') ?? false;
  set closeHintShown(bool v) => set('closeHint', v);

  // ---------------------------------------------------------------- aggiornamenti e varie
  int get lastUpdateCheck => get<int>('lastUpdateCheck') ?? 0;
  set lastUpdateCheck(int v) => set('lastUpdateCheck', v);
  Map<String, dynamic>? get availableUpdate => (get<Map>('update'))?.cast<String, dynamic>();
  set availableUpdate(Map<String, dynamic>? v) => set('update', v);
  String? get dismissedUpdate => get<String>('dismissedUpdate');
  set dismissedUpdate(String? v) => set('dismissedUpdate', v);
  int get updateLaterAt => get<int>('updateLaterAt') ?? 0;
  set updateLaterAt(int v) => set('updateLaterAt', v);

  int get pricesAt => get<int>('pricesAt') ?? 0;
  set pricesAt(int v) => set('pricesAt', v);

  /// Resoconti già visti ("m:2026-09", "w:2026-10-12").
  List<String> get reportsSeen => (get<List>('reportsSeen') ?? const []).cast<String>();
  set reportsSeen(List<String> v) => set('reportsSeen', v.length > 60 ? v.sublist(v.length - 60) : v);
}
