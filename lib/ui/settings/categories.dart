import 'package:flutter/material.dart';

import '../../core/fmt.dart';
import '../../core/money.dart';
import '../../core/ids.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../widgets.dart';

/// Categorie (nome, budget, secchio, nascoste) e regole imparate.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _kind = CatKind.expense;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final list = app.catsOfKind(_kind, withHidden: true);
    return SubPage(
      title: 'Categorie',
      actions: [
        IconSquare(icon: Icons.rule_rounded, tooltip: 'Regole', onTap: () => push(context, const RulesScreen())),
        IconSquare(icon: Icons.add_rounded, tooltip: 'Nuova categoria', onTap: () => _edit(context, null, _kind)),
      ],
      body: PageBody(children: [
        Seg<String>(
          options: const [(CatKind.expense, 'Uscite'), (CatKind.income, 'Entrate'), (CatKind.transfer, 'Altro')],
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 14),
        if (_kind == CatKind.expense) Text('Tocca una categoria per il budget mensile e il secchio (necessità o desideri).', style: TS.muted(t, 12.5)),
        if (_kind == CatKind.transfer) Text('Giroconti, investimenti e rettifiche non contano né come spese né come entrate.', style: TS.muted(t, 12.5)),
        const SizedBox(height: 8),
        DCard(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Column(children: [
            for (final c in list)
              RowTile(
                leading: Opacity(opacity: c.hidden ? 0.4 : 1, child: CatIcon(c, size: 36)),
                title: c.name,
                titleColor: c.hidden ? t.dim : null,
                subtitle: [
                  if (c.isExpense) Bucket.labels[c.bucket] ?? '',
                  if (c.budget > 0) 'budget ${moneyText(context, c.budget, dec: false)}',
                  if (c.hidden) 'nascosta',
                ].where((s) => s.isNotEmpty).join(' · '),
                onTap: () => _edit(context, c, _kind),
              ),
          ]),
        ),
      ]),
    );
  }
}

Future<void> _edit(BuildContext context, Category? c, String kind) async {
  final app = context.appRead;
  final name = TextEditingController(text: c?.name ?? '');
  final budget = TextEditingController(text: c == null ? '' : centsToField(c.budget));
  var bucket = c?.bucket ?? Bucket.want;
  var icon = c?.icon ?? 'more';
  var hidden = c?.hidden ?? false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setS) {
        final t = sheet.tt;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(c == null ? 'Nuova categoria' : c.name, style: TS.h2(t)),
              const SizedBox(height: 14),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
              if (kind == CatKind.expense) ...[
                const SizedBox(height: 12),
                MoneyField(controller: budget, label: 'Budget mensile (vuoto = nessuno)'),
                const SizedBox(height: 12),
                Seg<String>(options: const [(Bucket.need, 'Necessità'), (Bucket.want, 'Desideri')], value: bucket == Bucket.future ? Bucket.want : bucket, onChanged: (v) => setS(() => bucket = v)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in catIcons.entries)
                  Tap(
                    radius: 10,
                    onTap: () => setS(() => icon = e.key),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: icon == e.key ? TC.accent.withValues(alpha: 0.25) : t.surf2, borderRadius: BorderRadius.circular(10)),
                      child: Icon(e.value, size: 19, color: icon == e.key ? TC.accent : t.soft),
                    ),
                  ),
              ]),
              if (c != null)
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Nascosta'), subtitle: const Text('Non compare nelle scelte.'), value: hidden, onChanged: (v) => setS(() => hidden = v)),
              const SizedBox(height: 14),
              Row(children: [
                if (c != null && c.custom)
                  Expanded(
                    child: GhostButton(
                      label: 'Elimina',
                      color: TC.neg,
                      onTap: () {
                        app.deleteCategory(c);
                        Navigator.pop(sheet);
                      },
                    ),
                  ),
                if (c != null && c.custom) const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Salva',
                    onTap: () {
                      final n = name.text.trim();
                      if (n.isEmpty) return;
                      final cat = Category(
                        id: c?.id ?? 'c_${newId()}',
                        name: n,
                        icon: icon,
                        kind: c?.kind ?? kind,
                        bucket: kind == CatKind.expense ? bucket : Bucket.future,
                        budget: (parseMoney(budget.text) ?? 0).abs(),
                        hidden: hidden,
                        custom: c?.custom ?? true,
                      );
                      app.saveCategory(cat);
                      Navigator.pop(sheet);
                    },
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    ),
  );
}

/// Regole "se la descrizione contiene X → categoria Y", imparate dalle tue correzioni.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final rules = app.rules;
    return SubPage(
      title: 'Regole',
      actions: [
        IconSquare(
          icon: Icons.add_rounded,
          onTap: () async {
            final p = await askText(context, title: 'Se la descrizione contiene…', hint: 'es. esselunga');
            if (p == null || p.trim().length < 2 || !context.mounted) return;
            final cat = await pickFrom<String>(context,
                title: 'Categoria', items: [for (final c in app.cats.values.where((c) => !c.hidden)) (c.id, c.name, null)], leading: (id) => CatIcon(app.cat(id), size: 30));
            if (cat == null) return;
            app.saveRule(Rule(id: newId(), pattern: fold(p.trim()), catId: cat));
          },
        ),
      ],
      body: PageBody(children: [
        Text('Quando cambi la categoria di un movimento, Dollarz crea o aggiorna una regola. Le regole vincono su quelle di base.', style: TS.muted(t, 12.5)),
        const SizedBox(height: 12),
        if (rules.isEmpty) Text('Ancora nessuna regola.', style: TS.muted(t)),
        if (rules.isNotEmpty)
          DCard(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Column(children: [
              for (final r in rules)
                RowTile(
                  leading: CatIcon(app.cat(r.catId), size: 32),
                  title: '"${r.pattern}"',
                  subtitle: '→ ${app.cat(r.catId)?.name ?? r.catId}',
                  trailing: IconButton(onPressed: () => app.deleteRule(r), icon: Icon(Icons.delete_outline_rounded, color: t.dim, size: 20)),
                ),
            ]),
          ),
      ]),
    );
  }
}
