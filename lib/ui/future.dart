import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/coach.dart';
import '../logic/projection.dart';
import 'charts.dart';
import 'consult.dart';
import 'report_screen.dart';
import 'settings/profile.dart';
import 'shell.dart';
import 'widgets.dart';

const scenarioNames = ['Prudente', 'Realistico', 'Ottimista'];

String whenLabel(int? m) {
  if (m == null) return 'oltre 80 anni';
  if (m == 0) return 'raggiunto';
  final d = dateAfterMonths(m);
  return '${mesiBrevi[d.month - 1]} ${d.year}';
}

/// Scheda Futuro: percorso, obiettivi, proiezioni, simulatore e consulenza.
class FutureTab extends StatelessWidget {
  const FutureTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final res = app.coach;
    final input = app.coachInput;
    final goals = res.goals;
    final main = goals.firstOrNull;
    final rates = app.profile.returns.isEmpty ? const [2.0, 4.0, 6.0] : app.profile.returns;
    final years = main?.monthsRealistic == null ? 30 : math.min(45, math.max(10, (main!.monthsRealistic! / 12).ceil() + 3));
    final start = main?.current ?? input.fiCapital;
    final series = [for (final r in rates) yearlySeries(start, input.monthlyContribution, r, years)];

    final left = <Widget>[
      const SectionLabel('Il tuo percorso'),
      DCard(child: Column(children: [for (final s in res.steps) _StepRow(step: s, move: s.state == PathState.current ? res.move : null)])),
      Row(children: [
        Expanded(child: GhostButton(label: 'Consulenza AI', icon: Icons.auto_awesome_rounded, onTap: () => push(context, const ConsultScreen()))),
        const SizedBox(width: 10),
        Expanded(child: GhostButton(label: 'Resoconti', icon: Icons.summarize_outlined, onTap: () => push(context, const ReportsScreen()))),
      ]),
    ];
    final right = <Widget>[
      SectionLabel('Obiettivi', action: 'Modifica', onAction: () => push(context, const GoalsScreen())),
      if (goals.isEmpty)
        DCard(
          onTap: () => push(context, const GoalsScreen()),
          child: Text('Nessun obiettivo: scegli una rendita mensile, un patrimonio da raggiungere o l\'indipendenza finanziaria.', style: TS.soft(t)),
        ),
      for (final g in goals) _GoalCard(goal: g),
      if (main != null) ...[
        const SectionLabel('Proiezione'),
        DCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Capitale che lavora per te, versando ${moneyText(context, input.monthlyContribution, dec: false)} al mese', style: TS.soft(t, 12.5)),
            const SizedBox(height: 12),
            ProjectionChart(series: series, labels: scenarioNames, target: main.target),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, children: [
              for (var i = 0; i < rates.length && i < 3; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 3, color: ProjectionChart.colors[i]),
                  const SizedBox(width: 6),
                  Text('${scenarioNames[i]} ${fDec(rates[i], 1, true)}%', style: TS.muted(t, 11.5)),
                ]),
            ]),
            const SizedBox(height: 6),
            Text('Rendimenti reali, già al netto dell\'inflazione: gli importi sono in euro di oggi.', style: TS.muted(t, 11.5)),
          ]),
        ),
        _Milestones(start: main.current, monthly: input.monthlyContribution, rate: rates.length > 1 ? rates[1] : rates.first, upTo: main.target),
        _Simulator(goal: main, rate: rates.length > 1 ? rates[1] : rates.first),
      ],
    ];
    return PageBody(maxWidth: 1180, children: [
      const TabHeader(title: 'Futuro', subtitle: 'Dove sei, dove vai, quando ci arrivi'),
      TwoCols(left: left, right: right, breakpoint: 1000),
      const SizedBox(height: 14),
      Text(coachDisclaimer, style: TS.muted(t, 11)),
    ]);
  }
}

class _StepRow extends StatelessWidget {
  final CoachStep step;
  final NextMove? move;
  const _StepRow({required this.step, this.move});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final s = step;
    final (icon, color) = switch (s.state) {
      PathState.done => (Icons.check_circle_rounded, TC.pos),
      PathState.current => (Icons.radio_button_checked_rounded, TC.accent),
      PathState.todo => (Icons.radio_button_unchecked_rounded, t.dim),
      PathState.off => (Icons.remove_circle_outline_rounded, t.line),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: TextStyle(fontSize: 14.5, fontWeight: s.state == PathState.current ? FontWeight.w700 : FontWeight.w500, color: s.state == PathState.off ? t.dim : t.ink)),
            const SizedBox(height: 2),
            Text(s.state == PathState.off ? 'Disattivata nel profilo' : s.status, style: TS.muted(t, 12.5)),
            if (s.state != PathState.off && s.state != PathState.done && s.progress > 0) ...[
              const SizedBox(height: 6),
              BarTrack(value: s.progress, height: 5, color: s.state == PathState.current ? TC.accent : t.dim),
            ],
            if (move != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(move!.title, style: TS.title(t)),
                  const SizedBox(height: 4),
                  Text(move!.text, style: TS.soft(t, 13)),
                  const SizedBox(height: 10),
                  SmallButton(label: move!.cta, icon: Icons.arrow_forward_rounded, filled: true, onTap: () => openRoute(context, move!.route)),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  const _GoalCard({required this.goal});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final g = goal;
    final p = app.profile;
    return DCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(g.title, style: TS.title(t))),
          Text(fPct(g.progress, 0), style: TS.num(t, 15, color: TC.accent, w: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        BarTrack(value: g.progress, height: 8),
        const SizedBox(height: 8),
        Text('${moneyText(context, g.current, dec: false)} su ${moneyText(context, g.target, dec: false)}', style: TS.muted(t, 12.5)),
        if (g.id != 'wealth')
          Text('Oggi questo capitale ti darebbe ${moneyText(context, sustainableIncome(g.current, p.swr), dec: false)} al mese (prelievo ${fDec(p.swr, 1, true)}%)',
              style: TS.muted(t, 12.5)),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < g.months.length && i < 3; i++)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(scenarioNames[i], style: TS.muted(t, 11.5)),
                const SizedBox(height: 2),
                Text(whenLabel(g.months[i]), style: TS.num(t, 14, color: i == 1 ? t.ink : t.soft, w: i == 1 ? FontWeight.w700 : FontWeight.w500)),
                if (g.months[i] != null && g.months[i]! > 0) Text(fYearsMonths(g.months[i]!), style: TS.muted(t, 11)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

class _Milestones extends StatelessWidget {
  final int start, monthly, upTo;
  final double rate;
  const _Milestones({required this.start, required this.monthly, required this.rate, required this.upTo});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final ms = milestones(start, upTo);
    if (ms.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Tappe'),
      DCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(children: [
          for (final m in ms)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 18, color: t.dim),
                const SizedBox(width: 10),
                Expanded(child: Text(fEuro(m), style: TS.num(t, 14))),
                Text(whenLabel(monthsToTarget(start, monthly, rate, m)), style: TS.soft(t, 13)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// "E se…": risparmio in più, aumento, spesa grande. Di quanto si sposta la data.
class _Simulator extends StatefulWidget {
  final Goal goal;
  final double rate;
  const _Simulator({required this.goal, required this.rate});
  @override
  State<_Simulator> createState() => _SimulatorState();
}

class _SimulatorState extends State<_Simulator> {
  double _extra = 0; // €/mese in più di risparmio
  double _raise = 0; // €/mese netti in più
  double _spend = 0; // spesa una tantum €
  double _keepPct = 50; // quanto dell'aumento resta risparmio

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final g = widget.goal;
    final base = monthsToTarget(g.current, g.monthly, widget.rate, g.target);
    final monthly = g.monthly + ((_extra + _raise * _keepPct / 100) * 100).round();
    final startNew = math.max(0, g.current - (_spend * 100).round());
    final sim = monthsToTarget(startNew, monthly, widget.rate, g.target);
    final diff = base != null && sim != null ? base - sim : null;
    final changed = _extra > 0 || _raise > 0 || _spend > 0;
    Widget slider(String label, String value, double v, double max, double div, ValueChanged<double> on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(label, style: TS.soft(t, 13))), Text(value, style: TS.num(t, 13.5))]),
          Slider(value: v, min: 0, max: max, divisions: div.round(), onChanged: (x) => setState(() => on(x))),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('E se…'),
      DCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          slider('Risparmio in più al mese', '+${fEuro((_extra * 100).round())}', _extra, 1000, 40, (x) => _extra = x),
          slider('Aumento netto al mese', '+${fEuro((_raise * 100).round())}', _raise, 1500, 30, (x) => _raise = x),
          if (_raise > 0) slider('…di cui risparmiato', '${_keepPct.round()}%', _keepPct, 100, 10, (x) => _keepPct = x),
          slider('Spesa grande oggi', fEuro((_spend * 100).round()), _spend, 50000, 100, (x) => _spend = x),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.title, style: TS.muted(t, 12)),
                  const SizedBox(height: 2),
                  Text(changed ? whenLabel(sim) : whenLabel(base), style: TS.num(t, 18, w: FontWeight.w700)),
                ]),
              ),
              if (changed && diff != null && diff != 0)
                StatusPill(diff > 0 ? '${fYearsMonths(diff)} prima' : '${fYearsMonths(-diff)} dopo', color: diff > 0 ? TC.pos : TC.neg),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Scenario realistico (${fDec(widget.rate, 1, true)}% reale). Non cambia i tuoi dati: è solo una prova.', style: TS.muted(t, 11.5)),
        ]),
      ),
    ]);
  }
}

/// Obiettivi e ipotesi delle proiezioni.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});
  @override
  Widget build(BuildContext context) => const ProfileScreen(goalsFirst: true);
}
