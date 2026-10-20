import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/fmt.dart';
import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/services.dart';
import '../../services/sync.dart';
import '../widgets.dart';

/// Sincronizzazione telefono ↔ PC sulla rete di casa.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Services.sync,
      builder: (context, _) => SubPage(
        title: 'Sincronizzazione',
        body: PageBody(children: isDesktop ? const [_ServerPanel()] : const [_ClientPanel()]),
      ),
    );
  }
}

class _ServerPanel extends StatelessWidget {
  const _ServerPanel();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final s = Services.sync;
    final peers = app.prefs.peers;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Il PC fa da "casa" dei dati: il telefono si collega quando è sulla stessa rete Wi-Fi e si scambiano solo le modifiche, cifrate.', style: TS.soft(t)),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sincronizzazione attiva su questo PC'),
        subtitle: Text(s.serverRunning ? 'In ascolto sulla porta ${SyncService.port}' : 'Spenta'),
        value: s.serverRunning,
        onChanged: (v) async {
          app.prefs.serverEnabled = v;
          v ? await s.startServer() : await s.stopServer();
        },
      ),
      if (s.serverError != null) NoteBox(s.serverError!, color: TC.neg, icon: Icons.error_outline_rounded),
      if (s.serverRunning) ...[
        const SectionLabel('Abbina il telefono'),
        DCard(
          child: Column(children: [
            Text('Apri Dollarz sul telefono → Impostazioni → Sincronizzazione → Inquadra il QR', style: TS.soft(t, 13), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: QrImageView(data: s.pairingPayload(), size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 14),
            Text('Oppure a mano', style: TS.muted(t, 12)),
            SelectableText(SyncService.prettyKey(s.serverKey), style: TS.num(t, 20, w: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(s.localIps.isEmpty ? 'Nessuna rete trovata' : s.localIps.join('  ·  '), style: TS.muted(t, 12.5)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SmallButton(label: 'Aggiorna indirizzi', icon: Icons.refresh_rounded, onTap: s.refreshIps),
              const SizedBox(width: 8),
              SmallButton(
                label: 'Nuovo codice',
                icon: Icons.key_rounded,
                onTap: () async {
                  final ok = await confirm(context, title: 'Cambiare codice?', body: 'I telefoni abbinati dovranno abbinarsi di nuovo.', ok: 'Cambia');
                  if (ok) await s.regenerateKey();
                },
              ),
            ]),
          ]),
        ),
        if (peers.isNotEmpty) ...[
          const SectionLabel('Dispositivi collegati'),
          DCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Column(children: [
              for (final e in peers.entries)
                RowTile(
                  leading: Icon(Icons.phone_android_rounded, color: t.soft),
                  title: '${(e.value as Map)['name'] ?? 'Telefono'}',
                  subtitle: 'Ultima sincronizzazione: ${_when((e.value as Map)['at'] as int?)}',
                ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Text('Se Windows chiede il permesso del firewall per Dollarz, consenti le reti private.', style: TS.muted(t, 12)),
      ],
    ]);
  }
}

String _when(int? ms) {
  if (ms == null || ms == 0) return 'mai';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${relDay(d).toLowerCase()} alle ${hhmm(d)}';
}

class _ClientPanel extends StatefulWidget {
  const _ClientPanel();
  @override
  State<_ClientPanel> createState() => _ClientPanelState();
}

class _ClientPanelState extends State<_ClientPanel> {
  bool _busy = false;

  Future<void> _pair(Map<String, dynamic> p) async {
    setState(() => _busy = true);
    final err = await Services.sync.pair(p);
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, err ?? 'Abbinato: dati sincronizzati');
  }

  Future<void> _scan() async {
    final raw = await Services.lock.withoutLock(() => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage())));
    if (raw == null || !mounted) return;
    final p = SyncService.parsePairing(raw);
    if (p == null) {
      toast(context, 'Questo QR non è di Dollarz');
      return;
    }
    await _pair(p);
  }

  Future<void> _manual() async {
    final host = await askText(context, title: 'Indirizzo del PC', hint: 'es. 192.168.1.20', body: 'Lo trovi su Dollarz del PC, sotto il QR.');
    if (host == null || host.trim().isEmpty || !mounted) return;
    final code = await askText(context, title: 'Codice di abbinamento', hint: 'XXXX-XXXX-XXXX-XXXX');
    if (code == null || code.trim().isEmpty) return;
    await _pair(SyncService.manualPairing(host, code));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final s = Services.sync;
    final p = app.prefs.pairing;
    if (p == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Collega il telefono a Dollarz sul PC: quando siete sulla stessa rete Wi-Fi si scambiano le modifiche in pochi secondi, cifrate. Niente cloud.', style: TS.soft(t)),
        const SizedBox(height: 18),
        PrimaryButton(label: 'Inquadra il QR del PC', icon: Icons.qr_code_scanner_rounded, busy: _busy, onTap: _scan),
        const SizedBox(height: 10),
        GhostButton(label: 'Inserisci il codice a mano', onTap: _busy ? null : _manual),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.computer_rounded, color: TC.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('Abbinato a ${p['name'] ?? 'PC'}', style: TS.title(t))),
          ]),
          const SizedBox(height: 8),
          Text('Ultima sincronizzazione: ${_when(app.prefs.lastSyncAt)}', style: TS.muted(t, 12.5)),
          if (s.lastError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.lastError!, style: const TextStyle(fontSize: 12.5, color: TC.warn))),
        ]),
      ),
      PrimaryButton(
        label: 'Sincronizza ora',
        icon: Icons.sync_rounded,
        busy: s.syncing,
        onTap: () async {
          final err = await s.syncNow();
          if (context.mounted) toast(context, err ?? 'Sincronizzato');
        },
      ),
      const SizedBox(height: 10),
      GhostButton(
        label: 'Scollega',
        color: TC.neg,
        onTap: () async {
          final ok = await confirm(context, title: 'Scollegare dal PC?', body: 'I dati restano su entrambi, ma smettono di sincronizzarsi.', ok: 'Scollega', danger: true);
          if (ok) s.unpair();
        },
      ),
    ]);
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _ctrl = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: 'Inquadra il QR',
      body: MobileScanner(
        controller: _ctrl,
        onDetect: (cap) {
          if (_done) return;
          final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().where((s) => s.startsWith('dollarz://')).firstOrNull;
          if (v == null) return;
          _done = true;
          Navigator.pop(context, v);
        },
      ),
    );
  }
}
