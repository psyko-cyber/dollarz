import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/app_state.dart';

class _Planned {
  final String key;
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const _Planned(this.key, this.id, this.at, this.title, this.body);
}

/// Promemoria locali: scadenze in arrivo, conto che va in rosso, resoconti.
/// Android: pianificati per i prossimi 14 giorni. Windows: controllo ogni 30 s
/// mentre l'app è aperta o nel tray.
class NotificationService {
  final AppState app;
  NotificationService(this.app);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _ticker;
  Timer? _debounce;
  final _fired = <String>{};

  static const _channel = AndroidNotificationDetails(
    'scadenze',
    'Scadenze e avvisi',
    channelDescription: 'Pagamenti in arrivo, conti che vanno in rosso, resoconti',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _hour = 9;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_dollarz'),
          windows: WindowsInitializationSettings(
            appName: 'Dollarz',
            appUserModelId: 'Dollarz.App',
            guid: '3f6b2c1e-8a4d-4f7b-9c2e-5d1a7b6e0c94',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notifiche non disponibili: $e');
    }
    if (isDesktop) _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tickDesktop());
  }

  Future<bool> requestPermission() async {
    if (!_ready || !isAndroid) return true;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.requestNotificationsPermission() ?? true;
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000 + 5000,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
      );
    } catch (e) {
      debugPrint('notifica non mostrata: $e');
    }
  }

  // ---------------------------------------------------------------- piano

  List<_Planned> _plan({int days = 14, Duration grace = Duration.zero}) {
    final now = DateTime.now();
    final out = <_Planned>[];
    if (!app.onboarded) return out;
    DateTime at(DateTime d, [int h = _hour, int m = 0]) => DateTime(d.year, d.month, d.day, h, m);
    final t = todayKey();
    var id = 100;

    // scadenze: qualche giorno prima (e il giorno stesso se il promemoria è a 0)
    for (final o in app.upcoming) {
      if (!o.open || o.date.compareTo(t) < 0) continue;
      final due = fromKey(o.date);
      final remind = addDays(due, -o.sched.remindDays);
      if (daysBetween(today(), remind) > days) continue;
      final amount = o.sched.variable ? 'circa ${fEuro(o.amount.abs())}' : fCents(o.amount.abs());
      final when = o.sched.remindDays == 0 ? 'oggi' : inDays(o.sched.remindDays);
      out.add(_Planned(
        'sched:${o.id}',
        id++,
        at(remind),
        o.amount > 0 ? 'In arrivo $when: ${o.sched.name}' : 'Scade $when: ${o.sched.name}',
        '$amount · ${shortDate(due)}${o.sched.accountId != null ? ' · ${app.account(o.sched.accountId)?.name ?? ''}' : ''}',
      ));
      if (id > 160) break;
    }

    // conto in rosso nei prossimi 10 giorni: avviso domattina
    final red = app.firstRed;
    if (red != null && daysBetween(today(), fromKey(red.$2.date)) <= 10) {
      final day = now.hour < _hour ? today() : addDays(today(), 1);
      out.add(_Planned('red:${red.$1.id}:${red.$2.date}', 190, at(day, _hour, 5), '${red.$1.name} andrà in rosso',
          'Saldo previsto ${fEuro(red.$2.balance)} il ${shortDate(fromKey(red.$2.date))}: sposta dei soldi prima.'));
    }

    // resoconti: il primo del mese e il lunedì
    for (var d = 0; d < days; d++) {
      final day = addDays(today(), d);
      if (day.day == 1) {
        final prev = addMonthsKey(monthKey(day), -1);
        out.add(_Planned('rep:m:$prev', 200 + d, at(day, 10), 'Resoconto di ${mesi[fromKey('$prev-01').month - 1]}',
            'Quanto hai messo da parte e dove sono andati i soldi.'));
      } else if (day.weekday == DateTime.monday) {
        out.add(_Planned('rep:w:${dayKey(day)}', 200 + d, at(day, 10), 'Resoconto della settimana', 'Spese e prossima mossa del coach.'));
      }
    }
    return out.where((e) => e.at.isAfter(now.subtract(grace))).toList();
  }

  /// Da chiamare quando cambiano dati rilevanti (con debounce).
  void reschedule({Duration delay = const Duration(seconds: 8)}) {
    if (!isAndroid) return;
    _debounce?.cancel();
    _debounce = Timer(delay, _scheduleAndroid);
  }

  Future<void> _scheduleAndroid() async {
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id < 1000) await _plugin.cancel(id: p.id);
      }
      for (final e in _plan()) {
        await _plugin.zonedSchedule(
          id: e.id,
          title: e.title,
          body: e.body,
          scheduledDate: tz.TZDateTime.from(e.at, tz.local),
          notificationDetails: const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('pianificazione promemoria fallita: $e');
    }
  }

  // ---------------------------------------------------------------- desktop

  void _tickDesktop() {
    if (!_ready || !app.onboarded) return;
    final now = DateTime.now();
    // scatta tutto ciò che è scaduto nell'ultimo minuto (il ticker gira ogni 30 s)
    for (final e in _plan(days: 1, grace: const Duration(seconds: 90))) {
      final d = now.difference(e.at).inSeconds;
      if (d < 0 || d > 60 || _fired.contains(e.key)) continue;
      _fired.add(e.key);
      show(e.title, e.body);
    }
  }

  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
  }
}
