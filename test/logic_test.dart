// Test della logica pura. Tutti i dati sono inventati.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dollarz/core/fmt.dart';
import 'package:dollarz/core/money.dart';
import 'package:dollarz/data/categories.dart';
import 'package:dollarz/data/models.dart';
import 'package:dollarz/logic/balances.dart';
import 'package:dollarz/logic/bank_notif.dart';
import 'package:dollarz/logic/budget.dart';
import 'package:dollarz/logic/categorize.dart';
import 'package:dollarz/logic/coach.dart';
import 'package:dollarz/logic/forecast.dart';
import 'package:dollarz/logic/import_parse.dart';
import 'package:dollarz/logic/invest.dart';
import 'package:dollarz/logic/projection.dart';
import 'package:dollarz/logic/recurring.dart';
import 'package:dollarz/logic/report.dart';
import 'package:dollarz/logic/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

final cats = {for (final c in defaultCategories) c.id: c};
var _n = 0;
String nid() => 'id${_n++}';

Tx tx(String date, int amount, {String acc = 'a', String? cat, String desc = '', int? created, String? tr, String? ik}) =>
    Tx(id: nid(), date: date, amount: amount, accountId: acc, catId: cat, desc: desc, created: created ?? 1, transferId: tr, importKey: ik);

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('formati', () {
    test('numeri e importi', () {
      expect(fInt(1234567), '1.234.567');
      expect(fMoney(123456), '1.235 €');
      expect(fMoney(12345), '123,45 €');
      expect(fMoney(-500), '−5,00 €');
      expect(fCompact(150000), '1,5k');
      expect(fCompact(1200000), '12k');
      expect(parseNum('1.234,56'), 1234.56);
      expect(parseNum('1,234.56'), 1234.56);
      expect(parseNum('-12,5'), -12.5);
      expect(parseNum('(10,00)'), -10);
      expect(parseNum('12,50-'), -12.5);
      expect(parseMoney('€ 9,99'), 999);
    });

    test('date', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonthsKey('2026-12', 1), '2027-01');
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(fYearsMonths(14), '1 anno e 2 mesi');
    });
  });

  group('saldi', () {
    final a = Account(id: 'a', name: 'Conto', anchorAmount: 100000, anchorDate: '2026-10-10', anchorAt: 1000);
    test('ancora e movimenti', () {
      final txs = [
        tx('2026-10-09', -5000), // prima dell'ancora: già compreso
        tx('2026-10-10', -2000, created: 500), // stesso giorno, prima: compreso
        tx('2026-10-10', -3000, created: 2000), // stesso giorno, dopo: si somma
        tx('2026-10-12', 10000),
      ];
      expect(balanceAt(a, txs, '2026-10-12'), 100000 - 3000 + 10000);
      expect(balanceAt(a, txs, '2026-10-10'), 97000);
      // indietro nel tempo: si tolgono i movimenti compresi nell'ancora
      expect(balanceAt(a, txs, '2026-10-09'), 100000 + 2000);
      expect(balanceAt(a, txs, '2026-10-08'), 100000 + 2000 + 5000);
    });
    test('cambio', () {
      expect(toEur(10800, 'USD', {'USD': 1.08}), 10000);
      expect(toEur(500, 'EUR', {}), 500);
    });
  });

  group('scadenze', () {
    test('mensile a fine mese', () {
      final s = Scheduled(id: 's', name: 'Affitto', amount: -80000, start: '2026-01-31');
      expect(occurrences(s, '2026-02-01', '2026-04-30'), ['2026-02-28', '2026-03-31', '2026-04-30']);
    });
    test('annuale, settimanale e una tantum', () {
      final y = Scheduled(id: 'y', name: 'Bollo', amount: -20000, start: '2025-05-10', freq: Freq.yearly);
      expect(occurrences(y, '2026-01-01', '2027-12-31'), ['2026-05-10', '2027-05-10']);
      final w = Scheduled(id: 'w', name: 'Palestra', amount: -1000, start: '2026-10-05', freq: Freq.weekly, every: 2);
      expect(occurrences(w, '2026-10-01', '2026-11-05'), ['2026-10-05', '2026-10-19', '2026-11-02']);
      final o = Scheduled(id: 'o', name: 'Tassa', amount: -5000, start: '2026-11-16', freq: Freq.once);
      expect(occurrences(o, '2026-01-01', '2026-12-31'), ['2026-11-16']);
    });
    test('abbinamento al movimento', () {
      final s = Scheduled(id: 's', name: 'Netflix', amount: -1399, start: '2026-01-05');
      final o = OccView(s, '2026-10-05', null);
      expect(matchScore(o, tx('2026-10-06', -1399, desc: 'NETFLIX.COM')), greaterThan(0));
      expect(matchScore(o, tx('2026-10-06', -1399, desc: 'Esselunga')), 0);
      expect(matchScore(o, tx('2026-10-20', -1399, desc: 'Netflix')), 0);
      final v = Scheduled(id: 'v', name: 'Luce', amount: -6000, start: '2026-01-15', variable: true, catId: 'bollette');
      expect(matchScore(OccView(v, '2026-10-15', null), tx('2026-10-14', -8200, cat: 'bollette')), greaterThan(0));
    });
    test('previsione: conto in rosso', () {
      final a = Account(id: 'a', name: 'Conto', anchorDate: '2026-01-01');
      final s = Scheduled(id: 's', name: 'Affitto', amount: -80000, start: addDaysKey(todayKey(), 5), freq: Freq.once);
      final open = occurrencesBetween([s], {}, todayKey(), addDaysKey(todayKey(), 90));
      final f = forecastAccount(a, 50000, open);
      expect(f.firstNegative?.balance, -30000);
      expect(f.min, -30000);
    });
    test('equivalente mensile', () {
      expect(monthlyEquivalent(Scheduled(id: 'x', name: 'x', amount: -12000, start: '2026-01-01', freq: Freq.yearly)), -1000);
    });
  });

  group('budget', () {
    final accs = {'a': Account(id: 'a', name: 'Conto', anchorDate: '2026-01-01')};
    test('statistiche del mese', () {
      final txs = [
        tx('2026-09-01', 200000, cat: 'stipendio'),
        tx('2026-09-03', -5000, cat: 'spesa'),
        tx('2026-09-04', -2000, cat: 'ristoranti'),
        tx('2026-09-05', -30000, cat: 'investimento'),
        tx('2026-09-06', -10000, tr: 't1'),
        tx('2026-09-07', 1000, cat: 'spesa'), // rimborso parziale
        tx('2026-09-08', -700),
      ];
      final s = monthStats('2026-09', txs, cats, accs, {});
      expect(s.income, 200000);
      expect(s.expense, 5000 + 2000 - 1000 + 700);
      expect(s.invested, 30000);
      expect(s.uncategorized, 1);
      expect(s.byBucket[Bucket.need], 4000);
    });
    test('budget a rischio', () {
      final c = defaultCategories.firstWhere((c) => c.id == 'ristoranti').copy()..budget = 20000;
      final s = MonthStats('2026-10')..spentByCat['ristoranti'] = 15000;
      final lines = budgetLines(s, [c], now: DateTime(2026, 10, 15));
      expect(lines.single.atRisk, true);
      expect(lines.single.over, false);
    });
  });

  group('categorie', () {
    test('regole di base e imparate', () {
      expect(suggestCategory('PAGAMENTO POS ESSELUNGA SPA', [], cats: cats), 'spesa');
      final r = learnRule('PAG POS BAR CENTRALE', 'ristoranti', [], nid);
      expect(r, isNotNull);
      expect(suggestCategory('Bar Centrale Milano', [r!], cats: cats), 'ristoranti');
      // una regola di spesa non si applica a un'entrata
      expect(suggestCategory('Bar Centrale', [r], amount: 500, cats: cats), isNull);
    });
  });

  group('ricorrenti', () {
    test('abbonamento mensile', () {
      final now = today();
      final txs = [for (var i = 0; i < 5; i++) tx(dayKey(addMonths(now, -i)), -999, desc: 'Spotify AB')];
      final found = findRecurring(txs);
      expect(found.length, 1);
      expect(found.single.freq, Freq.monthly);
      expect(found.single.amount, -999);
    });
  });

  group('investimenti', () {
    test('costo medio, vendita, dividendo', () {
      final h = Holding(id: 'h', name: 'ETF', symbol: 'TEST.DE');
      final trades = [
        Trade(id: '1', holdingId: 'h', date: '2026-01-10', type: TradeType.buy, qty: 10, price: 100, amount: 100000, fees: 200),
        Trade(id: '2', holdingId: 'h', date: '2026-02-10', type: TradeType.buy, qty: 10, price: 120, amount: 120000),
        Trade(id: '3', holdingId: 'h', date: '2026-03-10', type: TradeType.sell, qty: 5, price: 130, amount: 65000),
        Trade(id: '4', holdingId: 'h', date: '2026-04-10', type: TradeType.dividend, amount: 1500),
      ];
      final quotes = {'y:TEST.DE': Quote('y:TEST.DE', 140, 'EUR', DateTime.now().millisecondsSinceEpoch)};
      final p = computePosition(h, trades, quotes, {}, now: DateTime(2026, 10, 1));
      expect(p.qty, 15);
      // costo 220200 per 20 quote, ne escono 5 = 55050
      expect(p.cost, 220200 - 55050);
      expect(p.realized, 65000 - 55050);
      expect(p.value, 15 * 14000);
      expect(p.income, 1500);
      expect(p.taxIfSold, ((15 * 14000 - (220200 - 55050)) * 0.26).round());
    });
    test('conto deposito', () {
      final h = Holding(id: 'd', name: 'Deposito', kind: HoldingKind.deposit, principal: 1000000, rate: 3, start: '2026-01-01');
      final p = computePosition(h, [], {}, {}, now: DateTime(2027, 1, 1));
      expect(p.value, 1000000 + (1000000 * 0.03 * 0.74).round());
    });
  });

  group('proiezioni', () {
    test('numero FI e tempi', () {
      expect(fiNumber(2400000, 4), 60000000);
      expect(capitalForIncome(100000, 4), 30000000);
      expect(monthsToTarget(0, 100000, 0, 1200000), 12);
      expect(monthsToTarget(1000, 0, 0, 500), 0);
      expect(monthsToTarget(0, 0, 4, 100000), isNull);
      final need = monthlyNeeded(0, 1200000, 0, 12);
      expect(need, 100000);
      expect(valueAfter(100000, 0, 0, 24), 100000);
    });
  });

  group('coach', () {
    test('senza dati chiede il profilo', () {
      final r = runCoach(CoachInput(profile: Profile()));
      expect(r.move.route, CoachRoute.profilo);
    });
    test('conto in rosso viene prima di tutto', () {
      final r = runCoach(CoachInput(
        profile: Profile(),
        income: 200000,
        expenses: 150000,
        liquid: 1000000,
        redAccount: 'Fineco',
        redDate: addDaysKey(todayKey(), 4),
        redAmount: -20000,
      ));
      expect(r.move.stepId, 'scadenze');
      expect(r.current?.id, 'scadenze');
    });
    test('cuscinetto, debiti, fondo, investi in ordine', () {
      CoachResult run(int liquid, {List<Asset> debts = const [], int investedMonthly = 0}) => runCoach(CoachInput(
            profile: Profile(emergencyMonths: 6, savingsTargetPct: 20),
            income: 250000,
            expenses: 150000,
            liquid: liquid,
            debts: debts,
            investedMonthly: investedMonthly,
          ));
      expect(run(50000).move.stepId, 'cuscinetto');
      final debt = Asset(id: 'd', name: 'Prestito auto', kind: AssetKind.debt, value: 500000, rate: 9, monthly: 20000);
      expect(run(200000, debts: [debt]).move.stepId, 'debiti');
      expect(run(200000).move.stepId, 'fondo');
      expect(run(900000).move.stepId, 'investi');
      final ok = run(900000, investedMonthly: 50000);
      expect(ok.move.stepId, 'obiettivi');
      expect(ok.goals.first.id, 'fi');
      expect(ok.goals.first.target, fiNumber(150000 * 12, 4));
    });
    test('fondamenta disattivate', () {
      final r = runCoach(CoachInput(profile: Profile(foundations: false), income: 250000, expenses: 150000, liquid: 0));
      expect(r.steps.firstWhere((s) => s.id == 'fondo').state, PathState.off);
      expect(r.move.stepId, isNot('cuscinetto'));
    });
    test('spendere più di quanto entra', () {
      final r = runCoach(CoachInput(profile: Profile(), income: 150000, expenses: 180000, liquid: 500000));
      expect(r.move.stepId, 'risparmio');
    });
    test('payoff debito', () {
      expect(debtPayoffMonths(120000, 0, 10000), 12);
      expect(debtPayoffMonths(100000, 12, 0), isNull);
    });
  });

  group('import estratti', () {
    test('CSV stile Revolut', () {
      const csv = 'Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance\n'
          'CARD_PAYMENT,Current,2026-09-01 10:00:00,2026-09-02 08:00:00,Negozio Uno,-12.50,0.00,EUR,COMPLETED,987.50\n'
          'TOPUP,Current,2026-09-03 09:00:00,2026-09-03 09:00:01,Ricarica,100.00,0.00,EUR,COMPLETED,1087.50\n'
          'CARD_PAYMENT,Current,2026-09-04 12:00:00,,Negozio Due,-5.00,0.00,EUR,PENDING,\n'
          'TRANSFER,Current,2026-09-05 12:00:00,2026-09-05 12:00:00,Mario,-20.00,1.00,EUR,COMPLETED,1066.50\n'
          'EXCHANGE,Current,2026-09-06 12:00:00,2026-09-06 12:00:00,Cambio,10.00,0.00,USD,COMPLETED,10.00\n'
          'CARD_PAYMENT,Current,2026-09-07 12:00:00,2026-09-07 12:00:00,Negozio Tre,-1.00,0.00,EUR,REVERTED,\n';
      final f = analyzeBytes(bytesOf(csv), name: 'account-statement.csv');
      expect(f.format, 'revolut');
      expect(f.complete, true);
      final all = buildRows(f);
      expect(all.groups.length, 2);
      final g = mainGroup(all.groups);
      expect(g, 'Current · EUR');
      final b = buildRows(f, group: g);
      expect(b.rows.length, 3);
      expect(b.pending, 1);
      expect(b.cancelled, 1);
      expect(b.rows[0].amount, -1250);
      expect(b.rows[1].catHint, 'giroconto');
      expect(b.rows[2].amount, -2100); // commissione compresa
      expect(anchorFromRows(b.rows), ('2026-09-05', 106650));
      // stesso file due volte: stesse chiavi
      final again = buildRows(analyzeBytes(bytesOf(csv)), group: g);
      expect(again.rows.map((r) => r.key).toList(), b.rows.map((r) => r.key).toList());
    });

    test('CSV italiano con punto e virgola ed entrate/uscite', () {
      const csv = 'Estratto conto\n'
          'Periodo;01/09/2026 - 30/09/2026\n'
          '\n'
          'Data operazione;Data valuta;Entrate;Uscite;Descrizione;Descrizione completa\n'
          '01/09/2026;01/09/2026;;-45,30;Pagamento carta;NEGOZIO ALFA MILANO\n'
          '03/09/2026;03/09/2026;1.500,00;;Bonifico;STIPENDIO SETTEMBRE\n'
          '15/09/2026;15/09/2026;;12,00;Addebito SDD;GESTORE BETA\n'
          'Saldo finale;;;;;\n';
      final f = analyzeBytes(bytesOf(csv));
      expect(f.headerRow, 2);
      expect(f.map[Col.date], 0);
      expect(f.map[Col.valueDate], 1);
      final b = buildRows(f);
      expect(b.rows.map((r) => r.amount).toList(), [-4530, 150000, -1200]);
      expect(b.rows[0].desc, 'Pagamento carta - NEGOZIO ALFA MILANO');
      expect(b.rows[0].date, '2026-09-01');
      expect(b.invalid, 1); // la riga "Saldo finale"
    });

    test('tabella HTML salvata come .xls', () {
      const html = '<html><body><table>'
          '<tr><td>Data</td><td>Descrizione</td><td>Importo</td></tr>'
          '<tr><td>02/10/2026</td><td>Bar &amp; Caff&egrave;</td><td>-3,20</td></tr>'
          '<tr><td>05/10/2026</td><td>Rimborso</td><td>10,00</td></tr>'
          '</table></body></html>';
      final b = buildRows(analyzeBytes(bytesOf(html), name: 'movimenti.xls'));
      expect(b.rows.length, 2);
      expect(b.rows[0].amount, -320);
      expect(b.rows[1].amount, 1000);
    });

    test('date in vari formati', () {
      expect(parseDateCell('2026-09-01 10:00:00'), '2026-09-01');
      expect(parseDateCell('1/9/26'), '2026-09-01');
      expect(parseDateCell('09/01/2026', dayFirst: false), '2026-09-01');
      expect(parseDateCell('15 ott 2026'), '2026-10-15');
      expect(parseDateCell('Oct 15, 2026'), '2026-10-15');
      expect(parseDateCell(46280), '2026-09-15');
      expect(parseDateCell(DateTime(2026, 9, 1)), '2026-09-01');
      expect(parseDateCell('31/02/2026'), isNull);
      expect(detectDayFirst(['01/02/2026', '13/02/2026']), true);
      expect(detectDayFirst(['02/13/2026']), false);
    });

    test('doppioni e riconciliazione', () {
      const csv = 'Data,Descrizione,Importo\n2026-09-01,Negozio,-10.00\n2026-09-02,Altro,-5.00\n2026-09-02,Altro,-5.00\n';
      final rows = buildRows(analyzeBytes(bytesOf(csv))).rows;
      expect(rows[1].key == rows[2].key, false);
      final existing = [
        tx('2026-09-01', -1000, desc: 'Negozio (notifica)'),
        tx('2026-09-02', -500, ik: rows[1].key),
      ];
      final plan = planImport(rows, existing);
      expect(plan[0].dup, DupKind.likely);
      expect(plan[1].dup, DupKind.imported);
      expect(plan[2].dup, DupKind.none);
    });

    test('separatore e virgolette', () {
      final t = parseCsv('a;"b;c";"d ""e"""\r\n1;2;3\r\n');
      expect(t[0], ['a', 'b;c', 'd "e"']);
      expect(t[1], ['1', '2', '3']);
      expect(detectSeparator('a,b,c\n1,2,3\n'), ',');
      expect(detectSeparator('a;b;c\n1,5;2,5;3\n'), ';');
    });
  });

  group('notifiche banca', () {
    final at = DateTime(2026, 10, 15, 12, 30).millisecondsSinceEpoch;
    ParsedNotif p(String pkg, String title, String text) => parseBankNotif(BankNotif(pkg: pkg, title: title, text: text, at: at));

    test('pagamento con esercente nel titolo', () {
      final r = p('com.revolut.revolut', 'Negozio Uno 🛒', 'Hai pagato 12,34 €');
      expect(r.kind, NotifKind.expense);
      expect(r.amount, -1234);
      expect(r.merchant, 'Negozio Uno');
      expect(r.autoAdd, true);
      expect(r.date, '2026-10-15');
    });
    test('pagamento con "presso" e data', () {
      final r = p('it.fineco.mobile', 'Fineco', 'Pagamento con carta di 1.234,56 EUR presso NEGOZIO ALFA MILANO il 14/10/2026 alle 18:30');
      expect(r.amount, -123456);
      expect(r.merchant, 'NEGOZIO ALFA MILANO');
      expect(r.date, '2026-10-14');
      expect(r.bank, 'fineco');
    });
    test('entrata e "ti ha inviato"', () {
      final r = p('com.revolut.revolut', 'Denaro ricevuto', 'Mario ti ha inviato €50.00');
      expect(r.kind, NotifKind.income);
      expect(r.amount, 5000);
      final r2 = p('com.revolut.revolut', 'Revolut', 'Hai ricevuto 25 € da Anna Bianchi');
      expect(r2.amount, 2500);
      expect(r2.merchant, 'Anna Bianchi');
    });
    test('saldo ignorato, importo vero preso', () {
      final r = p('com.revolut.revolut', 'Revolut', 'Hai speso 8,00 € da Bar Due. Saldo disponibile: 1.000,00 €');
      expect(r.amount, -800);
    });
    test('rimborso e ricarica', () {
      expect(p('com.revolut.revolut', 'Negozio', 'Rimborso del pagamento di 9,99 € ricevuto').amount, 999);
      final t = p('com.revolut.revolut', 'Revolut', 'Hai aggiunto 100,00 € tramite carta');
      expect(t.kind, NotifKind.transfer);
      expect(t.catHint, 'giroconto');
    });
    test('investimenti', () {
      final r = p('de.traderepublic.app', 'Trade Republic', 'Ordine eseguito: hai acquistato 2,5 quote di Fondo Test a 100,00 €');
      expect(r.kind, NotifKind.invest);
      expect(r.amount, -25000);
      expect(r.catHint, 'investimento');
      final pac = p('de.traderepublic.app', 'Piano di accumulo', 'Il tuo piano di accumulo da 50,00 € è stato eseguito');
      expect(pac.amount, -5000);
    });
    test('da scartare', () {
      expect(p('com.revolut.revolut', 'Revolut', 'Il tuo codice è 123456').ignored, true);
      expect(p('com.revolut.revolut', 'Pagamento rifiutato', 'Pagamento di 20,00 € rifiutato').ignored, true);
      expect(p('com.revolut.revolut', 'Offerta', 'Invita un amico e ricevi 20 €').ignored, true);
      expect(p('com.revolut.revolut', 'Revolut', 'Nuovo accesso dal tuo account').ignored, true);
    });
    test('id stabile', () {
      final a = BankNotif(pkg: 'x', title: 't', text: 'b', at: at);
      final b = BankNotif(pkg: 'x', title: 't', text: 'b', at: at + 1000);
      expect(a.id, b.id);
    });
  });

  group('resoconti', () {
    final accs = {'a': Account(id: 'a', name: 'Conto', anchorDate: '2026-01-01')};
    test('mese', () {
      final txs = [
        for (final m in ['2026-06', '2026-07', '2026-08']) ...[tx('$m-01', 200000, cat: 'stipendio'), tx('$m-10', -100000, cat: 'casa')],
        tx('2026-09-01', 200000, cat: 'stipendio'),
        tx('2026-09-10', -100000, cat: 'casa'),
        tx('2026-09-12', -40000, cat: 'ristoranti'),
      ];
      final r = monthReport('2026-09', txs, cats, accs, {});
      expect(r.stats.saving, 60000);
      expect(r.lines.first, contains('30%'));
      expect(r.lines[1], contains('Ristoranti'));
    });
    test('settimana e resoconto dovuto', () {
      final monday = DateTime(2026, 10, 12);
      final r = weekReport(monday, [tx('2026-10-13', -1500, cat: 'spesa')], cats, accs, {});
      expect(r.stats.expense, 1500);
      expect(r.title, 'Settimana 12–18 ottobre');
      expect(dueReportId(DateTime(2026, 10, 3), {}), 'm:2026-09');
      expect(dueReportId(DateTime(2026, 10, 20), {}), 'w:2026-10-12');
      expect(dueReportId(DateTime(2026, 10, 20), {'w:2026-10-12'}), isNull);
    });
  });
}
