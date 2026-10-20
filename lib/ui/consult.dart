import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../services/gemini.dart';
import 'settings/gemini_screen.dart';
import 'widgets.dart';

/// Consulenza AI con Gemini: manda i totali (mai i singoli movimenti) e mostra le priorità.
class ConsultScreen extends StatefulWidget {
  const ConsultScreen({super.key});
  @override
  State<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends State<ConsultScreen> {
  final _q = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final app = context.appRead;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final c = await askConsult(app, question: _q.text);
      app.saveConsult(c);
      _q.clear();
    } on GeminiException catch (e) {
      _err = e.message;
    } catch (e) {
      _err = 'Consulenza non riuscita: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final hasKey = app.prefs.geminiKey.isNotEmpty;
    final list = app.consults;
    return SubPage(
      title: 'Consulenza AI',
      actions: [IconSquare(icon: Icons.key_outlined, tooltip: 'Chiave Gemini', onTap: () => push(context, const GeminiScreen()))],
      body: PageBody(children: [
        Text('Gemini riceve solo un riepilogo dei numeri: medie per categoria, patrimonio, debiti, obiettivi. Niente descrizioni dei movimenti, nomi dei conti o controparti.',
            style: TS.soft(t, 13)),
        const SizedBox(height: 10),
        Tap(
          onTap: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Cosa viene inviato'),
              content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(financialSummary(app), style: const TextStyle(fontSize: 12.5)))),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Chiudi'))],
            ),
          ),
          child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Vedi esattamente cosa viene inviato', style: TextStyle(fontSize: 13, color: TC.accent, fontWeight: FontWeight.w600))),
        ),
        const SizedBox(height: 14),
        if (!hasKey)
          DCard(
            onTap: () => push(context, const GeminiScreen()),
            child: Row(children: [
              const Icon(Icons.key_rounded, color: TC.warn),
              const SizedBox(width: 12),
              Expanded(child: Text('Incolla la tua chiave Gemini per usare la consulenza.', style: TS.title(t))),
              Icon(Icons.chevron_right_rounded, color: t.dim),
            ]),
          )
        else ...[
          TextField(controller: _q, decoration: const InputDecoration(labelText: 'Domanda in più (facoltativa)', hintText: 'Es. conviene chiudere prima il prestito o investire?'), maxLines: 2, minLines: 1),
          const SizedBox(height: 12),
          PrimaryButton(label: 'Chiedi le priorità', icon: Icons.auto_awesome_rounded, busy: _busy, onTap: _ask),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: NoteBox(_err!, color: TC.neg, icon: Icons.error_outline_rounded)),
        ],
        for (final c in list) _ConsultCard(consult: c),
        const SizedBox(height: 10),
        Text(coachDisclaimer, style: TS.muted(t, 11)),
      ]),
    );
  }
}

class _ConsultCard extends StatelessWidget {
  final Consult consult;
  const _ConsultCard({required this.consult});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final c = consult;
    final when = DateTime.fromMillisecondsSinceEpoch(c.at);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${shortDateY(when)} · ${hhmm(when)}', style: TS.muted(t, 12))),
            IconButton(
              onPressed: () async {
                final ok = await confirm(context, title: 'Eliminare la consulenza?', body: 'Resta solo nella memoria di Gemini, non qui.', ok: 'Elimina', danger: true);
                if (ok) app.deleteConsult(c);
              },
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: t.dim),
            ),
          ]),
          if (c.summary.isNotEmpty) ...[Text(c.summary, style: TS.body(t)), const SizedBox(height: 10)],
          for (var i = 0; i < c.points.length; i++)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Checkbox(
                  value: c.points[i].done,
                  onChanged: (v) {
                    c.points[i].done = v ?? false;
                    app.saveConsult(c);
                  },
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${i + 1}. ${c.points[i].title}',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.ink, decoration: c.points[i].done ? TextDecoration.lineThrough : null)),
                    if (c.points[i].why.isNotEmpty) ...[const SizedBox(height: 4), Text(c.points[i].why, style: TS.soft(t, 13))],
                    if (c.points[i].action.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('→ ${c.points[i].action}', style: const TextStyle(fontSize: 13, color: TC.accentHi, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
