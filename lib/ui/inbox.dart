import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/bank_notif.dart';
import 'widgets.dart';

/// Notifiche della banca che non erano abbastanza chiare per diventare subito un movimento.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final items = app.inbox;
    return SubPage(
      title: 'Da confermare',
      actions: [
        if (items.isNotEmpty)
          IconSquare(
            icon: Icons.delete_sweep_outlined,
            tooltip: 'Scarta tutte',
            onTap: () async {
              final ok = await confirm(context, title: 'Scartare tutte?', body: 'Le ${items.length} notifiche non diventano movimenti.', ok: 'Scarta', danger: true);
              if (ok) {
                app.store.batch(() {
                  for (final i in items) {
                    app.dropInbox(i);
                  }
                });
              }
            },
          ),
      ],
      body: PageBody(children: [
        if (items.isEmpty)
          const EmptyState(icon: Icons.inbox_outlined, title: 'Tutto confermato', body: 'Qui arrivano le notifiche della banca che non ho capito bene.'),
        for (final i in items) _InboxCard(item: i),
        if (items.isNotEmpty) Text('Confermando con una categoria, Dollarz la ricorda per i movimenti simili.', style: TS.muted(t, 12.5)),
      ]),
    );
  }
}

class _InboxCard extends StatefulWidget {
  final InboxItem item;
  const _InboxCard({required this.item});
  @override
  State<_InboxCard> createState() => _InboxCardState();
}

class _InboxCardState extends State<_InboxCard> {
  late int _amount;
  late String _desc;
  String? _acc;
  String? _cat;

  @override
  void initState() {
    super.initState();
    final app = context.appRead;
    final i = widget.item;
    _amount = i.amount;
    _desc = i.merchant;
    _acc = (app.accountForBank(i.bank, invest: i.kind == NotifKind.invest.name) ?? app.mainAccount)?.id;
    _cat = i.catHint ?? (i.merchant.isEmpty ? null : app.suggestCat(i.merchant, i.amount));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final i = widget.item;
    final when = DateTime.fromMillisecondsSinceEpoch(i.at);
    return DCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusPill(bankLabels[i.bank] ?? 'Banca', color: TC.accent),
          const SizedBox(width: 8),
          Text('${relDay(when)} ${hhmm(when)}', style: TS.muted(t, 12)),
        ]),
        const SizedBox(height: 10),
        Text(i.text, style: TS.soft(t, 13)),
        Divider(height: 22, color: t.line),
        Row(children: [
          Expanded(
            child: Tap(
              onTap: () async {
                final v = await askText(context, title: 'Descrizione', initial: _desc);
                if (v != null) setState(() => _desc = v.trim());
              },
              child: Text(_desc.isEmpty ? 'Aggiungi descrizione' : _desc, style: TS.title(t)),
            ),
          ),
          Tap(
            onTap: () async {
              final v = await askMoney(context, title: 'Importo', initial: _amount, allowNegative: true, body: 'Le uscite con il meno davanti.');
              if (v != null) setState(() => _amount = v);
            },
            child: Text(fMoney(_amount, cur: i.currency, sign: _amount > 0), style: TS.num(t, 17, color: _amount > 0 ? TC.pos : t.ink, w: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillChip(
            label: app.account(_acc)?.name ?? 'Conto',
            icon: Icons.account_balance_wallet_outlined,
            onTap: () async {
              final r = await pickFrom<String>(context, title: 'Conto', selected: _acc, items: [for (final a in app.accounts) (a.id, a.name, null)]);
              if (r != null) setState(() => _acc = r);
            },
          ),
          PillChip(
            label: app.cat(_cat)?.name ?? 'Categoria',
            icon: Icons.label_outline_rounded,
            onTap: () async {
              final r = await pickFrom<String>(context,
                  title: 'Categoria',
                  selected: _cat,
                  items: [for (final c in app.cats.values.where((c) => !c.hidden)) (c.id, c.name, null)],
                  leading: (id) => CatIcon(app.cat(id), size: 30));
              if (r != null) setState(() => _cat = r);
            },
          ),
          PillChip(label: shortDateY(fromKey(i.date)), icon: Icons.calendar_today_rounded),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: GhostButton(label: 'Scarta', onTap: () => app.dropInbox(i))),
          const SizedBox(width: 10),
          Expanded(
            child: PrimaryButton(
              label: 'Conferma',
              icon: Icons.check_rounded,
              onTap: _acc == null || _amount == 0
                  ? null
                  : () {
                      app.confirmInbox(i, accountId: _acc!, catId: _cat, amount: _amount, desc: _desc.isEmpty ? null : _desc);
                      if (_cat != null && _desc.isNotEmpty) app.learn(_desc, _cat!, applyToOthers: false);
                    },
            ),
          ),
        ]),
      ]),
    );
  }
}
