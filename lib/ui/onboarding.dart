import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/projection.dart';
import '../services/backup.dart';
import '../services/services.dart';
import 'lock_screen.dart';
import 'settings/sync_screen.dart';
import 'widgets.dart';

/// Primo avvio guidato: entrate e spese, conti, patrimonio, obiettivi, sicurezza, piano.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _income = TextEditingController();
  final _expenses = TextEditingController();
  final _invested = TextEditingController();
  final _pension = TextEditingController();
  final _passive = TextEditingController();
  final _wealth = TextEditingController();
  bool _goalFi = true;
  double _savePct = 20;

  static const _steps = 7;

  @override
  void dispose() {
    for (final c in [_name, _income, _expenses, _invested, _pension, _passive, _wealth]) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveProfile({bool done = false}) {
    final app = context.appRead;
    final p = app.profile
      ..name = _name.text.trim()
      ..incomeMonthly = (parseMoney(_income.text) ?? 0).abs()
      ..expensesMonthly = (parseMoney(_expenses.text) ?? 0).abs()
      ..goalFi = _goalFi
      ..targetPassive = (parseMoney(_passive.text) ?? 0).abs()
      ..targetWealth = (parseMoney(_wealth.text) ?? 0).abs()
      ..savingsTargetPct = _savePct
      ..onboarded = done;
    app.saveProfile(p);
  }

  void _next() {
    if (_step == 3) _saveWealth();
    _saveProfile();
    setState(() => _step = (_step + 1).clamp(0, _steps - 1));
  }

  void _saveWealth() {
    final app = context.appRead;
    final inv = parseMoney(_invested.text)?.abs() ?? 0;
    final pen = parseMoney(_pension.text)?.abs() ?? 0;
    app.store.batch(() {
      if (inv > 0 && app.holdings.isEmpty) {
        final h = Holding(id: newId(), name: 'Investimenti (stima iniziale)', kind: HoldingKind.other, manualPrice: inv / 100, manualAt: DateTime.now().millisecondsSinceEpoch);
        app.saveHolding(h);
        app.saveTrade(Trade(id: newId(), holdingId: h.id, date: todayKey(), type: TradeType.buy, qty: 1, price: inv / 100, amount: inv));
      }
      if (pen > 0 && !app.things.any((a) => a.kind == AssetKind.pension)) {
        app.saveAsset(Asset(id: newId(), name: 'Fondo pensione', kind: AssetKind.pension, value: pen));
      }
    });
  }

  void _finish() {
    _saveProfile(done: true);
    context.appRead.updateSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final pages = [_welcome, _money, _accounts, _wealthPage, _goals, _security, _plan];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(children: [
              if (_step > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 18, 0),
                  child: Row(children: [
                    BackSquare(onTap: () => setState(() => _step--)),
                    const SizedBox(width: 14),
                    Expanded(child: BarTrack(value: _step / (_steps - 1), height: 5)),
                    const SizedBox(width: 14),
                    Text('${_step + 1}/$_steps', style: TS.muted(t, 12)),
                  ]),
                ),
              Expanded(child: pages[_step](context)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _page({required String title, String? sub, required List<Widget> children, String next = 'Avanti', VoidCallback? onNext, Widget? extra}) {
    final t = context.tt;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 22), children: [
          Text(title, style: TS.h1(t)),
          if (sub != null) ...[const SizedBox(height: 8), Text(sub, style: TS.soft(t, 14))],
          const SizedBox(height: 22),
          ...children,
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
        child: Column(children: [PrimaryButton(label: next, onTap: onNext ?? _next), ?extra]),
      ),
    ]);
  }

  Widget _welcome(BuildContext context) {
    final t = context.tt;
    return _page(
      title: 'Benvenuto in Dollarz',
      sub: 'Il tuo coach per arrivare a essere ricco e sereno, il prima possibile e con stime realistiche. Due minuti per impostarlo.',
      next: 'Iniziamo',
      children: [
        const Center(child: DollarzMark(size: 92)),
        const SizedBox(height: 28),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Come ti chiami? (facoltativo)')),
        const SizedBox(height: 22),
        Text('Hai già Dollarz su un altro dispositivo?', style: TS.muted(t, 12.5)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: GhostButton(label: isDesktop ? 'Sincronizza' : 'Collega al PC', icon: Icons.sync_rounded, onTap: () => push(context, const SyncScreen()))),
          const SizedBox(width: 10),
          Expanded(
            child: GhostButton(
              label: 'Da backup',
              icon: Icons.restore_rounded,
              onTap: () async {
                final app = context.appRead;
                final bytes = await Services.lock.withoutLock(Backup.pick);
                if (bytes == null || !context.mounted) return;
                final pass = await askText(context, title: 'Password del backup', obscure: true, ok: 'Ripristina');
                if (pass == null) return;
                try {
                  final n = await Backup.restore(app, bytes, pass);
                  if (context.mounted) toast(context, 'Ripristinati $n elementi');
                } on FormatException catch (e) {
                  if (context.mounted) toast(context, e.message);
                }
              },
            ),
          ),
        ]),
      ],
    );
  }

  Widget _money(BuildContext context) {
    final t = context.tt;
    final inc = parseMoney(_income.text)?.abs() ?? 0, exp = parseMoney(_expenses.text)?.abs() ?? 0;
    return _page(
      title: 'Quanto entra, quanto esce',
      sub: 'Due cifre indicative al mese. Appena ci sono movimenti veri, uso quelli.',
      children: [
        MoneyField(controller: _income, label: 'Entrate nette al mese', helper: 'Stipendio netto e altre entrate fisse', autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        MoneyField(controller: _expenses, label: 'Spese al mese', helper: 'Tutto compreso: affitto, bollette, spesa, svago', onChanged: (_) => setState(() {})),
        if (inc > 0 && exp > 0) ...[
          const SizedBox(height: 18),
          DCard(
            child: Text(
              inc > exp
                  ? 'Metti da parte circa ${fEuro(inc - exp)} al mese, il ${fPct((inc - exp) / inc, 0)} delle entrate.'
                  : 'Oggi esce più di quanto entra: sarà la prima cosa da sistemare.',
              style: TS.soft(t),
            ),
          ),
        ],
      ],
    );
  }

  Widget _accounts(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    Future<void> add(String inst, String type, String name) async {
      final v = await askMoney(context, title: 'Saldo di oggi: $name', allowNegative: true, body: 'Quello che vedi adesso nell\'app della banca.');
      if (v == null) return;
      app.saveAccount(Account(
        id: newId(),
        name: name,
        type: type,
        institution: inst,
        anchorAmount: v,
        anchorDate: todayKey(),
        anchorAt: DateTime.now().millisecondsSinceEpoch,
        order: app.allAccounts.length,
      ));
    }

    return _page(
      title: 'I tuoi conti',
      sub: 'Aggiungi dove tieni i soldi, con il saldo di oggi. Puoi aggiungerne altri dopo.',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillChip(label: 'Revolut', icon: Icons.add_rounded, onTap: () => add('revolut', AccountType.conto, 'Revolut')),
          PillChip(label: 'Fineco', icon: Icons.add_rounded, onTap: () => add('fineco', AccountType.conto, 'Fineco')),
          PillChip(label: 'Trade Republic', icon: Icons.add_rounded, onTap: () => add('traderepublic', AccountType.broker, 'Trade Republic')),
          PillChip(label: 'Contanti', icon: Icons.add_rounded, onTap: () => add('altro', AccountType.contanti, 'Contanti')),
          PillChip(label: 'Conto risparmio', icon: Icons.add_rounded, onTap: () => add('altro', AccountType.risparmio, 'Risparmi')),
          PillChip(
            label: 'Altro conto',
            icon: Icons.add_rounded,
            onTap: () async {
              final n = await askText(context, title: 'Nome del conto', hint: 'es. Conto Intesa');
              if (n != null && n.trim().isNotEmpty && context.mounted) await add('altro', AccountType.conto, n.trim());
            },
          ),
        ]),
        const SizedBox(height: 18),
        for (final a in app.accounts)
          RowTile(
            leading: Icon(accountIcon(a.type), color: TC.accent),
            title: a.name,
            subtitle: AccountType.labels[a.type],
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fMoney(app.balance(a), cur: a.currency), style: TS.num(t, 14)),
              IconButton(onPressed: () => app.deleteAccount(a), icon: Icon(Icons.close_rounded, size: 18, color: t.dim)),
            ]),
          ),
        if (app.accounts.isEmpty) Text('Ancora nessun conto.', style: TS.muted(t)),
        const SizedBox(height: 10),
        Text('Trade Republic come "liquidità broker": i titoli li aggiungi in Investimenti.', style: TS.muted(t, 12)),
      ],
    );
  }

  Widget _wealthPage(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    return _page(
      title: 'Investimenti e debiti',
      sub: 'Una stima basta: il dettaglio (titoli, prezzi, operazioni) lo aggiungi quando vuoi.',
      children: [
        if (app.holdings.isEmpty) MoneyField(controller: _invested, label: 'Valore attuale degli investimenti', helper: 'ETF, azioni, crypto, BTP… in totale. Vuoto se nessuno.'),
        if (app.holdings.isNotEmpty) Text('Investimenti già inseriti: ${fEuro(app.portfolio.value)}', style: TS.soft(t)),
        const SizedBox(height: 14),
        MoneyField(controller: _pension, label: 'Fondo pensione (facoltativo)'),
        const SizedBox(height: 20),
        Text('Debiti', style: TS.title(t)),
        const SizedBox(height: 6),
        for (final d in app.debts)
          RowTile(
            leading: const Icon(Icons.credit_score_rounded, color: TC.neg),
            title: d.name,
            subtitle: 'TAN ${fDec(d.rate, 2, true)}% · rata ${fEuro(d.monthly)}',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fEuro(d.value), style: TS.num(t, 14, color: TC.neg)),
              IconButton(onPressed: () => app.deleteAsset(d), icon: Icon(Icons.close_rounded, size: 18, color: t.dim)),
            ]),
          ),
        SmallButton(
          label: 'Aggiungi un debito',
          icon: Icons.add_rounded,
          onTap: () async {
            final name = await askText(context, title: 'Che debito è?', hint: 'es. Prestito auto, mutuo, carta revolving');
            if (name == null || name.trim().isEmpty || !context.mounted) return;
            final left = await askMoney(context, title: 'Quanto devi ancora');
            if (left == null || !context.mounted) return;
            final rate = await askText(context, title: 'TAN %', hint: 'es. 7,5', body: 'Lo trovi nel contratto. Vuoto se non lo sai.');
            if (!context.mounted) return;
            final rata = await askMoney(context, title: 'Rata mensile');
            app.saveAsset(Asset(id: newId(), name: name.trim(), kind: AssetKind.debt, value: left.abs(), rate: parseNum(rate ?? '') ?? 0, monthly: (rata ?? 0).abs()));
          },
        ),
      ],
    );
  }

  Widget _goals(BuildContext context) {
    final t = context.tt;
    final exp = parseMoney(_expenses.text)?.abs() ?? 0;
    return _page(
      title: 'Dove vuoi arrivare',
      sub: 'Scegli uno o più obiettivi: ti dico quando ci arrivi e come accorciare i tempi.',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Indipendenza finanziaria'),
          subtitle: Text(exp > 0 ? 'Vivere di rendita: servono circa ${fEuro(fiNumber(exp * 12, 4))}' : 'Vivere di rendita senza dover lavorare'),
          value: _goalFi,
          onChanged: (v) => setState(() => _goalFi = v),
        ),
        const SizedBox(height: 8),
        MoneyField(controller: _passive, label: 'Rendita passiva al mese che vorresti', helper: 'Es. 500 € al mese in più. Vuoto se non ti interessa.'),
        const SizedBox(height: 14),
        MoneyField(controller: _wealth, label: 'Patrimonio da raggiungere', helper: 'Es. 100.000 €. Vuoto se non ti interessa.'),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text('Quanto vuoi risparmiare e investire', style: TS.soft(t))),
          Text('${_savePct.round()}% delle entrate', style: TS.num(t, 14)),
        ]),
        Slider(value: _savePct, min: 5, max: 50, divisions: 9, onChanged: (v) => setState(() => _savePct = v)),
        Text('Il 20% è un buon inizio; più alto è, prima arrivi.', style: TS.muted(t, 12)),
      ],
    );
  }

  Widget _security(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final lock = Services.lock;
    return _page(
      title: 'Proteggi i tuoi dati',
      sub: 'I dati sono già cifrati su questo dispositivo. Con il PIN (e l\'impronta) nessuno apre Dollarz al posto tuo.',
      children: [
        DCard(
          child: Row(children: [
            Icon(app.prefs.hasPin ? Icons.lock_rounded : Icons.lock_open_rounded, color: app.prefs.hasPin ? TC.pos : TC.warn),
            const SizedBox(width: 12),
            Expanded(child: Text(app.prefs.hasPin ? 'PIN impostato' : 'Nessun PIN', style: TS.title(t))),
            SmallButton(label: app.prefs.hasPin ? 'Cambia' : 'Imposta PIN', onTap: () => setupPin(context)),
          ]),
        ),
        if (app.prefs.hasPin && lock.bioAvailable)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(isWindows ? 'Sblocco con Windows Hello' : 'Sblocco con impronta o volto'),
            value: app.prefs.bioOn,
            onChanged: (v) => app.prefs.bioOn = v,
          ),
        if (isAndroid) ...[
          const SizedBox(height: 12),
          const NoteBox('Dopo potrai attivare la lettura delle notifiche di Revolut, Fineco e Trade Republic: i movimenti si registrano da soli. Impostazioni → Notifiche della banca.',
              icon: Icons.notifications_active_outlined),
        ],
      ],
    );
  }

  Widget _plan(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final res = runCoach(app.coachInput);
    return _page(
      title: 'Il tuo piano',
      sub: 'Ecco da dove partire. Il coach si aggiorna da solo con i tuoi movimenti.',
      next: 'Vai a Dollarz',
      onNext: _finish,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.accentLine)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PROSSIMA MOSSA', style: TS.label(t, TC.accentHi)),
            const SizedBox(height: 8),
            Text(res.move.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: t.ink)),
            const SizedBox(height: 6),
            Text(res.move.text, style: TS.soft(t)),
          ]),
        ),
        const SizedBox(height: 18),
        for (final s in res.active)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(s.done ? Icons.check_circle_rounded : (s.state == PathState.current ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                  color: s.done ? TC.pos : (s.state == PathState.current ? TC.accent : t.dim), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(s.title, style: TS.body(t))),
              Text(s.done ? 'fatto' : s.status, style: TS.muted(t, 12)),
            ]),
          ),
        for (final g in res.goals)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${g.title}: ${g.monthsRealistic == null ? 'servono più risparmi' : 'circa ${fYearsMonths(g.monthsRealistic!)}'} (scenario realistico).',
                style: TS.soft(t, 13)),
          ),
        const SizedBox(height: 16),
        Text(coachDisclaimer, style: TS.muted(t, 11)),
      ],
    );
  }
}
