import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/models.dart';
import 'balances.dart';
import 'schedule.dart';

const noCat = '_none';

/// Entrate e uscite di un mese, in euro (centesimi). Giroconti, investimenti e
/// rettifiche non sono né spese né entrate.
class MonthStats {
  final String month;
  int income = 0;
  int expense = 0; // positivo
  int invested = 0; // verso investimenti e accantonamenti
  final Map<String, int> spentByCat = {}; // spese positive
  final Map<String, int> incomeByCat = {};
  final Map<String, int> byBucket = {};
  int uncategorized = 0;
  int count = 0;

  MonthStats(this.month);

  int get saving => income - expense;
  double get savingRate => income > 0 ? saving / income : 0;
}

bool isTransferTx(Tx t, Map<String, Category> cats) {
  if (t.isTransfer) return true;
  final c = cats[t.catId];
  return c != null && c.isTransfer;
}

MonthStats monthStats(String mk, Iterable<Tx> txs, Map<String, Category> cats, Map<String, Account> accs, FxRates fx) =>
    periodStats(mk, (d) => d.startsWith(mk), txs, cats, accs, fx);

/// Come [monthStats] ma su un periodo qualsiasi (una settimana, un anno).
MonthStats periodStats(String label, bool Function(String date) inPeriod, Iterable<Tx> txs, Map<String, Category> cats,
    Map<String, Account> accs, FxRates fx) {
  final s = MonthStats(label);
  for (final t in txs) {
    if (!inPeriod(t.date)) continue;
    final acc = accs[t.accountId];
    final eur = toEur(t.amount, acc?.currency ?? 'EUR', fx);
    final c = cats[t.catId];
    if (isTransferTx(t, cats)) {
      if (c != null && (c.id == 'investimento' || c.id == 'risparmio') && eur < 0) s.invested += -eur;
      continue;
    }
    s.count++;
    if (c == null) {
      s.uncategorized++;
      if (eur < 0) {
        s.expense += -eur;
        s.spentByCat[noCat] = (s.spentByCat[noCat] ?? 0) - eur;
      } else {
        s.income += eur;
        s.incomeByCat[noCat] = (s.incomeByCat[noCat] ?? 0) + eur;
      }
      continue;
    }
    if (c.isIncome) {
      s.income += eur;
      s.incomeByCat[c.id] = (s.incomeByCat[c.id] ?? 0) + eur;
    } else {
      // una spesa rimborsata (importo positivo in una categoria di spesa) riduce la spesa
      s.expense += -eur;
      s.spentByCat[c.id] = (s.spentByCat[c.id] ?? 0) - eur;
      s.byBucket[c.bucket] = (s.byBucket[c.bucket] ?? 0) - eur;
    }
  }
  return s;
}

/// Media mensile di entrate e uscite degli ultimi [months] mesi completi con dati.
class Averages {
  final int income, expense, invested, months;
  const Averages(this.income, this.expense, this.invested, this.months);
  int get saving => income - expense;
  double get savingRate => income > 0 ? saving / income : 0;
}

Averages averages(List<MonthStats> completeMonths) {
  final withData = completeMonths.where((m) => m.count > 0).toList();
  if (withData.isEmpty) return const Averages(0, 0, 0, 0);
  final n = withData.length;
  return Averages(
    (withData.fold(0, (a, m) => a + m.income) / n).round(),
    (withData.fold(0, (a, m) => a + m.expense) / n).round(),
    (withData.fold(0, (a, m) => a + m.invested) / n).round(),
    n,
  );
}

class BudgetLine {
  final Category cat;
  final int spent;
  final int budget;
  final double monthFraction; // quanto mese è passato (0..1)
  const BudgetLine(this.cat, this.spent, this.budget, this.monthFraction);

  int get left => budget - spent;
  double get pct => budget > 0 ? spent / budget : 0;

  /// Al ritmo attuale, a fine mese.
  int get projected => monthFraction > 0 ? (spent / monthFraction).round() : spent;
  bool get over => budget > 0 && spent > budget;

  /// Sta correndo troppo: oltre il budget o, al ritmo attuale, oltre del 15%.
  bool get atRisk => budget > 0 && !over && monthFraction > 0.25 && projected > budget * 1.15;
}

List<BudgetLine> budgetLines(MonthStats s, Iterable<Category> cats, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = fromKey('${s.month}-01');
  final dim = daysInMonth(d.year, d.month);
  final isCurrent = monthKey(n) == s.month;
  final frac = isCurrent ? n.day / dim : 1.0;
  final out = <BudgetLine>[];
  for (final c in cats) {
    if (!c.isExpense || c.hidden) continue;
    final spent = s.spentByCat[c.id] ?? 0;
    if (c.budget <= 0 && spent <= 0) continue;
    out.add(BudgetLine(c, spent, c.budget, frac));
  }
  out.sort((a, b) {
    if (a.budget > 0 && b.budget <= 0) return -1;
    if (b.budget > 0 && a.budget <= 0) return 1;
    return b.spent.compareTo(a.spent);
  });
  return out;
}

/// "Quanto posso ancora spendere": entrate previste − scadenze del mese −
/// quota di risparmio − spese già fatte che non sono scadenze.
class SpendPlan {
  final int income;
  final int fixed;
  final int saving;
  final int variableSpent;
  final int daysLeft;
  const SpendPlan({required this.income, required this.fixed, required this.saving, required this.variableSpent, required this.daysLeft});

  int get free => income - fixed - saving - variableSpent;
  int get perDay => daysLeft > 0 ? (free / daysLeft).floor() : free;
  bool get hasIncome => income > 0;
}

SpendPlan computeSpendPlan({
  required MonthStats stats,
  required List<OccView> monthOccs,
  required Set<String> linkedTxIds,
  required Iterable<Tx> monthTxs,
  required Map<String, Category> cats,
  required Map<String, Account> accs,
  required FxRates fx,
  required int profileIncome,
  required double savingsPct,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  var plannedIncome = 0;
  var fixed = 0;
  for (final o in monthOccs) {
    if (o.state == OccState.skipped) continue;
    if (o.amount > 0) {
      plannedIncome += o.amount;
    } else if (!isTransferCat(o.sched.catId, cats)) {
      fixed += -o.amount;
    }
  }
  final income = math.max(stats.income, math.max(plannedIncome, profileIncome));
  var variable = 0;
  for (final t in monthTxs) {
    if (t.amount >= 0 || linkedTxIds.contains(t.id) || isTransferTx(t, cats)) continue;
    variable += -toEur(t.amount, accs[t.accountId]?.currency ?? 'EUR', fx);
  }
  final d = DateTime(n.year, n.month, 1);
  final isCurrent = monthKey(n) == stats.month;
  final dim = daysInMonth(d.year, d.month);
  return SpendPlan(
    income: income,
    fixed: fixed,
    saving: (income * savingsPct / 100).round(),
    variableSpent: variable,
    daysLeft: isCurrent ? dim - n.day + 1 : 0,
  );
}

bool isTransferCat(String? catId, Map<String, Category> cats) => cats[catId]?.isTransfer ?? false;
