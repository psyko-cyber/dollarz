import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/models.dart';
import 'text_keys.dart';

/// Date delle scadenze di [s] tra [from] e [to] (incluse).
List<String> occurrences(Scheduled s, String from, String to) {
  final out = <String>[];
  if (!s.active) return out;
  final start = fromKey(s.start);
  final last = s.end != null && s.end!.compareTo(to) < 0 ? s.end! : to;
  if (last.compareTo(from) < 0 || s.start.compareTo(last) > 0) return out;
  final every = math.max(1, s.every);

  void add(DateTime d) {
    final k = dayKey(d);
    if (k.compareTo(from) >= 0 && k.compareTo(last) <= 0) out.add(k);
  }

  switch (s.freq) {
    case Freq.once:
      add(start);
    case Freq.weekly:
      final step = 7 * every;
      final f = fromKey(from);
      var k = math.max(0, daysBetween(start, f) ~/ step - 1);
      for (var i = 0; i < 2000; i++, k++) {
        final d = addDays(start, k * step);
        if (dayKey(d).compareTo(last) > 0) break;
        add(d);
      }
    default:
      final stepMonths = s.freq == Freq.yearly ? 12 * every : every;
      final f = fromKey(from);
      final monthsDiff = (f.year - start.year) * 12 + f.month - start.month;
      var k = math.max(0, monthsDiff ~/ stepMonths - 1);
      for (var i = 0; i < 2000; i++, k++) {
        final d = addMonths(start, k * stepMonths, day: start.day);
        if (dayKey(d).compareTo(last) > 0) break;
        add(d);
      }
  }
  return out;
}

/// Prossima scadenza da oggi in poi (null se non ce ne sono più).
String? nextOccurrence(Scheduled s, {String? from}) {
  final f = from ?? todayKey();
  final list = occurrences(s, f, addDaysKey(f, 800));
  return list.isEmpty ? null : list.first;
}

enum OccState { paid, skipped, due, overdue }

class OccView {
  final Scheduled sched;
  final String date;
  final Occurrence? rec;
  const OccView(this.sched, this.date, this.rec);

  String get id => Occurrence.key(sched.id, date);
  int get amount => rec?.amount ?? sched.amount;

  OccState get state {
    if (rec?.status == 'paid') return OccState.paid;
    if (rec?.status == 'skip') return OccState.skipped;
    return date.compareTo(todayKey()) < 0 ? OccState.overdue : OccState.due;
  }

  bool get open => state == OccState.due || state == OccState.overdue;
  int get daysLeft => daysBetween(today(), fromKey(date));
}

/// Tutte le scadenze nell'intervallo, in ordine di data.
List<OccView> occurrencesBetween(Iterable<Scheduled> scheds, Map<String, Occurrence> occ, String from, String to) {
  final out = <OccView>[];
  for (final s in scheds) {
    for (final d in occurrences(s, from, to)) {
      out.add(OccView(s, d, occ[Occurrence.key(s.id, d)]));
    }
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.sched.name.compareTo(b.sched.name);
  });
  return out;
}

/// Il movimento [t] può essere il pagamento della scadenza [o]? Ritorna un punteggio (0 = no).
double matchScore(OccView o, Tx t) {
  final s = o.sched;
  if (t.isTransfer && s.catId != 'giroconto' && s.catId != 'investimento' && s.catId != 'risparmio') return 0;
  if ((t.amount > 0) != (s.amount > 0)) return 0;
  final days = daysBetween(fromKey(o.date), fromKey(t.date)).abs();
  if (days > 7) return 0;
  final want = o.amount.abs(), got = t.amount.abs();
  final diff = (want - got).abs();
  final tol = s.variable ? math.max(want * 0.6, 2000) : math.max(want * 0.03, 100);
  if (diff > tol) return 0;
  final text = fold('${t.desc} ${t.note}');
  final pattern = fold(s.match.isNotEmpty ? s.match : s.name);
  final words = descWords(pattern);
  final textHit = words.isNotEmpty && words.every((w) => containsWord(text, w)) || (pattern.length >= 3 && text.contains(pattern));
  final sameAccount = s.accountId == null || s.accountId == t.accountId;
  final sameCat = s.catId != null && s.catId == t.catId;
  if (!textHit && !(sameCat && sameAccount)) return 0;
  var score = 1.0;
  if (textHit) score += 3;
  if (sameCat) score += 1;
  if (sameAccount) score += 0.5;
  score += 1 - diff / math.max(1, want);
  score += (7 - days) / 7;
  return score;
}

/// Abbina le scadenze aperte ai movimenti già registrati: ritorna (scadenza, movimento).
/// [taken]: movimenti già collegati ad altre scadenze.
List<(OccView, Tx)> autoMatch(List<OccView> open, Iterable<Tx> txs, Set<String> taken) {
  final out = <(OccView, Tx)>[];
  final used = {...taken};
  for (final o in open.where((o) => o.open)) {
    Tx? best;
    var bestScore = 0.0;
    for (final t in txs) {
      if (used.contains(t.id)) continue;
      final sc = matchScore(o, t);
      if (sc > bestScore) {
        bestScore = sc;
        best = t;
      }
    }
    if (best != null) {
      used.add(best.id);
      out.add((o, best));
    }
  }
  return out;
}

/// Totale mensile equivalente di una scadenza (annuale / 12, settimanale × 4,33…).
int monthlyEquivalent(Scheduled s) => switch (s.freq) {
      Freq.monthly => s.amount,
      Freq.everyN => (s.amount / math.max(1, s.every)).round(),
      Freq.yearly => (s.amount / (12 * math.max(1, s.every))).round(),
      Freq.weekly => (s.amount * 52 / 12 / math.max(1, s.every)).round(),
      _ => 0,
    };
