import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../logic/coach.dart';
import '../../services/backup.dart';
import '../../services/desktop.dart';
import '../../services/services.dart';
import '../../services/updates.dart';
import '../accounts.dart';
import '../lock_screen.dart';
import '../update_dialog.dart';
import '../widgets.dart';
import 'bank_notif_screen.dart';
import 'categories.dart';
import 'gemini_screen.dart';
import 'profile.dart';
import 'sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    Widget item(IconData icon, String title, String? sub, Widget page) => RowTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 20, color: TC.accent),
          ),
          title: title,
          subtitle: sub,
          trailing: Icon(Icons.chevron_right_rounded, color: t.dim),
          onTap: () => push(context, page),
        );
    final pairing = app.prefs.pairing;
    return SubPage(
      title: 'Impostazioni',
      body: PageBody(children: [
        DCard(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Column(children: [
            item(Icons.person_outline_rounded, 'Profilo e obiettivi', 'Entrate, spese, risparmio, ipotesi', const ProfileScreen()),
            item(Icons.account_balance_wallet_outlined, 'Conti', '${app.accounts.length} conti', const AccountsScreen()),
            item(Icons.label_outline_rounded, 'Categorie e regole', 'Budget, secchi, regole imparate', const CategoriesScreen()),
          ]),
        ),
        DCard(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Column(children: [
            item(Icons.lock_outline_rounded, 'Sicurezza', app.prefs.hasPin ? 'PIN attivo${app.prefs.bioOn ? ' · impronta' : ''}' : 'Nessun PIN', const SecurityScreen()),
            item(Icons.sync_rounded, 'Sincronizzazione', isDesktop ? (Services.sync.serverRunning ? 'Attiva su questo PC' : 'Spenta') : (pairing == null ? 'Non abbinato' : 'Con ${pairing['name'] ?? 'PC'}'),
                const SyncScreen()),
            if (isAndroid) item(Icons.notifications_active_outlined, 'Notifiche della banca', app.prefs.bankNotifOn ? 'Attive' : 'Spente', const BankNotifScreen()),
            item(Icons.auto_awesome_outlined, 'Consulenza AI', app.prefs.geminiKey.isEmpty ? 'Chiave Gemini da inserire' : 'Chiave inserita', const GeminiScreen()),
            item(Icons.save_alt_rounded, 'Backup ed esportazione', null, const BackupScreen()),
            if (isDesktop) item(Icons.desktop_windows_outlined, 'PC', 'Tray e avvio con Windows', const PcScreen()),
          ]),
        ),
        DCard(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Column(children: [
            RowTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.system_update_outlined, size: 20, color: TC.accent),
              ),
              title: 'Aggiornamenti',
              subtitle: 'Versione $appVersion',
              trailing: SmallButton(
                label: 'Controlla',
                onTap: () async {
                  final u = await checkForUpdate(app.prefs, force: true);
                  if (!context.mounted) return;
                  if (u == null) {
                    toast(context, 'Hai già l\'ultima versione');
                  } else {
                    updateNotice.value = u;
                    await offerUpdate(context, u);
                  }
                },
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(coachDisclaimer, style: TS.muted(t, 11.5)),
        const SizedBox(height: 4),
        Text('Dati cifrati su questo dispositivo (AES-256). Nessun server: solo il tuo PC e il tuo telefono.', style: TS.muted(t, 11.5)),
      ]),
    );
  }
}

// =================================================================== sicurezza

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final lock = Services.lock;
    final p = app.prefs;
    return SubPage(
      title: 'Sicurezza',
      body: PageBody(children: [
        DCard(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Column(children: [
            SwitchListTile(
              title: const Text('Blocco con PIN'),
              subtitle: const Text('All\'apertura e dopo un po\' in background'),
              value: p.hasPin,
              onChanged: (v) async {
                if (v) {
                  await setupPin(context);
                } else {
                  final ok = await confirm(context, title: 'Togliere il PIN?', body: 'Chiunque abbia il dispositivo sbloccato potrà aprire Dollarz.', ok: 'Togli', danger: true);
                  if (ok) lock.removePin();
                }
              },
            ),
            if (p.hasPin && lock.bioAvailable)
              SwitchListTile(
                title: Text(isWindows ? 'Windows Hello' : 'Impronta o volto'),
                subtitle: const Text('Il PIN resta come riserva'),
                value: p.bioOn,
                onChanged: (v) => p.bioOn = v,
              ),
            if (p.hasPin)
              ListTile(
                title: const Text('Cambia PIN'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setupPin(context),
              ),
          ]),
        ),
        if (p.hasPin) ...[
          const SectionLabel('Blocca dopo'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in [0, 1, 2, 5, 15]) PillChip(label: m == 0 ? 'Subito' : '$m min', selected: p.lockAfterMin == m, onTap: () => p.lockAfterMin = m),
          ]),
          const SizedBox(height: 6),
          Text('Tempo in background prima di chiedere di nuovo lo sblocco.', style: TS.muted(t, 12)),
        ],
        const SectionLabel('Privacy'),
        DCard(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Column(children: [
            SwitchListTile(
              title: const Text('Nascondi gli importi'),
              subtitle: const Text('Per quando c\'è gente intorno (anche dall\'occhio in home)'),
              value: p.hideAmounts,
              onChanged: (v) => p.hideAmounts = v,
            ),
            if (isAndroid)
              SwitchListTile(
                title: const Text('Schermata protetta'),
                subtitle: const Text('Niente screenshot e anteprima nascosta nelle app recenti'),
                value: p.secureScreen,
                onChanged: (v) {
                  p.secureScreen = v;
                  Services.bank.setSecure(v);
                },
              ),
          ]),
        ),
      ]),
    );
  }
}

// =================================================================== backup

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<String?> _newPassword(String title) async {
    final a = await askText(context, title: title, obscure: true, body: 'Almeno 8 caratteri. Senza questa password il backup non si apre: segnatela.');
    if (a == null || !mounted) return null;
    if (a.length < 8) {
      toast(context, 'Password troppo corta');
      return null;
    }
    final b = await askText(context, title: 'Ripeti la password', obscure: true);
    if (b == null || !mounted) return null;
    if (a != b) {
      toast(context, 'Le password non coincidono');
      return null;
    }
    return a;
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await Services.lock.withoutLock(fn);
    } catch (e) {
      if (mounted) toast(context, e is FormatException ? e.message : 'Operazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    return SubPage(
      title: 'Backup ed esportazione',
      body: PageBody(children: [
        Text('Il backup contiene tutti i dati, cifrati con una password che scegli tu. Ripristinandolo, i dati si uniscono a quelli presenti (vince la modifica più recente).',
            style: TS.soft(t)),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Esporta backup',
          icon: Icons.lock_outline_rounded,
          busy: _busy,
          onTap: () => _run(() async {
            final pass = await _newPassword('Password del backup');
            if (pass == null) return;
            final r = await Backup.export(app, pass);
            if (r != null && context.mounted) toast(context, r == 'condivisione' ? 'Backup pronto' : 'Salvato in $r');
          }),
        ),
        const SizedBox(height: 10),
        GhostButton(
          label: 'Ripristina un backup',
          icon: Icons.restore_rounded,
          onTap: _busy
              ? null
              : () => _run(() async {
                    final bytes = await Backup.pick();
                    if (bytes == null || !context.mounted) return;
                    final pass = await askText(context, title: 'Password del backup', obscure: true, ok: 'Ripristina');
                    if (pass == null) return;
                    final n = await Backup.restore(app, bytes, pass);
                    if (context.mounted) toast(context, 'Ripristinati $n elementi');
                  }),
        ),
        if (isDesktop) ...[
          const SectionLabel('Copia automatica sul PC'),
          DCard(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
            child: SwitchListTile(
              title: const Text('Un backup al giorno'),
              subtitle: const Text('In Documenti\\Dollarz backup, le ultime 14 copie. Con i dati del telefono, se è sincronizzato.'),
              value: Backup.autoOn(app),
              onChanged: (v) => _run(() async {
                if (!v) {
                  await Backup.setAutoPassword(app, null);
                } else {
                  final pass = await _newPassword('Password dei backup automatici');
                  if (pass == null) return;
                  await Backup.setAutoPassword(app, pass);
                  await Backup.autoBackup(app);
                  if (context.mounted) toast(context, 'Primo backup fatto');
                }
                if (mounted) setState(() {});
              }),
            ),
          ),
        ],
        const SectionLabel('Esporta i movimenti'),
        GhostButton(
          label: 'Movimenti in CSV (per Excel)',
          icon: Icons.table_view_outlined,
          onTap: _busy
              ? null
              : () => _run(() async {
                    final r = await exportMovementsCsv(app);
                    if (r != null && context.mounted) toast(context, r == 'condivisione' ? 'File pronto' : 'Salvato in $r');
                  }),
        ),
        const SizedBox(height: 18),
        Text('I dati si salvano da soli a ogni modifica: il backup serve se perdi o cambi il dispositivo.', style: TS.muted(t, 12)),
      ]),
    );
  }
}

// =================================================================== PC

class PcScreen extends StatefulWidget {
  const PcScreen({super.key});
  @override
  State<PcScreen> createState() => _PcScreenState();
}

class _PcScreenState extends State<PcScreen> {
  bool? _auto;

  @override
  void initState() {
    super.initState();
    DesktopService.isAutostart().then((v) {
      if (mounted) setState(() => _auto = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SubPage(
      title: 'PC',
      body: PageBody(children: [
        DCard(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Column(children: [
            SwitchListTile(
              title: const Text('Avvia con Windows'),
              subtitle: const Text('Parte nel tray, pronto per la sincronizzazione'),
              value: _auto ?? false,
              onChanged: _auto == null
                  ? null
                  : (v) async {
                      final ok = await DesktopService.setAutostart(v);
                      if (ok && mounted) setState(() => _auto = v);
                    },
            ),
            SwitchListTile(
              title: const Text('Chiudendo resta nel tray'),
              subtitle: const Text('La X nasconde la finestra; per uscire usa il menu dell\'icona'),
              value: app.prefs.trayEnabled,
              onChanged: (v) => app.prefs.trayEnabled = v,
            ),
          ]),
        ),
      ]),
    );
  }
}
