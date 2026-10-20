import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/crypto_box.dart';
import '../core/ids.dart';
import '../data/app_state.dart';

/// Sincronizzazione PC ↔ telefono sulla rete di casa, senza cloud (come Tigert).
///
/// Il PC espone un piccolo server HTTP (porta 47820) e risponde agli annunci
/// UDP (porta 47821). Il telefono si abbina leggendo un QR con indirizzi e
/// codice, poi invia e riceve solo i record cambiati dall'ultima volta.
/// In più rispetto a Tigert: richieste e risposte viaggiano cifrate con
/// AES-256-GCM, con una chiave derivata dal codice di abbinamento.
class SyncService extends ChangeNotifier {
  static const port = 47820;
  static const discoveryPort = 47821;
  static const _keyAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _maxBody = 80 * 1024 * 1024;

  /// Richieste più vecchie (o dal futuro) di così vengono rifiutate.
  static const _maxSkewMs = 15 * 60 * 1000;

  final AppState app;
  SyncService(this.app);

  // ================================================================ server (PC)

  HttpServer? _server;
  RawDatagramSocket? _udp;
  String? serverError;
  List<String> localIps = [];
  DateTime? lastServed;

  bool get serverRunning => _server != null;

  String get serverKey {
    var k = app.prefs.serverKey;
    if (k == null || k.length < 16) {
      k = randomString(16, _keyAlphabet);
      app.prefs.serverKey = k;
    }
    return k;
  }

  static String keyTag(String key) => CryptoBox.sha256Hex(utf8.encode('dollarz-tag:$key')).substring(0, 12);

  static String prettyKey(String k) => k.length == 16 ? [for (var i = 0; i < 16; i += 4) k.substring(i, i + 4)].join('-') : k;

  Future<void> startServer() async {
    if (_server != null) return;
    serverError = null;
    final key = serverKey;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handle, onError: (Object e) => debugPrint('sync server: $e'));
    } catch (e) {
      serverError = 'Non riesco ad aprire la porta $port (forse è già in uso).';
      _server = null;
      notifyListeners();
      return;
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
      _udp!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = _udp?.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (msg == 'DOLLARZ?${keyTag(key)}') {
          _udp?.send(utf8.encode('DOLLARZ!$port'), dg.address, dg.port);
        }
      });
    } catch (e) {
      debugPrint('sync discovery non disponibile: $e');
    }
    localIps = await listLocalIps();
    notifyListeners();
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _udp?.close();
    _udp = null;
    notifyListeners();
  }

  Future<void> regenerateKey() async {
    app.prefs.serverKey = randomString(16, _keyAlphabet);
    app.prefs.peers = {};
    if (serverRunning) {
      await stopServer();
      await startServer();
    }
    notifyListeners();
  }

  Future<void> refreshIps() async {
    localIps = await listLocalIps();
    notifyListeners();
  }

  /// Contenuto del QR di abbinamento.
  String pairingPayload() {
    final j = {'h': localIps, 'p': port, 'k': serverKey, 'n': deviceLabel(), 'id': app.store.deviceId};
    return 'dollarz://pair?d=${base64Url.encode(utf8.encode(jsonEncode(j)))}';
  }

  Future<Uint8List> _readBody(HttpRequest req) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in req) {
      b.add(chunk);
      if (b.length > _maxBody) throw const HttpException('richiesta troppo grande');
    }
    return b.toBytes();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (path == '/dollarz/hello') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'app': 'dollarz', 'v': 1, 'name': deviceLabel(), 'id': app.store.deviceId}));
        await res.close();
        return;
      }
      if (path == '/dollarz/sync' && req.method == 'POST') {
        final key = CryptoBox.keyFromCode(serverKey);
        final Map body;
        try {
          body = jsonDecode(await CryptoBox.openString(key, await _readBody(req))) as Map;
        } catch (_) {
          // non si apre con la nostra chiave: codice di abbinamento sbagliato o vecchio
          res.statusCode = HttpStatus.unauthorized;
          await res.close();
          return;
        }
        final ts = (body['ts'] as num?)?.toInt() ?? 0;
        if ((DateTime.now().millisecondsSinceEpoch - ts).abs() > _maxSkewMs) {
          res.statusCode = HttpStatus.preconditionFailed;
          await res.close();
          return;
        }
        final since = (body['since'] as num?)?.toInt() ?? 0;
        final out = app.store.changesSince(since);
        app.store.applyRemote((body['changes'] as List?) ?? const []);
        final dev = body['device'];
        if (dev is Map && dev['id'] is String) {
          final peers = Map<String, dynamic>.from(app.prefs.peers);
          peers[dev['id'] as String] = {'name': dev['name'] ?? 'Telefono', 'at': DateTime.now().millisecondsSinceEpoch};
          app.prefs.peers = peers;
        }
        lastServed = DateTime.now();
        final reply = jsonEncode({'seq': app.store.seq, 'id': app.store.deviceId, 'changes': out, 'ts': DateTime.now().millisecondsSinceEpoch});
        res.headers.contentType = ContentType.binary;
        res.add(await CryptoBox.sealString(key, reply));
        await res.close();
        notifyListeners();
        return;
      }
      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  // ================================================================ client (telefono)

  bool syncing = false;
  String? lastError;
  Timer? _debounce;
  Timer? _periodic;

  bool get paired => app.prefs.pairing != null;
  DateTime? get lastSyncAt => app.prefs.lastSyncAt == 0 ? null : DateTime.fromMillisecondsSinceEpoch(app.prefs.lastSyncAt);

  /// Da chiamare dopo ogni modifica locale: sincronizza dopo qualche secondo.
  void onLocalChange() {
    if (!paired) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => syncNow(quiet: true));
  }

  void startAuto() {
    _periodic?.cancel();
    if (!paired) return;
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) => syncNow(quiet: true));
  }

  void stopAuto() {
    _periodic?.cancel();
    _debounce?.cancel();
  }

  static Map<String, dynamic>? parsePairing(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'dollarz' || uri.host != 'pair') return null;
      final d = uri.queryParameters['d'];
      if (d == null) return null;
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(d)))) as Map;
      return {
        'hosts': ((j['h'] as List?) ?? const []).cast<String>(),
        'port': (j['p'] as num?)?.toInt() ?? port,
        'key': j['k'] as String,
        'name': (j['n'] as String?) ?? 'PC',
        'serverId': j['id'] as String?,
      };
    } catch (_) {
      return null;
    }
  }

  /// Abbinamento a mano: indirizzo del PC e codice.
  static Map<String, dynamic> manualPairing(String host, String code) => {
        'hosts': [host.trim()],
        'port': port,
        'key': code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase(),
        'name': 'PC',
        'serverId': null,
      };

  /// Abbina il telefono al PC e fa la prima sincronizzazione completa.
  Future<String?> pair(Map<String, dynamic> pairing) async {
    final hosts = (pairing['hosts'] as List).cast<String>();
    final p = (pairing['port'] as num?)?.toInt() ?? port;
    String? ok;
    for (final h in hosts) {
      if (await _hello(h, p) != null) {
        ok = h;
        break;
      }
    }
    ok ??= await _discover(pairing['key'] as String, p);
    if (ok == null) {
      return 'Non trovo il PC. Controlla che Dollarz sia aperto sul PC con la sincronizzazione attiva e che telefono e PC siano sulla stessa rete Wi-Fi.';
    }
    app.prefs.pairing = {...pairing, 'hosts': [ok, ...hosts.where((h) => h != ok)], 'port': p};
    app.prefs.lastServerSeq = 0;
    app.prefs.lastPushedSeq = 0;
    final err = await syncNow();
    if (err != null) {
      app.prefs.pairing = null;
      return err;
    }
    startAuto();
    return null;
  }

  void unpair() {
    app.prefs.pairing = null;
    app.prefs.lastServerSeq = 0;
    app.prefs.lastPushedSeq = 0;
    stopAuto();
    notifyListeners();
  }

  /// Ritorna null se è andata bene, altrimenti il messaggio di errore.
  Future<String?> syncNow({bool quiet = false}) async {
    final pairing = app.prefs.pairing;
    if (pairing == null) return 'Nessun PC abbinato.';
    if (syncing) return null;
    syncing = true;
    if (!quiet) notifyListeners();
    try {
      final code = pairing['key'] as String;
      final key = CryptoBox.keyFromCode(code);
      final p = (pairing['port'] as num?)?.toInt() ?? port;
      final hosts = ((pairing['hosts'] as List?) ?? const []).cast<String>();
      String? host;
      Map? hello;
      for (final h in hosts) {
        hello = await _hello(h, p);
        if (hello != null) {
          host = h;
          break;
        }
      }
      if (host == null) {
        host = await _discover(code, p);
        if (host != null) {
          hello = await _hello(host, p);
          app.prefs.pairing = {...pairing, 'hosts': [host, ...hosts.where((h) => h != host)]};
        }
      }
      if (host == null || hello == null) {
        throw const _SyncError('PC non raggiungibile: apri Dollarz sul PC e collegati alla stessa rete Wi-Fi.');
      }
      // Il PC è stato reinstallato? Riparto da zero.
      final serverId = hello['id'] as String?;
      if (serverId != null && pairing['serverId'] != null && pairing['serverId'] != serverId) {
        app.prefs.lastServerSeq = 0;
        app.prefs.lastPushedSeq = 0;
      }
      if (serverId != null) app.prefs.pairing = {...app.prefs.pairing!, 'serverId': serverId};

      final store = app.store;
      final upTo = store.seq;
      final since = app.prefs.lastServerSeq;
      final changes = store.changesSince(app.prefs.lastPushedSeq);
      final payload = await CryptoBox.sealString(
          key,
          jsonEncode({
            'since': since,
            'changes': changes,
            'device': {'id': store.deviceId, 'name': deviceLabel()},
            'ts': DateTime.now().millisecondsSinceEpoch,
          }));
      final r = await http
          .post(Uri.parse('http://$host:$p/dollarz/sync'), headers: {'Content-Type': 'application/octet-stream'}, body: payload)
          .timeout(const Duration(seconds: 90));
      if (r.statusCode == 401) throw const _SyncError('Il PC ha cambiato codice di abbinamento: abbina di nuovo il telefono.');
      if (r.statusCode == 412) throw const _SyncError('Data e ora del telefono e del PC non coincidono: controllale.');
      if (r.statusCode != 200) throw _SyncError('Il PC ha risposto con errore ${r.statusCode}.');
      final Map j;
      try {
        j = jsonDecode(await CryptoBox.openString(key, r.bodyBytes)) as Map;
      } catch (_) {
        throw const _SyncError('Risposta del PC non valida.');
      }
      final remote = (j['changes'] as List?) ?? const [];
      final applied = store.applyRemote(remote);
      final newSeq = (j['seq'] as num?)?.toInt() ?? since;
      app.prefs.lastServerSeq = newSeq < since ? 0 : newSeq;
      // se nel frattempo non ho modificato nulla, non rimando indietro ciò che ho appena ricevuto
      app.prefs.lastPushedSeq = store.seq == upTo + applied ? store.seq : upTo;
      app.prefs.lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      lastError = null;
      return null;
    } on _SyncError catch (e) {
      lastError = e.message;
      return e.message;
    } on TimeoutException {
      lastError = 'La sincronizzazione ci sta mettendo troppo: riprova.';
      return lastError;
    } catch (e) {
      lastError = 'Sincronizzazione non riuscita: $e';
      return lastError;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<Map?> _hello(String host, int p) async {
    try {
      final r = await http.get(Uri.parse('http://$host:$p/dollarz/hello')).timeout(const Duration(milliseconds: 2500));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map && j['app'] == 'dollarz' ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Chiede in broadcast "chi è il PC con questo codice?".
  Future<String?> _discover(String key, int p) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final c = Completer<String?>();
      sock.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = sock?.receive();
        if (dg == null) return;
        if (utf8.decode(dg.data, allowMalformed: true).startsWith('DOLLARZ!') && !c.isCompleted) c.complete(dg.address.address);
      });
      final msg = utf8.encode('DOLLARZ?${keyTag(key)}');
      final targets = <String>{'255.255.255.255'};
      for (final ip in await listLocalIps()) {
        final parts = ip.split('.');
        if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
      for (var round = 0; round < 3 && !c.isCompleted; round++) {
        for (final t in targets) {
          try {
            sock.send(msg, InternetAddress(t), discoveryPort);
          } catch (_) {}
        }
        await Future.any([c.future, Future<void>.delayed(const Duration(milliseconds: 700))]);
      }
      return c.isCompleted ? await c.future : null;
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  @override
  void dispose() {
    stopAuto();
    stopServer();
    super.dispose();
  }
}

class _SyncError implements Exception {
  final String message;
  const _SyncError(this.message);
}

String deviceLabel() {
  try {
    if (isAndroid) return 'Telefono Android';
    final h = Platform.localHostname;
    return h.isEmpty ? 'PC' : h;
  } catch (_) {
    return isAndroid ? 'Telefono Android' : 'PC';
  }
}

Future<List<String>> listLocalIps() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <String>[];
    for (final i in ifs) {
      final n = i.name.toLowerCase();
      final virtual = n.contains('vethernet') || n.contains('virtual') || n.contains('vmware') || n.contains('vbox') || n.contains('wsl') || n.contains('docker');
      if (virtual) continue;
      for (final a in i.addresses) {
        if (a.address.startsWith('169.254.')) continue;
        out.add(a.address);
      }
    }
    // reti di casa prima
    out.sort((a, b) => (b.startsWith('192.168.') ? 1 : 0).compareTo(a.startsWith('192.168.') ? 1 : 0));
    return out;
  } catch (_) {
    return [];
  }
}
