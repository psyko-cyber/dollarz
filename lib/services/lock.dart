import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../core/crypto_box.dart';
import '../core/ids.dart';
import '../data/local_prefs.dart';

/// Blocco dell'app: PIN (sempre) e impronta/volto o Windows Hello (se attivi).
/// Si blocca all'avvio e dopo [LocalPrefs.lockAfterMin] minuti in background.
class LockService extends ChangeNotifier with WidgetsBindingObserver {
  final LocalPrefs prefs;
  LockService(this.prefs);

  static const _pinIterations = 60000;

  final _auth = LocalAuthentication();
  bool locked = false;
  bool bioAvailable = false;
  DateTime? _bgAt;
  int _suspended = 0;

  bool get enabled => prefs.hasPin;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      bioAvailable = await _auth.isDeviceSupported();
      if (bioAvailable && isAndroid) bioAvailable = await _auth.canCheckBiometrics;
    } catch (_) {
      bioAvailable = false;
    }
    locked = enabled;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = state;
    if (!enabled) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      if (_suspended == 0) _bgAt ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final at = _bgAt;
      _bgAt = null;
      if (at != null && _suspended == 0 && DateTime.now().difference(at).inSeconds >= prefs.lockAfterMin * 60) lock();
    }
  }

  /// Per selettori di file, condivisione, fotocamera: uscire un attimo dall'app non la blocca.
  Future<T> withoutLock<T>(Future<T> Function() fn) async {
    _suspended++;
    try {
      return await fn();
    } finally {
      _suspended--;
      _bgAt = null;
    }
  }

  void lock() {
    if (!enabled || locked) return;
    locked = true;
    notifyListeners();
  }

  void _unlocked() {
    locked = false;
    _bgAt = null;
    notifyListeners();
  }

  bool get canUseBio => prefs.bioOn && bioAvailable;

  Future<bool> unlockBio() async {
    if (!canUseBio) return false;
    try {
      final ok = await withoutLock(() => _auth.authenticate(
            localizedReason: 'Sblocca Dollarz',
            biometricOnly: isAndroid,
            persistAcrossBackgrounding: true,
          ));
      if (ok) _unlocked();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Secondi da aspettare dopo troppi PIN sbagliati.
  int get waitSeconds => math.max(0, ((prefs.lockedUntil - DateTime.now().millisecondsSinceEpoch) / 1000).ceil());

  Future<bool> unlockPin(String pin) async {
    if (waitSeconds > 0) return false;
    if (await checkPin(pin)) {
      prefs.failCount = 0;
      prefs.lockedUntil = 0;
      _unlocked();
      return true;
    }
    final n = prefs.failCount + 1;
    prefs.failCount = n;
    if (n >= 5) prefs.lockedUntil = DateTime.now().millisecondsSinceEpoch + 30000 * (1 << math.min(6, n - 5));
    notifyListeners();
    return false;
  }

  Future<bool> checkPin(String pin) async {
    final salt = prefs.pinSalt, hash = prefs.pinHash;
    if (salt == null || hash == null) return true;
    final k = await CryptoBox.keyFromPassword(pin, base64.decode(salt), iterations: _pinIterations);
    final a = base64.encode(k);
    // confronto a tempo costante
    if (a.length != hash.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> setPin(String pin) async {
    final salt = CryptoBox.randomBytes(16);
    final k = await CryptoBox.keyFromPassword(pin, salt, iterations: _pinIterations);
    prefs.setPin(base64.encode(k), base64.encode(salt));
    prefs.failCount = 0;
    notifyListeners();
  }

  void removePin() {
    prefs.set('pinHash', null);
    prefs.set('pinSalt', null);
    prefs.bioOn = false;
    locked = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
