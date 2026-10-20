import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/budget.dart';
import 'budget.dart';
import 'import_screen.dart';
import 'inbox.dart';
import 'tx_editor.dart';
import 'widgets.dart';

/// Scheda Movimenti: mese, ricerca, filtri, lista per giorno.
class TransactionsTab extends StatefulWidget {
  const TransactionsTab({super.key});
  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<TransactionsTab> {
  String? _month = thisMonthKey();
  String? _acc;
  String? _cat;
  final _q = TextEditingController();
  bool _search = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final q = _q.text;
    final list = app.filterTxs(q: q, accountId: _acc, catId: _cat, month: q.isEmpty ? _month : null);
    final st = _month != null && q.isEmpty && _acc == null && _cat == null ? app.statsFor(_month!) : null;
    final inbox = app.inbox.length;
    return PageBody(maxWidth: 820, children: [
      TabHeader(title: 'Movimenti', actions: [
        IconSquare(icon: _search ? Icons.close_rounded : Icons.search_rounded, tooltip: 'Cerca', onTap: () => setState(() {
              _search = !_search;
              if (!_search) _q.clear();
            })),
        IconSquare(icon: Icons.upload_file_rounded, tooltip: 'Importa estratto conto', onTap: () => push(context, const ImportScreen())),
        IconSquare(icon: Icons.pie_chart_outline_rounded, tooltip: 'Budget', onTap: () => push(context, const BudgetScreen())),
      ]),
      if (_search) ...[
        TextField(
          controller: _q,
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cerca in tutti i movimenti'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
      ],
      if (inbox > 0)
        DCard(
          color: TC.warn.withValues(alpha: 0.08),
          border: TC.warn.withValues(alpha: 0.35),
          onTap: () => push(context, const InboxScreen()),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, color: TC.warn),
            const SizedBox(width: 12),
            Expanded(child: Text('$inbox ${inbox == 1 ? 'notifica della banca da confermare' : 'notifiche della banca da confermare'}', style: TS.title(t))),
            Icon(Icons.chevron_right_rounded, color: t.dim),
          ]),
        ),
      if (q.isEmpty)
        Row(children: [
          IconButton(
            onPressed: () => setState(() => _month = addMonthsKey(_month ?? thisMonthKey(), -1)),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Tap(
              onTap: () => setState(() => _month = _month == null ? thisMonthKey() : null),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_month == null ? 'Tutti i mesi' : monthTitle(_month!), textAlign: TextAlign.center, style: TS.h2(t)),
              ),
            ),
          ),
          IconButton(
            onPressed: _month == null || _month == thisMonthKey() ? null : () => setState(() => _month = addMonthsKey(_month!, 1)),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          PillChip(
            label: _acc == null ? 'Tutti i conti' : app.account(_acc)?.name ?? 'Conto',
            icon: Icons.account_balance_wallet_outlined,
            selected: _acc != null,
            onTap: () async {
              final r = await pickFrom<String>(context,
                  title: 'Conto', selected: _acc ?? '', items: [('', 'Tutti i conti', null), for (final a in app.allAccounts) (a.id, a.name, null)]);
              if (r != null) setState(() => _acc = r.isEmpty ? null : r);
            },
          ),
          const SizedBox(width: 8),
          PillChip(
            label: _cat == null ? 'Tutte le categorie' : (_cat == noCat ? 'Senza categoria' : app.cat(_cat)?.name ?? 'Categoria'),
            icon: Icons.label_outline_rounded,
            selected: _cat != null,
            onTap: () async {
              final r = await pickFrom<String>(context, title: 'Categoria', selected: _cat ?? '', items: [
                ('', 'Tutte le categorie', null),
                (noCat, 'Senza categoria', null),
                for (final c in app.cats.values.where((c) => !c.hidden)) (c.id, c.name, null),
              ]);
              if (r != null) setState(() => _cat = r.isEmpty ? null : r);
            },
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (st != null && st.count > 0)
        DCard(
          child: Row(children: [
            Expanded(child: _Stat('Entrate', st.income, TC.pos)),
            Expanded(child: _Stat('Uscite', -st.expense, t.ink)),
            Expanded(child: _Stat('Risparmio', st.saving, st.saving >= 0 ? TC.pos : TC.neg, sub: st.income > 0 ? fPct(st.savingRate, 0) : null)),
          ]),
        ),
      if (st != null && st.uncategorized > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tap(
            onTap: () => setState(() => _cat = noCat),
            child: Text('${st.uncategorized} senza categoria: tocca per vederli', style: const TextStyle(fontSize: 13, color: TC.warn)),
          ),
        ),
      if (list.isEmpty)
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: q.isNotEmpty ? 'Nessun risultato' : 'Nessun movimento',
          body: q.isNotEmpty ? 'Prova con un\'altra parola.' : 'Aggiungi una spesa con il + oppure importa l\'estratto conto della banca.',
          action: q.isEmpty ? 'Nuovo movimento' : null,
          onAction: () => openTxEditor(context),
        ),
      TxGroupedList(txs: list.take(600).toList(), showAccount: _acc == null),
      if (list.length > 600) Padding(padding: const EdgeInsets.all(12), child: Text('Mostro i 600 più recenti: usa i filtri per gli altri.', style: TS.muted(t))),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int cents;
  final Color color;
  final String? sub;
  const _Stat(this.label, this.cents, this.color, {this.sub});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TS.muted(t, 12)),
      const SizedBox(height: 3),
      Money(cents, size: 15.5, color: color, dec: false),
      if (sub != null) Text(sub!, style: TS.muted(t, 11.5)),
    ]);
  }
}

/// Movimenti raggruppati per giorno.
class TxGroupedList extends StatelessWidget {
  final List<Tx> txs;
  final bool showAccount;
  const TxGroupedList({super.key, required this.txs, this.showAccount = true});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final app = context.app;
    final out = <Widget>[];
    String? day;
    var dayTotal = 0;
    var dayStart = 0;
    for (final x in txs) {
      if (x.date != day) {
        if (day != null) out.insert(dayStart, _DayHeader(day, dayTotal));
        day = x.date;
        dayTotal = 0;
        dayStart = out.length;
      }
      if (!x.isTransfer && !(app.cat(x.catId)?.isTransfer ?? false)) dayTotal += app.eur(x.amount, app.account(x.accountId)?.currency ?? 'EUR');
      out.add(TxRow(tx: x, showAccount: showAccount));
    }
    if (day != null) out.insert(dayStart, _DayHeader(day, dayTotal));
    if (out.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: t.surf, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.line)),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String day;
  final int total;
  const _DayHeader(this.day, this.total);
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
      child: Row(children: [
        Expanded(child: Text(relDay(fromKey(day)), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.dim))),
        if (total != 0) Text(moneyText(context, total, sign: true), style: TS.num(t, 12, color: t.dim)),
      ]),
    );
  }
}

class TxRow extends StatelessWidget {
  final Tx tx;
  final bool showAccount;
  const TxRow({super.key, required this.tx, this.showAccount = true});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = app.cat(tx.catId);
    final acc = app.account(tx.accountId);
    final paired = app.linkedTxIds.contains(tx.id);
    final sub = [
      c?.name ?? (tx.isTransfer ? 'Giroconto' : 'Senza categoria'),
      if (showAccount && acc != null) acc.name,
      if (tx.src == 'notif') 'da notifica',
      if (paired) 'scadenza',
    ].join(' · ');
    return RowTile(
      leading: CatIcon(c, size: 36, icon: tx.isTransfer ? Icons.swap_horiz_rounded : null),
      title: tx.desc.isEmpty ? (c?.name ?? 'Movimento') : tx.desc,
      subtitle: sub,
      titleColor: c == null && !tx.isTransfer ? TC.warn : null,
      trailing: Money(tx.amount, cur: acc?.currency ?? 'EUR', colored: true, sign: tx.amount > 0),
      onTap: () => openTxEditor(context, tx: tx),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    );
  }
}
