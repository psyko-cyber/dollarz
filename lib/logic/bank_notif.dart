import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../core/fmt.dart';

/// Lettura delle notifiche push delle banche (Android).
/// Parser euristico: importo, verso, esercente. Quello che non è sicuro finisce
/// tra i "da confermare" invece di diventare subito un movimento.

class BankNotif {
  final String pkg;
  final String title;
  final String text;
  final String big;
  final String sub;
  final int at;
  final String key;

  const BankNotif({required this.pkg, this.title = '', this.text = '', this.big = '', this.sub = '', required this.at, this.key = ''});

  factory BankNotif.fromMap(Map<String, dynamic> m) => BankNotif(
        pkg: '${m['pkg'] ?? ''}',
        title: '${m['title'] ?? ''}',
        text: '${m['text'] ?? ''}',
        big: '${m['big'] ?? ''}',
        sub: '${m['sub'] ?? ''}',
        at: m['at'] is num ? (m['at'] as num).toInt() : DateTime.now().millisecondsSinceEpoch,
        key: '${m['key'] ?? ''}',
      );

  Map<String, dynamic> toMap() => {'pkg': pkg, 'title': title, 'text': text, 'big': big, 'sub': sub, 'at': at, 'key': key};

  /// Il testo più completo tra quello breve e quello espanso.
  String get body => big.length > text.length ? big : text;

  /// Stessa notifica ripubblicata entro 2 minuti = stesso id.
  String get id => sha1.convert(utf8.encode('$pkg|$title|$body|${at ~/ 120000}')).toString().substring(0, 20);
}

enum NotifKind { expense, income, transfer, invest, ignore, unknown }

class ParsedNotif {
  final String bank;
  final NotifKind kind;

  /// Centesimi con segno: uscita negativa.
  final int amount;
  final String currency;
  final String merchant;
  final String date;
  final double confidence;
  final String? catHint;
  final String reason;

  const ParsedNotif({
    required this.bank,
    required this.kind,
    this.amount = 0,
    this.currency = 'EUR',
    this.merchant = '',
    required this.date,
    this.confidence = 0,
    this.catHint,
    this.reason = '',
  });

  /// Abbastanza sicuro da diventare subito un movimento.
  bool get autoAdd => confidence >= 0.75 && amount != 0 && kind != NotifKind.ignore && kind != NotifKind.unknown;
  bool get ignored => kind == NotifKind.ignore;

  String get bankLabel => bankLabels[bank] ?? 'Banca';

  /// Descrizione del movimento.
  String get desc {
    if (merchant.isNotEmpty) return merchant;
    return switch (kind) {
      NotifKind.income => 'Entrata $bankLabel',
      NotifKind.transfer => 'Ricarica $bankLabel',
      NotifKind.invest => 'Investimento $bankLabel',
      _ => 'Pagamento $bankLabel',
    };
  }
}

const bankLabels = {'revolut': 'Revolut', 'fineco': 'Fineco', 'traderepublic': 'Trade Republic', 'altro': 'Banca'};

String bankOf(String pkg) {
  final p = pkg.toLowerCase();
  if (p.contains('revolut')) return 'revolut';
  if (p.contains('fineco')) return 'fineco';
  if (p.contains('traderepublic') || p.contains('trade_republic') || p.contains('trade.republic')) return 'traderepublic';
  return 'altro';
}

// ------------------------------------------------------------------ parole chiave (testo già con fold)

/// Sempre da scartare: codici, accessi, pagamenti rifiutati.
const _hardIgnore = [
  'codice', 'password', 'passcode', 'accedi', 'login', 'nuovo dispositivo', 'nuovo accesso', 'accesso effettuato',
  'autorizza il', 'autorizzare', 'da autorizzare', 'conferma nell', 'approva', '3d secure', '3ds', 'rifiutat', 'declined',
  'non riuscit', 'non e andat', 'failed', 'non autorizzat', 'insufficien', 'bloccat', 'verifica la tua', 'verify',
];

/// Promozioni e avvisi: scartati se non c'è un verbo di pagamento vero.
const _softIgnore = [
  'offerta', 'promo', 'scopri', 'invita', 'sondaggio', 'survey', 'vinci', 'estratto conto', 'documento', 'aggiorna l',
  'nuova funzione', 'novita', 'saldo disponibile', 'il tuo saldo', 'your balance',
];

const _invest = [
  'piano di accumulo', "piano d'accumulo", 'piano daccumulo', 'savings plan', 'sparplan', 'ordine eseguito', 'ordine di acquisto',
  'ordine di vendita', 'order executed', 'buy order', 'sell order', 'acquisto eseguito', 'vendita eseguita', 'hai acquistato',
  'hai comprato', 'hai venduto', 'you bought', 'you sold', 'compravendita', 'esecuzione ordine', 'ordine limite eseguito',
];
const _sell = ['vendita', 'venduto', 'sell', 'sold'];
const _refund = ['rimbors', 'refund', 'restituit', 'storno'];
const _income = [
  'ricevut', 'received', 'accredit', 'in entrata', 'incoming', 'ti ha inviato', 'ti ha mandato', 'sent you', 'stipendio', 'salary',
  'interessi', 'interest', 'dividend', 'cedola', 'hai guadagnato', 'earned',
];
const _topup = ['hai aggiunto', 'aggiunti', 'added', 'ricarica', 'top up', 'top-up', 'topped up', 'hai depositato', 'deposited'];
const _expense = [
  'pagat', 'paid', 'pagamento', 'payment', 'hai speso', 'spent', 'addebit', 'debited', 'prelievo', 'prelevat', 'withdraw',
  'acquisto', 'purchase', 'hai inviato', 'you sent', 'inviato', 'bonifico in uscita', 'in uscita', 'transazione', 'spesa', 'charged',
];

const _strongVerbs = ['pagat', 'paid', 'addebit', 'accredit', 'ricevut', 'received', 'hai speso', 'spent', 'prelievo'];

bool _any(String f, List<String> words) => words.any(f.contains);

// ------------------------------------------------------------------ importi

class _Money {
  final int start, end;
  final int cents;
  final String currency;
  final String sign;
  const _Money(this.start, this.end, this.cents, this.currency, this.sign);
}

const _num = r'(\d{1,3}(?:[.,  ]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)';
final _nbsp = RegExp('[  ]');
final _moneyA = RegExp('(?<![\\w.,])([+\\-−]?)\\s?(€|eur|euro|usd|us\\\$|\\\$|£|gbp|chf)\\s?([+\\-−]?)$_num(?!\\d)', caseSensitive: false);
final _moneyB = RegExp('(?<![\\w.,])([+\\-−]?)$_num\\s?(€|eur|euro|usd|\\\$|£|gbp|chf)(?![a-z])', caseSensitive: false);

String _curCode(String s) => switch (s.toLowerCase()) {
      '€' || 'eur' || 'euro' => 'EUR',
      r'$' || 'usd' || r'us$' => 'USD',
      '£' || 'gbp' => 'GBP',
      'chf' => 'CHF',
      _ => 'EUR',
    };

List<_Money> _amounts(String t) {
  final out = <_Money>[];
  for (final m in _moneyA.allMatches(t)) {
    final v = parseNum(m[4]!.replaceAll(_nbsp, ''));
    if (v == null) continue;
    final sign = m[1]!.isNotEmpty ? m[1]! : m[3]!;
    out.add(_Money(m.start, m.end, (v * 100).round(), _curCode(m[2]!), sign));
  }
  for (final m in _moneyB.allMatches(t)) {
    if (out.any((o) => m.start < o.end && o.start < m.end)) continue;
    final v = parseNum(m[2]!.replaceAll(_nbsp, ''));
    if (v == null) continue;
    out.add(_Money(m.start, m.end, (v * 100).round(), _curCode(m[3]!), m[1]!));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// L'importo dell'operazione: il primo che non sia un saldo o un cashback.
_Money? _mainAmount(String t, List<_Money> all) {
  for (final m in all) {
    if (m.cents == 0) continue;
    final before = fold(t.substring(math.max(0, m.start - 28), m.start));
    if (RegExp(r'saldo|balance|disponibil|available|limite|limit|cashback|commission').hasMatch(before)) continue;
    return m;
  }
  return null;
}

// ------------------------------------------------------------------ esercente

final _emoji = RegExp(r'[^\p{L}\p{N}\s&@\x27’.,\-+/]', unicode: true);
final _stop = RegExp(
    r'\s+(?:il|alle|on|del|con|tramite|via|carta|card|in data|data|ore|at\s+\d|\d{1,2}[/.]\d{1,2}|\d{1,2}:\d{2})\b.*$',
    caseSensitive: false);

String _cleanName(String s) {
  var t = s.replaceAll(_emoji, ' ');
  final cut = RegExp(r'[;!?\n·|()]|\.\s|,\s|\s-\s').firstMatch(t);
  if (cut != null) t = t.substring(0, cut.start);
  t = t.replaceFirst(_stop, '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'[.,:\-]+$'), '').trim();
  if (t.length < 2 || t.length > 40) return '';
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(t)) return '';
  if (RegExp(r'^[\d€$£+\-−]').hasMatch(t)) return '';
  return t;
}

const _genericTitles = [
  'revolut', 'fineco', 'trade republic', 'pagament', 'payment', 'transazion', 'transaction', 'notific', 'carta', 'card', 'bonifico',
  'addebito', 'accredito', 'movimento', 'conto', 'account', 'ordine', 'order', 'hai ', 'you ', 'nuova', 'new ', 'acquisto', 'spesa',
  'entrata', 'uscita', 'ricarica', 'interessi', 'dividend', 'piano', 'savings',
];

String _merchant(String title, String body, _Money? amt, NotifKind kind) {
  // nel testo, dopo l'importo: "presso X", "at X", "da X", "a X"
  final after = amt != null ? body.substring(math.min(body.length, amt.end)) : body;
  final rels = kind == NotifKind.income || kind == NotifKind.transfer
      ? [r'\b(?:da|dal|dalla|from)\s+', r'\b(?:presso|at|c/o)\s+']
      : kind == NotifKind.invest
          ? [r'\b(?:in|su|di|of)\s+']
          : [r'\b(?:presso|at|c/o|da)\s+', r'\b(?:a favore di|a|to|per|verso)\s+'];
  for (final src in kind == NotifKind.invest ? [after] : [after, body]) {
    for (final r in rels) {
      final m = RegExp('$r(.+)', caseSensitive: false).firstMatch(src);
      if (m == null) continue;
      final n = _cleanName(m[1]!);
      if (n.isNotEmpty) return n;
    }
  }
  final t = _cleanName(title);
  final ft = fold(t);
  if (t.isNotEmpty && !_genericTitles.any(ft.contains) && _amounts(title).isEmpty) return t;
  return '';
}

// ------------------------------------------------------------------ data

String _dateIn(String f, int at) {
  final when = DateTime.fromMillisecondsSinceEpoch(at);
  final m = RegExp(r'(?:\bil|\bdel|\bon|\bin data|\bdata)\s+(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{2,4}))?').firstMatch(f);
  if (m != null) {
    final d = int.parse(m[1]!), mo = int.parse(m[2]!);
    var y = m[3] != null ? int.parse(m[3]!) : when.year;
    if (y < 100) y += 2000;
    if (m[3] == null && mo > when.month) y--;
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
      final dt = DateTime(y, mo, d);
      final diff = daysBetween(dt, when);
      if (dt.month == mo && diff >= 0 && diff <= 10) return dayKey(dt);
    }
  }
  return dayKey(when);
}

// ------------------------------------------------------------------ parser

/// Primo indice in cui compare una delle parole (o -1).
int _first(String f, List<String> words, {int before = 1 << 30}) {
  var best = -1;
  for (final w in words) {
    final i = f.indexOf(w);
    if (i >= 0 && i < before && (best < 0 || i < best)) best = i;
  }
  return best;
}

/// L'ultima parola chiave che compare prima di [pos] (entro 60 caratteri).
NotifKind? _nearestBefore(String f, int pos) {
  NotifKind? kind;
  var bestEnd = -1, bestLen = 0;
  void scan(List<String> words, NotifKind k) {
    for (final w in words) {
      var i = f.indexOf(w);
      while (i >= 0 && i < pos) {
        final end = i + w.length;
        // a parità di fine vince la parola più lunga ("ti ha inviato" su "inviato")
        if (pos - i <= 60 && (end > bestEnd || (end == bestEnd && w.length > bestLen))) {
          bestEnd = end;
          bestLen = w.length;
          kind = k;
        }
        i = f.indexOf(w, i + 1);
      }
    }
  }

  scan(_expense, NotifKind.expense);
  scan(_topup, NotifKind.transfer);
  scan(_income, NotifKind.income);
  return kind;
}

ParsedNotif parseBankNotif(BankNotif n) {
  final bank = bankOf(n.pkg);
  // un solo testo: titolo, corpo e sottotesto (il titolo spesso è l'esercente)
  final body = [n.body, if (n.sub.isNotEmpty && !n.body.contains(n.sub)) n.sub].join(' · ');
  final full = '${n.title} · $body';
  final f = fold(full);
  final date = _dateIn(f, n.at);
  ParsedNotif ignore(String why) => ParsedNotif(bank: bank, kind: NotifKind.ignore, date: date, reason: why);

  if (_any(f, _hardIgnore) || RegExp(r'\b(?:pin|otp|3ds|cvv)\b').hasMatch(f)) return ignore('codice, accesso o operazione rifiutata');
  final strong = _any(f, _strongVerbs);
  if (_any(f, _softIgnore) && !strong) return ignore('promozione o avviso');

  final amounts = _amounts(full);
  final amt = _mainAmount(full, amounts);
  if (amt == null) return ignore('nessun importo');

  // verso dell'operazione
  NotifKind kind;
  var fromKeyword = true;
  String? hint;
  if (_any(f, _invest)) {
    kind = NotifKind.invest;
    hint = 'investimento';
  } else if (_any(f, _refund)) {
    kind = NotifKind.income;
    hint = 'rimborsi';
  } else {
    final k = _nearestBefore(f, amt.start);
    if (k != null) {
      kind = k;
    } else {
      final ie = _first(f, _expense), ii = _first(f, _income), it = _first(f, _topup);
      final firsts = [(ie, NotifKind.expense), (ii, NotifKind.income), (it, NotifKind.transfer)].where((e) => e.$1 >= 0).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
      if (firsts.isNotEmpty) {
        kind = firsts.first.$2;
      } else if (amt.sign == '-' || amt.sign == '−') {
        kind = NotifKind.expense;
        fromKeyword = false;
      } else if (amt.sign == '+') {
        kind = NotifKind.income;
        fromKeyword = false;
      } else {
        kind = NotifKind.unknown;
        fromKeyword = false;
      }
    }
  }
  if (kind == NotifKind.income) {
    if (RegExp(r'interess|interest|dividend|cedol').hasMatch(f)) hint ??= 'rendite';
    if (RegExp(r'stipendio|salary').hasMatch(f)) hint ??= 'stipendio';
  }
  if (kind == NotifKind.transfer) hint = 'giroconto';

  // importo: per gli ordini "2,5 quote a 110,20 €" il totale è quantità × prezzo
  var cents = amt.cents.abs();
  if (kind == NotifKind.invest) {
    final before = fold(full.substring(math.max(0, amt.start - 12), amt.start));
    final q = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:azioni|azione|quote|quota|pezzi|titoli|shares|share|units|unita)').firstMatch(f);
    if (q != null && RegExp(r'(?:\ba|\bat|@|prezzo|per)\s*$').hasMatch(before)) {
      final qty = parseNum(q[1]!);
      if (qty != null && qty > 0) cents = (qty * amt.cents.abs()).round();
    }
  }
  final sell = kind == NotifKind.invest && _any(f, _sell);
  final signed = switch (kind) {
    NotifKind.income || NotifKind.transfer => cents,
    NotifKind.invest => sell ? cents : -cents,
    NotifKind.expense => -cents,
    _ => amt.sign == '+' ? cents : -cents,
  };

  final merchant = _merchant(n.title, body, _mainAmount(body, _amounts(body)), kind);
  var conf = 0.35;
  if (kind != NotifKind.unknown) conf += fromKeyword ? 0.3 : 0.15;
  if (merchant.isNotEmpty) conf += 0.15;
  if (bank != 'altro') conf += 0.15;
  if (amounts.length > 2) conf -= 0.1;

  return ParsedNotif(
    bank: bank,
    kind: kind,
    amount: signed,
    currency: amt.currency,
    merchant: merchant,
    date: date,
    confidence: clamp01(conf),
    catHint: hint,
    reason: '${kind.name}${fromKeyword ? '' : ' (dal segno)'}',
  );
}
