import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../logic/balances.dart';
import '../logic/bank_notif.dart';
import '../logic/budget.dart';
import '../logic/categorize.dart';
import '../logic/coach.dart';
import '../logic/forecast.dart';
import '../logic/invest.dart';
import '../logic/recurring.dart';
import '../logic/report.dart';
import '../logic/schedule.dart';
import '../logic/text_keys.dart';
import 'categories.dart';
import 'local_prefs.dart';
import 'models.dart';
import 'store.dart';

/// Patrimonio netto in euro (centesimi).
class NetWorth {
  /// Tutti i conti (le carte di credito contano in negativo).
  final int liquid;
  final int invested;
  final int assets;
  final int debts;
  const NetWorth(this.liquid, this.invested, this.assets, this.debts);
  int get total => liquid + invested + assets - debts;
}

/// Stato centrale: dati tipizzati + cache derivate invalidate a ogni modifica.
class AppState extends ChangeNotifier {
  final Store store;
  final LocalPrefs prefs;

  AppState(this.store, this.prefs) {
    store.addListener(_onStore);
    prefs.addListener(notifyListeners);
  }

  final Map<String, Object?> _cache = {};

  void _onStore() {
    _cache.clear();
    notifyListeners();
  }

  /// Svuota le cache (es. cambio di giorno, prezzi aggiornati).
  void refresh() {
    _cache.clear();
    notifyListeners();
  }

  T memo<T>(String key, T Function() fn) {
    if (_cache.containsKey(key)) return _cache[key] as T;
    final v = fn();
    _cache[key] = v;
    return v;
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ================================================================ profilo

  Profile get profile => memo('profile', () {
        final m = store.get('profile', 'me');
        return m == null ? Profile() : Profile.fromMap(m);
      });

  bool get onboarded => profile.onboarded;
  void saveProfile(Profile p) => store.put('profile', 'me', p.toMap());

  // ================================================================ cambi

  FxRates get fx => memo('fx', () {
        final r = store.get('misc', 'fx')?['rates'];
        if (r is! Map) return <String, double>{};
        return {for (final e in r.entries) '${e.key}': (e.value as num).toDouble()};
      });

  int get fxAt => (store.get('misc', 'fx')?['at'] as num?)?.toInt() ?? 0;
  void saveFx(Map<String, double> rates) => store.put('misc', 'fx', {'rates': rates, 'at': _now});
  int eur(int cents, String cur) => toEur(cents, cur, fx);

  /// Valute usate nei conti e nei titoli (oltre all'euro).
  Set<String> get currencies => {
        for (final a in allAccounts) a.currency,
        for (final h in holdings) h.currency,
        for (final q in quotes.values) q.currency,
      }..remove('EUR');

  // ================================================================ conti

  List<Account> get allAccounts => memo('accounts', () {
        return store.all('accounts').map(Account.fromMap).toList()
          ..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.name.compareTo(b.name));
      });

  List<Account> get accounts => memo('accountsActive', () => allAccounts.where((a) => !a.archived).toList());
  Map<String, Account> get accountById => memo('accountById', () => {for (final a in allAccounts) a.id: a});
  Account? account(String? id) => id == null ? null : accountById[id];

  /// Il conto di tutti i giorni: il primo conto corrente.
  Account? get mainAccount => memo('main', () => accounts.where((a) => a.type == AccountType.conto).firstOrNull ?? accounts.firstOrNull);

  /// Conto di una banca per i movimenti dalle notifiche (gli investimenti vanno sul conto broker).
  Account? accountForBank(String bank, {bool invest = false}) {
    final mine = accounts.where((a) => a.institution == bank).toList();
    if (invest) {
      final b = mine.where((a) => a.type == AccountType.broker).firstOrNull;
      if (b != null) return b;
    }
    return mine.where((a) => a.type == AccountType.conto || a.type == AccountType.carta).firstOrNull ?? mine.firstOrNull;
  }

  void saveAccount(Account a) => store.put('accounts', a.id, a.toMap());

  void deleteAccount(Account a) => store.batch(() {
        for (final t in txsOf(a.id)) {
          store.remove('tx', t.id);
        }
        store.remove('accounts', a.id);
      });

  int balance(Account a) => memo('bal:${a.id}', () => currentBalance(a, txsOf(a.id)));
  int balanceEur(Account a) => eur(balance(a), a.currency);

  /// L'utente scrive il saldo vero: diventa il nuovo riferimento del conto.
  void setBalance(Account a, int amount, {String? date}) {
    a.anchorAmount = amount;
    a.anchorDate = date ?? todayKey();
    a.anchorAt = _now;
    saveAccount(a);
  }

  /// Liquidità per fondo emergenza e scadenze: conti, risparmi e contanti.
  int get liquidCash => memo('liquidCash', () => accounts.where((a) => a.liquid).fold(0, (s, a) => s + balanceEur(a)));

  // ================================================================ movimenti

  static int _txOrder(Tx a, Tx b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.created.compareTo(a.created);
  }

  /// Tutti i movimenti, dal più recente.
  List<Tx> get txs => memo('txs', () => store.all('tx').map(Tx.fromMap).toList()..sort(_txOrder));
  Map<String, Tx> get txById => memo('txById', () => {for (final t in txs) t.id: t});
  Tx? tx(String? id) => id == null ? null : txById[id];

  Map<String, List<Tx>> get txByAccount => memo('txByAcc', () {
        final m = <String, List<Tx>>{};
        for (final t in txs) {
          (m[t.accountId] ??= []).add(t);
        }
        return m;
      });

  List<Tx> txsOf(String accountId) => txByAccount[accountId] ?? const [];

  List<Tx> transferPair(Tx t) => t.transferId == null ? [t] : txs.where((x) => x.transferId == t.transferId).toList();

  void saveTx(Tx t) => store.put('tx', t.id, t.toMap());

  Tx addTx({
    required int amount,
    required String accountId,
    String? catId,
    String desc = '',
    String note = '',
    String? date,
    String src = 'manual',
    String? importKey,
    bool suggest = true,
    int? created,
  }) {
    final t = Tx(
      id: newId(),
      date: date ?? todayKey(),
      amount: amount,
      accountId: accountId,
      catId: catId ?? (suggest ? suggestCat(desc, amount) : null),
      desc: desc.trim(),
      note: note.trim(),
      src: src,
      importKey: importKey,
      created: created,
    );
    saveTx(t);
    return t;
  }

  /// Toglie un movimento (e l'altra metà se è un giroconto), sganciando le scadenze.
  void deleteTx(Tx t) => store.batch(() {
        for (final x in transferPair(t)) {
          store.remove('tx', x.id);
          for (final o in occ.values.where((o) => o.txId == x.id)) {
            store.remove('occ', o.id);
          }
          for (final tr in allTrades.where((tr) => tr.txId == x.id)) {
            tr.txId = null;
            store.put('trades', tr.id, tr.toMap());
          }
        }
      });

  /// Giroconto tra due conti propri. [amountTo] serve se le valute sono diverse.
  void saveTransfer({
    required Account from,
    required Account to,
    required int amount,
    int? amountTo,
    required String date,
    String desc = '',
    String catId = transferCat,
    String? transferId,
  }) {
    final id = transferId ?? newId();
    final old = transferId == null ? <Tx>[] : txs.where((x) => x.transferId == transferId).toList();
    final out = old.where((x) => x.amount < 0).firstOrNull;
    final inn = old.where((x) => x.amount > 0).firstOrNull;
    final label = desc.trim().isEmpty ? 'Giroconto ${from.name} → ${to.name}' : desc.trim();
    store.batch(() {
      saveTx(Tx(
        id: out?.id ?? newId(),
        date: date,
        amount: -amount.abs(),
        accountId: from.id,
        catId: catId,
        desc: label,
        src: out?.src ?? 'manual',
        transferId: id,
        created: out?.created,
      ));
      saveTx(Tx(
        id: inn?.id ?? newId(),
        date: date,
        amount: (amountTo ?? amount).abs(),
        accountId: to.id,
        catId: transferCat,
        desc: label,
        src: inn?.src ?? 'manual',
        transferId: id,
        created: inn?.created,
      ));
    });
  }

  /// Movimenti filtrati per la lista.
  List<Tx> filterTxs({String q = '', String? accountId, String? catId, String? month, bool uncategorized = false}) {
    final words = fold(q.trim()).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return txs.where((t) {
      if (accountId != null && t.accountId != accountId) return false;
      if (month != null && !t.date.startsWith(month)) return false;
      if (uncategorized && (t.catId != null || t.isTransfer)) return false;
      if (catId != null && (catId == noCat ? t.catId != null : t.catId != catId)) return false;
      if (words.isNotEmpty) {
        final text = fold('${t.desc} ${t.note} ${cat(t.catId)?.name ?? ''} ${(t.amount / 100).toStringAsFixed(2)}');
        if (!words.every(text.contains)) return false;
      }
      return true;
    }).toList();
  }

  // ================================================================ categorie e regole

  Map<String, Category> get cats => memo('cats', () {
        final over = {for (final m in store.all('cats')) m['id'] as String: m};
        final out = <String, Category>{};
        for (final c in defaultCategories) {
          out[c.id] = over.containsKey(c.id) ? c.merged(over[c.id]!) : c;
        }
        for (final e in over.entries) {
          if (out.containsKey(e.key)) continue;
          out[e.key] = Category(id: e.key, name: 'Categoria', icon: 'more', kind: CatKind.expense, custom: true).merged(e.value);
        }
        return out;
      });

  Category? cat(String? id) => id == null ? null : cats[id];

  List<Category> catsOfKind(String kind, {bool withHidden = false}) =>
      cats.values.where((c) => c.kind == kind && (withHidden || !c.hidden)).toList();

  void saveCategory(Category c) => store.put('cats', c.id, c.toMap());

  void deleteCategory(Category c) {
    if (!c.custom) {
      saveCategory(c.copy()..hidden = true);
      return;
    }
    store.batch(() {
      for (final t in txs.where((t) => t.catId == c.id)) {
        t.catId = null;
        saveTx(t);
      }
      for (final r in rules.where((r) => r.catId == c.id)) {
        store.remove('rules', r.id);
      }
      store.remove('cats', c.id);
    });
  }

  List<Rule> get rules => memo('rules', () => store.all('rules').map(Rule.fromMap).toList()..sort((a, b) => a.pattern.compareTo(b.pattern)));

  String? suggestCat(String desc, int amount) => suggestCategory(desc, rules, amount: amount, cats: cats);

  /// Impara dalla scelta dell'utente. Ritorna quanti altri movimenti senza
  /// categoria hanno ricevuto la stessa categoria.
  int learn(String desc, String catId, {bool applyToOthers = true, String? exceptTx}) {
    final r = learnRule(desc, catId, rules, newId);
    if (r == null) return 0;
    var n = 0;
    final c = cats[catId];
    store.batch(() {
      store.put('rules', r.id, r.toMap());
      if (!applyToOthers) return;
      for (final t in txs) {
        if (t.catId != null || t.isTransfer || t.id == exceptTx) continue;
        if (c != null && !c.isTransfer && (t.amount < 0) != c.isExpense) continue;
        if (!containsWord(fold(t.desc), r.pattern)) continue;
        t.catId = catId;
        saveTx(t);
        n++;
      }
    });
    return n;
  }

  void deleteRule(Rule r) => store.remove('rules', r.id);
  void saveRule(Rule r) => store.put('rules', r.id, r.toMap());

  // ================================================================ scadenze

  List<Scheduled> get scheds => memo('scheds', () => store.all('sched').map(Scheduled.fromMap).toList()..sort((a, b) => a.name.compareTo(b.name)));
  Scheduled? sched(String id) => scheds.where((s) => s.id == id).firstOrNull;
  Map<String, Occurrence> get occ => memo('occ', () => {for (final m in store.all('occ')) m['id'] as String: Occurrence.fromMap(m)});
  Set<String> get linkedTxIds => memo('linked', () => {for (final o in occ.values) if (o.txId != null) o.txId!});

  List<OccView> occBetween(String from, String to) =>
      memo('occ:$from:$to', () => occurrencesBetween(scheds.where((s) => s.active), occ, from, to));

  /// Dagli ultimi 40 giorni ai prossimi 90.
  List<OccView> get upcoming => occBetween(addDaysKey(todayKey(), -40), addDaysKey(todayKey(), 90));

  /// Scadenze passate da poco e non segnate.
  List<OccView> get overdue => memo('overdue', () {
        final t = todayKey(), from = addDaysKey(t, -10);
        return upcoming.where((o) => o.state == OccState.overdue && o.date.compareTo(from) >= 0).toList();
      });

  void saveSched(Scheduled s) => store.put('sched', s.id, s.toMap());

  void deleteSched(Scheduled s) => store.batch(() {
        for (final o in occ.values.where((o) => o.schedId == s.id)) {
          store.remove('occ', o.id);
        }
        store.remove('sched', s.id);
      });

  void markPaid(OccView o, {String? txId, int? amount}) => store.put(
      'occ',
      o.id,
      Occurrence(id: o.id, schedId: o.sched.id, date: o.date, status: 'paid', txId: txId, amount: amount ?? o.rec?.amount).toMap());

  void markSkipped(OccView o) =>
      store.put('occ', o.id, Occurrence(id: o.id, schedId: o.sched.id, date: o.date, status: 'skip').toMap());

  void reopen(OccView o) => store.remove('occ', o.id);

  /// Paga la scadenza creando il movimento.
  Tx? payNow(OccView o, {int? amount, String? accountId, String? date}) {
    final acc = account(accountId ?? o.sched.accountId) ?? mainAccount;
    if (acc == null) return null;
    final amt = amount ?? o.amount;
    Tx? t;
    store.batch(() {
      t = addTx(amount: amt, accountId: acc.id, catId: o.sched.catId, desc: o.sched.name, date: date ?? todayKey(), src: 'sched', suggest: o.sched.catId == null);
      markPaid(o, txId: t!.id, amount: amt != o.sched.amount ? amt : null);
    });
    return t;
  }

  /// Abbina in automatico le scadenze aperte ai movimenti arrivati. Ritorna quante.
  int matchScheduled() {
    final t = todayKey();
    final open = occBetween(addDaysKey(t, -40), addDaysKey(t, 7)).where((o) => o.open).toList();
    if (open.isEmpty) return 0;
    final from = addDaysKey(t, -50);
    final pool = txs.where((x) => x.date.compareTo(from) >= 0 && x.src != 'sched').toList();
    final found = autoMatch(open, pool, linkedTxIds);
    if (found.isEmpty) return 0;
    store.batch(() {
      for (final (o, x) in found) {
        markPaid(o, txId: x.id, amount: x.amount != o.sched.amount ? x.amount : null);
      }
    });
    return found.length;
  }

  /// Saldo previsto di ogni conto per 90 giorni.
  List<AccountForecast> get forecasts => memo('forecasts', () {
        final open = upcoming.where((o) => o.open).toList();
        final main = mainAccount;
        return [
          for (final a in accounts)
            if (a.liquid || a.isCard) forecastAccount(a, balance(a), openFor(a, open, isMain: a.id == main?.id)),
        ];
      });

  /// Il primo conto che andrebbe in rosso.
  (Account, ForecastPoint)? get firstRed => memo('firstRed', () {
        (Account, ForecastPoint)? best;
        for (final f in forecasts) {
          // le carte di credito vivono "in rosso": conta solo se peggiora
          if (f.account.isCard) continue;
          final p = f.firstNegative;
          if (p == null || f.start < 0 && p.balance >= f.start) continue;
          if (best == null || p.date.compareTo(best.$2.date) < 0) best = (f.account, p);
        }
        return best;
      });

  /// Spese ricorrenti trovate nei movimenti che non sono ancora scadenze.
  List<RecurringFound> get recurring => memo('recurring', () {
        final ignore = {...ignoredRecurring, for (final s in scheds) merchantKey(s.match.isNotEmpty ? s.match : s.name)};
        return findRecurring(txs, ignore: ignore, transferCats: {for (final c in cats.values) if (c.isTransfer) c.id});
      });

  Set<String> get ignoredRecurring => ((store.get('misc', 'recIgnore')?['keys'] as List?) ?? const []).cast<String>().toSet();
  void ignoreRecurring(String key) => store.put('misc', 'recIgnore', {'keys': [...ignoredRecurring, key]});

  Scheduled schedFromRecurring(RecurringFound r) {
    final s = Scheduled(
      id: newId(),
      name: r.name,
      amount: r.amount,
      accountId: r.accountId,
      catId: r.catId,
      freq: r.freq,
      start: r.nextDate,
      variable: r.variable,
      match: r.key,
    );
    saveSched(s);
    return s;
  }

  // ================================================================ investimenti

  List<Holding> get allHoldings => memo('holdings', () => store.all('holdings').map(Holding.fromMap).toList()..sort((a, b) => a.name.compareTo(b.name)));
  List<Holding> get holdings => memo('holdingsActive', () => allHoldings.where((h) => !h.archived).toList());
  Holding? holding(String id) => allHoldings.where((h) => h.id == id).firstOrNull;
  List<Trade> get allTrades => memo('trades', () => store.all('trades').map(Trade.fromMap).toList()..sort((a, b) => b.date.compareTo(a.date)));

  Map<String, List<Trade>> get tradesByHolding => memo('tradesBy', () {
        final m = <String, List<Trade>>{};
        for (final t in allTrades) {
          (m[t.holdingId] ??= []).add(t);
        }
        return m;
      });

  Map<String, Quote> get quotes => memo('quotes', () => {for (final m in store.all('prices')) m['id'] as String: Quote.fromMap(m)});

  Position position(Holding h) => memo('pos:${h.id}', () => computePosition(h, tradesByHolding[h.id] ?? const [], quotes, fx));
  Portfolio get portfolio => memo('portfolio', () => Portfolio([for (final h in holdings) position(h)]));

  void saveHolding(Holding h) => store.put('holdings', h.id, h.toMap());

  void deleteHolding(Holding h) => store.batch(() {
        for (final t in tradesByHolding[h.id] ?? const <Trade>[]) {
          _removeTrade(t);
        }
        store.remove('holdings', h.id);
      });

  void saveQuote(Quote q) => store.put('prices', q.key, q.toMap(), notify: false);

  /// Salva un'operazione e, se c'è un conto, il movimento di liquidità collegato.
  void saveTrade(Trade t, {String? cashAccountId}) {
    final h = holding(t.holdingId);
    store.batch(() {
      final old = tx(t.txId);
      final accId = cashAccountId ?? old?.accountId;
      if (accId == null) {
        if (old != null) store.remove('tx', old.id);
        t.txId = null;
      } else {
        final (amount, catId) = switch (t.type) {
          TradeType.buy => (-(t.amount + t.fees), investCat),
          TradeType.sell => (t.amount - t.fees, investCat),
          TradeType.dividend || TradeType.coupon => (t.amount, 'rendite'),
          _ => (-(t.amount + t.fees), 'tasse'),
        };
        final label = '${TradeType.labels[t.type] ?? 'Operazione'} ${h?.name ?? ''}'.trim();
        final x = Tx(
          id: old?.id ?? newId(),
          date: t.date,
          amount: amount,
          accountId: accId,
          catId: catId,
          desc: label,
          src: 'trade',
          created: old?.created,
        );
        saveTx(x);
        t.txId = x.id;
      }
      store.put('trades', t.id, t.toMap());
    });
  }

  void _removeTrade(Trade t) {
    if (t.txId != null) store.remove('tx', t.txId!);
    store.remove('trades', t.id);
  }

  void deleteTrade(Trade t) => store.batch(() => _removeTrade(t));

  // ================================================================ beni e debiti

  List<Asset> get assets => memo('assets', () => store.all('assets').map(Asset.fromMap).toList()..sort((a, b) => b.value.compareTo(a.value)));
  List<Asset> get debts => assets.where((a) => a.isDebt).toList();
  List<Asset> get things => assets.where((a) => !a.isDebt).toList();
  void saveAsset(Asset a) => store.put('assets', a.id, a.toMap());
  void deleteAsset(Asset a) => store.remove('assets', a.id);

  // ================================================================ patrimonio

  NetWorth get netWorth => memo('nw', () {
        final liquid = accounts.fold(0, (s, a) => s + balanceEur(a));
        var ass = 0, debt = 0;
        for (final x in assets) {
          if (x.isDebt) {
            debt += x.value;
          } else {
            ass += x.value;
          }
        }
        return NetWorth(liquid, portfolio.value, ass, debt);
      });

  List<Snapshot> get snapshots => memo('snaps', () => store.all('snaps').map(Snapshot.fromMap).toList()..sort((a, b) => a.month.compareTo(b.month)));
  Map<String, Snapshot> get snapById => memo('snapById', () => {for (final s in snapshots) s.month: s});

  /// Fotografia del mese in corso (si aggiorna finché il mese non finisce).
  void updateSnapshot() {
    if (accounts.isEmpty && holdings.isEmpty && assets.isEmpty) return;
    final mk = thisMonthKey();
    final n = netWorth;
    final cur = snapById[mk];
    if (cur != null && cur.liquid == n.liquid && cur.invested == n.invested && cur.assets == n.assets && cur.debts == n.debts) return;
    store.put('snaps', mk, Snapshot(mk, liquid: n.liquid, invested: n.invested, assets: n.assets, debts: n.debts).toMap(), notify: false);
  }

  /// Variazione dall'ultima fotografia del mese prima.
  int? get netWorthChange {
    final prev = snapById[addMonthsKey(thisMonthKey(), -1)];
    return prev == null ? null : netWorth.total - prev.total;
  }

  // ================================================================ statistiche

  MonthStats statsFor(String mk) => memo('stats:$mk', () => monthStats(mk, txs, cats, accountById, fx));

  /// Ultimi [n] mesi completi (il mese in corso escluso), dal più recente.
  List<String> completeMonths(int n) => [for (var i = 1; i <= n; i++) addMonthsKey(thisMonthKey(), -i)];

  Averages get avg3 => memo('avg3', () => averages([for (final mk in completeMonths(3)) statsFor(mk)]));

  /// Abbastanza storico per fidarsi delle medie.
  bool get usingHistory => avg3.months >= 2 && avg3.income > 0;
  int get monthlyIncome => usingHistory ? avg3.income : (profile.incomeMonthly > 0 ? profile.incomeMonthly : avg3.income);
  int get monthlyExpenses => usingHistory ? avg3.expense : (profile.expensesMonthly > 0 ? profile.expensesMonthly : avg3.expense);

  /// Versato in investimenti al mese: storico o, senza storico, le scadenze verso investimenti.
  int get monthlyInvested => memo('monthlyInvested', () {
        if (avg3.months >= 2 && avg3.invested > 0) return avg3.invested;
        return scheds
            .where((s) => s.active && (s.catId == investCat || s.catId == 'risparmio'))
            .fold(0, (a, s) => a + monthlyEquivalent(s).abs());
      });

  List<BudgetLine> get budget => memo('budget', () => budgetLines(statsFor(thisMonthKey()), cats.values));

  SpendPlan get spendPlan => memo('spendPlan', () {
        final mk = thisMonthKey();
        final last = dayKey(DateTime(DateTime.now().year, DateTime.now().month + 1, 0));
        return computeSpendPlan(
          stats: statsFor(mk),
          monthOccs: occBetween('$mk-01', last),
          linkedTxIds: linkedTxIds,
          monthTxs: txs.where((t) => t.date.startsWith(mk)),
          cats: cats,
          accs: accountById,
          fx: fx,
          profileIncome: profile.incomeMonthly,
          savingsPct: profile.savingsTargetPct,
        );
      });

  // ================================================================ coach

  CoachInput get coachInput => memo('coachInput', () {
        final p = profile;
        final red = firstRed;
        final t = todayKey();
        final due30 = upcoming
            .where((o) => o.open && o.amount < 0 && o.date.compareTo(t) >= 0 && o.date.compareTo(addDaysKey(t, 30)) <= 0)
            .where((o) => !isTransferCat(o.sched.catId, cats))
            .fold(0, (a, o) => a - o.amount);
        final od = overdue;
        final cur = statsFor(thisMonthKey());
        final months = completeMonths(4).map(statsFor).toList();
        final last = months.first;
        final prev = months.skip(1).where((m) => m.income > 0).toList();
        final subs = scheds.where((s) => s.active && s.catId == 'abbonamenti' && s.amount < 0).toList();
        // categoria dei desideri che pesa di più negli ultimi 3 mesi
        final want = <String, int>{};
        for (final m in months.take(3)) {
          for (final e in m.spentByCat.entries) {
            if (cats[e.key]?.bucket == Bucket.want) want[e.key] = (want[e.key] ?? 0) + e.value;
          }
        }
        final topWant = want.entries.isEmpty ? null : want.entries.reduce((a, b) => b.value > a.value ? b : a);
        final nMonths = math.max(1, months.take(3).where((m) => m.count > 0).length);
        return CoachInput(
          profile: p,
          liquid: liquidCash,
          invested: portfolio.value,
          fiAssets: things.where((a) => a.inFi).fold(0, (s, a) => s + a.value),
          netWorth: netWorth.total,
          debts: debts,
          income: monthlyIncome,
          expenses: monthlyExpenses,
          investedMonthly: monthlyInvested,
          historyMonths: avg3.months,
          passiveYearly: portfolio.annualIncomeNet,
          redAccount: red?.$1.name,
          redDate: red?.$2.date,
          redAmount: red?.$2.balance ?? 0,
          overdueCount: od.length,
          overdueAmount: od.fold(0, (a, o) => a + o.amount),
          due30: due30,
          budget: budget,
          uncategorized: cur.uncategorized,
          inbox: inbox.length,
          stalePrices: portfolio.open.where((x) => x.stalePrice).length,
          subsMonthly: subs.fold(0, (a, s) => a - monthlyEquivalent(s)),
          subsCount: subs.length,
          lastSavingRate: last.income > 0 ? last.savingRate : null,
          prevSavingRate: prev.isEmpty ? null : prev.fold(0.0, (a, m) => a + m.savingRate) / prev.length,
          lastMonth: last.month,
          topWant: topWant == null ? null : (cats[topWant.key]?.name ?? topWant.key, (topWant.value / nMonths).round()),
        );
      });

  CoachResult get coach => memo('coach', () => runCoach(coachInput));

  // ================================================================ resoconti

  Report? get dueReport => memo('dueReport', () {
        final id = dueReportId(DateTime.now(), prefs.reportsSeen.toSet());
        if (id == null || txs.isEmpty) return null;
        final r = reportFor(id);
        return r.empty ? null : r;
      });

  Report reportFor(String id) {
    if (id.startsWith('m:')) {
      return monthReport(id.substring(2), txs, cats, accountById, fx, snaps: snapById, targetPct: profile.savingsTargetPct);
    }
    return weekReport(fromKey(id.substring(2)), txs, cats, accountById, fx);
  }

  void markReportSeen(String id) => prefs.reportsSeen = [...prefs.reportsSeen.where((x) => x != id), id];

  // ================================================================ notifiche banca

  List<InboxItem> get inbox => memo('inbox', () => store.all('inbox').map(InboxItem.fromMap).toList()..sort((a, b) => b.at.compareTo(a.at)));

  void dropInbox(InboxItem i) => store.remove('inbox', i.id);

  Tx? confirmInbox(InboxItem i, {required String accountId, String? catId, int? amount, String? desc, String? date}) {
    Tx? t;
    store.batch(() {
      t = addTx(
        amount: amount ?? i.amount,
        accountId: accountId,
        catId: catId ?? i.catHint,
        desc: desc ?? (i.merchant.isNotEmpty ? i.merchant : 'Movimento ${bankLabels[i.bank] ?? ''}'.trim()),
        date: date ?? i.date,
        src: 'notif',
      );
      store.remove('inbox', i.id);
    });
    matchScheduled();
    return t;
  }

  /// Una notifica della banca: diventa un movimento, va tra i da confermare o
  /// viene scartata. Ritorna cosa è successo (per il registro).
  String ingestNotif(BankNotif n) {
    final p = parseBankNotif(n);
    if (p.ignored) return 'scartata: ${p.reason}';
    final acc = accountForBank(p.bank, invest: p.kind == NotifKind.invest);
    if (p.autoAdd && acc != null) {
      final dup = txsOf(acc.id).where((t) {
        if (t.amount != p.amount) return false;
        if (daysBetween(fromKey(t.date), fromKey(p.date)).abs() > 1) return false;
        // scritto a mano prima che arrivasse la notifica
        if (t.src == 'manual') return true;
        // notifica dell'app e SMS dello stesso pagamento arrivano a pochi minuti; due caffè uguali in un giorno no
        return t.src == 'notif' && (t.created - n.at).abs() <= 10 * 60000;
      }).firstOrNull;
      if (dup != null) return 'già registrato (${dup.desc})';
      // creato all'ora della notifica: conta giusto rispetto al saldo corretto dopo
      addTx(
          amount: p.amount, accountId: acc.id, catId: p.catHint ?? suggestCat(p.desc, p.amount), desc: p.desc, date: p.date, src: 'notif', created: n.at);
      matchScheduled();
      return 'movimento creato su ${acc.name}';
    }
    store.put(
      'inbox',
      n.id,
      InboxItem(
        id: n.id,
        at: n.at,
        bank: p.bank,
        kind: p.kind.name,
        amount: p.amount,
        currency: p.currency,
        merchant: p.merchant,
        date: p.date,
        conf: p.confidence,
        catHint: p.catHint,
        text: '${n.title}\n${n.body}'.trim(),
      ).toMap(),
    );
    return acc == null ? 'da confermare (nessun conto ${p.bankLabel})' : 'da confermare';
  }

  // ================================================================ consulenze AI

  List<Consult> get consults => memo('consults', () => store.all('consult').map(Consult.fromMap).toList()..sort((a, b) => b.at.compareTo(a.at)));
  Consult? get lastConsult => consults.firstOrNull;
  void saveConsult(Consult c) => store.put('consult', c.id, c.toMap());
  void deleteConsult(Consult c) => store.remove('consult', c.id);
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppX on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
}
