import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/gemini.dart';
import '../widgets.dart';

/// Chiave e modello di Gemini per la consulenza AI.
class GeminiScreen extends StatefulWidget {
  const GeminiScreen({super.key});
  @override
  State<GeminiScreen> createState() => _GeminiScreenState();
}

class _GeminiScreenState extends State<GeminiScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    final p = context.appRead.prefs;
    _key.text = p.geminiKey;
    _model.text = p.geminiModel;
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final p = context.appRead.prefs;
    p.geminiKey = _key.text;
    p.geminiModel = _model.text;
    setState(() => _busy = true);
    try {
      await testGemini(p.geminiKey, p.geminiModel);
      if (mounted) toast(context, 'Chiave valida: Gemini risponde');
    } on GeminiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return SubPage(
      title: 'Consulenza AI',
      body: PageBody(children: [
        Text('La consulenza usa Gemini di Google con la tua chiave personale (gratuita, con dei limiti giornalieri). La chiave resta su questo dispositivo, cifrata.',
            style: TS.soft(t)),
        const SizedBox(height: 10),
        Tap(
          onTap: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Crea una chiave su Google AI Studio →', style: TextStyle(fontSize: 13.5, color: TC.accent, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _key,
          obscureText: !_show,
          decoration: InputDecoration(
            labelText: 'Chiave API',
            suffixIcon: IconButton(onPressed: () => setState(() => _show = !_show), icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined)),
          ),
          onChanged: (v) => context.appRead.prefs.geminiKey = v,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          decoration: const InputDecoration(labelText: 'Modello', helperText: 'gemini-flash-latest va bene: se non esiste uso il Flash più recente.'),
          onChanged: (v) => context.appRead.prefs.geminiModel = v,
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Prova la chiave', icon: Icons.check_circle_outline_rounded, busy: _busy, onTap: _test),
        const SizedBox(height: 10),
        GhostButton(
          label: 'Rimuovi la chiave',
          color: TC.neg,
          onTap: () {
            context.appRead.prefs.geminiKey = '';
            _key.clear();
          },
        ),
      ]),
    );
  }
}
