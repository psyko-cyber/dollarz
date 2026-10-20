// Archivio cifrato, sincronizzazione dei record e backup. Dati inventati.
import 'dart:io';

import 'package:dollarz/core/crypto_box.dart';
import 'package:dollarz/data/local_prefs.dart';
import 'package:dollarz/data/store.dart';
import 'package:dollarz/services/backup.dart';
import 'package:dollarz/services/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('dollarz_test'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('cifratura: andata e ritorno, chiave sbagliata', () async {
    final k = CryptoBox.randomKey();
    final sealed = await CryptoBox.sealString(k, 'ciao €');
    expect(CryptoBox.isSealed(sealed), true);
    expect(await CryptoBox.openString(k, sealed), 'ciao €');
    expect(() => CryptoBox.openString(CryptoBox.randomKey(), sealed), throwsFormatException);
    // contenuto grande (passa da un isolate)
    final big = 'x' * 200000;
    expect(await CryptoBox.openString(k, await CryptoBox.sealString(k, big)), big);
  });

  test('i file sul disco non sono in chiaro e si riaprono con la stessa chiave', () async {
    final k = CryptoBox.randomKey();
    final s = Store();
    await s.init(dir: dir, key: k);
    s.put('tx', 't1', {'desc': 'NEGOZIO SEGRETO', 'amt': -1234});
    await s.flush();
    final raw = File('${dir.path}/data/tx.dz').readAsBytesSync();
    expect(String.fromCharCodes(raw).contains('SEGRETO'), false);

    final s2 = Store();
    await s2.init(dir: dir, key: k);
    expect(s2.get('tx', 't1')?['desc'], 'NEGOZIO SEGRETO');

    final s3 = Store();
    await s3.init(dir: dir, key: CryptoBox.randomKey());
    expect(s3.unreadable, contains('tx'));
    expect(s3.get('tx', 't1'), isNull);
    // con dati illeggibili non si scrive nulla: il file originale resta intatto
    s3.put('tx', 't2', {'amt': 1});
    await s3.flush();
    final s4 = Store();
    await s4.init(dir: dir, key: k);
    expect(s4.get('tx', 't1')?['desc'], 'NEGOZIO SEGRETO');
    await s2.flush();
    await s4.flush();
  });

  test('sincronizzazione: modifiche dopo una sequenza e vince l\'ultima', () async {
    final a = Store(), b = Store();
    final da = await Directory('${dir.path}/a').create(), db = await Directory('${dir.path}/b').create();
    await a.init(dir: da, key: CryptoBox.randomKey());
    await b.init(dir: db, key: CryptoBox.randomKey());
    a.put('accounts', 'x', {'name': 'Conto A'});
    final seq = a.seq;
    a.put('tx', 'y', {'amt': 100});
    expect(a.changesSince(seq).length, 1);
    expect(b.applyRemote(a.changesSince(0)), 2);
    expect(b.get('accounts', 'x')?['name'], 'Conto A');
    // una modifica più vecchia non vince
    final old = a.changesSince(0).first..['u'] = 1;
    old['d'] = {'id': 'x', 'name': 'Vecchio'};
    expect(b.applyRemote([old]), 0);
    // cancellazione
    a.remove('tx', 'y');
    b.applyRemote(a.changesSince(seq + 1));
    expect(b.get('tx', 'y'), isNull);
    await a.flush();
    await b.flush();
  });

  test('preferenze locali cifrate', () async {
    final k = CryptoBox.randomKey();
    final p = LocalPrefs();
    await p.init(dir, k);
    p.geminiKey = 'chiave-finta';
    await p.flush();
    final p2 = LocalPrefs();
    await p2.init(dir, k);
    expect(p2.geminiKey, 'chiave-finta');
  });

  test('backup con password', () async {
    final s = Store();
    await s.init(dir: dir, key: CryptoBox.randomKey());
    s.put('tx', 't1', {'amt': -500});
    final salt = CryptoBox.randomBytes(16);
    final key = await CryptoBox.keyFromPassword('password-di-prova', salt);
    // build() vuole un AppState: qui uso direttamente il formato
    final sealed = await CryptoBox.sealString(key, '{"app":"dollarz","format":1,"changes":[]}');
    final bytes = [...'DZB1'.codeUnits, ...salt, ...sealed];
    expect(Backup.looksLike(bytes), true);
    expect((await Backup.open(bytes, 'password-di-prova'))['app'], 'dollarz');
    expect(() => Backup.open(bytes, 'sbagliata'), throwsFormatException);
    await s.flush();
  });

  test('QR di abbinamento', () {
    expect(SyncService.parsePairing('tigert://pair?d=xx'), isNull);
    final m = SyncService.manualPairing(' 192.168.1.5 ', 'abcd-efgh-2345-6789');
    expect(m['key'], 'ABCDEFGH23456789');
    expect(SyncService.prettyKey('ABCDEFGH23456789'), 'ABCD-EFGH-2345-6789');
    expect(CryptoBox.keyFromCode('abcd'), CryptoBox.keyFromCode('ABCD'));
  });
}
