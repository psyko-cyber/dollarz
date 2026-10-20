import 'dart:math' as math;

/// Formattazione numeri e date in italiano (senza dipendenze esterne).

String fInt(num v) {
  final n = v.round();
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// Decimale con virgola. Se [trim] toglie gli zeri finali.
String fDec(num v, [int digits = 1, bool trim = false]) {
  final neg = v < 0;
  var s = v.abs().toStringAsFixed(digits);
  if (trim && s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  final parts = s.split('.');
  final intPart = fInt(int.parse(parts[0]));
  final r = parts.length > 1 ? '$intPart,${parts[1]}' : intPart;
  final isZero = double.tryParse(s) == 0;
  return neg && !isZero ? '-$r' : r;
}

/// Percentuale: 0.183 -> "18,3%".
String fPct(num frac, [int digits = 1]) => '${fDec(frac * 100, digits, true)}%';

/// Percentuale con segno: 0.024 -> "+2,4%".
String fPctSigned(num frac, [int digits = 1]) => (frac > 0 ? '+' : frac < 0 ? '−' : '') + fPct(frac.abs(), digits);

/// "1.234,5" / "1,25" / "0,3" (numero letto dall'utente o da un file).
double? parseNum(String s) {
  var t = s.trim().replaceAll(RegExp(r'[\s  ]'), '');
  if (t.isEmpty) return null;
  t = t.replaceAll(RegExp(r'[€$£]|EUR|USD|GBP|CHF', caseSensitive: false), '');
  var neg = false;
  if (t.startsWith('(') && t.endsWith(')')) {
    neg = true;
    t = t.substring(1, t.length - 1);
  }
  if (t.startsWith('−') || t.startsWith('-')) {
    neg = !neg;
    t = t.substring(1);
  } else if (t.startsWith('+')) {
    t = t.substring(1);
  }
  if (t.endsWith('-')) {
    neg = !neg;
    t = t.substring(0, t.length - 1);
  }
  final lastComma = t.lastIndexOf(',');
  final lastDot = t.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // il separatore decimale è l'ultimo dei due
    if (lastComma > lastDot) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    // "1,234" con tre cifre dopo un'unica virgola: separatore delle migliaia all'inglese
    final after = t.length - lastComma - 1;
    if (after == 3 && ','.allMatches(t).length == 1 && t.length > 4 && !t.startsWith('0,')) {
      t = t.replaceAll(',', '');
    } else {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }
  } else if (lastDot >= 0) {
    // "1.234" (migliaia all'italiana) contro "12.34"
    final dots = '.'.allMatches(t).length;
    final after = t.length - lastDot - 1;
    if (dots > 1 || (after == 3 && !t.startsWith('0.'))) t = t.replaceAll('.', '');
  }
  final v = double.tryParse(t);
  if (v == null) return null;
  return neg ? -v : v;
}

// ---------------------------------------------------------------- date

const giorni = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];
const giorniBrevi = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
const mesi = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
];
const mesiBrevi = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => dateOnly(DateTime.now());

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String todayKey() => dayKey(DateTime.now());

DateTime fromKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), p.length > 2 ? int.parse(p[2]) : 1);
}

/// "2026-10" del giorno [d].
String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
String monthOfKey(String dayK) => dayK.substring(0, 7);
String thisMonthKey() => monthKey(DateTime.now());

/// Mese successivo/precedente: "2026-12" + 1 = "2027-01".
String addMonthsKey(String mk, int n) {
  final y = int.parse(mk.substring(0, 4)), m = int.parse(mk.substring(5, 7));
  return monthKey(DateTime(y, m + n, 1));
}

/// Giorni di calendario in più o in meno. Non usare `add(Duration(days:))` sulle date:
/// sposta di 24 ore e nei giorni del cambio dell'ora finisce nel giorno sbagliato.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second, d.millisecond);

String addDaysKey(String k, int days) => dayKey(addDays(fromKey(k), days));

/// Stesso giorno [n] mesi dopo, fermandosi all'ultimo giorno del mese (31 gen + 1 = 28/29 feb).
DateTime addMonths(DateTime d, int n, {int? day}) {
  final first = DateTime(d.year, d.month + n, 1);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, math.min(day ?? d.day, last));
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Differenza in giorni di calendario (b - a).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// "Martedì 14 ottobre"
String longDate(DateTime d) => '${giorni[d.weekday - 1]} ${d.day} ${mesi[d.month - 1]}';

/// "14 ott"
String shortDate(DateTime d) => '${d.day} ${mesiBrevi[d.month - 1]}';

/// "14 ott 2026" se anno diverso da quello corrente.
String shortDateY(DateTime d) => d.year == DateTime.now().year ? shortDate(d) : '${shortDate(d)} ${d.year}';

/// "ottobre 2026"
String monthLabel(String mk) {
  final d = fromKey(mk);
  return '${mesi[d.month - 1]} ${d.year}';
}

/// "Ottobre" (con l'anno se diverso da quello corrente).
String monthTitle(String mk) {
  final d = fromKey(mk);
  final m = mesi[d.month - 1];
  final cap = m[0].toUpperCase() + m.substring(1);
  return d.year == DateTime.now().year ? cap : '$cap ${d.year}';
}

String relDay(DateTime d) {
  final diff = daysBetween(today(), d);
  if (diff == 0) return 'Oggi';
  if (diff == -1) return 'Ieri';
  if (diff == 1) return 'Domani';
  return '${giorniBrevi[d.weekday - 1]} ${shortDate(d)}';
}

/// "tra 3 giorni", "oggi", "2 giorni fa".
String inDays(int n) => switch (n) {
      0 => 'oggi',
      1 => 'domani',
      -1 => 'ieri',
      > 1 => 'tra $n giorni',
      _ => '${-n} giorni fa',
    };

String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "3 anni e 4 mesi", "8 mesi".
String fYearsMonths(int months) {
  if (months <= 0) return 'già raggiunto';
  final y = months ~/ 12, m = months % 12;
  final ys = y == 1 ? '1 anno' : '$y anni';
  final ms = m == 1 ? '1 mese' : '$m mesi';
  if (y == 0) return ms;
  if (m == 0) return ys;
  return '$ys e $ms';
}

/// Normalizza per ricerche: minuscolo senza accenti.
String fold(String s) {
  const from = 'àáâäãèéêëìíîïòóôöõùúûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

double clamp01(double v) => math.max(0, math.min(1, v));
