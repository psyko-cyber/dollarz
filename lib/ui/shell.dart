import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/coach.dart';
import '../services/backup.dart';
import '../services/services.dart';
import '../services/updates.dart';
import 'accounts.dart';
import 'assets.dart';
import 'budget.dart';
import 'future.dart';
import 'home.dart';
import 'import_screen.dart';
import 'inbox.dart';
import 'invest.dart';
import 'scheduled.dart';
import 'settings/profile.dart';
import 'settings/settings.dart';
import 'transactions.dart';
import 'tx_editor.dart';
import 'update_dialog.dart';
import 'widgets.dart';

/// Permette alle schermate di cambiare scheda e di aprire il "nuovo movimento".
class ShellNav {
  static final tab = ValueNotifier<int>(0);
  static final quickAdd = ValueNotifier<int>(0);
  static void go(int i) => tab.value = i;
}

/// Apre la destinazione di una mossa o di un avviso del coach.
void openRoute(BuildContext context, String route) {
  final nav = Navigator.of(context);
  void tab(int i) {
    nav.popUntil((r) => r.isFirst);
    ShellNav.go(i);
  }

  switch (route) {
    case CoachRoute.patrimonio:
      tab(0);
    case CoachRoute.movimenti:
      tab(1);
    case CoachRoute.scadenze:
      tab(2);
    case CoachRoute.investimenti:
      tab(3);
    case CoachRoute.futuro:
      tab(4);
    case CoachRoute.budget:
      push(context, const BudgetScreen());
    case CoachRoute.debiti:
      push(context, const AssetsScreen());
    case CoachRoute.inbox:
      push(context, const InboxScreen());
    case CoachRoute.profilo:
      push(context, const ProfileScreen());
    case CoachRoute.conti:
      push(context, const AccountsScreen());
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData iconOn;
  const _NavItem(this.label, this.icon, this.iconOn);
}

const _items = [
  _NavItem('Patrimonio', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded),
  _NavItem('Movimenti', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  _NavItem('Scadenze', Icons.event_outlined, Icons.event_rounded),
  _NavItem('Investimenti', Icons.show_chart_outlined, Icons.show_chart_rounded),
  _NavItem('Futuro', Icons.flag_outlined, Icons.flag_rounded),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    ShellNav.tab.addListener(_onTab);
    ShellNav.quickAdd.addListener(_onQuickAdd);
    Services.bank.sharedFile.addListener(_onShared);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    ShellNav.tab.removeListener(_onTab);
    ShellNav.quickAdd.removeListener(_onQuickAdd);
    Services.bank.sharedFile.removeListener(_onShared);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // il PC resta aperto nel tray per giorni: ricontrolla gli aggiornamenti ogni 6 ore
    if (DateTime.now().millisecondsSinceEpoch - context.appRead.prefs.lastUpdateCheck > 6 * 3600 * 1000) unawaited(_checkUpdate());
  }

  void _onTab() => setState(() {});
  void _onQuickAdd() => openTxEditor(context);

  void _onShared() {
    final p = Services.bank.sharedFile.value;
    if (p == null) return;
    Services.bank.sharedFile.value = null;
    push(context, ImportScreen(path: p));
  }

  Future<void> _checkUpdate() async {
    final prefs = context.appRead.prefs;
    final u = await checkForUpdate(prefs, force: true);
    if (u == null || !mounted || updateSnoozed(prefs, u)) return;
    updateNotice.value = u;
    await offerUpdate(context, u);
  }

  Future<void> _startup() async {
    final app = context.appRead;
    unawaited(Services.bank.setSecure(app.prefs.secureScreen));
    app.matchScheduled();
    app.updateSnapshot();
    _onShared();
    unawaited(cleanUpdates());
    unawaited(Services.prices.refresh());
    unawaited(Backup.autoBackup(app));
    await Services.notif.requestPermission();
    unawaited(_checkUpdate());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final index = ShellNav.tab.value;
    final wide = isWide(context);
    const pages = [HomeTab(), TransactionsTab(), ScheduledTab(), InvestTab(), FutureTab()];
    final body = IndexedStack(index: index, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          _SideNav(index: index, onTap: ShellNav.go),
          VerticalDivider(width: 1, color: t.line),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: FloatingActionButton(
        backgroundColor: TC.accent,
        foregroundColor: TC.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: () {
          HapticFeedback.lightImpact();
          openTxEditor(context);
        },
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      bottomNavigationBar: _BottomNav(index: index, onTap: ShellNav.go),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.line))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(index == i ? _items[i].iconOn : _items[i].icon, size: 23, color: index == i ? TC.accent : t.dim),
                    const SizedBox(height: 3),
                    Text(_items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(fontSize: 10.5, fontWeight: index == i ? FontWeight.w700 : FontWeight.w500, color: index == i ? t.ink : t.dim)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _SideNav({required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    Widget item(IconData icon, String label, bool on, VoidCallback tap) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: on ? t.surf2 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  Icon(icon, size: 22, color: on ? TC.accent : t.dim),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 14.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? t.ink : t.soft)),
                ]),
              ),
            ),
          ),
        );
    return Container(
      width: 228,
      color: t.bg,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const DollarzMark(size: 34),
          const SizedBox(width: 10),
          Text('Dollarz', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: t.ink)),
        ]),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Nuovo movimento', icon: Icons.add_rounded, onTap: () => openTxEditor(context)),
        const SizedBox(height: 18),
        for (var i = 0; i < _items.length; i++) item(index == i ? _items[i].iconOn : _items[i].icon, _items[i].label, index == i, () => onTap(i)),
        const Spacer(),
        ListenableBuilder(
          listenable: Services.sync,
          builder: (context, _) {
            final s = Services.sync;
            final on = s.serverRunning;
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Icon(on ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 16, color: on ? TC.accent : t.dim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(on ? (s.lastServed == null ? 'Sync Wi-Fi attiva' : 'Sync ${hhmm(s.lastServed!)}') : 'Sync Wi-Fi spenta',
                      style: TextStyle(fontSize: 12, color: t.dim)),
                ),
              ]),
            );
          },
        ),
        item(Icons.settings_outlined, 'Impostazioni', false, () => push(context, const SettingsScreen())),
        if (isDesktop) Padding(padding: const EdgeInsets.only(left: 12, top: 6), child: Text('v$appVersion', style: TS.muted(t, 11))),
      ]),
    );
  }
}
