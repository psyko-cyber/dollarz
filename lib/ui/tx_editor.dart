import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/categories.dart';
import '../data/models.dart';
import 'accounts.dart';
import 'widgets.dart';

enum TxMode { expense, income, transfer }

/// Nuovo movimento (o modifica). Sul telefono è un foglio dal basso, sul PC un dialogo.
Future<void> openTxEditor(BuildContext context, {Tx? tx, String? accountId}) async {
  final app = context.appRead;
  if (app.accounts.isEmpty) {
    final go = await confirm(context, title: 'Prima un conto', body: 'Per registrare un movimento serve almeno un conto.', ok: 'Aggiungi conto');
    if (go && context.mounted) await push(context, const AccountEditor());
    return;
  }
  if (!context.mounted) return;
  final editor = TxEditor(tx: tx, accountId: accountId);
  if (isWide(context)) {
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: editor),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: editor),
    );
  }
}

class TxEditor extends StatefulWidget {
  final Tx? tx;
  final String? accountId;
  const TxEditor({super.key, this.tx, this.accountId});
  @override
  State<TxEditor> createState() => _TxEditorState();
}

class _TxEditorState extends State<TxEditor> {
  late TxMode _mode;
  final _amount = TextEditingController();
  final _amountTo = TextEditingController();
  final _desc = TextEditingController();
  final _note = TextEditingController();
  late String _date;
  late String _acc;
  String? _accTo;
  String? _cat;
  bool _catByUser = false;
  String? _err;

  bool get _editing => widget.tx != null;

  @override
  void initState() {
    super.initState();
    final app = context.appRead;
    final t = widget.tx;
    _date = t?.date ?? todayKey();
    _acc = t?.accountId ?? widget.accountId ?? app.mainAccount!.id;
    if (t != null) {
      _amount.text = centsToField(t.amount.abs());
      _desc.text = t.desc;
      _note.text = t.note;
      _cat = t.catId;
      _catByUser = t.catId != null;
      if (t.isTransfer) {
        _mode = TxMode.transfer;
        final pair = app.transferPair(t);
        final out = pair.where((x) => x.amount < 0).firstOrNull ?? t;
        final inn = pair.where((x) => x.amount > 0).firstOrNull;
        _acc = out.accountId;
        _accTo = inn?.accountId;
        _amount.text = centsToField(out.amount.abs());
        if (inn != null && inn.amount.abs() != out.amount.abs()) _amountTo.text = centsToField(inn.amount.abs());
        _cat = out.catId;
      } else {
        _mode = t.amount > 0 ? TxMode.income : TxMode.expense;
      }
    } else {
      _mode = TxMode.expense;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountTo.dispose();
    _desc.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Category> _catsFor(AppState app) {
    final kind = _mode == TxMode.income ? CatKind.income : CatKind.expense;
    final list = app.catsOfKind(kind);
    if (_mode == TxMode.expense) list.addAll(app.catsOfKind(CatKind.transfer).where((c) => c.id == investCat || c.id == 'risparmio'));
    // le più usate prima
    final use = <String, int>{};
    for (final t in app.txs.take(400)) {
      if (t.catId != null) use[t.catId!] = (use[t.catId!] ?? 0) + 1;
    }
    list.sort((a, b) => (use[b.id] ?? 0).compareTo(use[a.id] ?? 0));
    return list;
  }

  void _onDesc(String v) {
    if (_catByUser || _mode == TxMode.transfer) return;
    final app = context.appRead;
    final amt = _mode == TxMode.income ? 1 : -1;
    final s = app.suggestCat(v, amt);
    if (s != _cat) setState(() => _cat = s);
  }

  int? _parsedAmount() {
    final v = parseMoney(_amount.text);
    if (v == null || v == 0) return null;
    return v.abs();
  }

  Future<void> _save({bool fromCat = false}) async {
    final app = context.appRead;
    final amt = _parsedAmount();
    if (amt == null) {
      if (!fromCat) setState(() => _err = 'Scrivi l\'importo');
      return;
    }
    final nav = Navigator.of(context);
    if (_mode == TxMode.transfer) {
      final from = app.account(_acc), to = app.account(_accTo);
      if (from == null || to == null || from.id == to.id) {
        setState(() => _err = 'Scegli due conti diversi');
        return;
      }
      final amtTo = parseMoney(_amountTo.text)?.abs();
      app.saveTransfer(
        from: from,
        to: to,
        amount: amt,
        amountTo: from.currency != to.currency ? amtTo : null,
        date: _date,
        desc: _desc.text,
        catId: _cat == investCat || _cat == 'risparmio' ? _cat! : transferCat,
        transferId: widget.tx?.transferId,
      );
      nav.pop();
      return;
    }
    final signed = _mode == TxMode.income ? amt : -amt;
    final old = widget.tx;
    String? learned;
    if (old != null) {
      final changedCat = old.catId != _cat && _cat != null;
      old
        ..amount = signed
        ..accountId = _acc
        ..catId = _cat
        ..date = _date
        ..desc = _desc.text.trim()
        ..note = _note.text.trim();
      app.saveTx(old);
      if (changedCat && old.desc.isNotEmpty) {
        final n = app.learn(old.desc, _cat!, exceptTx: old.id);
        learned = 'Categoria imparata${n > 0 ? ': applicata anche ad altri $n movimenti' : ''}';
      }
    } else {
      final t = app.addTx(amount: signed, accountId: _acc, catId: _cat, desc: _desc.text, note: _note.text, date: _date, suggest: false);
      if (_catByUser && _cat != null && t.desc.isNotEmpty) app.learn(t.desc, _cat!, applyToOthers: false);
      app.matchScheduled();
    }
    HapticFeedback.lightImpact();
    nav.pop();
    if (learned != null && mounted) toast(context, learned);
  }

  Future<void> _delete() async {
    final app = context.appRead;
    final t = widget.tx!;
    final ok = await confirm(context,
        title: 'Eliminare il movimento?', body: t.isTransfer ? 'Si elimina il giroconto su entrambi i conti.' : 'Il saldo del conto si aggiorna.', ok: 'Elimina', danger: true);
    if (!ok || !mounted) return;
    app.deleteTx(t);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final acc = app.account(_acc);
    final cur = acc?.currency ?? 'EUR';
    final accTo = app.account(_accTo);
    final cats = _catsFor(app);
    final quick = !_editing && _mode != TxMode.transfer;

    Widget accountChip(String label, String? id, ValueChanged<String> onPick) {
      final a = app.account(id);
      return Tap(
        radius: 12,
        onTap: () async {
          final r = await pickFrom<String>(context,
              title: label,
              selected: id,
              items: [for (final x in app.accounts) (x.id, x.name, AccountType.labels[x.type])],
              leading: (aid) => Icon(accountIcon(app.account(aid)!.type), color: t.soft));
          if (r != null) onPick(r);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(a == null ? Icons.account_balance_wallet_outlined : accountIcon(a.type), size: 18, color: t.soft),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TS.muted(t, 11)),
                Text(a?.name ?? 'Scegli', maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.title(t)),
              ]),
            ),
            Icon(Icons.expand_more_rounded, color: t.dim),
          ]),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(_editing ? 'Modifica movimento' : 'Nuovo movimento', style: TS.h2(t))),
            if (_editing) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: TC.neg)),
          ]),
          const SizedBox(height: 12),
          if (!(_editing && widget.tx!.src == 'trade'))
            Seg<TxMode>(
              options: const [(TxMode.expense, 'Uscita'), (TxMode.income, 'Entrata'), (TxMode.transfer, 'Giroconto')],
              value: _mode,
              onChanged: (m) => setState(() {
                _mode = m;
                if (!_catByUser) _cat = null;
                if (m == TxMode.transfer) {
                  _accTo ??= app.accounts.where((a) => a.id != _acc).firstOrNull?.id;
                  _cat = transferCat;
                } else if (_cat != null && app.cat(_cat)?.isTransfer == true && _cat != investCat && _cat != 'risparmio') {
                  _cat = null;
                }
              }),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: !_editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TS.num(t, 38, w: FontWeight.w700, color: _mode == TxMode.income ? TC.pos : t.ink),
            decoration: InputDecoration(
              hintText: '0,00',
              prefixText: _mode == TxMode.income ? '+ ' : (_mode == TxMode.expense ? '− ' : ''),
              prefixStyle: TS.num(t, 30, color: t.dim),
              suffixText: curSymbol(cur),
              suffixStyle: TS.num(t, 24, color: t.dim),
              errorText: _err,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (_) {
              if (_err != null) setState(() => _err = null);
            },
          ),
          const SizedBox(height: 8),
          if (_mode == TxMode.transfer) ...[
            Row(children: [
              Expanded(child: accountChip('Da', _acc, (v) => setState(() => _acc = v))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, color: t.dim)),
              Expanded(child: accountChip('A', _accTo, (v) => setState(() => _accTo = v))),
            ]),
            if (acc != null && accTo != null && acc.currency != accTo.currency) ...[
              const SizedBox(height: 12),
              MoneyField(controller: _amountTo, label: 'Arrivano su ${accTo.name}', cur: accTo.currency),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in [(transferCat, 'Giroconto'), (investCat, 'Verso investimenti'), ('risparmio', 'Accantonamento')])
                PillChip(label: c.$2, selected: _cat == c.$1, onTap: () => setState(() => _cat = c.$1)),
            ]),
          ] else ...[
            Text(quick ? 'Tocca la categoria per salvare' : 'Categoria', style: TS.muted(t, 12.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in cats)
                _CatChip(
                  cat: c,
                  selected: _cat == c.id,
                  onTap: () {
                    setState(() {
                      _cat = c.id;
                      _catByUser = true;
                    });
                    if (quick && _parsedAmount() != null) _save(fromCat: true);
                  },
                ),
            ]),
            const SizedBox(height: 14),
            accountChip('Conto', _acc, (v) => setState(() => _acc = v)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descrizione (es. Esselunga)'),
            onChanged: _onDesc,
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final d in [(todayKey(), 'Oggi'), (addDaysKey(todayKey(), -1), 'Ieri')]) ...[
              PillChip(label: d.$2, selected: _date == d.$1, onTap: () => setState(() => _date = d.$1)),
              const SizedBox(width: 8),
            ],
            PillChip(
              label: _date != todayKey() && _date != addDaysKey(todayKey(), -1) ? shortDateY(fromKey(_date)) : 'Altro giorno',
              icon: Icons.calendar_today_rounded,
              selected: _date != todayKey() && _date != addDaysKey(todayKey(), -1),
              onTap: () async {
                final d = await pickDay(context, _date);
                if (d != null) setState(() => _date = d);
              },
            ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota (facoltativa)'), maxLines: 2, minLines: 1),
          const SizedBox(height: 18),
          PrimaryButton(label: _editing ? 'Salva modifiche' : 'Salva', icon: Icons.check_rounded, onTap: _save),
        ]),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final Category cat;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.cat, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final c = catColor(cat);
    return Material(
      color: selected ? c.withValues(alpha: 0.22) : t.surf2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? c : Colors.transparent)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(catIcons[cat.icon] ?? Icons.label_rounded, size: 17, color: c),
            const SizedBox(width: 6),
            Text(cat.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? t.ink : t.soft)),
          ]),
        ),
      ),
    );
  }
}
