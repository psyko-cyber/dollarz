import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/balances.dart';
import 'charts.dart';
import 'import_screen.dart';
import 'transactions.dart';
import 'tx_editor.dart';
import 'widgets.dart';

/// Elenco dei conti con i saldi.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final archived = app.allAccounts.where((a) => a.archived).toList();
    return SubPage(
      title: 'Conti',
      actions: [IconSquare(icon: Icons.add_rounded, tooltip: 'Nuovo conto', onTap: () => push(context, const AccountEditor()))],
      body: PageBody(children: [
        if (app.accounts.isEmpty)
          EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Nessun conto',
            body: 'Aggiungi i conti che usi: corrente, risparmio, contanti, carta, broker.',
            action: 'Aggiungi conto',
            onAction: () => push(context, const AccountEditor()),
          ),
        for (final a in app.accounts) AccountRow(account: a),
        if (app.accounts.isNotEmpty)
          DCard(
            child: KV('Totale sui conti', moneyText(context, app.netWorth.liquid), strong: true),
          ),
        if (archived.isNotEmpty) ...[
          const SectionLabel('Archiviati'),
          for (final a in archived) AccountRow(account: a),
        ],
        const SizedBox(height: 8),
        Text('Il saldo si calcola dal saldo che scrivi tu più i movimenti registrati dopo. Se non torna, correggilo: diventa il nuovo punto di partenza.',
            style: TS.muted(t, 12.5)),
      ]),
    );
  }
}

class AccountRow extends StatelessWidget {
  final Account account;
  const AccountRow({super.key, required this.account});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final a = account;
    final b = app.balance(a);
    return DCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => push(context, AccountScreen(accountId: a.id)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(12)),
          child: Icon(accountIcon(a.type), color: TC.accent, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, style: TS.title(t), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${AccountType.labels[a.type]}${a.institution != 'altro' ? ' · ${Institutions.labels[a.institution]}' : ''}', style: TS.muted(t, 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Money(b, cur: a.currency, size: 15.5, color: b < 0 ? TC.neg : null),
          if (a.currency != 'EUR') Text(moneyText(context, app.balanceEur(a)), style: TS.muted(t, 11.5)),
        ]),
      ]),
    );
  }
}

/// Dettaglio di un conto: saldo, andamento, previsione e movimenti.
class AccountScreen extends StatelessWidget {
  final String accountId;
  const AccountScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final a = app.account(accountId);
    if (a == null) return const SubPage(title: 'Conto', body: SizedBox());
    final b = app.balance(a);
    final txs = app.txsOf(a.id);
    final hist = monthlyBalances(a, txs, 12);
    final fc = app.forecasts.where((f) => f.account.id == a.id).firstOrNull;
    return SubPage(
      title: a.name,
      actions: [
        IconSquare(icon: Icons.upload_file_rounded, tooltip: 'Importa estratto', onTap: () => push(context, ImportScreen(accountId: a.id))),
        IconSquare(icon: Icons.edit_outlined, tooltip: 'Modifica conto', onTap: () => push(context, AccountEditor(account: a))),
      ],
      fab: FloatingActionButton(
        backgroundColor: TC.accent,
        foregroundColor: TC.onAccent,
        onPressed: () => openTxEditor(context, accountId: a.id),
        child: const Icon(Icons.add_rounded),
      ),
      body: PageBody(children: [
        DCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SALDO DI OGGI', style: TS.label(t)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Money(b, cur: a.currency, size: 30, weight: FontWeight.w700, color: b < 0 ? TC.neg : null)),
              SmallButton(
                label: 'Correggi',
                icon: Icons.tune_rounded,
                onTap: () async {
                  final v = await askMoney(context,
                      title: 'Saldo vero di ${a.name}',
                      initial: b,
                      cur: a.currency,
                      allowNegative: true,
                      body: 'Scrivi il saldo che vedi nell\'app della banca adesso.');
                  if (v != null) app.setBalance(a, v);
                },
              ),
            ]),
            Text('Riferimento: ${fMoney(a.anchorAmount, cur: a.currency)} al ${shortDateY(fromKey(a.anchorDate))}', style: TS.muted(t, 12)),
            const SizedBox(height: 14),
            NetWorthChart(points: hist, height: 140),
          ]),
        ),
        if (fc != null && fc.points.isNotEmpty) ...[
          const SectionLabel('Prossimi 90 giorni'),
          DCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (fc.firstNegative != null)
                NoteBox('Il ${shortDate(fromKey(fc.firstNegative!.date))} il saldo previsto scende a ${fMoney(fc.firstNegative!.balance, cur: a.currency)}.',
                    icon: Icons.warning_amber_rounded, color: TC.neg),
              ForecastChart(f: fc),
              const SizedBox(height: 8),
              KV('Saldo minimo previsto', fMoney(fc.min, cur: a.currency), color: fc.min < 0 ? TC.neg : null),
              KV('Tra 90 giorni', fMoney(fc.end, cur: a.currency)),
            ]),
          ),
        ],
        SectionLabel('Movimenti (${txs.length})'),
        if (txs.isEmpty) Text('Nessun movimento: aggiungine uno o importa l\'estratto.', style: TS.muted(t)),
        TxGroupedList(txs: txs.take(300).toList()),
      ]),
    );
  }
}

class AccountEditor extends StatefulWidget {
  final Account? account;
  const AccountEditor({super.key, this.account});
  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  String _type = AccountType.conto;
  String _inst = 'altro';
  String _cur = 'EUR';
  bool _archived = false;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      _name.text = a.name;
      _type = a.type;
      _inst = a.institution;
      _cur = a.currency;
      _archived = a.archived;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _save() {
    final app = context.appRead;
    final name = _name.text.trim().isEmpty ? (Institutions.labels[_inst] ?? AccountType.labels[_type]!) : _name.text.trim();
    final a = widget.account;
    if (a == null) {
      final bal = parseMoney(_balance.text) ?? 0;
      app.saveAccount(Account(
        id: newId(),
        name: name,
        type: _type,
        institution: _inst,
        currency: _cur,
        anchorAmount: bal,
        anchorDate: todayKey(),
        anchorAt: DateTime.now().millisecondsSinceEpoch,
        order: app.allAccounts.length,
      ));
    } else {
      a
        ..name = name
        ..type = _type
        ..institution = _inst
        ..currency = _cur
        ..archived = _archived;
      app.saveAccount(a);
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final app = context.appRead;
    final a = widget.account!;
    final n = app.txsOf(a.id).length;
    final ok = await confirm(context,
        title: 'Eliminare ${a.name}?',
        body: n == 0 ? 'Il conto non ha movimenti.' : 'Si eliminano anche i suoi $n movimenti. Se vuoi tenerli, archivialo invece.',
        ok: 'Elimina',
        danger: true);
    if (!ok || !mounted) return;
    app.deleteAccount(a);
    Navigator.of(context)
      ..pop()
      ..maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final editing = widget.account != null;
    return SubPage(
      title: editing ? 'Modifica conto' : 'Nuovo conto',
      actions: [if (editing) IconSquare(icon: Icons.delete_outline_rounded, color: TC.neg, onTap: _delete)],
      bottom: BottomActions(children: [PrimaryButton(label: 'Salva', icon: Icons.check_rounded, onTap: _save)]),
      body: PageBody(children: [
        Text('Banca', style: TS.muted(t, 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in Institutions.labels.entries) PillChip(label: e.value, selected: _inst == e.key, onTap: () => setState(() => _inst = e.key)),
        ]),
        const SizedBox(height: 16),
        Text('Tipo', style: TS.muted(t, 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in AccountType.labels.entries)
            PillChip(label: e.value, icon: accountIcon(e.key), selected: _type == e.key, onTap: () => setState(() => _type = e.key)),
        ]),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome (es. Revolut, Fineco conto)')),
        const SizedBox(height: 12),
        Row(children: [
          Text('Valuta', style: TS.soft(t)),
          const SizedBox(width: 12),
          for (final c in ['EUR', 'USD', 'GBP', 'CHF']) ...[
            PillChip(label: c, selected: _cur == c, onTap: () => setState(() => _cur = c)),
            const SizedBox(width: 6),
          ],
        ]),
        if (!editing) ...[
          const SizedBox(height: 16),
          MoneyField(
            controller: _balance,
            label: 'Saldo di oggi',
            cur: _cur,
            signed: true,
            helper: _type == AccountType.carta ? 'Per una carta di credito: quanto devi, con il meno davanti.' : 'Quello che vedi adesso nell\'app della banca.',
          ),
        ],
        if (editing) ...[
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Archiviato'),
            subtitle: const Text('Non conta nel patrimonio e non compare nelle scelte.'),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
        ],
      ]),
    );
  }
}
