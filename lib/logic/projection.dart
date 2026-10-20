import 'dart:math' as math;

/// Proiezioni in euro di oggi (rendimenti reali, al netto dell'inflazione).
/// Tutti gli importi sono in centesimi.

/// Capitale che ti fa vivere di rendita: spese annue / tasso di prelievo.
int fiNumber(int annualExpenses, double swr) => swr <= 0 ? 0 : (annualExpenses * 100 / swr).round();

/// Capitale che serve per una rendita mensile [monthly] al tasso [swr].
int capitalForIncome(int monthly, double swr) => swr <= 0 ? 0 : (monthly * 12 * 100 / swr).round();

/// Rendita mensile sostenibile oggi con [capital].
int sustainableIncome(int capital, double swr) => (capital * swr / 100 / 12).round();

double _monthlyRate(double annualPct) => math.pow(1 + annualPct / 100, 1 / 12).toDouble() - 1;

/// Mesi per passare da [start] a [target] versando [monthly] al mese al rendimento
/// reale [annualPct]. 0 se già raggiunto, null se non ci si arriva in [maxYears].
int? monthsToTarget(int start, int monthly, double annualPct, int target, {int maxYears = 80}) {
  if (target <= 0) return null;
  if (start >= target) return 0;
  final r = _monthlyRate(annualPct);
  var w = start.toDouble();
  for (var m = 1; m <= maxYears * 12; m++) {
    w = w * (1 + r) + monthly;
    if (w >= target) return m;
  }
  return null;
}

/// Valore dopo [months] mesi.
int valueAfter(int start, int monthly, double annualPct, int months) {
  final r = _monthlyRate(annualPct);
  var w = start.toDouble();
  for (var m = 0; m < months; m++) {
    w = w * (1 + r) + monthly;
  }
  return w.round();
}

/// Serie annuale (anno 0 = oggi) per il grafico.
List<int> yearlySeries(int start, int monthly, double annualPct, int years) {
  final out = <int>[start];
  final r = _monthlyRate(annualPct);
  var w = start.toDouble();
  for (var y = 1; y <= years; y++) {
    for (var m = 0; m < 12; m++) {
      w = w * (1 + r) + monthly;
    }
    out.add(w.round());
  }
  return out;
}

/// Quanti mesi prima arrivi a [target] versando [extra] in più al mese.
int? monthsSaved(int start, int monthly, int extra, double annualPct, int target) {
  final base = monthsToTarget(start, monthly, annualPct, target);
  final faster = monthsToTarget(start, monthly + extra, annualPct, target);
  if (base == null && faster == null) return null;
  if (base == null) return null;
  return base - (faster ?? base);
}

/// Versamento mensile che serve per arrivare a [target] in [months] mesi.
int monthlyNeeded(int start, int target, double annualPct, int months) {
  if (months <= 0) return 0;
  final r = _monthlyRate(annualPct);
  final grown = start * math.pow(1 + r, months);
  final left = target - grown;
  if (left <= 0) return 0;
  if (r == 0) return (left / months).ceil();
  final factor = (math.pow(1 + r, months) - 1) / r;
  return (left / factor).ceil();
}

/// Tappe di patrimonio standard fino a [upTo] (centesimi).
List<int> milestones(int current, int upTo) {
  const steps = [1000000, 2500000, 5000000, 10000000, 25000000, 50000000, 100000000, 200000000, 500000000];
  final out = steps.where((s) => s > current && s <= math.max(upTo, current * 2)).toList();
  if (upTo > current && !out.contains(upTo)) out.add(upTo);
  out.sort();
  return out.take(6).toList();
}

class Scenario {
  final String label;
  final double rate;
  const Scenario(this.label, this.rate);
}

/// Data stimata dopo [months] mesi da oggi.
DateTime dateAfterMonths(int months, {DateTime? from}) {
  final f = from ?? DateTime.now();
  return DateTime(f.year, f.month + months, 1);
}
