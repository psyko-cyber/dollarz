import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/ids.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/schedule.dart';
import 'charts.dart';
import 'widgets.dart';

/// Scheda Scadenze: pagamenti in arrivo, previsione dei conti, ricorrenze trovate.
class ScheduledTab extends StatelessWidget {
  const ScheduledTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final today = todayKey();
    final all = app.upcoming;
    final overdue = app.overdue;
    final week = all.where((o) => o.open && o.date.compareTo(today) >= 0 && o.date.compareTo(addDaysKey(today, 7)) <= 0).toList();
    final month = all.where((o) => o.open && o.date.compareTo(addDaysKey(today, 7)) > 0 && o.date.compareTo(addDaysKey(today, 31)) <= 0).toList();
    final later = all.where((o) => o.open && o.date.compareTo(addDaysKey(today, 31)) > 0).toList();
    final done = all.where((o) => !o.open && o.date.compareTo(addDaysKey(today, -20)) >= 0).toList().reversed.toList();
    final fixed = app.scheds.where((s) => s.active && s.amount < 0).fold(0, (a, s) => a - monthlyEquivalent(s));
    final income = app.scheds.where((s) => s.active && s.amount > 0).fold(0, (a, s) => a + monthlyEquivalent(s));
    final reds = app.forecasts.where((f) => f.firstNegative != null && !f.account.isCard).toList();
    final rec = app.recurring;
    final main = app.mainAccount;
    final mainFc = app.forecasts.where((f) => f.account.id == main?.id).firstOrNull;

    Widget section(String title, List<OccView> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionLabel(title),
            DCard(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: Column(children: [for (final o in list) OccRow(occ: o)])),
          ]);

    return PageBody(maxWidth: 820, children: [
      TabHeader(title: 'Scadenze', actions: [
        IconSquare(icon: Icons.list_alt_rounded, tooltip: 'Tutte le scadenze', onTap: () => push(context, const SchedListScreen())),
        IconSquare(icon: Icons.add_rounded, tooltip: 'Nuova scadenza', onTap: () => push(context, const SchedEditor())),
      ]),
      if (app.scheds.isNotEmpty)
        DCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Uscite fisse', style: TS.muted(t, 12)),
                Money(-fixed, size: 18, dec: false),
                Text('al mese', style: TS.muted(t, 11.5)),
              ]),
            ),
            if (income > 0)
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Entrate fisse', style: TS.muted(t, 12)),
                  Money(income, size: 18, dec: false, color: TC.pos),
                  Text('al mese', style: TS.muted(t, 11.5)),
                ]),
              ),
          ]),
        ),
      for (final f in reds)
        DCard(
          color: TC.neg.withValues(alpha: 0.07),
          border: TC.neg.withValues(alpha: 0.35),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: TC.neg),
              const SizedBox(width: 10),
              Expanded(child: Text('${f.account.name} andrà in rosso', style: TS.title(t))),
            ]),
            const SizedBox(height: 6),
            Text(
              'Il ${shortDate(fromKey(f.firstNegative!.date))} il saldo previsto scende a ${fMoney(f.firstNegative!.balance, cur: f.account.currency)} '
              '(${f.firstNegative!.events.map((e) => e.sched.name).join(', ')}). Sposta dei soldi su questo conto prima di quella data.',
              style: TS.soft(t),
            ),
            const SizedBox(height: 10),
            ForecastChart(f: f, height: 120),
          ]),
        ),
      if (app.scheds.isEmpty)
        EmptyState(
          icon: Icons.event_outlined,
          title: 'Nessuna scadenza',
          body: 'Affitto, bollette, abbonamenti, rate, bollo auto: inseriscili una volta e ti avviso prima, prevedendo il saldo dei conti.',
          action: 'Nuova scadenza',
          onAction: () => push(context, const SchedEditor()),
        ),
      if (rec.isNotEmpty) const _RecurringCard(),
      section('Da segnare', overdue),
      section('Prossimi 7 giorni', week),
      section('Entro un mese', month),
      section('Più avanti', later.take(30).toList()),
      if (mainFc != null && mainFc.points.isNotEmpty && reds.every((f) => f.account.id != mainFc.account.id)) ...[
        SectionLabel('Previsione ${mainFc.account.name}'),
        DCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ForecastChart(f: mainFc),
            const SizedBox(height: 8),
            KV('Saldo minimo nei prossimi 90 giorni', moneyText(context, mainFc.min)),
          ]),
        ),
      ],
      section('Fatte di recente', done.take(15).toList()),
    ]);
  }
}

class OccRow extends StatelessWidget {
  final OccView occ;
  const OccRow({super.key, required this.occ});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final o = occ;
    final c = app.cat(o.sched.catId);
    final days = o.daysLeft;
    final (stateLabel, stateColor) = switch (o.state) {
      OccState.paid => ('pagata', TC.pos),
      OccState.skipped => ('saltata', t.dim),
      OccState.overdue => ('${-days} gg fa', TC.warn),
      OccState.due => (days == 0 ? 'oggi' : (days == 1 ? 'domani' : 'tra $days gg'), days <= 2 ? TC.warn : t.dim),
    };
    return RowTile(
      leading: CatIcon(c, size: 36),
      title: o.sched.name,
      subtitle: '${relDay(fromKey(o.date))}${o.sched.accountId != null ? ' · ${app.account(o.sched.accountId)?.name ?? ''}' : ''}${o.sched.variable ? ' · importo variabile' : ''}',
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Money(o.amount, colored: true, sign: o.amount > 0, color: o.state == OccState.skipped ? t.dim : null),
        const SizedBox(height: 2),
        Text(stateLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: stateColor)),
      ]),
      onTap: () => _occActions(context, o),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    );
  }
}

Future<void> _occActions(BuildContext context, OccView o) async {
  final app = context.appRead;
  final t = context.tt;
  final linked = app.tx(o.rec?.txId);
  await showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(o.sched.name, style: TS.h2(t)),
          Text('${longDate(fromKey(o.date))} · ${fMoney(o.amount)}', style: TS.muted(t)),
          if (linked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Collegata a: ${linked.desc} (${shortDate(fromKey(linked.date))})', style: TS.soft(t, 12.5))),
          const SizedBox(height: 14),
          if (o.open) ...[
            RowTile(
              leading: const Icon(Icons.check_circle_outline_rounded, color: TC.pos),
              title: o.amount > 0 ? 'Incassata: registra il movimento' : 'Pagata: registra il movimento',
              subtitle: 'Crea il movimento sul conto della scadenza',
              onTap: () async {
                Navigator.pop(c);
                var amt = o.amount;
                if (o.sched.variable) {
                  final v = await askMoney(context, title: 'Importo effettivo', initial: o.amount.abs());
                  if (v == null) return;
                  amt = o.amount < 0 ? -v.abs() : v.abs();
                }
                app.payNow(o, amount: amt);
              },
            ),
            RowTile(
              leading: Icon(Icons.link_rounded, color: t.soft),
              title: 'Già registrata: segna come fatta',
              subtitle: 'Il movimento c\'è già (o non serve)',
              onTap: () {
                Navigator.pop(c);
                app.markPaid(o);
              },
            ),
            RowTile(
              leading: Icon(Icons.skip_next_rounded, color: t.soft),
              title: 'Salta questa volta',
              onTap: () {
                Navigator.pop(c);
                app.markSkipped(o);
              },
            ),
          ] else
            RowTile(
              leading: Icon(Icons.undo_rounded, color: t.soft),
              title: 'Riapri',
              subtitle: 'Torna da pagare',
              onTap: () {
                Navigator.pop(c);
                app.reopen(o);
              },
            ),
          RowTile(
            leading: Icon(Icons.edit_outlined, color: t.soft),
            title: 'Modifica la scadenza',
            onTap: () {
              Navigator.pop(c);
              push(context, SchedEditor(sched: o.sched));
            },
          ),
        ]),
      ),
    ),
  );
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final list = app.recurring;
    return DCard(
      border: t.accentLine,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: TC.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('Spese che si ripetono', style: TS.title(t))),
        ]),
        const SizedBox(height: 4),
        Text('Le ho trovate nei movimenti: aggiungile alle scadenze per prevedere il saldo e ricordartele.', style: TS.muted(t, 12.5)),
        const SizedBox(height: 6),
        for (final r in list.take(6))
          RowTile(
            leading: CatIcon(app.cat(r.catId), size: 34),
            title: r.name,
            subtitle: '${r.freq == Freq.yearly ? 'Ogni anno' : 'Ogni mese'} · ${r.count} volte · prossima ${shortDate(fromKey(r.nextDate))}',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fMoney(r.amount), style: TS.num(t, 13.5)),
              IconButton(tooltip: 'Ignora', onPressed: () => app.ignoreRecurring(r.key), icon: Icon(Icons.close_rounded, size: 19, color: t.dim)),
              IconButton(
                tooltip: 'Aggiungi',
                onPressed: () {
                  app.schedFromRecurring(r);
                  toast(context, '${r.name} aggiunta alle scadenze');
                },
                icon: const Icon(Icons.add_circle_rounded, color: TC.accent),
              ),
            ]),
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
      ]),
    );
  }
}

/// Tutte le scadenze, attive e no.
class SchedListScreen extends StatelessWidget {
  const SchedListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final list = app.scheds;
    return SubPage(
      title: 'Tutte le scadenze',
      actions: [IconSquare(icon: Icons.add_rounded, onTap: () => push(context, const SchedEditor()))],
      body: PageBody(children: [
        if (list.isEmpty) Text('Nessuna scadenza.', style: TS.muted(t)),
        if (list.isNotEmpty)
          DCard(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Column(children: [
              for (final s in list)
                RowTile(
                  leading: CatIcon(app.cat(s.catId), size: 36),
                  title: s.name,
                  titleColor: s.active ? null : t.dim,
                  subtitle: '${Freq.label(s.freq, s.every)}${s.active ? (nextOccurrence(s) != null ? ' · prossima ${shortDateY(fromKey(nextOccurrence(s)!))}' : ' · finita') : ' · in pausa'}',
                  trailing: Money(s.amount, colored: true, sign: s.amount > 0),
                  onTap: () => push(context, SchedEditor(sched: s)),
                ),
            ]),
          ),
      ]),
    );
  }
}

class SchedEditor extends StatefulWidget {
  final Scheduled? sched;
  const SchedEditor({super.key, this.sched});
  @override
  State<SchedEditor> createState() => _SchedEditorState();
}

class _SchedEditorState extends State<SchedEditor> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _match = TextEditingController();
  final _note = TextEditingController();
  bool _income = false;
  bool _variable = false;
  bool _active = true;
  String _freq = Freq.monthly;
  int _every = 1;
  String _start = todayKey();
  String? _end;
  String? _acc;
  String? _cat;
  int _remind = 2;

  @override
  void initState() {
    super.initState();
    final s = widget.sched;
    if (s != null) {
      _name.text = s.name;
      _amount.text = centsToField(s.amount.abs());
      _match.text = s.match;
      _note.text = s.note;
      _income = s.amount > 0;
      _variable = s.variable;
      _active = s.active;
      _freq = s.freq;
      _every = s.every;
      _start = s.start;
      _end = s.end;
      _acc = s.accountId;
      _cat = s.catId;
      _remind = s.remindDays;
    } else {
      _acc = context.appRead.mainAccount?.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _match.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final app = context.appRead;
    final amt = parseMoney(_amount.text)?.abs();
    if (_name.text.trim().isEmpty || amt == null) {
      toast(context, 'Servono nome e importo');
      return;
    }
    final s = Scheduled(
      id: widget.sched?.id ?? newId(),
      name: _name.text.trim(),
      amount: _income ? amt : -amt,
      accountId: _acc,
      catId: _cat,
      freq: _freq,
      every: _freq == Freq.everyN ? _every : (_freq == Freq.weekly ? _every : 1),
      start: _start,
      end: _end,
      remindDays: _remind,
      variable: _variable,
      active: _active,
      match: _match.text.trim(),
      note: _note.text.trim(),
    );
    app.saveSched(s);
    app.matchScheduled();
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final app = context.appRead;
    final ok = await confirm(context, title: 'Eliminare la scadenza?', body: 'I movimenti già registrati restano.', ok: 'Elimina', danger: true);
    if (!ok || !mounted) return;
    app.deleteSched(widget.sched!);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final kind = _income ? CatKind.income : CatKind.expense;
    final cats = [...app.catsOfKind(kind), if (!_income) ...app.catsOfKind(CatKind.transfer).where((c) => c.id != 'rettifica')];
    return SubPage(
      title: widget.sched == null ? 'Nuova scadenza' : 'Modifica scadenza',
      actions: [if (widget.sched != null) IconSquare(icon: Icons.delete_outline_rounded, color: TC.neg, onTap: _delete)],
      bottom: BottomActions(children: [PrimaryButton(label: 'Salva', icon: Icons.check_rounded, onTap: _save)]),
      body: PageBody(children: [
        Seg<bool>(options: const [(false, 'Uscita'), (true, 'Entrata')], value: _income, onChanged: (v) => setState(() {
              _income = v;
              _cat = null;
            })),
        const SizedBox(height: 14),
        TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: _income ? 'Nome (es. Stipendio)' : 'Nome (es. Affitto, Netflix)')),
        const SizedBox(height: 12),
        MoneyField(controller: _amount, label: _variable ? 'Importo indicativo' : 'Importo'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Importo variabile'),
          subtitle: const Text('Bollette e simili: l\'abbinamento al movimento è più tollerante.'),
          value: _variable,
          onChanged: (v) => setState(() => _variable = v),
        ),
        const SectionLabel('Quando'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in [(Freq.monthly, 'Ogni mese'), (Freq.everyN, 'Ogni N mesi'), (Freq.yearly, 'Ogni anno'), (Freq.weekly, 'Settimanale'), (Freq.once, 'Una volta')])
            PillChip(label: f.$2, selected: _freq == f.$1, onTap: () => setState(() {
                  _freq = f.$1;
                  if (f.$1 == Freq.everyN && _every < 2) _every = 2;
                  if (f.$1 != Freq.everyN && f.$1 != Freq.weekly) _every = 1;
                })),
        ]),
        if (_freq == Freq.everyN || _freq == Freq.weekly) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text(_freq == Freq.weekly ? 'Ogni quante settimane' : 'Ogni quanti mesi', style: TS.soft(t)),
            const Spacer(),
            IconButton(onPressed: _every > 1 ? () => setState(() => _every--) : null, icon: const Icon(Icons.remove_rounded)),
            Text('$_every', style: TS.num(t, 18)),
            IconButton(onPressed: () => setState(() => _every++), icon: const Icon(Icons.add_rounded)),
          ]),
        ],
        const SizedBox(height: 10),
        RowTile(
          leading: Icon(Icons.event_rounded, color: t.soft),
          title: _freq == Freq.once ? 'Data' : 'Prima scadenza',
          subtitle: longDate(fromKey(_start)),
          onTap: () async {
            final d = await pickDay(context, _start);
            if (d != null) setState(() => _start = d);
          },
        ),
        if (_freq != Freq.once)
          RowTile(
            leading: Icon(Icons.event_busy_rounded, color: t.soft),
            title: 'Fine',
            subtitle: _end == null ? 'Nessuna' : longDate(fromKey(_end!)),
            trailing: _end == null ? null : IconButton(onPressed: () => setState(() => _end = null), icon: const Icon(Icons.close_rounded)),
            onTap: () async {
              final d = await pickDay(context, _end ?? addDaysKey(_start, 365));
              if (d != null) setState(() => _end = d);
            },
          ),
        const SectionLabel('Promemoria'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in [0, 1, 2, 3, 5, 7]) PillChip(label: d == 0 ? 'Il giorno stesso' : '$d gg prima', selected: _remind == d, onTap: () => setState(() => _remind = d)),
        ]),
        const SectionLabel('Conto e categoria'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillChip(label: 'Nessun conto', selected: _acc == null, onTap: () => setState(() => _acc = null)),
          for (final a in app.accounts) PillChip(label: a.name, icon: accountIcon(a.type), selected: _acc == a.id, onTap: () => setState(() => _acc = a.id)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats) PillChip(label: c.name, icon: catIcons[c.icon], selected: _cat == c.id, onTap: () => setState(() => _cat = c.id)),
        ]),
        const SectionLabel('Abbinamento automatico'),
        TextField(
          controller: _match,
          decoration: const InputDecoration(labelText: 'Testo da cercare nei movimenti', helperText: 'Vuoto = il nome. Es. "enel" per la bolletta della luce.'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota'), maxLines: 2, minLines: 1),
        if (widget.sched != null)
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Attiva'), value: _active, onChanged: (v) => setState(() => _active = v)),
      ]),
    );
  }
}
