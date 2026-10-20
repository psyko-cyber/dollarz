import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/coach.dart';
import '../services/updates.dart';
import 'accounts.dart';
import 'budget.dart';
import 'charts.dart';
import 'report_screen.dart';
import 'scheduled.dart';
import 'settings/settings.dart';
import 'shell.dart';
import 'update_dialog.dart';
import 'widgets.dart';

/// Scheda Patrimonio (home): patrimonio netto, prossima mossa, avvisi, conti.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final coach = app.coach;
    final name = app.profile.name.trim();
    final h = DateTime.now().hour;
    final hello = h < 13 ? 'Buongiorno' : (h < 18 ? 'Buon pomeriggio' : 'Buonasera');
    final report = app.dueReport;
    final upcoming = app.upcoming.where((o) => o.open && o.date.compareTo(addDaysKey(todayKey(), 7)) <= 0).take(5).toList();

    final left = <Widget>[
      const _NetWorthCard(),
      ValueListenableBuilder<UpdateInfo?>(
        valueListenable: updateNotice,
        builder: (context, u, _) => u == null
            ? const SizedBox.shrink()
            : DCard(
                border: t.accentLine,
                onTap: () => offerUpdate(context, u, ask: false),
                child: Row(children: [
                  const Icon(Icons.system_update_rounded, color: TC.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Dollarz ${u.version} disponibile: tocca per aggiornare', style: TS.title(t))),
                ]),
              ),
      ),
      if (report != null)
        DCard(
          onTap: () {
            app.markReportSeen(report.id);
            push(context, ReportScreen(reportId: report.id));
          },
          child: Row(children: [
            const Icon(Icons.summarize_outlined, color: TC.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(report.kind == 'month' ? 'Resoconto di ${report.title.toLowerCase()}' : report.title, style: TS.title(t)),
                Text(report.lines.first, style: TS.muted(t, 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(onPressed: () => app.markReportSeen(report.id), icon: Icon(Icons.close_rounded, color: t.dim, size: 19)),
          ]),
        ),
      _MoveCard(result: coach),
      for (final a in coach.alerts.take(5)) _AlertRow(alert: a),
    ];
    final right = <Widget>[
      if (isWide(context)) const SizedBox(height: 0) else const SizedBox(height: 4),
      const SpendPlanCard(),
      SectionLabel('Conti', action: 'Gestisci', onAction: () => push(context, const AccountsScreen())),
      if (app.accounts.isEmpty)
        DCard(
          onTap: () => push(context, const AccountEditor()),
          child: Row(children: [
            const Icon(Icons.add_rounded, color: TC.accent),
            const SizedBox(width: 10),
            Text('Aggiungi il primo conto', style: TS.title(t)),
          ]),
        ),
      for (final a in app.accounts) AccountRow(account: a),
      if (upcoming.isNotEmpty) ...[
        SectionLabel('In scadenza', action: 'Tutte', onAction: () => ShellNav.go(2)),
        DCard(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: Column(children: [for (final o in upcoming) OccRow(occ: o)])),
      ],
    ];

    return PageBody(maxWidth: 1180, children: [
      TabHeader(
        title: name.isEmpty ? hello : '$hello, $name',
        subtitle: longDate(DateTime.now()),
        actions: [
          IconSquare(
            icon: app.prefs.hideAmounts ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            tooltip: app.prefs.hideAmounts ? 'Mostra gli importi' : 'Nascondi gli importi',
            onTap: () => app.prefs.hideAmounts = !app.prefs.hideAmounts,
          ),
          if (!isWide(context) || !isDesktop) IconSquare(icon: Icons.settings_outlined, tooltip: 'Impostazioni', onTap: () => push(context, const SettingsScreen())),
        ],
      ),
      TwoCols(left: left, right: right, breakpoint: 980),
      const SizedBox(height: 14),
      Text(coachDisclaimer, style: TS.muted(t, 11)),
    ]);
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final nw = app.netWorth;
    final delta = app.netWorthChange;
    final snaps = app.snapshots;
    final points = [for (final s in snaps.length > 24 ? snaps.sublist(snaps.length - 24) : snaps) (s.month, s.total)];
    if (points.isNotEmpty && points.last.$1 == thisMonthKey()) points[points.length - 1] = (thisMonthKey(), nw.total);
    Widget part(String label, int v, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TS.muted(t, 11.5)),
            const SizedBox(height: 2),
            Money(v, size: 14, dec: false, color: color),
          ]),
        );
    return DCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PATRIMONIO NETTO', style: TS.label(t)),
        const SizedBox(height: 8),
        Money(nw.total, size: 36, weight: FontWeight.w700, dec: false),
        if (delta != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(delta >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 17, color: delta >= 0 ? TC.pos : TC.neg),
            const SizedBox(width: 5),
            Text('${moneyText(context, delta, sign: true, dec: false)} da inizio mese', style: TextStyle(fontSize: 13, color: delta >= 0 ? TC.pos : TC.neg, fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 16),
        Row(children: [
          part('Liquidità', nw.liquid),
          part('Investimenti', nw.invested),
          if (nw.assets > 0) part('Beni', nw.assets),
          if (nw.debts > 0) part('Debiti', -nw.debts, color: TC.neg),
        ]),
        const SizedBox(height: 14),
        NetWorthChart(points: points, height: 130),
      ]),
    );
  }
}

class _MoveCard extends StatelessWidget {
  final CoachResult result;
  const _MoveCard({required this.result});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final m = result.move;
    final steps = result.active;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [TC.accent.withValues(alpha: 0.22), TC.accent.withValues(alpha: 0.06)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.accentLine),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt_rounded, color: TC.accentHi, size: 19),
          const SizedBox(width: 6),
          Text('PROSSIMA MOSSA', style: TS.label(t, TC.accentHi)),
          const Spacer(),
          if (steps.isNotEmpty)
            Tap(
              onTap: () => ShellNav.go(4),
              radius: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('Tappa ${result.level} di ${steps.length}', style: TS.muted(t, 12)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Text(m.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: t.ink, height: 1.25)),
        const SizedBox(height: 6),
        Text(m.text, style: TS.soft(t, 13.5)),
        const SizedBox(height: 14),
        SmallButton(label: m.cta, icon: Icons.arrow_forward_rounded, filled: true, onTap: () => openRoute(context, m.route)),
      ]),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final CoachAlert alert;
  const _AlertRow({required this.alert});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final a = alert;
    final (icon, color) = switch (a.level) {
      AlertLevel.danger => (Icons.error_outline_rounded, TC.neg),
      AlertLevel.warn => (Icons.warning_amber_rounded, TC.warn),
      AlertLevel.good => (Icons.celebration_rounded, TC.pos),
      AlertLevel.info => (Icons.info_outline_rounded, TC.accent),
    };
    return DCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => openRoute(context, a.route),
      child: Row(children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: TS.title(t)),
            Text(a.text, style: TS.muted(t, 12.5)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: t.dim),
      ]),
    );
  }
}
