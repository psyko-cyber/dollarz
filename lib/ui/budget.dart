import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/budget.dart';
import 'charts.dart';
import 'settings/categories.dart';
import 'widgets.dart';

/// Budget del mese: "puoi ancora spendere", i tre secchi, le categorie.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  String _month = thisMonthKey();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final st = app.statsFor(_month);
    final current = _month == thisMonthKey();
    final lines = budgetLines(st, app.cats.values);
    final income = st.income > 0 ? st.income : app.monthlyIncome;
    final months = [for (var i = 5; i >= 0; i--) addMonthsKey(thisMonthKey(), -i)].map(app.statsFor).toList();
    final byCat = st.spentByCat.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return SubPage(
      title: 'Budget',
      actions: [IconSquare(icon: Icons.tune_rounded, tooltip: 'Categorie e regole', onTap: () => push(context, const CategoriesScreen()))],
      body: PageBody(children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => _month = addMonthsKey(_month, -1)), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(child: Text(monthTitle(_month), textAlign: TextAlign.center, style: TS.h2(t))),
          IconButton(onPressed: current ? null : () => setState(() => _month = addMonthsKey(_month, 1)), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        if (current) const SpendPlanCard(),
        SectionLabel('I tre secchi'),
        DCard(
          child: Column(children: [
            for (final b in [(Bucket.need, 50, 'Casa, bollette, spesa, trasporti'), (Bucket.want, 30, 'Ristoranti, shopping, svago'), (Bucket.future, 20, 'Risparmio e investimenti')])
              _BucketRow(
                label: Bucket.labels[b.$1]!,
                hint: b.$3,
                amount: b.$1 == Bucket.future ? math.max(0, st.saving) : (st.byBucket[b.$1] ?? 0),
                income: income,
                idealPct: b.$2,
              ),
            const SizedBox(height: 4),
            Text('Riferimento classico 50/30/20 delle entrate: una guida, non una regola.', style: TS.muted(t, 11.5)),
          ]),
        ),
        SectionLabel('Categorie', action: 'Budget per categoria', onAction: () => push(context, const CategoriesScreen())),
        if (lines.isEmpty) Text('Nessuna spesa in questo mese.', style: TS.muted(t)),
        if (lines.isNotEmpty)
          DCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(children: [for (final l in lines) _CatLine(line: l, editable: true)]),
          ),
        if (byCat.isNotEmpty) ...[
          const SectionLabel('Dove vanno i soldi'),
          DCard(
            child: Donut(
              items: [
                for (var i = 0; i < byCat.length; i++)
                  (byCat[i].key == noCat ? 'Senza categoria' : app.cat(byCat[i].key)?.name ?? byCat[i].key, byCat[i].value, TC.series[i % TC.series.length]),
              ],
              centerTop: fEuro(st.expense),
              centerBottom: 'spese',
            ),
          ),
        ],
        const SectionLabel('Ultimi 6 mesi'),
        DCard(child: MonthBars(months: [for (final m in months) (m.month, m.income, m.expense)])),
      ]),
    );
  }
}

class _BucketRow extends StatelessWidget {
  final String label, hint;
  final int amount, income, idealPct;
  const _BucketRow({required this.label, required this.hint, required this.amount, required this.income, required this.idealPct});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final pct = income > 0 ? amount / income : 0.0;
    final ideal = idealPct / 100;
    final over = label != Bucket.labels[Bucket.future] ? pct > ideal + 0.05 : pct < ideal - 0.05;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: TS.title(t))),
          Money(amount, size: 14, dec: false),
          const SizedBox(width: 8),
          SizedBox(width: 44, child: Text(income > 0 ? fPct(pct, 0) : '–', textAlign: TextAlign.right, style: TS.num(t, 13, color: over ? TC.warn : t.dim))),
        ]),
        const SizedBox(height: 2),
        Text(hint, style: TS.muted(t, 11.5)),
        const SizedBox(height: 6),
        BarTrack(value: pct, marker: ideal, color: over ? TC.warn : TC.accent),
      ]),
    );
  }
}

class _CatLine extends StatelessWidget {
  final BudgetLine line;
  final bool editable;
  const _CatLine({required this.line, this.editable = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.appRead;
    final l = line;
    final color = l.over ? TC.neg : (l.atRisk ? TC.warn : TC.accent);
    return Tap(
      radius: 10,
      onTap: !editable
          ? null
          : () async {
              final v = await askMoney(context,
                  title: 'Budget mensile: ${l.cat.name}', initial: l.budget > 0 ? l.budget : null, body: 'Lascia vuoto o 0 per nessun budget.');
              if (v != null) app.saveCategory(l.cat.copy()..budget = v.abs());
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          CatIcon(l.cat, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(l.cat.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: t.ink))),
                Text(moneyText(context, l.spent, dec: false), style: TS.num(t, 13.5)),
                if (l.budget > 0) Text(' / ${moneyText(context, l.budget, dec: false)}', style: TS.num(t, 12.5, color: t.dim)),
              ]),
              if (l.budget > 0) ...[
                const SizedBox(height: 6),
                BarTrack(value: l.pct, color: color, height: 6, marker: l.monthFraction < 1 ? l.monthFraction : null),
                if (l.over || l.atRisk)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l.over ? 'Oltre di ${moneyText(context, -l.left, dec: false)}' : 'Al ritmo attuale: ${moneyText(context, l.projected, dec: false)}',
                        style: TextStyle(fontSize: 11.5, color: color)),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "Puoi ancora spendere": entrate − scadenze − quota di risparmio − spese già fatte.
class SpendPlanCard extends StatelessWidget {
  const SpendPlanCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final sp = app.spendPlan;
    if (!sp.hasIncome) {
      return DCard(
        child: Text('Imposta le entrate mensili nel profilo o aggiungi una scadenza "Stipendio": ti dico quanto puoi spendere ogni giorno.', style: TS.soft(t)),
      );
    }
    final free = sp.free;
    final color = free < 0 ? TC.neg : (sp.perDay < 1000 ? TC.warn : TC.pos);
    return DCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PUOI ANCORA SPENDERE', style: TS.label(t)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Money(free, size: 28, weight: FontWeight.w700, color: color, dec: false),
          const SizedBox(width: 10),
          if (free > 0 && sp.daysLeft > 0)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${moneyText(context, sp.perDay, dec: false)} al giorno · ${sp.daysLeft} giorni', style: TS.muted(t))),
        ]),
        const SizedBox(height: 12),
        KV('Entrate del mese', moneyText(context, sp.income, dec: false)),
        KV('Scadenze del mese', '− ${moneyText(context, sp.fixed, dec: false)}'),
        KV('Quota di risparmio (${fDec(app.profile.savingsTargetPct, 0)}%)', '− ${moneyText(context, sp.saving, dec: false)}'),
        KV('Spese già fatte', '− ${moneyText(context, sp.variableSpent, dec: false)}'),
        if (free < 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Sei oltre di ${moneyText(context, -free, dec: false)}: questo mese la quota di risparmio salta, cerca di non toccare il resto.',
                style: const TextStyle(fontSize: 12.5, color: TC.neg)),
          ),
      ]),
    );
  }
}
