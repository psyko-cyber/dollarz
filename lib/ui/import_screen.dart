import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../logic/import_parse.dart';
import '../services/services.dart';
import 'accounts.dart';
import 'widgets.dart';

/// Import di un estratto conto (CSV, Excel): riconosce il formato, scarta i
/// doppioni, collega i movimenti già arrivati dalle notifiche.
class ImportScreen extends StatefulWidget {
  final String? path;
  final String? accountId;
  const ImportScreen({super.key, this.path, this.accountId});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportFile? _file;
  String _name = '';
  String? _error;
  String? _acc;
  String? _group;
  bool _pending = false;
  bool _invert = false;
  bool _anchor = true;
  bool _busy = false;
  BuildResult? _built;
  List<PlanItem> _plan = [];

  @override
  void initState() {
    super.initState();
    _acc = widget.accountId;
    if (widget.path != null) WidgetsBinding.instance.addPostFrameCallback((_) => _load(File(widget.path!)));
  }

  Future<void> _pick() async {
    final x = await Services.lock.withoutLock(() => openFile(acceptedTypeGroups: const [
          XTypeGroup(label: 'Estratti conto', extensions: ['csv', 'xlsx', 'xls', 'txt', 'tsv']),
        ]));
    if (x == null) return;
    setState(() => _busy = true);
    try {
      _analyze(await x.readAsBytes(), x.name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(File f) async {
    setState(() => _busy = true);
    try {
      _analyze(await f.readAsBytes(), f.uri.pathSegments.last);
    } catch (e) {
      setState(() => _error = 'Non riesco a leggere il file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _analyze(Uint8List bytes, String name) {
    final app = context.appRead;
    try {
      final f = analyzeBytes(bytes, name: name);
      _file = f;
      _name = name;
      _error = null;
      if (_acc == null) {
        final bank = f.format == 'generico' ? null : f.format;
        _acc = (bank == null ? null : app.accountForBank(bank))?.id ?? app.mainAccount?.id;
      }
      final all = buildRows(f);
      _group = mainGroup(all.groups);
      if (_group != null) {
        // per Revolut: il gruppo nella valuta del conto, se c'è
        final acc = app.account(_acc);
        final match = all.groups.keys.where((g) => acc != null && g.endsWith(acc.currency)).toList();
        if (match.isNotEmpty) _group = match.reduce((a, b) => (all.groups[b] ?? 0) > (all.groups[a] ?? 0) ? b : a);
      }
      _rebuild();
    } on ImportError catch (e) {
      setState(() {
        _file = null;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _file = null;
        _error = 'File non riconosciuto: $e';
      });
    }
  }

  void _rebuild() {
    final f = _file;
    if (f == null) return;
    final app = context.appRead;
    final b = f.complete ? buildRows(f, includePending: _pending, invert: _invert, group: _group, defaultCurrency: app.account(_acc)?.currency ?? 'EUR') : null;
    setState(() {
      _built = b;
      _plan = b == null || _acc == null ? [] : planImport(b.rows, app.txsOf(_acc!));
    });
  }

  Future<void> _import() async {
    final app = context.appRead;
    final acc = app.account(_acc);
    final b = _built;
    if (acc == null || b == null) return;
    var added = 0, linked = 0;
    app.store.batch(() {
      for (final p in _plan) {
        if (!p.selected) continue;
        final r = p.row;
        if (p.dup == DupKind.likely && p.match != null) {
          final t = p.match!;
          t.importKey = r.key;
          t.date = r.date;
          t.catId ??= r.catHint ?? app.suggestCat(r.desc, r.amount);
          if (t.desc.isEmpty) t.desc = r.desc;
          app.saveTx(t);
          linked++;
        } else if (p.dup == DupKind.none) {
          app.addTx(
            amount: r.amount,
            accountId: acc.id,
            catId: r.catHint ?? app.suggestCat(r.desc, r.amount),
            desc: r.desc,
            date: r.date,
            src: 'import',
            importKey: r.key,
            suggest: false,
          );
          added++;
        }
      }
    });
    final anchor = anchorFromRows(b.rows, dayFirst: _file!.dayFirst);
    if (_anchor && anchor != null) app.setBalance(acc, anchor.$2, date: anchor.$1);
    final matched = app.matchScheduled();
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, 'Importati $added movimenti${linked > 0 ? ', $linked collegati a quelli già presenti' : ''}${matched > 0 ? ', $matched scadenze segnate pagate' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final f = _file;
    final b = _built;
    final acc = app.account(_acc);
    final toAdd = _plan.where((p) => p.selected && p.dup == DupKind.none).length;
    final toLink = _plan.where((p) => p.selected && p.dup == DupKind.likely).length;
    final already = _plan.where((p) => p.dup == DupKind.imported).length;
    final anchor = b == null ? null : anchorFromRows(b.rows, dayFirst: f!.dayFirst);
    final groups = f == null ? <String, int>{} : buildRows(f).groups;
    final otherCur = b != null && acc != null && b.rows.any((r) => r.currency != acc.currency);

    return SubPage(
      title: 'Importa estratto',
      bottom: f == null || b == null
          ? null
          : BottomActions(children: [
              PrimaryButton(
                label: toAdd + toLink == 0 ? 'Niente di nuovo' : 'Importa $toAdd${toLink > 0 ? ' + $toLink da collegare' : ''}',
                icon: Icons.download_done_rounded,
                onTap: toAdd + toLink == 0 || acc == null ? null : _import,
              ),
            ]),
      body: PageBody(children: [
        if (f == null) ...[
          const SizedBox(height: 8),
          Text('Dall\'app della banca esporta i movimenti (CSV o Excel) e condividili con Dollarz, oppure scegli il file qui.', style: TS.soft(t)),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Scegli il file', icon: Icons.folder_open_rounded, busy: _busy, onTap: _pick),
          const SizedBox(height: 16),
          if (_error != null) NoteBox(_error!, icon: Icons.error_outline_rounded, color: TC.neg),
          const SectionLabel('Dove trovo l\'export'),
          const NoteBox('Revolut: Conto → … → Estratto conto → Excel o CSV, scegli il periodo e condividi.', icon: Icons.lightbulb_outline_rounded),
          const NoteBox('Fineco: dal sito, Conto corrente → Movimenti → Esporta in Excel.', icon: Icons.lightbulb_outline_rounded),
          const NoteBox('Trade Republic: Profilo → Attività → Esporta (o un estratto in CSV).', icon: Icons.lightbulb_outline_rounded),
          Text('I movimenti già importati vengono riconosciuti e saltati: puoi importare periodi che si sovrappongono.', style: TS.muted(t, 12.5)),
        ] else ...[
          DCard(
            child: Row(children: [
              const Icon(Icons.description_outlined, color: TC.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name, style: TS.title(t), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${f.formatLabel} · ${f.dataRows.length} righe', style: TS.muted(t, 12.5)),
                ]),
              ),
              SmallButton(label: 'Cambia', onTap: _pick),
            ]),
          ),
          const SectionLabel('Su quale conto'),
          if (app.accounts.isEmpty)
            SmallButton(label: 'Crea un conto', icon: Icons.add_rounded, onTap: () => push(context, const AccountEditor()))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in app.accounts)
                PillChip(
                  label: a.name,
                  icon: accountIcon(a.type),
                  selected: a.id == _acc,
                  onTap: () {
                    _acc = a.id;
                    _rebuild();
                  },
                ),
            ]),
          if (groups.length > 1) ...[
            const SectionLabel('Parte del file'),
            Text('Il file contiene più conti o valute: scegli quella di questo conto.', style: TS.muted(t, 12.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in groups.entries)
                PillChip(
                  label: '${g.key.isEmpty ? 'Senza nome' : g.key} (${g.value})',
                  selected: g.key == _group,
                  onTap: () {
                    _group = g.key;
                    _rebuild();
                  },
                ),
            ]),
          ],
          if (!f.complete || b == null) ...[
            const SectionLabel('Colonne'),
            const NoteBox('Non ho riconosciuto tutte le colonne: indica quale è la data e quale l\'importo.', color: TC.warn),
          ],
          _ColumnsCard(file: f, onChanged: _rebuild),
          if (b != null) ...[
            const SectionLabel('Opzioni'),
            DCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Column(children: [
                if (b.pending > 0 || _pending)
                  CheckboxListTile(
                    value: _pending,
                    onChanged: (v) {
                      _pending = v ?? false;
                      _rebuild();
                    },
                    title: Text('Includi i ${b.pending} movimenti in attesa'),
                    subtitle: const Text('Di solito si importano solo quelli completati.'),
                  ),
                CheckboxListTile(
                  value: _invert,
                  onChanged: (v) {
                    _invert = v ?? false;
                    _rebuild();
                  },
                  title: const Text('Inverti entrate e uscite'),
                  subtitle: const Text('Se le spese risultano come entrate.'),
                ),
                if (anchor != null)
                  CheckboxListTile(
                    value: _anchor,
                    onChanged: (v) => setState(() => _anchor = v ?? true),
                    title: Text('Saldo del conto a ${fMoney(anchor.$2, cur: acc?.currency ?? 'EUR')}'),
                    subtitle: Text('Come risulta nel file al ${shortDateY(fromKey(anchor.$1))}.'),
                  ),
              ]),
            ),
            if (otherCur) NoteBox('Alcune righe sono in una valuta diversa da quella del conto (${acc.currency}).', color: TC.warn),
            SectionLabel('Anteprima'),
            Text(
              [
                '$toAdd nuovi',
                if (toLink > 0) '$toLink già presenti da notifica o a mano (verranno collegati)',
                if (already > 0) '$already già importati',
                if (b.cancelled > 0) '${b.cancelled} annullati',
                if (b.invalid > 0) '${b.invalid} righe non lette',
              ].join(' · '),
              style: TS.muted(t, 12.5),
            ),
            const SizedBox(height: 10),
            DCard(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(children: [
                for (final p in _plan.reversed.take(120)) _PlanRow(item: p, cur: acc?.currency ?? 'EUR', onChanged: () => setState(() {})),
                if (_plan.length > 120) Padding(padding: const EdgeInsets.all(10), child: Text('… e altri ${_plan.length - 120}', style: TS.muted(t))),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

class _ColumnsCard extends StatelessWidget {
  final ImportFile file;
  final VoidCallback onChanged;
  const _ColumnsCard({required this.file, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final f = file;
    const keys = [Col.date, Col.desc, Col.amount, Col.income, Col.expense, Col.desc2, Col.balance, Col.state, Col.currency];
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      initiallyExpanded: !f.complete,
      title: Text('Colonne riconosciute', style: TS.title(t)),
      subtitle: Text([for (final k in keys) if (f.map[k] != null) Col.labels[k]].join(', '), style: TS.muted(t, 12), maxLines: 2),
      children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 150, child: Text(Col.labels[k]!, style: TS.soft(t))),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: f.map[k] ?? -1,
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('—')),
                    for (var i = 0; i < f.headers.length; i++) DropdownMenuItem(value: i, child: Text(f.headers[i], overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v == null || v < 0) {
                      f.map.remove(k);
                    } else {
                      f.map[k] = v;
                    }
                    onChanged();
                  },
                ),
              ),
            ]),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  final PlanItem item;
  final String cur;
  final VoidCallback onChanged;
  const _PlanRow({required this.item, required this.cur, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final r = item.row;
    final (label, color) = switch (item.dup) {
      DupKind.imported => ('già importato', t.dim),
      DupKind.likely => ('già presente', TC.warn),
      DupKind.none => ('nuovo', TC.pos),
    };
    return Row(children: [
      Checkbox(
        value: item.selected,
        onChanged: item.dup == DupKind.imported
            ? null
            : (v) {
                item.selected = v ?? false;
                onChanged();
              },
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.desc.isEmpty ? '(senza descrizione)' : r.desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: t.ink)),
          Row(children: [
            Text(shortDateY(fromKey(r.date)), style: TS.muted(t, 11.5)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
            if (item.match != null) Flexible(child: Text(' · ${item.match!.desc}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.muted(t, 11.5))),
          ]),
        ]),
      ),
      const SizedBox(width: 8),
      Text(fMoney(r.amount, cur: r.currency, sign: r.amount > 0), style: TS.num(t, 13.5, color: r.amount > 0 ? TC.pos : t.ink)),
      const SizedBox(width: 6),
    ]);
  }
}
