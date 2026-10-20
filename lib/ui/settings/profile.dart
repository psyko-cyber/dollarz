import 'package:flutter/material.dart';

import '../../core/fmt.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../logic/projection.dart';
import '../widgets.dart';

/// Profilo, obiettivi e ipotesi delle proiezioni.
class ProfileScreen extends StatefulWidget {
  final bool goalsFirst;
  const ProfileScreen({super.key, this.goalsFirst = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Profile _p;
  final _name = TextEditingController();
  final _income = TextEditingController();
  final _expenses = TextEditingController();
  final _passive = TextEditingController();
  final _wealth = TextEditingController();
  final _r = [TextEditingController(), TextEditingController(), TextEditingController()];
  final _infl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _p = Profile.fromMap(context.appRead.profile.toMap());
    _name.text = _p.name;
    _income.text = centsToField(_p.incomeMonthly);
    _expenses.text = centsToField(_p.expensesMonthly);
    _passive.text = centsToField(_p.targetPassive);
    _wealth.text = centsToField(_p.targetWealth);
    for (var i = 0; i < 3; i++) {
      _r[i].text = fDec(i < _p.returns.length ? _p.returns[i] : [2.0, 4.0, 6.0][i], 1, true);
    }
    _infl.text = fDec(_p.inflation, 1, true);
  }

  @override
  void dispose() {
    for (final c in [_name, _income, _expenses, _passive, _wealth, _infl, ..._r]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final app = context.appRead;
    _p
      ..name = _name.text.trim()
      ..incomeMonthly = (parseMoney(_income.text) ?? 0).abs()
      ..expensesMonthly = (parseMoney(_expenses.text) ?? 0).abs()
      ..targetPassive = (parseMoney(_passive.text) ?? 0).abs()
      ..targetWealth = (parseMoney(_wealth.text) ?? 0).abs()
      ..inflation = parseNum(_infl.text) ?? 2
      ..returns = [for (var i = 0; i < 3; i++) parseNum(_r[i].text) ?? [2.0, 4.0, 6.0][i]];
    app.saveProfile(_p);
    Navigator.pop(context);
    toast(context, 'Profilo salvato');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final expenses = app.usingHistory ? app.monthlyExpenses : ((parseMoney(_expenses.text) ?? 0).abs());
    final fi = fiNumber(expenses * 12, _p.swr);

    final money = <Widget>[
      const SectionLabel('Tu'),
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Come ti chiami')),
      const SizedBox(height: 12),
      MoneyField(controller: _income, label: 'Entrate nette al mese', helper: 'Stipendio netto più entrate fisse. Quando ci sono 2 mesi di movimenti uso quelli.'),
      const SizedBox(height: 12),
      MoneyField(controller: _expenses, label: 'Spese al mese', helper: 'Tutto: affitto, bollette, spesa, svago. Una stima va bene.', onChanged: (_) => setState(() {})),
      if (app.usingHistory)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Dai movimenti degli ultimi mesi: entrate ${moneyText(context, app.monthlyIncome, dec: false)}, spese ${moneyText(context, app.monthlyExpenses, dec: false)} al mese.',
              style: TS.muted(t, 12.5)),
        ),
      const SectionLabel('Risparmio'),
      Row(children: [
        Expanded(child: Text('Quota da risparmiare e investire', style: TS.soft(t))),
        Text('${_p.savingsTargetPct.round()}%', style: TS.num(t, 15)),
      ]),
      Slider(value: _p.savingsTargetPct.clamp(5, 60), min: 5, max: 60, divisions: 11, onChanged: (v) => setState(() => _p.savingsTargetPct = v)),
      Row(children: [
        Expanded(child: Text('Fondo emergenza', style: TS.soft(t))),
        Text('${_p.emergencyMonths} mesi di spese', style: TS.num(t, 15)),
      ]),
      Slider(value: _p.emergencyMonths.toDouble(), min: 3, max: 12, divisions: 9, onChanged: (v) => setState(() => _p.emergencyMonths = v.round())),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Fondamenta nel percorso'),
        subtitle: const Text('Scadenze coperte e fondo emergenza come prime tappe del coach.'),
        value: _p.foundations,
        onChanged: (v) => setState(() => _p.foundations = v),
      ),
    ];
    final goals = <Widget>[
      const SectionLabel('Obiettivi'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Indipendenza finanziaria'),
        subtitle: Text(expenses > 0 ? 'Capitale per vivere di rendita: ${fEuro(fi)}' : 'Il capitale per vivere di rendita (spese annue ÷ tasso di prelievo)'),
        value: _p.goalFi,
        onChanged: (v) => setState(() => _p.goalFi = v),
      ),
      const SizedBox(height: 6),
      MoneyField(controller: _passive, label: 'Rendita passiva mensile desiderata', helper: 'Vuoto se non ti interessa.'),
      const SizedBox(height: 12),
      MoneyField(controller: _wealth, label: 'Patrimonio da raggiungere', helper: 'Es. 100.000 €. Vuoto se non ti interessa.'),
      const SectionLabel('Ipotesi'),
      Text('Tasso di prelievo sostenibile', style: TS.soft(t)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final s in [(4.0, '4% classico'), (3.5, '3,5% prudente'), (3.0, '3% molto prudente')])
          PillChip(label: s.$2, selected: _p.swr == s.$1, onTap: () => setState(() => _p.swr = s.$1)),
      ]),
      const SizedBox(height: 14),
      Text('Rendimenti reali annui degli scenari (già al netto dell\'inflazione)', style: TS.soft(t)),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _r[i],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: ['Prudente', 'Realistico', 'Ottimista'][i], suffixText: '%'),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _infl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Inflazione attesa', suffixText: '%', helperText: 'Serve per stimare quanto perde la liquidità ferma.'),
      ),
    ];
    return SubPage(
      title: widget.goalsFirst ? 'Obiettivi' : 'Profilo e obiettivi',
      bottom: BottomActions(children: [PrimaryButton(label: 'Salva', icon: Icons.check_rounded, onTap: _save)]),
      body: PageBody(children: widget.goalsFirst ? [...goals, ...money] : [...money, ...goals]),
    );
  }
}
