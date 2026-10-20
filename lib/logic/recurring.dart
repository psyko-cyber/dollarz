import '../core/fmt.dart';
import '../data/models.dart';
import 'text_keys.dart';

/// Spesa che si ripete (abbonamento, bolletta) trovata nei movimenti.
class RecurringFound {
  final String key;
  final String name;
  final int amount; // negativo, mediana
  final String freq; // Freq.monthly | Freq.yearly
  final String lastDate;
  final String nextDate;
  final String accountId;
  final String? catId;
  final int count;
  final bool variable;
  const RecurringFound({
    required this.key,
    required this.name,
    required this.amount,
    required this.freq,
    required this.lastDate,
    required this.nextDate,
    required this.accountId,
    required this.catId,
    required this.count,
    required this.variable,
  });
}

int _median(List<int> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Cerca spese ricorrenti negli ultimi 14 mesi. Esclude le chiavi in [ignore]
/// (già scadenze o scartate dall'utente).
List<RecurringFound> findRecurring(Iterable<Tx> txs, {Set<String> ignore = const {}, Set<String> transferCats = const {}}) {
  final from = addDaysKey(todayKey(), -425);
  final groups = <String, List<Tx>>{};
  for (final t in txs) {
    if (t.amount >= 0 || t.isTransfer || t.date.compareTo(from) < 0) continue;
    if (t.catId != null && transferCats.contains(t.catId)) continue;
    final k = merchantKey(t.desc);
    if (k.length < 3 || ignore.contains(k)) continue;
    groups.putIfAbsent(k, () => []).add(t);
  }
  final out = <RecurringFound>[];
  for (final e in groups.entries) {
    final list = e.value..sort((a, b) => a.date.compareTo(b.date));
    if (list.length < 2) continue;
    // un solo movimento per mese (il più vicino alla mediana)
    final gaps = <int>[];
    for (var i = 1; i < list.length; i++) {
      gaps.add(daysBetween(fromKey(list[i - 1].date), fromKey(list[i].date)));
    }
    final g = _median(gaps);
    String? freq;
    if (g >= 25 && g <= 35 && list.length >= 3) freq = Freq.monthly;
    if (g >= 350 && g <= 380) freq = Freq.yearly;
    if (freq == null) continue;
    // i salti devono essere regolari: al massimo uno fuori posto
    final irregular = gaps.where((x) => freq == Freq.monthly ? (x < 20 || x > 40) : (x < 330 || x > 400)).length;
    if (irregular > 1) continue;
    final amounts = list.map((t) => t.amount).toList();
    final med = _median(amounts);
    final spread = amounts.map((a) => (a - med).abs()).reduce((a, b) => a > b ? a : b);
    final variable = spread > med.abs() * 0.1;
    if (spread > med.abs() * 0.6) continue;
    final last = list.last;
    // l'ultimo deve essere recente: un abbonamento disdetto non si propone
    final limit = freq == Freq.monthly ? 45 : 400;
    if (daysBetween(fromKey(last.date), today()) > limit) continue;
    final next = freq == Freq.monthly ? addMonths(fromKey(last.date), 1) : addMonths(fromKey(last.date), 12);
    out.add(RecurringFound(
      key: e.key,
      name: prettyMerchant(last.desc),
      amount: med,
      freq: freq,
      lastDate: last.date,
      nextDate: dayKey(next),
      accountId: last.accountId,
      catId: last.catId,
      count: list.length,
      variable: variable,
    ));
  }
  out.sort((a, b) => a.amount.compareTo(b.amount));
  return out;
}
