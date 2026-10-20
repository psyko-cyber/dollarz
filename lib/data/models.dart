import '../core/fmt.dart';

// Gli importi sono interi in centesimi (int). Le date sono chiavi "yyyy-mm-dd".

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);
double _d(Object? v, [double d = 0]) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? d : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;

// =================================================================== conti

class AccountType {
  static const conto = 'conto';
  static const risparmio = 'risparmio';
  static const contanti = 'contanti';
  static const carta = 'carta';
  static const broker = 'broker';
  static const crypto = 'crypto';

  static const labels = {
    conto: 'Conto corrente',
    risparmio: 'Conto risparmio',
    contanti: 'Contanti',
    carta: 'Carta di credito',
    broker: 'Liquidità broker',
    crypto: 'Exchange crypto',
  };
}

class Institutions {
  static const labels = {
    'revolut': 'Revolut',
    'fineco': 'Fineco',
    'traderepublic': 'Trade Republic',
    'altro': 'Altra banca',
  };
}

class Account {
  final String id;
  String name;
  String type;
  String institution;
  String currency;

  /// Saldo di riferimento: vale alla fine del giorno [anchorDate], comprese le
  /// operazioni registrate prima di [anchorAt] (ms). Tutto il resto si somma da lì.
  int anchorAmount;
  String anchorDate;
  int anchorAt;
  bool archived;
  int order;

  Account({
    required this.id,
    required this.name,
    this.type = AccountType.conto,
    this.institution = 'altro',
    this.currency = 'EUR',
    this.anchorAmount = 0,
    required this.anchorDate,
    this.anchorAt = 0,
    this.archived = false,
    this.order = 0,
  });

  /// Conta come liquidità disponibile (fondo emergenza, scadenze).
  bool get liquid => type == AccountType.conto || type == AccountType.risparmio || type == AccountType.contanti;
  bool get isCard => type == AccountType.carta;

  factory Account.fromMap(Map<String, dynamic> m) => Account(
        id: m['id'] as String,
        name: _s(m['name'], 'Conto'),
        type: _s(m['type'], AccountType.conto),
        institution: _s(m['inst'], 'altro'),
        currency: _s(m['cur'], 'EUR'),
        anchorAmount: _i(m['anchor']),
        anchorDate: _s(m['anchorDate'], todayKey()),
        anchorAt: _i(m['anchorAt']),
        archived: _b(m['archived']),
        order: _i(m['order']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'inst': institution,
        'cur': currency,
        'anchor': anchorAmount,
        'anchorDate': anchorDate,
        'anchorAt': anchorAt,
        'archived': archived,
        'order': order,
      };
}

// =================================================================== movimenti

class Tx {
  final String id;
  String date;
  int amount; // nella valuta del conto; negativo = uscita
  String accountId;
  String? catId;
  String desc;
  String note;

  /// manual | notif | import | sched | trade | adjust
  String src;

  /// Coppia di un giroconto (stesso id sui due movimenti).
  String? transferId;

  /// Impronta della riga dell'estratto da cui viene (per non importarla due volte).
  String? importKey;

  /// Creato in Dollarz alle (ms): decide se conta prima o dopo il saldo di riferimento.
  int created;

  Tx({
    required this.id,
    required this.date,
    required this.amount,
    required this.accountId,
    this.catId,
    this.desc = '',
    this.note = '',
    this.src = 'manual',
    this.transferId,
    this.importKey,
    int? created,
  }) : created = created ?? DateTime.now().millisecondsSinceEpoch;

  bool get isTransfer => transferId != null;

  factory Tx.fromMap(Map<String, dynamic> m) => Tx(
        id: m['id'] as String,
        date: _s(m['date'], todayKey()),
        amount: _i(m['amt']),
        accountId: _s(m['acc']),
        catId: _sn(m['cat']),
        desc: _s(m['desc']),
        note: _s(m['note']),
        src: _s(m['src'], 'manual'),
        transferId: _sn(m['tr']),
        importKey: _sn(m['ik']),
        created: _i(m['created']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'amt': amount,
        'acc': accountId,
        if (catId != null) 'cat': catId,
        if (desc.isNotEmpty) 'desc': desc,
        if (note.isNotEmpty) 'note': note,
        'src': src,
        if (transferId != null) 'tr': transferId,
        if (importKey != null) 'ik': importKey,
        'created': created,
      };

  Tx copy() => Tx.fromMap(toMap());
}

// =================================================================== categorie e regole

class CatKind {
  static const expense = 'expense';
  static const income = 'income';
  static const transfer = 'transfer';
}

class Bucket {
  static const need = 'need';
  static const want = 'want';
  static const future = 'future';
  static const labels = {need: 'Necessità', want: 'Desideri', future: 'Futuro'};
}

class Category {
  final String id;
  String name;
  String icon;
  String kind;
  String bucket;

  /// Budget mensile (centesimi, 0 = nessuno).
  int budget;
  bool hidden;
  bool custom;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    this.bucket = Bucket.want,
    this.budget = 0,
    this.hidden = false,
    this.custom = false,
  });

  bool get isExpense => kind == CatKind.expense;
  bool get isIncome => kind == CatKind.income;
  bool get isTransfer => kind == CatKind.transfer;

  Category copy() => Category(id: id, name: name, icon: icon, kind: kind, bucket: bucket, budget: budget, hidden: hidden, custom: custom);

  /// Salvate solo le differenze rispetto alla categoria di base (o tutto, se nuova).
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'kind': kind,
        'bucket': bucket,
        'budget': budget,
        'hidden': hidden,
        'custom': custom,
      };

  Category merged(Map<String, dynamic> m) => Category(
        id: id,
        name: _s(m['name'], name),
        icon: _s(m['icon'], icon),
        kind: _s(m['kind'], kind),
        bucket: _s(m['bucket'], bucket),
        budget: _i(m['budget'], budget),
        hidden: _b(m['hidden'], hidden),
        custom: _b(m['custom'], custom),
      );
}

/// "Se la descrizione contiene X → categoria Y" (imparata dalle correzioni).
class Rule {
  final String id;
  String pattern; // testo normalizzato con fold()
  String catId;
  String? rename;
  int hits;

  Rule({required this.id, required this.pattern, required this.catId, this.rename, this.hits = 0});

  factory Rule.fromMap(Map<String, dynamic> m) =>
      Rule(id: m['id'] as String, pattern: _s(m['p']), catId: _s(m['cat']), rename: _sn(m['rename']), hits: _i(m['hits']));

  Map<String, dynamic> toMap() => {'id': id, 'p': pattern, 'cat': catId, if (rename != null) 'rename': rename, 'hits': hits};
}

// =================================================================== scadenze

class Freq {
  static const monthly = 'm';
  static const yearly = 'y';
  static const weekly = 'w';
  static const once = 'o';
  static const everyN = 'n';

  static String label(String f, int every) => switch (f) {
        monthly => 'Ogni mese',
        yearly => 'Ogni anno',
        weekly => every > 1 ? 'Ogni $every settimane' : 'Ogni settimana',
        once => 'Una volta',
        everyN => every == 2
            ? 'Ogni 2 mesi'
            : every == 3
                ? 'Ogni 3 mesi'
                : every == 6
                    ? 'Ogni 6 mesi'
                    : 'Ogni $every mesi',
        _ => f,
      };
}

class Scheduled {
  final String id;
  String name;
  int amount; // negativo = uscita, positivo = entrata (es. stipendio)
  String? accountId;
  String? catId;
  String freq;
  int every;
  String start; // prima scadenza
  String? end;
  int remindDays;

  /// Importo variabile (bollette): l'abbinamento ai movimenti è più tollerante.
  bool variable;
  bool active;
  String match; // testo da cercare nei movimenti (vuoto = nome)
  String note;

  Scheduled({
    required this.id,
    required this.name,
    required this.amount,
    this.accountId,
    this.catId,
    this.freq = Freq.monthly,
    this.every = 1,
    required this.start,
    this.end,
    this.remindDays = 2,
    this.variable = false,
    this.active = true,
    this.match = '',
    this.note = '',
  });

  bool get isIncome => amount > 0;

  factory Scheduled.fromMap(Map<String, dynamic> m) => Scheduled(
        id: m['id'] as String,
        name: _s(m['name'], 'Scadenza'),
        amount: _i(m['amt']),
        accountId: _sn(m['acc']),
        catId: _sn(m['cat']),
        freq: _s(m['freq'], Freq.monthly),
        every: _i(m['every'], 1).clamp(1, 60),
        start: _s(m['start'], todayKey()),
        end: _sn(m['end']),
        remindDays: _i(m['remind'], 2),
        variable: _b(m['var']),
        active: _b(m['active'], true),
        match: _s(m['match']),
        note: _s(m['note']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'amt': amount,
        if (accountId != null) 'acc': accountId,
        if (catId != null) 'cat': catId,
        'freq': freq,
        'every': every,
        'start': start,
        if (end != null) 'end': end,
        'remind': remindDays,
        'var': variable,
        'active': active,
        if (match.isNotEmpty) 'match': match,
        if (note.isNotEmpty) 'note': note,
      };
}

/// Stato di una singola scadenza: id = "scadenza|data".
class Occurrence {
  final String id;
  final String schedId;
  final String date;
  String status; // paid | skip
  String? txId;
  int? amount;

  Occurrence({required this.id, required this.schedId, required this.date, required this.status, this.txId, this.amount});

  static String key(String schedId, String date) => '$schedId|$date';

  factory Occurrence.fromMap(Map<String, dynamic> m) => Occurrence(
        id: m['id'] as String,
        schedId: _s(m['sid']),
        date: _s(m['date']),
        status: _s(m['st'], 'paid'),
        txId: _sn(m['tx']),
        amount: m['amt'] is num ? (m['amt'] as num).toInt() : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'sid': schedId,
        'date': date,
        'st': status,
        if (txId != null) 'tx': txId,
        if (amount != null) 'amt': amount,
      };
}

// =================================================================== investimenti

class HoldingKind {
  static const etf = 'etf';
  static const stock = 'azione';
  static const bond = 'bond';
  static const crypto = 'crypto';
  static const deposit = 'deposito';
  static const fund = 'fondo';
  static const other = 'altro';

  static const labels = {
    etf: 'ETF',
    stock: 'Azione',
    bond: 'Obbligazione / BTP',
    crypto: 'Crypto',
    deposit: 'Conto deposito',
    fund: 'Fondo',
    other: 'Altro',
  };

  /// Aliquota sulle plusvalenze di default (Italia, 2026).
  static double defaultTax(String k) => switch (k) {
        bond => 12.5,
        crypto => 33,
        _ => 26,
      };
}

class Holding {
  final String id;
  String name;
  String kind;
  String isin;

  /// Simbolo Yahoo (es. "VWCE.DE") o id CoinGecko (es. "bitcoin").
  String symbol;
  String currency;
  String? accountId;
  double taxRate;

  /// Prezzo inserito a mano (per unità, nella valuta del titolo); 0 = usa i prezzi online.
  double manualPrice;
  int manualAt;

  /// Obbligazioni: prezzo in percentuale del nominale (100 = alla pari).
  bool pricePct;

  /// Cedola o tasso annuo lordo (%), per obbligazioni e conti deposito.
  double rate;

  // conti deposito
  int principal;
  String? start;
  String? maturity;
  bool archived;

  Holding({
    required this.id,
    required this.name,
    this.kind = HoldingKind.etf,
    this.isin = '',
    this.symbol = '',
    this.currency = 'EUR',
    this.accountId,
    double? taxRate,
    this.manualPrice = 0,
    this.manualAt = 0,
    this.pricePct = false,
    this.rate = 0,
    this.principal = 0,
    this.start,
    this.maturity,
    this.archived = false,
  }) : taxRate = taxRate ?? HoldingKind.defaultTax(kind);

  bool get isDeposit => kind == HoldingKind.deposit;
  bool get isCrypto => kind == HoldingKind.crypto;
  bool get isBond => kind == HoldingKind.bond;

  /// Chiave del prezzo nella collezione "prices".
  String? get priceKey => symbol.isEmpty ? null : (isCrypto ? 'c:$symbol' : 'y:$symbol');

  factory Holding.fromMap(Map<String, dynamic> m) => Holding(
        id: m['id'] as String,
        name: _s(m['name'], 'Titolo'),
        kind: _s(m['kind'], HoldingKind.etf),
        isin: _s(m['isin']),
        symbol: _s(m['sym']),
        currency: _s(m['cur'], 'EUR'),
        accountId: _sn(m['acc']),
        taxRate: m['tax'] is num ? (m['tax'] as num).toDouble() : null,
        manualPrice: _d(m['mp']),
        manualAt: _i(m['mpAt']),
        pricePct: _b(m['pct']),
        rate: _d(m['rate']),
        principal: _i(m['principal']),
        start: _sn(m['start']),
        maturity: _sn(m['maturity']),
        archived: _b(m['archived']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind,
        if (isin.isNotEmpty) 'isin': isin,
        if (symbol.isNotEmpty) 'sym': symbol,
        'cur': currency,
        if (accountId != null) 'acc': accountId,
        'tax': taxRate,
        if (manualPrice > 0) 'mp': manualPrice,
        if (manualAt > 0) 'mpAt': manualAt,
        if (pricePct) 'pct': true,
        if (rate != 0) 'rate': rate,
        if (principal != 0) 'principal': principal,
        if (start != null) 'start': start,
        if (maturity != null) 'maturity': maturity,
        'archived': archived,
      };
}

class TradeType {
  static const buy = 'buy';
  static const sell = 'sell';
  static const dividend = 'div';
  static const coupon = 'cedola';
  static const fee = 'fee';

  static const labels = {buy: 'Acquisto', sell: 'Vendita', dividend: 'Dividendo', coupon: 'Cedola / interessi', fee: 'Costo'};
}

class Trade {
  final String id;
  String holdingId;
  String date;
  String type;
  double qty;
  double price; // per unità (per le obbligazioni: % del nominale)
  int amount; // controvalore in euro, senza commissioni (dividendi e cedole: netti)
  int fees;

  /// Movimento di liquidità collegato (sul conto del broker).
  String? txId;

  Trade({
    required this.id,
    required this.holdingId,
    required this.date,
    required this.type,
    this.qty = 0,
    this.price = 0,
    this.amount = 0,
    this.fees = 0,
    this.txId,
  });

  factory Trade.fromMap(Map<String, dynamic> m) => Trade(
        id: m['id'] as String,
        holdingId: _s(m['hid']),
        date: _s(m['date'], todayKey()),
        type: _s(m['type'], TradeType.buy),
        qty: _d(m['qty']),
        price: _d(m['price']),
        amount: _i(m['amt']),
        fees: _i(m['fees']),
        txId: _sn(m['tx']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'hid': holdingId,
        'date': date,
        'type': type,
        if (qty != 0) 'qty': qty,
        if (price != 0) 'price': price,
        'amt': amount,
        if (fees != 0) 'fees': fees,
        if (txId != null) 'tx': txId,
      };
}

// =================================================================== beni e debiti

class AssetKind {
  static const home = 'immobile';
  static const vehicle = 'veicolo';
  static const pension = 'pensione';
  static const other = 'altro';
  static const debt = 'debito';

  static const labels = {
    home: 'Immobile',
    vehicle: 'Veicolo',
    pension: 'Fondo pensione',
    other: 'Altro bene',
    debt: 'Debito / finanziamento',
  };
}

class Asset {
  final String id;
  String name;
  String kind;
  int value; // per i debiti: residuo da restituire (positivo)
  double rate; // debiti: TAN %; pensione: rendimento atteso %
  int monthly; // rata o versamento mensile
  String updated;

  /// Conta per l'indipendenza finanziaria (rende o si può usare per vivere).
  bool inFi;

  Asset({
    required this.id,
    required this.name,
    required this.kind,
    this.value = 0,
    this.rate = 0,
    this.monthly = 0,
    String? updated,
    bool? inFi,
  })  : updated = updated ?? todayKey(),
        inFi = inFi ?? (kind == AssetKind.pension);

  bool get isDebt => kind == AssetKind.debt;

  factory Asset.fromMap(Map<String, dynamic> m) => Asset(
        id: m['id'] as String,
        name: _s(m['name'], 'Bene'),
        kind: _s(m['kind'], AssetKind.other),
        value: _i(m['value']),
        rate: _d(m['rate']),
        monthly: _i(m['monthly']),
        updated: _sn(m['updated']),
        inFi: m['inFi'] is bool ? m['inFi'] as bool : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind,
        'value': value,
        if (rate != 0) 'rate': rate,
        if (monthly != 0) 'monthly': monthly,
        'updated': updated,
        'inFi': inFi,
      };
}

// =================================================================== profilo e obiettivi

class Profile {
  String name;

  /// Entrate nette e spese mensili dichiarate (servono finché non c'è storico).
  int incomeMonthly;
  int expensesMonthly;

  /// Tasso di prelievo sostenibile (%): 4 = regola del 4%, 3,5 = prudente.
  double swr;
  double inflation;

  /// Rendimenti reali annui degli scenari (%): prudente, realistico, ottimista.
  List<double> returns;
  int emergencyMonths;
  double savingsTargetPct;

  /// Obiettivi: rendita passiva mensile e patrimonio target (centesimi, 0 = non impostato).
  int targetPassive;
  int targetWealth;
  bool goalFi;

  /// Le tappe "fondamenta" (scadenze coperte, fondo emergenza, debiti) nel percorso del coach.
  bool foundations;
  bool onboarded;

  Profile({
    this.name = '',
    this.incomeMonthly = 0,
    this.expensesMonthly = 0,
    this.swr = 4,
    this.inflation = 2,
    List<double>? returns,
    this.emergencyMonths = 6,
    this.savingsTargetPct = 20,
    this.targetPassive = 0,
    this.targetWealth = 0,
    this.goalFi = true,
    this.foundations = true,
    this.onboarded = false,
  }) : returns = returns ?? [2, 4, 6];

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        name: _s(m['name']),
        incomeMonthly: _i(m['income']),
        expensesMonthly: _i(m['expenses']),
        swr: _d(m['swr'], 4),
        inflation: _d(m['infl'], 2),
        returns: (m['returns'] as List?)?.map((e) => _d(e)).toList(),
        emergencyMonths: _i(m['emerg'], 6),
        savingsTargetPct: _d(m['saveT'], 20),
        targetPassive: _i(m['tPassive']),
        targetWealth: _i(m['tWealth']),
        goalFi: _b(m['goalFi'], true),
        foundations: _b(m['found'], true),
        onboarded: _b(m['onb']),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'income': incomeMonthly,
        'expenses': expensesMonthly,
        'swr': swr,
        'infl': inflation,
        'returns': returns,
        'emerg': emergencyMonths,
        'saveT': savingsTargetPct,
        'tPassive': targetPassive,
        'tWealth': targetWealth,
        'goalFi': goalFi,
        'found': foundations,
        'onb': onboarded,
      };
}

/// Fotografia del patrimonio di un mese (id "yyyy-mm"), aggiornata ogni giorno.
class Snapshot {
  final String month;
  final int liquid, invested, assets, debts;
  const Snapshot(this.month, {this.liquid = 0, this.invested = 0, this.assets = 0, this.debts = 0});

  int get total => liquid + invested + assets - debts;

  factory Snapshot.fromMap(Map<String, dynamic> m) =>
      Snapshot(m['id'] as String, liquid: _i(m['liq']), invested: _i(m['inv']), assets: _i(m['ass']), debts: _i(m['debt']));

  Map<String, dynamic> toMap() => {'id': month, 'liq': liquid, 'inv': invested, 'ass': assets, 'debt': debts};
}

/// Prezzo scaricato (id "y:VWCE.DE" o "c:bitcoin").
class Quote {
  final String key;
  final double price;
  final String currency;
  final int at;
  final String name;
  const Quote(this.key, this.price, this.currency, this.at, [this.name = '']);

  factory Quote.fromMap(Map<String, dynamic> m) =>
      Quote(m['id'] as String, _d(m['p']), _s(m['cur'], 'EUR'), _i(m['at']), _s(m['name']));

  Map<String, dynamic> toMap() => {'id': key, 'p': price, 'cur': currency, 'at': at, if (name.isNotEmpty) 'name': name};
}

/// Consulenza AI salvata.
class Consult {
  final String id;
  final int at;
  final String summary;
  final List<ConsultPoint> points;
  final String raw;
  const Consult({required this.id, required this.at, required this.summary, required this.points, this.raw = ''});

  factory Consult.fromMap(Map<String, dynamic> m) => Consult(
        id: m['id'] as String,
        at: _i(m['at']),
        summary: _s(m['sum']),
        points: ((m['pts'] as List?) ?? const []).map((e) => ConsultPoint.fromMap((e as Map).cast<String, dynamic>())).toList(),
        raw: _s(m['raw']),
      );

  Map<String, dynamic> toMap() => {'id': id, 'at': at, 'sum': summary, 'pts': points.map((p) => p.toMap()).toList(), if (raw.isNotEmpty) 'raw': raw};
}

class ConsultPoint {
  final String title, why, action;
  bool done;
  ConsultPoint(this.title, this.why, this.action, {this.done = false});

  factory ConsultPoint.fromMap(Map<String, dynamic> m) =>
      ConsultPoint(_s(m['t']), _s(m['w']), _s(m['a']), done: _b(m['done']));

  Map<String, dynamic> toMap() => {'t': title, 'w': why, 'a': action, 'done': done};
}

/// Notifica della banca letta ma non abbastanza sicura: va confermata.
class InboxItem {
  final String id;
  final int at;
  final String bank;
  final String kind;
  final int amount;
  final String currency;
  final String merchant;
  final String date;
  final double conf;
  final String? catHint;

  /// Testo della notifica (titolo e corpo), per capire cosa era.
  final String text;

  const InboxItem({
    required this.id,
    required this.at,
    required this.bank,
    required this.kind,
    required this.amount,
    this.currency = 'EUR',
    this.merchant = '',
    required this.date,
    this.conf = 0,
    this.catHint,
    this.text = '',
  });

  factory InboxItem.fromMap(Map<String, dynamic> m) => InboxItem(
        id: m['id'] as String,
        at: _i(m['at']),
        bank: _s(m['bank'], 'altro'),
        kind: _s(m['kind'], 'unknown'),
        amount: _i(m['amt']),
        currency: _s(m['cur'], 'EUR'),
        merchant: _s(m['merchant']),
        date: _s(m['date'], todayKey()),
        conf: _d(m['conf']),
        catHint: _sn(m['cat']),
        text: _s(m['text']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'at': at,
        'bank': bank,
        'kind': kind,
        'amt': amount,
        'cur': currency,
        if (merchant.isNotEmpty) 'merchant': merchant,
        'date': date,
        'conf': conf,
        if (catHint != null) 'cat': catHint,
        if (text.isNotEmpty) 'text': text,
      };
}
