import '../core/fmt.dart';
import '../data/models.dart';
import 'schedule.dart';

class ForecastPoint {
  final String date;
  final int balance;
  final List<OccView> events;
  const ForecastPoint(this.date, this.balance, this.events);
}

class AccountForecast {
  final Account account;
  final int start;
  final List<ForecastPoint> points; // un punto per ogni giorno con movimenti previsti
  const AccountForecast(this.account, this.start, this.points);

  int get min => points.fold(start, (m, p) => p.balance < m ? p.balance : m);
  int get end => points.isEmpty ? start : points.last.balance;

  /// Primo giorno in cui il conto andrebbe sotto zero (null = mai).
  ForecastPoint? get firstNegative {
    for (final p in points) {
      if (p.balance < 0) return p;
    }
    return null;
  }

  /// Il saldo più basso raggiunto fino a [date] compresa.
  int minUntil(String date) {
    var m = start;
    for (final p in points) {
      if (p.date.compareTo(date) > 0) break;
      if (p.balance < m) m = p.balance;
    }
    return m;
  }
}

/// Saldo previsto di un conto per i prossimi [days] giorni, con le scadenze
/// ancora aperte. Quelle scadute da poco e non pagate contano come "oggi".
AccountForecast forecastAccount(Account a, int currentBalance, List<OccView> open, {int days = 90}) {
  final t = todayKey();
  final end = addDaysKey(t, days);
  final byDay = <String, List<OccView>>{};
  for (final o in open) {
    if (!o.open) continue;
    if (o.date.compareTo(end) > 0) continue;
    // scaduta da più di 10 giorni: probabilmente pagata senza abbinamento, la ignoro
    if (o.date.compareTo(addDaysKey(t, -10)) < 0) continue;
    final d = o.date.compareTo(t) < 0 ? t : o.date;
    byDay.putIfAbsent(d, () => []).add(o);
  }
  final keys = byDay.keys.toList()..sort();
  var b = currentBalance;
  final points = <ForecastPoint>[];
  for (final k in keys) {
    for (final o in byDay[k]!) {
      b += o.amount;
    }
    points.add(ForecastPoint(k, b, byDay[k]!));
  }
  return AccountForecast(a, currentBalance, points);
}

/// Scadenze aperte che pesano su [a]: quelle del conto, e quelle senza conto
/// se [a] è il conto principale.
List<OccView> openFor(Account a, List<OccView> all, {required bool isMain}) =>
    all.where((o) => o.open && (o.sched.accountId == a.id || (o.sched.accountId == null && isMain))).toList();
