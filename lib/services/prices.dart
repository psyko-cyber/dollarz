import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/app_state.dart';
import '../data/models.dart';

/// Risultato di una ricerca di titoli o crypto.
class SymbolHit {
  final String symbol;
  final String name;
  final String exchange;
  final String type; // ETF, EQUITY, MUTUALFUND, CRYPTO…
  final String currency;
  const SymbolHit(this.symbol, this.name, this.exchange, this.type, [this.currency = '']);
}

/// Prezzi da fonti gratuite: Yahoo Finance (non ufficiale) per titoli ed ETF,
/// CoinGecko per le crypto, BCE per i cambi. Se una fonte non risponde si
/// tiene l'ultimo prezzo e si può sempre scrivere il prezzo a mano.
class PriceService extends ChangeNotifier {
  final AppState app;
  PriceService(this.app);

  bool busy = false;
  String? lastError;

  static const _ua = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Dollarz', 'Accept': 'application/json'};
  static const _every = Duration(hours: 6);

  Timer? _timer;

  void startAuto() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => refresh());
  }

  /// Aggiorna cambi e prezzi (al massimo ogni 6 ore, se non [force]).
  Future<String?> refresh({bool force = false}) async {
    if (busy) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - app.prefs.pricesAt < _every.inMilliseconds) return null;
    final hs = app.holdings.where((h) => h.symbol.isNotEmpty && !h.isDeposit).toList();
    if (hs.isEmpty && app.currencies.isEmpty) return null;
    busy = true;
    notifyListeners();
    final errors = <String>[];
    try {
      final fx = await fetchEcb();
      if (fx != null) app.saveFx(fx);
      final quotes = <Quote>[];
      final cryptoIds = hs.where((h) => h.isCrypto).map((h) => h.symbol).toSet();
      if (cryptoIds.isNotEmpty) {
        final cg = await fetchCoinGecko(cryptoIds);
        quotes.addAll(cg);
        if (cg.length < cryptoIds.length) errors.add('alcune crypto');
      }
      for (final h in hs.where((h) => !h.isCrypto)) {
        final q = await fetchYahoo(h.symbol);
        if (q != null) {
          quotes.add(q);
        } else {
          errors.add(h.name);
        }
      }
      if (quotes.isNotEmpty) {
        app.store.batch(() {
          for (final q in quotes) {
            app.saveQuote(q);
          }
        });
      }
      app.prefs.pricesAt = now;
      app.updateSnapshot();
      app.refresh();
      lastError = errors.isEmpty ? null : 'Prezzo non trovato per: ${errors.take(4).join(', ')}';
      return lastError;
    } catch (e) {
      lastError = 'Aggiornamento prezzi non riuscito: $e';
      return lastError;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- fonti

  /// Cambi BCE del giorno: quante unità di valuta per 1 euro.
  static Future<Map<String, double>?> fetchEcb() async {
    try {
      final r = await http.get(Uri.parse('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final out = <String, double>{};
      for (final m in RegExp(r'''currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]''').allMatches(r.body)) {
        out[m[1]!] = double.parse(m[2]!);
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<Quote?> fetchYahoo(String symbol) async {
    for (final host in const ['query1', 'query2']) {
      try {
        final r = await http
            .get(Uri.parse('https://$host.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}?range=5d&interval=1d'), headers: _ua)
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) continue;
        final res = ((jsonDecode(r.body) as Map)['chart'] as Map?)?['result'] as List?;
        if (res == null || res.isEmpty) continue;
        final meta = (res.first as Map)['meta'] as Map? ?? const {};
        var price = (meta['regularMarketPrice'] as num?)?.toDouble();
        if (price == null || price <= 0) continue;
        var cur = (meta['currency'] as String?) ?? 'EUR';
        // le borse inglesi quotano in pence
        if (cur == 'GBp' || cur == 'GBX') {
          price /= 100;
          cur = 'GBP';
        }
        final name = (meta['longName'] ?? meta['shortName'] ?? '') as String;
        return Quote('y:$symbol', price, cur.toUpperCase(), DateTime.now().millisecondsSinceEpoch, name);
      } catch (_) {}
    }
    return null;
  }

  static Future<List<Quote>> fetchCoinGecko(Set<String> ids) async {
    try {
      final r = await http
          .get(Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=${ids.map(Uri.encodeComponent).join(',')}&vs_currencies=eur'),
              headers: _ua)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(r.body) as Map;
      final now = DateTime.now().millisecondsSinceEpoch;
      return [
        for (final id in ids)
          if ((j[id] as Map?)?['eur'] is num) Quote('c:$id', ((j[id] as Map)['eur'] as num).toDouble(), 'EUR', now),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Cerca un titolo per ISIN, ticker o nome (Yahoo Finance).
  static Future<List<SymbolHit>> searchSecurities(String q) async {
    final query = q.trim();
    if (query.length < 2) return const [];
    try {
      final r = await http
          .get(Uri.parse('https://query2.finance.yahoo.com/v1/finance/search?q=${Uri.encodeComponent(query)}&quotesCount=10&newsCount=0'),
              headers: _ua)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      final quotes = ((jsonDecode(r.body) as Map)['quotes'] as List?) ?? const [];
      final out = <SymbolHit>[];
      for (final x in quotes) {
        final m = x as Map;
        final sym = m['symbol'] as String?;
        if (sym == null) continue;
        out.add(SymbolHit(sym, '${m['longname'] ?? m['shortname'] ?? sym}', '${m['exchDisp'] ?? m['exchange'] ?? ''}', '${m['quoteType'] ?? ''}'));
      }
      // prima le borse europee in euro (Milano, Xetra, Amsterdam, Parigi)
      int rank(SymbolHit h) => RegExp(r'\.(MI|DE|AS|PA|F)$').hasMatch(h.symbol) ? 0 : 1;
      out.sort((a, b) => rank(a).compareTo(rank(b)));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<SymbolHit>> searchCrypto(String q) async {
    final query = q.trim();
    if (query.length < 2) return const [];
    try {
      final r = await http
          .get(Uri.parse('https://api.coingecko.com/api/v3/search?query=${Uri.encodeComponent(query)}'), headers: _ua)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      final coins = ((jsonDecode(r.body) as Map)['coins'] as List?) ?? const [];
      return [
        for (final c in coins.take(10))
          SymbolHit('${(c as Map)['id']}', '${c['name']} (${'${c['symbol'] ?? ''}'.toUpperCase()})', 'CoinGecko', 'CRYPTO', 'EUR'),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
