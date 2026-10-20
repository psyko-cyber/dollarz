import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';

import '../core/fmt.dart';
import '../data/models.dart';

/// Import degli estratti conto (CSV, Excel, tabelle HTML salvate come .xls).
/// Riconosce Revolut e Fineco; per il resto trova da solo le colonne e
/// lascia correggere la scelta a mano.

typedef RawTable = List<List<Object?>>;

class ImportError implements Exception {
  final String message;
  const ImportError(this.message);
  @override
  String toString() => message;
}

// ------------------------------------------------------------------ lettura file

RawTable readTable(Uint8List bytes, {String name = ''}) {
  final lower = name.toLowerCase();
  if (bytes.isEmpty) throw const ImportError('Il file è vuoto.');
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (isZip || lower.endsWith('.xlsx')) return _readXlsx(bytes);
  final isOle = bytes.length > 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;
  if (isOle) {
    throw const ImportError('È un file Excel vecchio (.xls): aprilo e salvalo come .xlsx o CSV, poi riprova.');
  }
  final text = decodeText(bytes);
  if (RegExp(r'<table', caseSensitive: false).hasMatch(text)) return _readHtml(text);
  return parseCsv(text);
}

/// UTF-8 (con o senza BOM), UTF-16 o, se non è UTF-8 valido, Latin-1.
String decodeText(Uint8List b) {
  if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
    final le = b[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  var start = 0;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) start = 3;
  final body = Uint8List.sublistView(b, start);
  try {
    return utf8.decode(body);
  } on FormatException {
    return latin1.decode(body);
  }
}

RawTable _readXlsx(Uint8List bytes) {
  final Excel ex;
  try {
    ex = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const ImportError('Non riesco a leggere questo file Excel. Prova a salvarlo come CSV.');
  }
  RawTable best = [];
  for (final sheet in ex.tables.values) {
    final rows = sheet.rows.map((r) => r.map((c) => _cell(c?.value)).toList()).toList();
    if (rows.length > best.length) best = rows;
  }
  return best;
}

Object? _cell(CellValue? v) => switch (v) {
      null => null,
      TextCellValue() => v.value.toString(),
      IntCellValue() => v.value,
      DoubleCellValue() => v.value,
      DateCellValue() => v.asDateTimeLocal(),
      DateTimeCellValue() => v.asDateTimeLocal(),
      BoolCellValue() => v.value.toString(),
      FormulaCellValue() => v.formula,
      TimeCellValue() => v.toString(),
    };

RawTable _readHtml(String html) {
  final rows = <List<Object?>>[];
  final trRe = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
  final tdRe = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
  for (final tr in trRe.allMatches(html)) {
    final cells = tdRe.allMatches(tr.group(1)!).map((m) => _htmlText(m.group(1)!)).toList();
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  return rows;
}

String _htmlText(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&euro;', '€')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _countOutside(String line, String sep) {
  var n = 0;
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') q = !q;
    if (!q && c == sep) n++;
  }
  return n;
}

/// Il separatore che dà lo stesso numero di colonne sul maggior numero di righe.
String detectSeparator(String text) {
  final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).take(20).toList();
  var best = ',';
  var bestScore = -1;
  for (final sep in const [';', ',', '\t', '|']) {
    final freq = <int, int>{};
    for (final l in lines) {
      final c = _countOutside(l, sep);
      if (c > 0) freq[c] = (freq[c] ?? 0) + 1;
    }
    if (freq.isEmpty) continue;
    final mode = freq.entries.reduce((a, b) => b.value > a.value || (b.value == a.value && b.key > a.key) ? b : a);
    final score = mode.value * 1000 + mode.key;
    if (score > bestScore) {
      bestScore = score;
      best = sep;
    }
  }
  return best;
}

RawTable parseCsv(String text, {String? sep}) {
  final s = sep ?? detectSeparator(text);
  final rows = <List<Object?>>[];
  var row = <Object?>[];
  final f = StringBuffer();
  var q = false;
  var fieldStarted = false;

  void endField() {
    row.add(f.toString());
    f.clear();
    fieldStarted = false;
  }

  void endRow() {
    endField();
    if (row.any((x) => (x as String).trim().isNotEmpty)) rows.add(row);
    row = <Object?>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          f.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        f.write(c);
      }
      continue;
    }
    if (c == '"' && !fieldStarted) {
      q = true;
      fieldStarted = true;
    } else if (c == s) {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      f.write(c);
      if (c != ' ') fieldStarted = true;
    }
  }
  if (f.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

// ------------------------------------------------------------------ colonne

class Col {
  static const date = 'date';
  static const completed = 'completed';
  static const valueDate = 'valueDate';
  static const desc = 'desc';
  static const desc2 = 'desc2';
  static const amount = 'amount';
  static const income = 'income';
  static const expense = 'expense';
  static const fee = 'fee';
  static const currency = 'currency';
  static const state = 'state';
  static const balance = 'balance';
  static const type = 'type';
  static const product = 'product';

  static const labels = {
    date: 'Data',
    completed: 'Data di completamento',
    valueDate: 'Data valuta',
    desc: 'Descrizione',
    desc2: 'Descrizione estesa',
    amount: 'Importo (+/−)',
    income: 'Entrate',
    expense: 'Uscite',
    fee: 'Commissioni',
    currency: 'Valuta',
    state: 'Stato',
    balance: 'Saldo',
    type: 'Tipo',
    product: 'Prodotto',
  };
}

/// Nomi di colonna conosciuti (già normalizzati), dal più specifico.
const _headerNames = <String, List<String>>{
  Col.completed: ['completed date', 'data di completamento', 'data completamento'],
  Col.valueDate: ['data valuta', 'value date', 'valuta data'],
  Col.date: [
    'started date', 'data di inizio', 'data inizio', 'data operazione', 'data contabile', 'data movimento',
    'data registrazione', 'data transazione', 'data contabilizzazione', 'transaction date', 'booking date', 'data', 'date', 'giorno',
  ],
  Col.desc2: ['descrizione completa', 'descrizione estesa', 'causale estesa', 'dettaglio', 'dettagli', 'details', 'note', 'reference', 'riferimento'],
  Col.desc: ['descrizione', 'description', 'causale', 'esercente', 'merchant', 'beneficiario', 'controparte', 'payee', 'operazione', 'name', 'nome'],
  Col.income: ['entrate', 'accrediti', 'accredito', 'avere', 'credit', 'money in', 'paid in', 'importo entrate'],
  Col.expense: ['uscite', 'addebiti', 'addebito', 'dare', 'debit', 'money out', 'paid out', 'importo uscite'],
  Col.amount: ['importo', 'amount', 'ammontare', 'importo in euro', 'valore', 'totale', 'value'],
  Col.fee: ['fee', 'commissione', 'commissioni', 'costo'],
  Col.currency: ['currency', 'divisa', 'moneta', 'valuta'],
  Col.state: ['state', 'stato', 'status'],
  Col.balance: ['balance', 'saldo', 'saldo contabile', 'saldo disponibile'],
  Col.type: ['type', 'tipo', 'tipologia', 'tipo operazione', 'moneymap', 'categoria'],
  Col.product: ['product', 'prodotto'],
};

String normHeader(Object? v) => fold(v?.toString() ?? '').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// (colonna, quanto è sicuro: 2 = nome esatto, 1 = inizia così).
(String, int)? _matchHeader(String h) {
  if (h.isEmpty || h.length > 40) return null;
  for (final e in _headerNames.entries) {
    if (e.value.contains(h)) return (e.key, 2);
  }
  for (final e in _headerNames.entries) {
    for (final n in e.value) {
      if (n.length >= 4 && h.startsWith('$n ')) return (e.key, 1);
    }
  }
  return null;
}

Map<String, int> mapColumns(List<Object?> header, {List<List<Object?>> sample = const []}) {
  final map = <String, int>{};
  final strength = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final h = normHeader(header[i]);
    var m = _matchHeader(h);
    if (m == null) continue;
    // "Valuta" in italiano può essere la data valuta o la divisa: decide il contenuto
    if (h == 'valuta') {
      final vals = sample.map((r) => i < r.length ? r[i] : null).where((v) => v != null && '$v'.trim().isNotEmpty).take(10).toList();
      final dates = vals.where((v) => parseDateCell(v) != null).length;
      m = (dates > vals.length / 2 ? Col.valueDate : Col.currency, 2);
    }
    var kind = m.$1;
    // seconda colonna di descrizione: diventa quella estesa
    if (kind == Col.desc && map.containsKey(Col.desc) && !map.containsKey(Col.desc2)) kind = Col.desc2;
    // seconda colonna di data (es. data valuta senza nome chiaro): la ignoro
    if (map.containsKey(kind) && (strength[kind] ?? 0) >= m.$2) continue;
    map[kind] = i;
    strength[kind] = m.$2;
  }
  // "Descrizione estesa" senza descrizione breve: diventa la descrizione
  if (!map.containsKey(Col.desc) && map.containsKey(Col.desc2)) map[Col.desc] = map.remove(Col.desc2)!;
  return map;
}

int _headerScore(List<Object?> row) {
  var n = 0;
  for (final c in row) {
    if (c is! String) continue;
    if (_matchHeader(normHeader(c)) != null) n++;
  }
  return n;
}

// ------------------------------------------------------------------ valori

int? _monthName(String s) {
  final f = fold(s);
  if (f.length < 3) return null;
  final p = f.substring(0, 3);
  const it = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
  const en = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final i = it.indexOf(p);
  if (i >= 0) return i + 1;
  final j = en.indexOf(p);
  return j >= 0 ? j + 1 : null;
}

String? _ymd(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  final dt = DateTime(y, m, d);
  if (dt.month != m) return null;
  return dayKey(dt);
}

/// Data di una cella: DateTime, numero seriale di Excel o testo in molti formati.
String? parseDateCell(Object? v, {bool dayFirst = true}) {
  if (v == null) return null;
  if (v is DateTime) return dayKey(v);
  if (v is num) {
    if (v > 25000 && v < 80000) return dayKey(DateTime(1899, 12, 30 + v.floor()));
    return null;
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
  if (m != null) return _ymd(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?!\d)').firstMatch(s);
  if (m != null) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    return dayFirst ? _ymd(y, b, a) : _ymd(y, a, b);
  }
  m = RegExp(r'^(\d{1,2})\s+([A-Za-zÀ-ÿ]{3,})\.?\s+(\d{4})').firstMatch(s);
  if (m != null) {
    final mo = _monthName(m[2]!);
    if (mo != null) return _ymd(int.parse(m[3]!), mo, int.parse(m[1]!));
  }
  m = RegExp(r'^([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})').firstMatch(s);
  if (m != null) {
    final mo = _monthName(m[1]!);
    if (mo != null) return _ymd(int.parse(m[3]!), mo, int.parse(m[2]!));
  }
  final n = RegExp(r'^\d{5}(\.\d+)?$').hasMatch(s) ? double.tryParse(s) : null;
  if (n != null) return parseDateCell(n);
  return null;
}

/// Le date "a/b/aaaa" di una colonna sono giorno/mese (true) o mese/giorno?
bool detectDayFirst(Iterable<Object?> values) {
  final re = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.]\d{2,4}');
  for (final v in values) {
    if (v is! String) continue;
    final m = re.firstMatch(v.trim());
    if (m == null) continue;
    if (int.parse(m[1]!) > 12) return true;
    if (int.parse(m[2]!) > 12) return false;
  }
  return true;
}

/// Virgola decimale (true), punto (false) o non si capisce (null).
bool? detectDecimalComma(Iterable<Object?> values) {
  var comma = 0, dot = 0;
  final c = RegExp(r',\d{1,2}(\s*(€|eur|usd|\$))?\s*-?$', caseSensitive: false);
  final d = RegExp(r'\.\d{1,2}(\s*(€|eur|usd|\$))?\s*-?$', caseSensitive: false);
  for (final v in values) {
    if (v is! String) continue;
    final t = v.trim();
    if (c.hasMatch(t)) {
      comma++;
    } else if (d.hasMatch(t)) {
      dot++;
    }
  }
  if (comma == 0 && dot == 0) return null;
  return comma >= dot;
}

/// Importo in centesimi di una cella.
int? parseAmountCell(Object? v, {bool? decimalComma}) {
  if (v == null) return null;
  if (v is num) return (v * 100).round();
  var s = v.toString().trim();
  if (s.isEmpty || s == '-') return null;
  if (decimalComma != null) {
    s = s.replaceAll(RegExp(r'[\s  ]'), '');
    s = decimalComma ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
  }
  final n = parseNum(s);
  return n == null ? null : (n * 100).round();
}

String normState(Object? v) {
  final f = fold(v?.toString() ?? '');
  if (f.trim().isEmpty) return 'completed';
  if (RegExp(r'revert|declin|fail|rifiutat|annullat|stornat|cancel|respint').hasMatch(f)) return 'cancelled';
  if (RegExp(r'pending|sospes|attesa|autorizzat|in corso|prenotat|non contabilizzat').hasMatch(f)) return 'pending';
  return 'completed';
}

/// Categoria suggerita dal tipo di operazione (Revolut).
String? catHintForType(String type) {
  final f = fold(type);
  if (f.isEmpty) return null;
  if (RegExp(r'top ?up|topup|ricarica|exchange|cambio valuta').hasMatch(f)) return 'giroconto';
  if (RegExp(r'interest|interessi').hasMatch(f)) return 'rendite';
  if (RegExp(r'cashback|reward|premio').hasMatch(f)) return 'extra';
  if (RegExp(r'refund|rimborso').hasMatch(f)) return 'rimborsi';
  if (RegExp(r'^fee$|commission').hasMatch(f)) return 'tasse';
  return null;
}

// ------------------------------------------------------------------ analisi e righe

class ImportFile {
  final RawTable table;
  final String format; // revolut | fineco | traderepublic | generico
  final int headerRow;
  final List<String> headers;
  Map<String, int> map;
  final bool dayFirst;

  ImportFile({
    required this.table,
    required this.format,
    required this.headerRow,
    required this.headers,
    required this.map,
    required this.dayFirst,
  });

  bool get complete =>
      map.containsKey(Col.date) && (map.containsKey(Col.amount) || map.containsKey(Col.income) || map.containsKey(Col.expense));

  String get formatLabel => const {'revolut': 'Revolut', 'fineco': 'Fineco', 'traderepublic': 'Trade Republic'}[format] ?? 'Formato generico';

  List<List<Object?>> get dataRows => headerRow + 1 < table.length ? table.sublist(headerRow + 1) : const [];

  int get columns => table.fold(0, (m, r) => r.length > m ? r.length : m);
}

String _detectFormat(Set<String> h, RawTable t, int headerRow) {
  final top = t.take(headerRow + 1).expand((r) => r).map((c) => fold('${c ?? ''}')).join(' ');
  if ((h.contains('product') || h.contains('prodotto')) &&
      (h.contains('state') || h.contains('stato')) &&
      (h.contains('started date') || h.contains('completed date') || h.contains('data di inizio') || h.contains('data di completamento'))) {
    return 'revolut';
  }
  if (h.contains('entrate') && h.contains('uscite') && (h.contains('descrizione completa') || h.contains('moneymap'))) return 'fineco';
  if (top.contains('fineco')) return 'fineco';
  if (top.contains('trade republic')) return 'traderepublic';
  if (top.contains('revolut')) return 'revolut';
  return 'generico';
}

ImportFile analyzeTable(RawTable t) {
  if (t.isEmpty) throw const ImportError('Nel file non ci sono righe.');
  var headerRow = -1;
  var best = 1;
  for (var i = 0; i < t.length && i < 40; i++) {
    final s = _headerScore(t[i]);
    if (s > best) {
      best = s;
      headerRow = i;
    }
  }
  final header = headerRow >= 0 ? t[headerRow] : const <Object?>[];
  final sample = t.skip(headerRow + 1).take(30).toList();
  final map = headerRow >= 0 ? mapColumns(header, sample: sample) : <String, int>{};
  final names = header.map(normHeader).where((h) => h.isNotEmpty).toSet();
  final dateCol = map[Col.date];
  final dayFirst = dateCol == null ? true : detectDayFirst(t.skip(headerRow + 1).map((r) => dateCol < r.length ? r[dateCol] : null));
  final width = t.fold(0, (m, r) => r.length > m ? r.length : m);
  return ImportFile(
    table: t,
    format: _detectFormat(names, t, headerRow),
    headerRow: headerRow,
    headers: [for (var i = 0; i < width; i++) i < header.length && '${header[i] ?? ''}'.trim().isNotEmpty ? '${header[i]}'.trim() : 'Colonna ${i + 1}'],
    map: map,
    dayFirst: dayFirst,
  );
}

ImportFile analyzeBytes(Uint8List bytes, {String name = ''}) => analyzeTable(readTable(bytes, name: name));

class ImportRow {
  final int line;
  final String date;
  final int amount;
  final String desc;
  final String currency;
  final int? balance;
  final String state;
  final String type;
  final String product;

  /// Data (e ora, se c'è) in cui il saldo è stato aggiornato: ordina le righe per il saldo finale.
  final String when;
  final String key;
  final String? catHint;

  const ImportRow({
    required this.line,
    required this.date,
    required this.amount,
    required this.desc,
    required this.currency,
    required this.balance,
    required this.state,
    required this.type,
    required this.product,
    required this.when,
    required this.key,
    required this.catHint,
  });

  String get group => [product, currency].where((s) => s.isNotEmpty).join(' · ');
}

class BuildResult {
  final List<ImportRow> rows;
  final int pending, cancelled, invalid;

  /// Prodotti/valute presenti (Revolut mette tutto nello stesso file) con il numero di righe.
  final Map<String, int> groups;
  const BuildResult(this.rows, this.pending, this.cancelled, this.invalid, this.groups);
}

String _str(Object? v) {
  if (v == null) return '';
  if (v is DateTime) return v.toIso8601String();
  if (v is double && v == v.roundToDouble()) return v.toInt().toString();
  return v.toString().trim();
}

String importKey(String format, String date, String when, int amount, String desc, int n) {
  final raw = '$format|$date|$when|$amount|${fold(desc).replaceAll(RegExp(r'\s+'), ' ').trim()}|$n';
  return sha1.convert(utf8.encode(raw)).toString().substring(0, 20);
}

BuildResult buildRows(
  ImportFile f, {
  bool includePending = false,
  bool invert = false,
  String? group,
  String defaultCurrency = 'EUR',
}) {
  final m = f.map;
  final rows = f.dataRows;
  Object? at(List<Object?> r, String col) {
    final i = m[col];
    return i == null || i >= r.length ? null : r[i];
  }

  final colVals = {
    for (final c in [Col.amount, Col.income, Col.expense, Col.fee, Col.balance]) c: rows.map((r) => at(r, c)).toList(),
  };
  final dec = {for (final e in colVals.entries) e.key: detectDecimalComma(e.value)};
  // un solo verso del separatore decimale per tutto il file, se una colonna non basta a capirlo
  final anyDec = dec.values.whereType<bool>().firstOrNull;

  final out = <ImportRow>[];
  final groups = <String, int>{};
  final seen = <String, int>{};
  var pending = 0, cancelled = 0, invalid = 0;
  for (var li = 0; li < rows.length; li++) {
    final r = rows[li];
    final rawDate = at(r, Col.date);
    final date = parseDateCell(rawDate, dayFirst: f.dayFirst);
    if (date == null) {
      if (r.any((c) => _str(c).isNotEmpty)) invalid++;
      continue;
    }
    int? amount;
    if (m.containsKey(Col.amount)) {
      amount = parseAmountCell(at(r, Col.amount), decimalComma: dec[Col.amount] ?? anyDec);
    }
    if (amount == null && (m.containsKey(Col.income) || m.containsKey(Col.expense))) {
      final inc = parseAmountCell(at(r, Col.income), decimalComma: dec[Col.income] ?? anyDec);
      final exp = parseAmountCell(at(r, Col.expense), decimalComma: dec[Col.expense] ?? anyDec);
      if (inc != null || exp != null) amount = (inc ?? 0).abs() - (exp ?? 0).abs();
    }
    if (amount == null) {
      invalid++;
      continue;
    }
    final fee = parseAmountCell(at(r, Col.fee), decimalComma: dec[Col.fee] ?? anyDec) ?? 0;
    amount -= fee.abs();
    if (invert) amount = -amount;
    if (amount == 0) {
      invalid++;
      continue;
    }

    final state = normState(at(r, Col.state));
    final cur = _str(at(r, Col.currency)).toUpperCase();
    final currency = RegExp(r'^[A-Z]{3}$').hasMatch(cur) ? cur : defaultCurrency;
    final product = _str(at(r, Col.product));
    final grp = [product, currency].where((s) => s.isNotEmpty).join(' · ');
    groups[grp] = (groups[grp] ?? 0) + 1;
    if (group != null && grp != group) continue;
    if (state == 'cancelled') {
      cancelled++;
      continue;
    }
    if (state == 'pending' && !includePending) {
      pending++;
      continue;
    }

    final d1 = _str(at(r, Col.desc)), d2 = _str(at(r, Col.desc2));
    final desc = d2.isEmpty || d2 == d1
        ? d1
        : d1.isEmpty || fold(d2).contains(fold(d1))
            ? d2
            : '$d1 - $d2';
    final type = _str(at(r, Col.type));
    final completedRaw = at(r, Col.completed);
    final when = _str(completedRaw ?? rawDate);
    final base = '$date|$when|$amount|${fold(desc)}';
    final n = seen[base] = (seen[base] ?? 0) + 1;
    out.add(ImportRow(
      line: f.headerRow + 2 + li,
      date: date,
      amount: amount,
      desc: desc.replaceAll(RegExp(r'\s+'), ' ').trim(),
      currency: currency,
      balance: parseAmountCell(at(r, Col.balance), decimalComma: dec[Col.balance] ?? anyDec),
      state: state,
      type: type,
      product: product,
      when: when,
      key: importKey(f.format, date, when, amount, desc, n),
      catHint: catHintForType(type),
    ));
  }
  return BuildResult(out, pending, cancelled, invalid, groups);
}

/// Il gruppo più numeroso (per Revolut: di solito il conto principale in euro).
String? mainGroup(Map<String, int> groups) {
  if (groups.length < 2) return null;
  return groups.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Saldo dopo l'ultima riga completata, se il file lo riporta: diventa il saldo di riferimento del conto.
(String, int)? anchorFromRows(List<ImportRow> rows, {bool dayFirst = true}) {
  final withBal = rows.where((r) => r.balance != null && r.state == 'completed').toList();
  if (withBal.isEmpty) return null;
  String dayOf(ImportRow r) => parseDateCell(r.when, dayFirst: dayFirst) ?? r.date;
  withBal.sort((a, b) {
    final c = dayOf(a).compareTo(dayOf(b));
    if (c != 0) return c;
    final w = a.when.compareTo(b.when);
    return w != 0 ? w : a.line.compareTo(b.line);
  });
  // stesso istante: vale l'ordine del file (Revolut li elenca in ordine di tempo)
  final last = withBal.last;
  return (dayOf(last), last.balance!);
}

// ------------------------------------------------------------------ doppioni

enum DupKind { none, imported, likely }

class PlanItem {
  final ImportRow row;
  final DupKind dup;

  /// Movimento già presente (da notifica o a mano) che sembra lo stesso.
  final Tx? match;
  bool selected;
  PlanItem(this.row, this.dup, this.match, {required this.selected});
}

/// Confronta le righe con i movimenti del conto: scarta quelle già importate e
/// abbina quelle che sembrano già registrate (stesso importo, data entro [days] giorni).
List<PlanItem> planImport(List<ImportRow> rows, Iterable<Tx> accountTxs, {int days = 3}) {
  final keys = {for (final t in accountTxs) if (t.importKey != null) t.importKey!};
  final candidates = accountTxs.where((t) => t.importKey == null).toList();
  final used = <String>{};
  final out = <PlanItem>[];
  for (final r in rows) {
    if (keys.contains(r.key)) {
      out.add(PlanItem(r, DupKind.imported, null, selected: false));
      continue;
    }
    Tx? best;
    var bestDays = days + 1;
    for (final t in candidates) {
      if (used.contains(t.id) || t.amount != r.amount) continue;
      final dd = daysBetween(fromKey(t.date), fromKey(r.date)).abs();
      if (dd < bestDays) {
        bestDays = dd;
        best = t;
      }
    }
    if (best != null) {
      used.add(best.id);
      out.add(PlanItem(r, DupKind.likely, best, selected: true));
    } else {
      out.add(PlanItem(r, DupKind.none, null, selected: true));
    }
  }
  return out;
}
