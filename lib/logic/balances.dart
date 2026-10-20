import '../core/fmt.dart';
import '../data/models.dart';

/// Cambi BCE: quante unità di valuta vale 1 euro ({"USD": 1.08}).
typedef FxRates = Map<String, double>;

/// Converte in euro un importo in [cur] (centesimi). Senza cambio: lo lascia com'è.
int toEur(int cents, String cur, FxRates fx) {
  if (cur == 'EUR') return cents;
  final r = fx[cur];
  if (r == null || r <= 0) return cents;
  return (cents / r).round();
}

/// Il movimento conta dopo il saldo di riferimento del conto?
/// Sì se è di un giorno successivo, o dello stesso giorno ma registrato dopo.
bool afterAnchor(Account a, Tx t) =>
    t.date.compareTo(a.anchorDate) > 0 || (t.date == a.anchorDate && t.created > a.anchorAt);

/// Saldo del conto alla fine del giorno [date] (valuta del conto).
/// [txs]: solo i movimenti di questo conto.
int balanceAt(Account a, Iterable<Tx> txs, String date) {
  var b = a.anchorAmount;
  if (date.compareTo(a.anchorDate) >= 0) {
    for (final t in txs) {
      if (afterAnchor(a, t) && t.date.compareTo(date) <= 0) b += t.amount;
    }
  } else {
    for (final t in txs) {
      if (!afterAnchor(a, t) && t.date.compareTo(date) > 0) b -= t.amount;
    }
  }
  return b;
}

/// Saldo di oggi (i movimenti con data futura non contano ancora).
int currentBalance(Account a, Iterable<Tx> txs) => balanceAt(a, txs, todayKey());

/// Saldo a fine mese per gli ultimi [months] mesi (il mese corrente: oggi).
List<(String, int)> monthlyBalances(Account a, Iterable<Tx> txs, int months) {
  final out = <(String, int)>[];
  final now = DateTime.now();
  for (var i = months - 1; i >= 0; i--) {
    final mk = monthKey(DateTime(now.year, now.month - i, 1));
    final end = i == 0 ? todayKey() : dayKey(DateTime(now.year, now.month - i + 1, 0));
    out.add((mk, balanceAt(a, txs, end)));
  }
  return out;
}
