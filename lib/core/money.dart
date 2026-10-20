import 'fmt.dart';

/// Gli importi sono sempre interi in centesimi: niente errori di arrotondamento.

const currencySymbols = {'EUR': '€', 'USD': r'$', 'GBP': '£', 'CHF': 'CHF', 'JPY': '¥'};

String curSymbol(String cur) => currencySymbols[cur] ?? cur;

/// 123456 -> "1.234,56 €". [dec] false toglie i centesimi; null li toglie solo da 1.000 € in su.
String fMoney(int cents, {String cur = 'EUR', bool? dec, bool sign = false}) {
  final showDec = dec ?? cents.abs() < 100000;
  final v = cents / 100;
  var s = showDec ? fDec(v.abs(), 2) : fInt(v.abs());
  if (!showDec && s == '0' && cents != 0) s = fDec(v.abs(), 2);
  final pre = cents < 0 ? '−' : (sign && cents > 0 ? '+' : '');
  return '$pre$s ${curSymbol(cur)}';
}

/// Sempre con i centesimi: "12,50 €".
String fCents(int cents, {String cur = 'EUR', bool sign = false}) => fMoney(cents, cur: cur, dec: true, sign: sign);

/// Senza centesimi: "48.320 €".
String fEuro(int cents, {bool sign = false}) => fMoney(cents, dec: false, sign: sign);

/// Compatto per assi e chip: "850", "12,5k", "1,2M".
String fCompact(int cents) {
  final v = cents.abs() / 100;
  final pre = cents < 0 ? '−' : '';
  if (v >= 1e6) return '$pre${fDec(v / 1e6, v >= 1e7 ? 0 : 1, true)}M';
  if (v >= 1e3) return '$pre${fDec(v / 1e3, v >= 1e4 ? 0 : 1, true)}k';
  return '$pre${fInt(v)}';
}

/// "12,5" / "-3" / "1.200,00 €" -> centesimi.
int? parseMoney(String s) {
  final v = parseNum(s);
  return v == null ? null : (v * 100).round();
}

int toCents(double euros) => (euros * 100).round();
double toEuros(int cents) => cents / 100;
