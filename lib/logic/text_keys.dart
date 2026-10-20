import '../core/fmt.dart';

/// Parole che non dicono nulla sul negozio ("PAGAMENTO POS ... CARTA ****1234").
const _noise = {
  'pagamento', 'pagam', 'pag', 'pos', 'carta', 'card', 'debit', 'credit', 'addebito', 'addebiti', 'sdd', 'sepa', 'bonifico',
  'a', 'favore', 'di', 'da', 'del', 'della', 'presso', 'at', 'to', 'from', 'il', 'la', 'lo', 'le', 'per', 'su', 'in', 'con',
  'acquisto', 'operazione', 'op', 'n', 'nr', 'num', 'rif', 'ref', 'eur', 'euro', 'mastercard', 'visa', 'maestro', 'contactless',
  'apple', 'pay', 'google', 'paypal', 'europe', 'sarl', 'srl', 'spa', 'ltd', 'inc', 'gmbh', 'sa', 'bv', 'it', 'com', 'www',
  'transaction', 'payment', 'purchase', 'online', 'web', 'shop', 'italia', 'italy', 'mi', 'rm', 'fattura',
};

/// Parole significative della descrizione (minuscole, senza accenti e numeri).
List<String> descWords(String desc) {
  final t = fold(desc).replaceAll(RegExp(r'[^a-z&]+'), ' ').trim();
  return t.split(' ').where((w) => w.length >= 2 && !_noise.contains(w)).toList();
}

/// Chiave del negozio: le prime parole significative ("esselunga", "netflix").
String merchantKey(String desc, {int words = 2}) {
  final w = descWords(desc);
  if (w.isEmpty) return '';
  return w.take(words).join(' ');
}

/// Nome leggibile del negozio dalla descrizione: "PAG POS ESSELUNGA SPA MILANO" -> "Esselunga Milano".
String prettyMerchant(String desc) {
  final w = descWords(desc).take(3).toList();
  if (w.isEmpty) return desc.trim();
  return w.map((x) => x.length <= 3 && x != 'bar' ? x.toUpperCase() : x[0].toUpperCase() + x.substring(1)).join(' ');
}

/// [pattern] compare in [text] come parola intera (entrambi già normalizzati con fold).
bool containsWord(String text, String pattern) {
  final p = pattern.trim();
  if (p.isEmpty) return false;
  final i = text.indexOf(p);
  if (i < 0) return false;
  bool isWordChar(String c) => RegExp(r'[a-z0-9]').hasMatch(c);
  var idx = i;
  while (idx >= 0) {
    final before = idx == 0 ? ' ' : text[idx - 1];
    final afterPos = idx + p.length;
    final after = afterPos >= text.length ? ' ' : text[afterPos];
    final startOk = !isWordChar(p[0]) || !isWordChar(before);
    final endOk = !isWordChar(p[p.length - 1]) || !isWordChar(after);
    if (startOk && endOk) return true;
    idx = text.indexOf(p, idx + 1);
  }
  return false;
}
