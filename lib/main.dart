import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/ids.dart';
import 'core/theme.dart';
import 'data/app_state.dart';
import 'data/local_prefs.dart';
import 'data/store.dart';
import 'services/bank_bridge.dart';
import 'services/desktop.dart';
import 'services/lock.dart';
import 'services/notifications.dart';
import 'services/prices.dart';
import 'services/resume_guard.dart';
import 'services/secure_key.dart';
import 'services/services.dart';
import 'services/sync.dart';
import 'ui/shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    // Se Dollarz è già aperto (anche nel tray) mostro quella finestra ed esco.
    if (!await DesktopService.ensureSingleInstance()) exit(0);
    await DesktopService.initWindow(hidden: args.contains('--tray'));
  }

  final List<int> key;
  try {
    (key, _) = await SecureKey.load();
  } catch (e) {
    runApp(FatalApp(message: 'Non riesco ad aprire il portachiavi del sistema, dove sta la chiave dei tuoi dati.\n\n$e'));
    return;
  }

  final store = Store();
  await store.init(key: key);
  final prefs = LocalPrefs();
  await prefs.init(store.root, key);
  final app = AppState(store, prefs);

  final sync = SyncService(app);
  final notif = NotificationService(app);
  final lock = LockService(prefs);
  final prices = PriceService(app);
  final bank = BankBridge(app);
  Services.app = app;
  Services.sync = sync;
  Services.notif = notif;
  Services.lock = lock;
  Services.prices = prices;
  Services.bank = bank;

  store.onLocalChange = () {
    sync.onLocalChange();
    notif.reschedule();
  };

  await lock.init();
  await notif.init();

  if (isDesktop) {
    final d = DesktopService(
      app,
      onSyncNow: () async {
        if (sync.paired) await sync.syncNow();
      },
      onQuit: () async {
        await store.flush();
        await prefs.flush();
        await sync.stopServer();
      },
      onQuickAdd: () => ShellNav.quickAdd.value++,
    );
    Services.desktop = d;
    await d.init();
    installResumeGuard();
    if (prefs.serverEnabled) unawaited(sync.startServer());
  }

  runApp(DollarzApp(app: app));

  unawaited(bank.init());
  if (sync.paired) {
    sync.startAuto();
    unawaited(sync.syncNow(quiet: true));
  }
  prices.startAuto();
  notif.reschedule(delay: const Duration(seconds: 3));
}

/// Schermata di errore quando non si può nemmeno aprire i dati.
class FatalApp extends StatelessWidget {
  final String message;
  const FatalApp({super.key, required this.message});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline_rounded, size: 44, color: TC.warn),
                const SizedBox(height: 16),
                const Text('Dollarz non può partire', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      );
}
