import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/projection.dart';
import '../logic/schedule.dart';

const _base = 'https://generativelanguage.googleapis.com/v1beta';

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => message;
}

/// Riepilogo dei numeri da mandare a Gemini: totali e medie, mai le
/// descrizioni dei singoli movimenti, i nomi dei conti o le controparti.
String financialSummary(AppState app) {
  final p = app.profile;
  final c = app.coachInput;
  final nw = app.netWorth;
  final b = StringBuffer();
  String e(int cents) => fEuro(cents);
  b.writeln('PROFILO');
  b.writeln('- Entrate nette medie al mese: ${e(c.income)}${app.usingHistory ? ' (media ultimi mesi)' : ' (dichiarate)'}');
  b.writeln('- Spese medie al mese: ${e(c.expenses)}');
  b.writeln('- Risparmio al mese: ${e(c.saving)} (${fPct(c.savingRate, 0)} delle entrate; obiettivo ${fDec(p.savingsTargetPct, 0)}%)');
  b.writeln('- Versato in investimenti/accantonamenti al mese: ${e(c.investedMonthly)}');
  b.writeln();
  b.writeln('PATRIMONIO');
  b.writeln('- Patrimonio netto: ${e(nw.total)}');
  b.writeln('- Liquidità sui conti: ${e(nw.liquid)} (disponibile per emergenze: ${e(c.liquid)}, pari a ${c.expenses > 0 ? fDec(c.liquid / c.expenses, 1, true) : '?'} mesi di spese)');
  b.writeln('- Investimenti: ${e(nw.invested)}');
  final byKind = app.portfolio.byKind;
  for (final k in byKind.entries) {
    b.writeln('  - ${HoldingKind.labels[k.key] ?? k.key}: ${e(k.value)}');
  }
  b.writeln('- Plus/minus non realizzate: ${e(app.portfolio.unrealized)}; rendita netta annua attuale: ${e(app.portfolio.annualIncomeNet)}');
  if (app.things.isNotEmpty) {
    for (final a in app.things) {
      b.writeln('- Bene (${AssetKind.labels[a.kind] ?? a.kind}): ${e(a.value)}${a.monthly > 0 ? ', versamento ${e(a.monthly)}/mese' : ''}');
    }
  }
  if (app.debts.isNotEmpty) {
    b.writeln('- Debiti:');
    for (final d in app.debts) {
      b.writeln('  - residuo ${e(d.value)}, TAN ${fDec(d.rate, 1, true)}%, rata ${e(d.monthly)}/mese');
    }
  }
  b.writeln();
  b.writeln('SPESE MEDIE PER CATEGORIA (ultimi 3 mesi completi)');
  final months = app.completeMonths(3).map(app.statsFor).where((m) => m.count > 0).toList();
  if (months.isEmpty) {
    b.writeln('- nessuno storico ancora');
  } else {
    final tot = <String, int>{};
    for (final m in months) {
      for (final x in m.spentByCat.entries) {
        tot[x.key] = (tot[x.key] ?? 0) + x.value;
      }
    }
    final list = tot.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final x in list.take(14)) {
      final cat = app.cat(x.key);
      b.writeln('- ${cat?.name ?? 'Senza categoria'} (${cat == null ? '' : '${cat.bucket}, '}al mese): ${e((x.value / months.length).round())}');
    }
  }
  b.writeln();
  b.writeln('USCITE FISSE PROGRAMMATE');
  final fixed = app.scheds.where((s) => s.active && s.amount < 0).toList();
  final fixedMonthly = fixed.fold(0, (a, s) => a - monthlyEquivalent(s));
  b.writeln('- ${fixed.length} scadenze attive, equivalenti a ${e(fixedMonthly)} al mese (abbonamenti: ${e(c.subsMonthly)} al mese)');
  b.writeln();
  b.writeln('OBIETTIVI');
  for (final g in app.coach.goals) {
    b.writeln('- ${g.title}: obiettivo ${e(g.target)}, oggi ${e(g.current)} (${fPct(g.progress, 0)}), '
        'tempo stimato al ${fDec(g.rates.length > 1 ? g.rates[1] : g.rates.first, 1, true)}% reale: ${g.monthsRealistic == null ? 'oltre 80 anni' : fYearsMonths(g.monthsRealistic!)}');
  }
  if (app.coach.goals.isEmpty) b.writeln('- nessun obiettivo impostato');
  b.writeln('- Tasso di prelievo usato: ${fDec(p.swr, 1, true)}%; capitale per vivere di rendita: ${e(fiNumber(c.expenses * 12, p.swr))}');
  b.writeln();
  b.writeln('PERCORSO DEL COACH (regole)');
  for (final s in app.coach.steps.where((s) => s.state != PathState.off)) {
    b.writeln('- ${s.title}: ${s.done ? 'fatto' : s.status}');
  }
  return b.toString();
}

String consultPrompt(AppState app, {String question = ''}) {
  final q = question.trim();
  return '''Sei un educatore di finanza personale, diretto e concreto. Parli in italiano a una persona che vive in Italia.
Ti do il riepilogo dei suoi numeri. Dimmi le priorità per arrivare il prima possibile, in modo realistico, a essere sereno e poi finanziariamente libero.

Regole:
- Massimo 5 priorità, in ordine di importanza. Ognuna con: titolo breve, perché (con i numeri), azione concreta da fare questo mese.
- Usa principi classici e prudenti: fondo emergenza, debiti costosi, spese, tasso di risparmio, investimento regolare diversificato e a basso costo, orizzonte lungo.
- Non consigliare singoli titoli, fondi o prodotti specifici: parla di categorie di strumenti.
- Tieni conto delle tasse italiane (26% sulle plusvalenze, 12,5% sui titoli di Stato, imposta di bollo).
- Niente frasi generiche: ogni punto deve riferirsi ai numeri qui sotto.${q.isEmpty ? '' : '\n- Domanda in più: $q'}

Rispondi SOLO con JSON valido, senza testo prima o dopo, con questa struttura:
{"dollarz": 1, "sintesi": "2-3 frasi sulla situazione", "priorita": [{"titolo": "...", "perche": "...", "azione": "..."}]}

NUMERI
${financialSummary(app)}''';
}

/// Legge la risposta anche se "sporca" (blocchi ```json, virgole finali).
Consult parseConsult(String raw) {
  var t = raw.trim().replaceAll(RegExp(r'```[a-zA-Z]*'), '');
  final s = t.indexOf('{'), en = t.lastIndexOf('}');
  if (s < 0 || en <= s) throw const GeminiException('Risposta di Gemini non leggibile.');
  t = t.substring(s, en + 1).replaceAll('“', '"').replaceAll('”', '"').replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
  final Map j;
  try {
    j = jsonDecode(t) as Map;
  } catch (_) {
    throw const GeminiException('Risposta di Gemini non leggibile.');
  }
  final pts = <ConsultPoint>[];
  for (final x in (j['priorita'] as List? ?? j['priorities'] as List? ?? const [])) {
    if (x is! Map) continue;
    pts.add(ConsultPoint('${x['titolo'] ?? x['title'] ?? ''}'.trim(), '${x['perche'] ?? x['why'] ?? ''}'.trim(), '${x['azione'] ?? x['action'] ?? ''}'.trim()));
  }
  if (pts.isEmpty) throw const GeminiException('Gemini non ha indicato priorità.');
  return Consult(id: newId(), at: DateTime.now().millisecondsSinceEpoch, summary: '${j['sintesi'] ?? j['summary'] ?? ''}'.trim(), points: pts, raw: raw);
}

Future<Consult> askConsult(AppState app, {String question = ''}) async {
  final txt = await _generate(app.prefs.geminiKey, app.prefs.geminiModel, consultPrompt(app, question: question), json: true);
  return parseConsult(txt);
}

/// Verifica chiave e modello con una richiesta minima.
Future<String> testGemini(String apiKey, String model) => _generate(apiKey, model, 'Rispondi solo con la parola: ok');

Future<String> _generate(String apiKey, String model, String prompt, {bool json = false}) async {
  if (apiKey.trim().isEmpty) throw const GeminiException('Manca la chiave API di Gemini (Impostazioni → Consulenza AI).');
  final body = jsonEncode({
    'contents': [
      {
        'role': 'user',
        'parts': [
          {'text': prompt}
        ]
      }
    ],
    'generationConfig': {'temperature': 0.3, if (json) 'responseMimeType': 'application/json'},
  });
  Future<http.Response> call(String m) => http
      .post(Uri.parse('$_base/models/$m:generateContent'), headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey.trim()}, body: body)
      .timeout(const Duration(seconds: 90));
  http.Response r;
  try {
    r = await call(model);
    if (r.statusCode == 404) {
      final alt = await latestFlashModel(apiKey);
      if (alt != null && alt != model) r = await call(alt);
    }
  } on TimeoutException {
    throw const GeminiException('Gemini non ha risposto in tempo. Controlla la connessione e riprova.');
  } catch (e) {
    throw GeminiException('Connessione a Gemini non riuscita: $e');
  }
  if (r.statusCode != 200) {
    var msg = '';
    try {
      msg = ((jsonDecode(r.body) as Map)['error'] as Map?)?['message']?.toString() ?? '';
    } catch (_) {}
    throw GeminiException(switch (r.statusCode) {
      400 when msg.toLowerCase().contains('api key') => 'La chiave API non è valida: controllala nelle impostazioni.',
      403 => 'La chiave API non ha i permessi per Gemini ($msg).',
      429 => 'Hai superato il limite gratuito di Gemini per ora. Riprova tra poco.',
      _ => 'Errore Gemini ${r.statusCode}${msg.isEmpty ? '' : ': $msg'}',
    });
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  final cands = j['candidates'] as List?;
  if (cands == null || cands.isEmpty) {
    final block = (j['promptFeedback'] as Map?)?['blockReason'];
    throw GeminiException(block != null ? 'Gemini ha bloccato la richiesta ($block).' : 'Gemini non ha restituito risposte.');
  }
  final ps = ((cands.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
  return ps.map((p) => (p as Map)['text'] ?? '').join();
}

/// Il modello Flash più recente disponibile per la chiave.
Future<String?> latestFlashModel(String apiKey) async {
  try {
    final r = await http.get(Uri.parse('$_base/models?pageSize=200'), headers: {'x-goog-api-key': apiKey.trim()}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    final models = ((jsonDecode(r.body) as Map)['models'] as List? ?? const []).cast<Map>();
    final names = <String>[];
    for (final m in models) {
      final name = (m['name'] as String? ?? '').replaceFirst('models/', '');
      final methods = (m['supportedGenerationMethods'] as List? ?? const []).cast<String>();
      if (!methods.contains('generateContent') || !name.contains('flash')) continue;
      if (RegExp(r'lite|image|tts|live|audio|preview|exp|embedding').hasMatch(name)) continue;
      names.add(name);
    }
    if (names.isEmpty) return null;
    double ver(String n) => double.tryParse(RegExp(r'(\d+(\.\d+)?)').firstMatch(n)?.group(1) ?? '0') ?? 0;
    names.sort((a, b) => ver(b).compareTo(ver(a)));
    return names.first;
  } catch (_) {
    return null;
  }
}
