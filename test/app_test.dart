// Apre le schermate principali con dati inventati e controlla che non ci siano errori.
import 'dart:io';

import 'package:dollarz/app.dart';
import 'package:dollarz/core/crypto_box.dart';
import 'package:dollarz/core/fmt.dart';
import 'package:dollarz/core/ids.dart';
import 'package:dollarz/data/app_state.dart';
import 'package:dollarz/data/local_prefs.dart';
import 'package:dollarz/data/models.dart';
import 'package:dollarz/data/store.dart';
import 'package:dollarz/logic/bank_notif.dart';
import 'package:dollarz/services/bank_bridge.dart';
import 'package:dollarz/services/lock.dart';
import 'package:dollarz/services/notifications.dart';
import 'package:dollarz/services/prices.dart';
import 'package:dollarz/services/services.dart';
import 'package:dollarz/services/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void seed(AppState app) {
  final p = Profile(name: 'Prova', incomeMonthly: 220000, expensesMonthly: 150000, targetPassive: 50000, targetWealth: 10000000, onboarded: true);
  app.saveProfile(p);
  final a = Account(id: 'acc1', name: 'Conto prova', institution: 'revolut', anchorAmount: 250000, anchorDate: addDaysKey(todayKey(), -60));
  final b = Account(id: 'acc2', name: 'Risparmi', type: AccountType.risparmio, anchorAmount: 500000, anchorDate: todayKey(), order: 1);
  app.saveAccount(a);
  app.saveAccount(b);
  for (var m = 0; m < 3; m++) {
    final d = addMonths(today(), -m);
    app.addTx(amount: 220000, accountId: 'acc1', catId: 'stipendio', desc: 'Stipendio', date: dayKey(DateTime(d.year, d.month, 1)));
    app.addTx(amount: -80000, accountId: 'acc1', catId: 'casa', desc: 'Affitto', date: dayKey(DateTime(d.year, d.month, 2)));
    app.addTx(amount: -4520, accountId: 'acc1', desc: 'Negozio Alfa', date: dayKey(DateTime(d.year, d.month, 5)));
    app.addTx(amount: -1299, accountId: 'acc1', desc: 'Servizio Streaming', date: dayKey(DateTime(d.year, d.month, 7)));
  }
  app.saveSched(Scheduled(id: newId(), name: 'Affitto', amount: -80000, accountId: 'acc1', catId: 'casa', start: dayKey(DateTime(today().year, today().month, 2))));
  final h = Holding(id: 'h1', name: 'ETF di prova', symbol: 'TEST.DE', manualPrice: 105, manualAt: DateTime.now().millisecondsSinceEpoch);
  app.saveHolding(h);
  app.saveTrade(Trade(id: 'tr1', holdingId: 'h1', date: addDaysKey(todayKey(), -100), type: TradeType.buy, qty: 20, price: 100, amount: 200000));
  app.saveAsset(Asset(id: 'd1', name: 'Prestito', kind: AssetKind.debt, value: 300000, rate: 8, monthly: 15000));
}

void main() {
  Store.autoSave = false;
  LocalPrefs.autoSave = false;
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('dollarz_ui'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<AppState> makeApp(WidgetTester tester, {bool data = false}) async {
    late AppState app;
    await tester.runAsync(() async {
      final key = CryptoBox.randomKey();
      final store = Store();
      await store.init(dir: dir, key: key);
      final prefs = LocalPrefs();
      await prefs.init(dir, key);
      app = AppState(store, prefs);
      Services.app = app;
      Services.sync = SyncService(app);
      Services.notif = NotificationService(app);
      Services.lock = LockService(prefs);
      Services.prices = PriceService(app);
      Services.bank = BankBridge(app);
      if (data) seed(app);
    });
    return app;
  }

  Future<void> close(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    await tester.runAsync(() async {
      await app.store.flush();
      await app.prefs.flush();
    });
  }

  test('SMS della banca: movimento creato, doppione scartato, due spese uguali tenute', () async {
    final key = CryptoBox.randomKey();
    final store = Store();
    await store.init(dir: dir, key: key);
    final prefs = LocalPrefs();
    await prefs.init(dir, key);
    final app = AppState(store, prefs);
    app.saveAccount(Account(id: 'f1', name: 'Conto prova', institution: 'fineco', anchorAmount: 100000, anchorDate: addDaysKey(todayKey(), -5)));
    // formato degli SMS di Fineco, con valori inventati
    const sms = 'Fineco - SMS Gratuito: Autorizzato utilizzo Carta ***1234 Importo: 3,5 EUR, per: BAR ESEMPIO. Info: 0200000000';
    BankNotif n(String pkg, int at) => BankNotif(pkg: pkg, title: 'Fineco', text: sms, at: at);
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(app.ingestNotif(n('com.google.android.apps.messaging', now - 3600000)), startsWith('movimento creato'));
    // lo stesso pagamento anche dalla notifica dell'app della banca, un minuto dopo
    expect(app.ingestNotif(n('it.fineco.app', now - 3540000)), startsWith('già registrato'));
    // un secondo pagamento uguale, un'ora dopo
    expect(app.ingestNotif(n('com.google.android.apps.messaging', now)), startsWith('movimento creato'));
    final txs = app.txsOf('f1').toList();
    expect(txs.length, 2);
    expect(txs.every((t) => t.amount == -350 && t.desc == 'BAR ESEMPIO' && t.src == 'notif'), true);
    expect(app.balance(app.accounts.single), 100000 - 700);
    await store.flush();
    await prefs.flush();
  });

  testWidgets('primo avvio', (tester) async {
    final app = await makeApp(tester);
    await tester.pumpWidget(DollarzApp(app: app));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Benvenuto in Dollarz'), findsOneWidget);
    await tester.tap(find.text('Iniziamo'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Quanto entra, quanto esce'), findsOneWidget);
    await close(tester, app);
  });

  testWidgets('schede principali', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final app = await makeApp(tester, data: true);
    await tester.pumpWidget(DollarzApp(app: app));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('PATRIMONIO NETTO'), findsOneWidget);
    expect(find.text('PROSSIMA MOSSA'), findsOneWidget);

    for (final tab in ['Movimenti', 'Scadenze', 'Investimenti', 'Futuro', 'Patrimonio']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: tab);
    }

    // nuovo movimento
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Nuovo movimento'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '12,50');
    await tester.ensureVisible(find.text('Spesa').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Spesa').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.txs.any((t) => t.amount == -1250 && t.catId == 'spesa'), true);
    await tester.pump(const Duration(seconds: 1));

    // impostazioni
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Impostazioni'), findsWidgets);
    await close(tester, app);
  });
}
