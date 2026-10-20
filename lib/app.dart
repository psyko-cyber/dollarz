import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/fmt.dart';
import 'core/theme.dart';
import 'data/app_state.dart';
import 'services/backup.dart';
import 'services/services.dart';
import 'ui/lock_screen.dart';
import 'ui/onboarding.dart';
import 'ui/recovery.dart';
import 'ui/shell.dart';

final navKey = GlobalKey<NavigatorState>();

class DollarzApp extends StatefulWidget {
  final AppState app;
  const DollarzApp({super.key, required this.app});
  @override
  State<DollarzApp> createState() => _DollarzAppState();
}

class _DollarzAppState extends State<DollarzApp> {
  late final AppLifecycleListener _life;
  String _day = todayKey();
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _onResume, onPause: _onPause, onHide: _onPause);
    // cambio di giorno anche se l'app resta aperta (tray sul PC)
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => _checkDay());
  }

  void _checkDay() {
    final k = todayKey();
    if (k == _day) return;
    _day = k;
    final app = widget.app;
    app.refresh();
    app.matchScheduled();
    app.updateSnapshot();
    Services.notif.reschedule(delay: const Duration(seconds: 2));
    unawaited(Backup.autoBackup(app));
  }

  void _onResume() {
    _checkDay();
    unawaited(Services.bank.drain());
    unawaited(Services.prices.refresh());
    if (Services.sync.paired) {
      Services.sync.startAuto();
      unawaited(Services.sync.syncNow(quiet: true));
    }
  }

  void _onPause() {
    widget.app.store.flush();
    widget.app.prefs.flush();
    Services.notif.reschedule(delay: Duration.zero);
  }

  @override
  void dispose() {
    _life.dispose();
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return AppScope(
      state: app,
      child: MaterialApp(
        title: 'Dollarz',
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        themeMode: ThemeMode.dark,
        locale: const Locale('it', 'IT'),
        supportedLocales: const [Locale('it', 'IT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // il blocco copre tutto, anche le schermate aperte sopra e i dialoghi
        builder: (context, child) => ListenableBuilder(
          listenable: Services.lock,
          builder: (context, _) => Stack(children: [
            child!,
            if (Services.lock.locked) const Positioned.fill(child: LockScreen()),
          ]),
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final Widget page;
    if (app.store.unreadable.isNotEmpty) {
      page = const RecoveryScreen(key: ValueKey('rec'));
    } else if (!app.onboarded) {
      page = const OnboardingScreen(key: ValueKey('onb'));
    } else {
      page = const HomeShell(key: ValueKey('home'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: page);
  }
}
