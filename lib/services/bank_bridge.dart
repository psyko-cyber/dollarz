import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/ids.dart';
import '../data/app_state.dart';
import '../logic/bank_notif.dart';

/// Ponte con il codice Android: notifiche delle banche e file condivisi
/// ("Condividi → Dollarz" da un'altra app).
class BankBridge extends ChangeNotifier {
  static const _ch = MethodChannel('dollarz/native');
  final AppState app;
  BankBridge(this.app);

  /// File arrivato da "Condividi": la UI apre l'import.
  final sharedFile = ValueNotifier<String?>(null);

  bool access = false;

  Future<void> init() async {
    if (!isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'bankNotif':
          await drain();
        case 'sharedFile':
          if (call.arguments is String) sharedFile.value = call.arguments as String;
      }
      return null;
    });
    await setSecure(app.prefs.secureScreen);
    await pushApps();
    await checkAccess();
    await drain();
    final f = await _ch.invokeMethod<String>('takeSharedFile').catchError((_) => null);
    if (f != null) sharedFile.value = f;
  }

  Future<bool> checkAccess() async {
    if (!isAndroid) return false;
    try {
      access = await _ch.invokeMethod<bool>('notifAccess') ?? false;
    } catch (_) {
      access = false;
    }
    notifyListeners();
    return access;
  }

  Future<void> openNotifSettings() => _ch.invokeMethod('openNotifSettings');
  Future<void> openAppDetails() => _ch.invokeMethod('openAppDetails');
  Future<void> setSecure(bool on) async {
    if (isAndroid) await _ch.invokeMethod('setSecure', on);
  }

  Future<void> pushApps() async {
    if (!isAndroid) return;
    try {
      await _ch.invokeMethod('setBankApps', app.prefs.bankApps);
    } catch (_) {}
  }

  bool _draining = false;

  /// Legge le notifiche arrivate (anche mentre l'app era chiusa) e le trasforma in movimenti.
  Future<int> drain() async {
    if (!isAndroid || _draining) return 0;
    _draining = true;
    try {
      final raw = await _ch.invokeMethod<String>('takeBankNotifs');
      if (raw == null || raw.isEmpty || raw == '[]') return 0;
      final list = jsonDecode(raw) as List;
      var n = 0;
      if (!app.prefs.bankNotifOn) return 0;
      final seen = [...app.prefs.notifSeen];
      final log = [...app.prefs.notifLog];
      app.store.batch(() {
        for (final x in list) {
          if (x is! Map) continue;
          final b = BankNotif.fromMap(x.cast<String, dynamic>());
          if (seen.contains(b.id)) continue;
          seen.add(b.id);
          final res = app.ingestNotif(b);
          log.add({...b.toMap(), 'res': res});
          n++;
        }
      });
      app.prefs.notifSeen = seen;
      app.prefs.notifLog = log;
      return n;
    } catch (e) {
      debugPrint('notifiche banca: $e');
      return 0;
    } finally {
      _draining = false;
    }
  }
}
