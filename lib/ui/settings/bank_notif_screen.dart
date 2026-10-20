import 'package:flutter/material.dart';

import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../logic/bank_notif.dart';
import '../../services/services.dart';
import '../widgets.dart';

/// Lettura delle notifiche della banca (solo Android): guida, permesso, registro.
class BankNotifScreen extends StatefulWidget {
  const BankNotifScreen({super.key});
  @override
  State<BankNotifScreen> createState() => _BankNotifScreenState();
}

class _BankNotifScreenState extends State<BankNotifScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Services.bank.checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // di ritorno dalle impostazioni di Android: ricontrollo il permesso
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Services.bank.checkAccess();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    return ListenableBuilder(
      listenable: Services.bank,
      builder: (context, _) {
        final access = Services.bank.access;
        final log = app.prefs.notifLog.reversed.toList();
        return SubPage(
          title: 'Notifiche della banca',
          body: PageBody(children: [
            Text('Quando Revolut, Fineco o Trade Republic ti mandano una notifica di pagamento, Dollarz la legge e crea il movimento. Il testo resta sul telefono.',
                style: TS.soft(t)),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Leggi le notifiche della banca'),
              subtitle: Text(access ? 'Permesso concesso' : 'Serve il permesso di Android (sotto)'),
              value: app.prefs.bankNotifOn,
              onChanged: (v) {
                app.prefs.bankNotifOn = v;
                if (v && !access) Services.bank.openNotifSettings();
              },
            ),
            if (!access) ...[
              const SectionLabel('Come dare il permesso'),
              DCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Step(1, 'Tocca "Apri impostazioni" e attiva Dollarz in "Accesso alle notifiche".'),
                  _Step(2, 'Se l\'interruttore è grigio o compare "Impostazione con restrizioni": torna qui e tocca "Info app".'),
                  _Step(3, 'In Info app tocca i tre puntini in alto a destra → "Consenti impostazioni con restrizioni" e conferma con impronta o PIN.'),
                  _Step(4, 'Torna su "Apri impostazioni" e attiva Dollarz. Android lo chiede una volta sola per le app installate fuori dal Play Store.'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: PrimaryButton(label: 'Apri impostazioni', onTap: Services.bank.openNotifSettings)),
                    const SizedBox(width: 10),
                    Expanded(child: GhostButton(label: 'Info app', onTap: Services.bank.openAppDetails)),
                  ]),
                ]),
              ),
            ],
            const SectionLabel('Altre app da leggere'),
            Text('Revolut, Fineco e Trade Republic sono già incluse. Aggiungi il nome del pacchetto di altre banche (es. com.banca.app).', style: TS.muted(t, 12.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in app.prefs.bankApps)
                InputChip(
                  label: Text(a),
                  onDeleted: () {
                    app.prefs.bankApps = app.prefs.bankApps.where((x) => x != a).toList();
                    Services.bank.pushApps();
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Aggiungi'),
                onPressed: () async {
                  final v = await askText(context, title: 'Pacchetto dell\'app', hint: 'com.banca.app');
                  if (v == null || v.trim().isEmpty) return;
                  app.prefs.bankApps = [...app.prefs.bankApps, v.trim()];
                  await Services.bank.pushApps();
                },
              ),
            ]),
            SectionLabel('Ultime notifiche lette (${log.length})', action: log.isEmpty ? null : 'Svuota', onAction: () => app.prefs.notifLog = []),
            Text('Servono a controllare che il lettore funzioni con la tua banca. Restano solo su questo telefono.', style: TS.muted(t, 12.5)),
            const SizedBox(height: 8),
            if (log.isEmpty) Text('Ancora nessuna notifica.', style: TS.muted(t)),
            for (final m in log.take(40))
              DCard(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusPill(bankLabels[bankOf('${m['pkg']}')] ?? '${m['pkg']}', color: TC.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_at(m['at']), style: TS.muted(t, 11.5))),
                  ]),
                  const SizedBox(height: 6),
                  Text('${m['title']}', style: TS.title(t)),
                  Text('${(m['big'] as String?)?.isNotEmpty == true ? m['big'] : m['text']}', style: TS.soft(t, 12.5)),
                  const SizedBox(height: 6),
                  Text('→ ${m['res']}', style: const TextStyle(fontSize: 12, color: TC.accentHi)),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

String _at(Object? ms) {
  if (ms is! int) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${relDay(d)} ${hhmm(d)}';
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step(this.n, this.text);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.accentTint, shape: BoxShape.circle),
          child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TC.accent)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TS.soft(t, 13))),
      ]),
    );
  }
}
