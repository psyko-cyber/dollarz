import 'dart:math' as math;

import '../core/fmt.dart';
import '../data/models.dart';
import 'balances.dart';

/// Posizione su un titolo calcolata dalle operazioni (metodo del costo medio).
class Position {
  final Holding h;
  double qty = 0;
  int cost = 0; // costo di carico residuo (€, commissioni comprese)
  int realized = 0; // plus/minus realizzate
  int income = 0; // dividendi e cedole incassati
  int income12m = 0; // ultimi 12 mesi
  int fees = 0;
  int invested = 0; // totale versato negli acquisti
  String? firstDate;

  /// Prezzo unitario usato (valuta del titolo) e da dove arriva.
  double? price;
  String priceSrc = ''; // online | manuale | ''
  int priceAt = 0;

  int value = 0; // valore di mercato in euro

  Position(this.h);

  int get unrealized => value - cost;
  double get unrealizedPct => cost > 0 ? unrealized / cost : 0;

  /// Tasse stimate se vendessi oggi (solo sulle plusvalenze).
  int get taxIfSold => unrealized > 0 ? (unrealized * h.taxRate / 100).round() : 0;
  int get netValue => value - taxIfSold;
  bool get hasPrice => price != null || h.isDeposit;
  bool get stalePrice => !h.isDeposit && priceSrc == 'online' && DateTime.now().millisecondsSinceEpoch - priceAt > 5 * 86400000;
  double get avgPrice => qty > 0 ? cost / 100 / qty : 0;
}

/// Calcola la posizione di [h]: operazioni, prezzo e valore di oggi in euro.
Position computePosition(Holding h, List<Trade> trades, Map<String, Quote> quotes, FxRates fx, {DateTime? now}) {
  final p = Position(h);
  final n = now ?? DateTime.now();
  final from12 = dayKey(DateTime(n.year - 1, n.month, n.day));
  final list = [...trades]..sort((a, b) => a.date.compareTo(b.date));
  for (final t in list) {
    p.firstDate ??= t.date;
    switch (t.type) {
      case TradeType.buy:
        p.qty += t.qty;
        p.cost += t.amount + t.fees;
        p.invested += t.amount + t.fees;
        p.fees += t.fees;
      case TradeType.sell:
        final q = math.min(t.qty, p.qty);
        final avg = p.qty > 0 ? p.cost / p.qty : 0;
        final costOut = (avg * q).round();
        p.realized += t.amount - t.fees - costOut;
        p.cost -= costOut;
        p.qty -= q;
        p.fees += t.fees;
        if (p.qty < 1e-9) {
          p.qty = 0;
          p.cost = 0;
        }
      case TradeType.dividend || TradeType.coupon:
        p.income += t.amount;
        if (t.date.compareTo(from12) >= 0) p.income12m += t.amount;
      case TradeType.fee:
        p.fees += t.amount + t.fees;
        p.realized -= t.amount + t.fees;
    }
  }

  if (h.isDeposit) {
    final principal = h.principal > 0 ? h.principal : p.cost;
    p.cost = principal;
    p.value = principal + depositInterestNet(h, n);
    return p;
  }

  // prezzo: quello a mano se più recente di quello online
  final q = h.priceKey == null ? null : quotes[h.priceKey];
  if (h.manualPrice > 0 && (q == null || h.manualAt >= q.at)) {
    p.price = h.manualPrice;
    p.priceSrc = 'manuale';
    p.priceAt = h.manualAt;
  } else if (q != null && q.price > 0) {
    p.price = q.price;
    p.priceSrc = 'online';
    p.priceAt = q.at;
  }
  final cur = q?.currency ?? h.currency;
  if (p.price != null) {
    final unit = h.pricePct ? p.price! / 100 : p.price!;
    final raw = (p.qty * unit * 100).round();
    p.value = toEur(raw, p.priceSrc == 'online' ? cur : h.currency, fx);
  } else {
    // senza prezzo vale quanto è costato
    p.value = p.cost;
  }
  return p;
}

/// Interessi netti maturati da un conto deposito fino a [now] (tassati al taxRate).
int depositInterestNet(Holding h, DateTime now) {
  if (h.start == null || h.rate <= 0) return 0;
  final start = fromKey(h.start!);
  var end = now;
  if (h.maturity != null) {
    final m = fromKey(h.maturity!);
    if (m.isBefore(end)) end = m;
  }
  final days = math.max(0, daysBetween(start, end));
  final gross = h.principal * h.rate / 100 * days / 365;
  return (gross * (1 - h.taxRate / 100)).round();
}

/// Rendita annua netta prevista di un titolo (dividendi degli ultimi 12 mesi,
/// cedole e interessi dei depositi).
int annualIncome(Position p) {
  final h = p.h;
  if (h.isDeposit) {
    if (h.maturity != null && h.maturity!.compareTo(todayKey()) < 0) return 0;
    return (h.principal * h.rate / 100 * (1 - h.taxRate / 100)).round();
  }
  if (h.isBond && h.rate > 0) {
    // cedola sul nominale (qty = nominale)
    final nominal = (p.qty * 100).round();
    return (nominal * h.rate / 100 * (1 - h.taxRate / 100)).round();
  }
  return p.income12m;
}

class Portfolio {
  final List<Position> positions;
  const Portfolio(this.positions);

  List<Position> get open => positions.where((p) => p.qty > 0 || (p.h.isDeposit && p.value > 0)).toList();
  int get value => open.fold(0, (a, p) => a + p.value);
  int get cost => open.fold(0, (a, p) => a + p.cost);
  int get unrealized => value - cost;
  int get realized => positions.fold(0, (a, p) => a + p.realized);
  int get income => positions.fold(0, (a, p) => a + p.income);
  int get taxIfSold => open.fold(0, (a, p) => a + p.taxIfSold);
  int get annualIncomeNet => open.fold(0, (a, p) => a + annualIncome(p));

  /// Imposta di bollo stimata all'anno (0,2% del valore; esclusi i conti non titoli).
  int get stampDuty => (value * 0.002).round();

  Map<String, int> get byKind {
    final m = <String, int>{};
    for (final p in open) {
      m[p.h.kind] = (m[p.h.kind] ?? 0) + p.value;
    }
    return m;
  }
}
