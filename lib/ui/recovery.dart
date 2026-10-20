import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/app_state.dart';
import '../services/backup.dart';
import 'widgets.dart';

/// I file dei dati esistono ma non si aprono (chiave del dispositivo persa o
/// file danneggiati): si ripristina un backup o si ricomincia.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    final app = context.appRead;
    final bytes = await Backup.pick();
    if (bytes == null || !mounted) return;
    final pass = await askText(context, title: 'Password del backup', obscure: true, ok: 'Ripristina');
    if (pass == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await app.store.wipe();
      app.store.unreadable.clear();
      final n = await Backup.restore(app, bytes, pass);
      if (mounted) toast(context, 'Ripristinati $n elementi');
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    app.refresh();
  }

  Future<void> _wipe() async {
    final app = context.appRead;
    final ok = await confirm(context,
        title: 'Ricominciare da zero?',
        body: 'I dati che non si aprono vengono cancellati da questo dispositivo. Se il telefono o il PC sono abbinati, i dati torneranno con la sincronizzazione.',
        ok: 'Ricomincia',
        danger: true);
    if (!ok) return;
    await app.store.wipe();
    app.store.unreadable.clear();
    app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.lock_reset_rounded, size: 48, color: TC.warn),
                const SizedBox(height: 16),
                Text('I dati non si aprono', style: TS.h1(t), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'Su questo dispositivo ci sono dati di Dollarz cifrati con una chiave che non c\'è più (app reinstallata o portachiavi azzerato). '
                  'Puoi ripristinare un backup oppure ricominciare.',
                  style: TS.soft(t),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                PrimaryButton(label: 'Ripristina un backup', icon: Icons.restore_rounded, busy: _busy, onTap: _restore),
                const SizedBox(height: 10),
                GhostButton(label: 'Ricomincia da zero', onTap: _busy ? null : _wipe, color: TC.neg),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
