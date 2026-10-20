import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import 'widgets.dart';

IconData assetIcon(String k) => switch (k) {
      AssetKind.home => Icons.home_rounded,
      AssetKind.vehicle => Icons.directions_car_rounded,
      AssetKind.pension => Icons.elderly_rounded,
      AssetKind.debt => Icons.credit_score_rounded,
      _ => Icons.category_rounded,
    };

/// Beni (pensione, immobili, veicoli…) e debiti, aggiornati a mano.
class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final things = app.things;
    final debts = app.debts;
    Widget row(Asset a) {
      final old = daysBetween(fromKey(a.updated), today()) > 120;
      return RowTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: (a.isDebt ? TC.neg : TC.accent).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(11)),
          child: Icon(assetIcon(a.kind), size: 19, color: a.isDebt ? TC.neg : TC.accent),
        ),
        title: a.name,
        subtitle: [
          AssetKind.labels[a.kind] ?? a.kind,
          if (a.rate > 0) '${a.isDebt ? 'TAN' : 'rende'} ${fDec(a.rate, 2, true)}%',
          if (a.monthly > 0) '${fEuro(a.monthly)}/mese',
          if (a.isDebt && a.rate >= expensiveDebtRate) 'costoso',
          if (old) 'da aggiornare',
        ].join(' · '),
        trailing: Money(a.isDebt ? -a.value : a.value, dec: false, color: a.isDebt ? TC.neg : null),
        onTap: () => push(context, AssetEditor(asset: a)),
      );
    }

    return SubPage(
      title: 'Beni e debiti',
      actions: [IconSquare(icon: Icons.add_rounded, tooltip: 'Aggiungi', onTap: () => push(context, const AssetEditor()))],
      body: PageBody(children: [
        Text('Quello che non è su un conto o in un investimento: fondo pensione, casa, auto, prestiti, mutuo. Aggiorna il valore ogni tanto.', style: TS.muted(t, 13)),
        const SectionLabel('Beni'),
        if (things.isEmpty) Text('Nessun bene.', style: TS.muted(t)),
        if (things.isNotEmpty) DCard(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: Column(children: [for (final a in things) row(a)])),
        const SectionLabel('Debiti'),
        if (debts.isEmpty) Text('Nessun debito.', style: TS.muted(t)),
        if (debts.isNotEmpty) DCard(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: Column(children: [for (final a in debts) row(a)])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GhostButton(label: 'Aggiungi bene', icon: Icons.add_rounded, onTap: () => push(context, const AssetEditor()))),
          const SizedBox(width: 10),
          Expanded(child: GhostButton(label: 'Aggiungi debito', icon: Icons.add_rounded, onTap: () => push(context, const AssetEditor(debt: true)))),
        ]),
      ]),
    );
  }
}

class AssetEditor extends StatefulWidget {
  final Asset? asset;
  final bool debt;
  const AssetEditor({super.key, this.asset, this.debt = false});
  @override
  State<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<AssetEditor> {
  late String _kind;
  final _name = TextEditingController();
  final _value = TextEditingController();
  final _rate = TextEditingController();
  final _monthly = TextEditingController();
  bool _inFi = false;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _kind = a?.kind ?? (widget.debt ? AssetKind.debt : AssetKind.pension);
    if (a != null) {
      _name.text = a.name;
      _value.text = centsToField(a.value);
      _rate.text = a.rate == 0 ? '' : fDec(a.rate, 2, true);
      _monthly.text = centsToField(a.monthly);
      _inFi = a.inFi;
    } else {
      _inFi = _kind == AssetKind.pension;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _value, _rate, _monthly]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final app = context.appRead;
    final name = _name.text.trim().isEmpty ? AssetKind.labels[_kind]! : _name.text.trim();
    app.saveAsset(Asset(
      id: widget.asset?.id ?? newId(),
      name: name,
      kind: _kind,
      value: (parseMoney(_value.text) ?? 0).abs(),
      rate: parseNum(_rate.text) ?? 0,
      monthly: (parseMoney(_monthly.text) ?? 0).abs(),
      updated: todayKey(),
      inFi: _kind == AssetKind.debt ? false : _inFi,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final isDebt = _kind == AssetKind.debt;
    return SubPage(
      title: widget.asset == null ? (isDebt ? 'Nuovo debito' : 'Nuovo bene') : 'Modifica',
      actions: [
        if (widget.asset != null)
          IconSquare(
            icon: Icons.delete_outline_rounded,
            color: TC.neg,
            onTap: () async {
              final ok = await confirm(context, title: 'Eliminare?', body: '${widget.asset!.name} non conterà più nel patrimonio.', ok: 'Elimina', danger: true);
              if (!ok || !context.mounted) return;
              context.appRead.deleteAsset(widget.asset!);
              Navigator.pop(context);
            },
          ),
      ],
      bottom: BottomActions(children: [PrimaryButton(label: 'Salva', icon: Icons.check_rounded, onTap: _save)]),
      body: PageBody(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in AssetKind.labels.entries)
            if (widget.asset == null || (e.key == AssetKind.debt) == isDebt)
              PillChip(label: e.value, icon: assetIcon(e.key), selected: _kind == e.key, onTap: () => setState(() {
                    _kind = e.key;
                    _inFi = e.key == AssetKind.pension;
                  })),
        ]),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: InputDecoration(labelText: isDebt ? 'Nome (es. Prestito auto, Mutuo)' : 'Nome (es. Fondo pensione, Casa)')),
        const SizedBox(height: 12),
        MoneyField(controller: _value, label: isDebt ? 'Debito residuo' : 'Valore di oggi'),
        const SizedBox(height: 12),
        TextField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: isDebt ? 'TAN %' : 'Rendimento atteso annuo % (facoltativo)', helperText: isDebt ? 'Dal ${fDec(expensiveDebtRate, 0)}% in su il coach lo considera costoso.' : null),
        ),
        const SizedBox(height: 12),
        MoneyField(controller: _monthly, label: isDebt ? 'Rata mensile' : 'Versamento mensile (facoltativo)'),
        if (!isDebt)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Conta per l\'indipendenza finanziaria'),
            subtitle: const Text('Sì per fondo pensione e beni che rendono; no per la casa in cui vivi e l\'auto.'),
            value: _inFi,
            onChanged: (v) => setState(() => _inFi = v),
          ),
        if (widget.asset != null) Text('Ultimo aggiornamento: ${shortDateY(fromKey(widget.asset!.updated))}', style: TS.muted(t, 12)),
        if (isDebt) const NoteBox('Le rate le puoi inserire anche come scadenza (categoria "Rate e prestiti"): così entrano nella previsione del conto.'),
      ]),
    );
  }
}
