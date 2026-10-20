import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/budget.dart';
import '../logic/report.dart';
import 'widgets.dart';

/// Un resoconto settimanale o mensile.
class ReportScreen extends StatelessWidget {
  final String reportId;
  const ReportScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final r = app.reportFor(reportId);
    final s = r.stats;
    return SubPage(
      title: r.kind == 'month' ? 'Resoconto di ${r.title.toLowerCase()}' : r.title,
      body: PageBody(children: [
        DCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final l in r.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: TC.accent)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l, style: TS.body(t))),
                ]),
              ),
          ]),
        ),
        DCard(
          child: Column(children: [
            KV('Entrate', moneyText(context, s.income, dec: false), color: TC.pos),
            KV('Uscite', moneyText(context, s.expense, dec: false)),
            if (s.income > 0) KV('Risparmio', '${moneyText(context, s.saving, dec: false)} · ${fPct(s.savingRate, 0)}', color: s.saving >= 0 ? TC.pos : TC.neg),
            if (s.invested > 0) KV('Investito / accantonato', moneyText(context, s.invested, dec: false)),
            if (r.netWorth != null) KV('Patrimonio a fine periodo', moneyText(context, r.netWorth!, dec: false), strong: true),
          ]),
        ),
        if (r.top.isNotEmpty) ...[
          const SectionLabel('Dove sono andati i soldi'),
          DCard(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(children: [
              for (final c in r.top)
                RowTile(
                  leading: CatIcon(c.catId == noCat ? null : app.cat(c.catId), size: 34),
                  title: c.catId == noCat ? 'Senza categoria' : app.cat(c.catId)?.name ?? c.catId,
                  subtitle: c.before > 0 ? 'prima ${moneyText(context, c.before, dec: false)}' : null,
                  trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Money(c.amount, dec: false),
                    if (c.before > 0 && c.delta != 0)
                      Text(moneyText(context, c.delta, sign: true, dec: false), style: TextStyle(fontSize: 11.5, color: c.delta > 0 ? TC.warn : TC.pos)),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Archivio dei resoconti mensili.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final months = <String>[];
    for (var i = 0; i < 24; i++) {
      final mk = addMonthsKey(thisMonthKey(), -i);
      if (app.statsFor(mk).count > 0) months.add(mk);
    }
    final week = weekStart(DateTime.now());
    return SubPage(
      title: 'Resoconti',
      body: PageBody(children: [
        DCard(
          onTap: () => push(context, ReportScreen(reportId: 'w:${dayKey(addDays(week, -7))}')),
          child: Row(children: [
            const Icon(Icons.date_range_rounded, color: TC.accent),
            const SizedBox(width: 12),
            Expanded(child: Text('Settimana scorsa', style: TS.title(t))),
            Icon(Icons.chevron_right_rounded, color: t.dim),
          ]),
        ),
        const SectionLabel('Mesi'),
        if (months.isEmpty) Text('Ancora nessun mese con movimenti.', style: TS.muted(t)),
        if (months.isNotEmpty)
          DCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Column(children: [
              for (final mk in months)
                Builder(builder: (context) {
                  final s = app.statsFor(mk);
                  return RowTile(
                    title: monthTitle(mk),
                    subtitle: s.income > 0 ? 'Risparmio ${fPct(s.savingRate, 0)}' : 'Spese ${moneyText(context, s.expense, dec: false)}',
                    trailing: Money(s.saving, dec: false, colored: true, sign: true),
                    onTap: () => push(context, ReportScreen(reportId: 'm:$mk')),
                  );
                }),
            ]),
          ),
      ]),
    );
  }
}
