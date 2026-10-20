import '../core/fmt.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'balances.dart';
import 'budget.dart';

/// Una categoria del resoconto con la variazione sul periodo prima.
class CatChange {
  final String catId;
  final int amount;
  final int before;
  const CatChange(this.catId, this.amount, this.before);
  int get delta => amount - before;
}

/// Resoconto settimanale o mensile, con le frasi del coach.
class Report {
  final String kind; // week | month
  final String id; // "m:2026-10" / "w:2026-10-13" (lunedì)
  final String title;
  final String from, to;
  final MonthStats stats;
  final MonthStats prev;
  final int avgExpense;
  final List<CatChange> top;
  final int? netWorth;
  final int? netWorthDelta;
  final List<String> lines;
  const Report({
    required this.kind,
    required this.id,
    required this.title,
    required this.from,
    required this.to,
    required this.stats,
    required this.prev,
    required this.avgExpense,
    required this.top,
    required this.netWorth,
    required this.netWorthDelta,
    required this.lines,
  });

  bool get empty => stats.count == 0;
}

List<CatChange> _top(MonthStats s, MonthStats prev, {int n = 4}) {
  final list = s.spentByCat.entries.where((e) => e.value > 0).map((e) => CatChange(e.key, e.value, prev.spentByCat[e.key] ?? 0)).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return list.take(n).toList();
}

String _catName(String id, Map<String, Category> cats) => id == noCat ? 'Senza categoria' : (cats[id]?.name ?? id);

List<String> _lines(MonthStats s, MonthStats prev, int avgExpense, String prevLabel, Map<String, Category> cats,
    {required double targetPct, int? netWorthDelta, int? netWorth, bool week = false}) {
  final out = <String>[];
  if (s.count == 0) {
    out.add(week ? 'Nessun movimento questa settimana.' : 'Nessun movimento registrato in questo mese.');
    return out;
  }
  if (!week && s.income > 0) {
    if (s.saving >= 0) {
      final good = s.savingRate * 100 >= targetPct;
      out.add('Hai messo da parte ${fEuro(s.saving)}, il ${fPct(s.savingRate, 0)} delle entrate.'
          '${good ? ' Sopra il tuo obiettivo del ${fDec(targetPct, 0)}%: ottimo.' : ' L\'obiettivo è il ${fDec(targetPct, 0)}%.'}');
    } else {
      out.add('Hai speso ${fEuro(-s.saving)} più di quanto è entrato. Il mese prossimo si chiude almeno in pari.');
    }
  } else {
    out.add('Hai speso ${fEuro(s.expense)}${s.income > 0 ? ' e incassato ${fEuro(s.income)}' : ''}.');
  }

  final ref = avgExpense > 0 ? avgExpense : prev.expense;
  if (ref > 0 && s.expense > 0) {
    final d = (s.expense - ref) / ref;
    final what = avgExpense > 0 ? 'alla media' : prevLabel;
    if (d > 0.1) {
      final changes = _top(s, prev, n: 20).where((c) => c.delta > 0).toList()..sort((a, b) => b.delta.compareTo(a.delta));
      final c = changes.firstOrNull;
      out.add('Spese ${fPctSigned(d, 0)} rispetto $what'
          '${c != null && c.delta >= 2000 ? ': pesa soprattutto ${_catName(c.catId, cats)} (+${fEuro(c.delta)})' : ''}.');
    } else if (d < -0.1) {
      out.add('Spese in calo del ${fPct(-d, 0)} rispetto $what: bene.');
    } else {
      out.add('Spese in linea con ${avgExpense > 0 ? 'la media' : prevLabel}.');
    }
  }
  if (s.invested > 0) out.add('Hai investito o accantonato ${fEuro(s.invested)}.');
  if (s.uncategorized > 0) out.add('${s.uncategorized} movimenti senza categoria: assegnala per avere numeri giusti.');
  if (netWorthDelta != null && netWorth != null && netWorthDelta != 0) {
    out.add('Patrimonio ${netWorthDelta > 0 ? '+' : '−'}${fEuro(netWorthDelta.abs())}: ora sei a ${fEuro(netWorth)}.');
  }
  return out;
}

/// Resoconto del mese [mk].
Report monthReport(
  String mk,
  Iterable<Tx> txs,
  Map<String, Category> cats,
  Map<String, Account> accs,
  FxRates fx, {
  Map<String, Snapshot> snaps = const {},
  double targetPct = 20,
}) {
  final s = monthStats(mk, txs, cats, accs, fx);
  final pk = addMonthsKey(mk, -1);
  final prev = monthStats(pk, txs, cats, accs, fx);
  final before = [for (var i = 1; i <= 3; i++) monthStats(addMonthsKey(mk, -i), txs, cats, accs, fx)];
  final avg = averages(before);
  final snap = snaps[mk], snapPrev = snaps[pk];
  final nwDelta = snap != null && snapPrev != null ? snap.total - snapPrev.total : null;
  final d = fromKey('$mk-01');
  return Report(
    kind: 'month',
    id: 'm:$mk',
    title: monthTitle(mk),
    from: '$mk-01',
    to: dayKey(DateTime(d.year, d.month + 1, 0)),
    stats: s,
    prev: prev,
    avgExpense: avg.months >= 2 ? avg.expense : 0,
    top: _top(s, prev),
    netWorth: snap?.total,
    netWorthDelta: nwDelta,
    lines: _lines(s, prev, avg.months >= 2 ? avg.expense : 0, 'a ${monthLabel(pk)}', cats,
        targetPct: targetPct, netWorthDelta: nwDelta, netWorth: snap?.total),
  );
}

/// Lunedì della settimana di [d].
DateTime weekStart(DateTime d) => addDays(dateOnly(d), -(d.weekday - 1));

/// Resoconto della settimana che inizia il lunedì [monday].
Report weekReport(DateTime monday, Iterable<Tx> txs, Map<String, Category> cats, Map<String, Account> accs, FxRates fx) {
  final from = dayKey(monday), to = dayKey(addDays(monday, 6));
  MonthStats statsFor(String a, String b) =>
      periodStats('$a/$b', (d) => d.compareTo(a) >= 0 && d.compareTo(b) <= 0, txs, cats, accs, fx);
  final s = statsFor(from, to);
  final prev = statsFor(dayKey(addDays(monday, -7)), dayKey(addDays(monday, -1)));
  final weeks = [for (var i = 1; i <= 8; i++) statsFor(dayKey(addDays(monday, -7 * i)), dayKey(addDays(monday, -7 * i + 6)))];
  final avg = averages(weeks);
  final end = addDays(monday, 6);
  final title = monday.month == end.month
      ? 'Settimana ${monday.day}–${end.day} ${mesi[end.month - 1]}'
      : 'Settimana ${shortDate(monday)} – ${shortDate(end)}';
  final avgExp = avg.months >= 3 ? avg.expense : 0;
  return Report(
    kind: 'week',
    id: 'w:$from',
    title: title,
    from: from,
    to: to,
    stats: s,
    prev: prev,
    avgExpense: avgExp,
    top: _top(s, prev, n: 3),
    netWorth: null,
    netWorthDelta: null,
    lines: _lines(s, prev, avgExp, 'alla settimana prima', cats, targetPct: 0, week: true),
  );
}

/// Il resoconto da mostrare adesso (null = già visto): il mese appena chiuso nei
/// primi 7 giorni del mese, altrimenti la settimana appena chiusa.
String? dueReportId(DateTime now, Set<String> seen) {
  final mk = addMonthsKey(monthKey(now), -1);
  if (now.day <= 7 && !seen.contains('m:$mk')) return 'm:$mk';
  final w = 'w:${dayKey(addDays(weekStart(now), -7))}';
  return seen.contains(w) ? null : w;
}
