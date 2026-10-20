import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../services/updates.dart';
import 'widgets.dart';

/// Popup "nuova versione": Aggiorna scarica dentro l'app e installa sopra
/// la versione attuale; Più tardi la ripropone dopo 20 ore.
/// [ask] false: scarica subito (card in home).
Future<void> offerUpdate(BuildContext context, UpdateInfo u, {bool ask = true}) async {
  final prefs = context.appRead.prefs;
  if (ask) {
    final t = context.tt;
    final notes = plainNotes(u.notes);
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Dollarz ${u.version} disponibile'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340, maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Hai la $appVersion. Si installa sopra quella attuale: i tuoi dati restano.', style: TS.soft(t)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(notes, style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Più tardi')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aggiorna')),
        ],
      ),
    );
    if (go != true) {
      snoozeUpdate(prefs, u);
      return;
    }
  }
  if (!context.mounted) return;
  if (u.downloadUrl == null || !(isAndroid || isWindows)) {
    await launchUrl(Uri.parse(u.downloadUrl ?? u.pageUrl), mode: LaunchMode.externalApplication);
    return;
  }
  await _download(context, u);
}

Future<void> _download(BuildContext context, UpdateInfo u) async {
  final progress = ValueNotifier<double>(0);
  var cancelled = false;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Scarico la ${u.version}'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: v > 0 ? v : null),
            const SizedBox(height: 10),
            Text(v > 0 ? '${(v * 100).round()}%' : 'Avvio del download…'),
          ]),
        ),
        actions: [TextButton(onPressed: () => cancelled = true, child: const Text('Annulla'))],
      ),
    ),
  );
  try {
    final f = await downloadUpdate(u, onProgress: (v) => progress.value = v, cancelled: () => cancelled);
    nav.pop();
    final ok = await installUpdate(f);
    if (isWindows && context.mounted) {
      toast(context, ok ? 'Installo la ${u.version}: tra poco Dollarz si chiude e si riapre aggiornato' : 'Aggiornamento annullato: la richiesta di Windows non è stata confermata');
    }
  } catch (_) {
    nav.pop();
    if (cancelled || !context.mounted) return;
    final web = await confirm(context,
        title: 'Aggiornamento non riuscito', body: 'Controlla la connessione e riprova, oppure scaricalo dalla pagina di GitHub.', ok: 'Apri GitHub');
    if (web) await launchUrl(Uri.parse(u.downloadUrl ?? u.pageUrl), mode: LaunchMode.externalApplication);
  } finally {
    progress.dispose();
  }
}
