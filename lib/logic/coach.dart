import 'dart:math' as math;

import '../core/fmt.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'budget.dart';
import 'projection.dart';

const coachDisclaimer =
    'Indicazioni educative basate su principi classici di finanza personale: non sono consulenza finanziaria abilitata.';

/// Debiti con un TAN da qui in su si chiudono prima di investire.
const expensiveDebtRate = 6.0;

/// Dove porta il bottone di una mossa o di un avviso.
class CoachRoute {
  static const scadenze = 'scadenze';
  static const movimenti = 'movimenti';
  static const budget = 'budget';
  static const investimenti = 'investimenti';
  static const futuro = 'futuro';
  static const patrimonio = 'patrimonio';
  static const debiti = 'debiti';
  static const inbox = 'inbox';
  static const profilo = 'profilo';
  static const conti = 'conti';
}

/// I numeri che servono al coach, già calcolati e in euro (centesimi).
class CoachInput {
  final Profile profile;
  final int liquid;
  final int invested;

  /// Beni che contano per l'indipendenza (fondo pensione…).
  final int fiAssets;
  final int netWorth;
  final List<Asset> debts;

  /// Medie mensili dello storico (o, senza storico, quelle dichiarate nel profilo).
  final int income;
  final int expenses;
  final int investedMonthly;
  final int historyMonths;

  /// Rendita netta annua che gli investimenti danno oggi.
  final int passiveYearly;

  // scadenze e previsione
  final String? redAccount;
  final String? redDate;
  final int redAmount;
  final int overdueCount;
  final int overdueAmount;

  /// Uscite programmate nei prossimi 30 giorni (positivo).
  final int due30;

  // mese in corso e pulizia
  final List<BudgetLine> budget;
  final int uncategorized;
  final int inbox;
  final int stalePrices;
  final int subsMonthly;
  final int subsCount;
  final double? lastSavingRate;
  final double? prevSavingRate;
  final String? lastMonth;

  /// Categoria dei desideri che pesa di più (nome, media al mese).
  final (String, int)? topWant;

  const CoachInput({
    required this.profile,
    this.liquid = 0,
    this.invested = 0,
    this.fiAssets = 0,
    this.netWorth = 0,
    this.debts = const [],
    this.income = 0,
    this.expenses = 0,
    this.investedMonthly = 0,
    this.historyMonths = 0,
    this.passiveYearly = 0,
    this.redAccount,
    this.redDate,
    this.redAmount = 0,
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.due30 = 0,
    this.budget = const [],
    this.uncategorized = 0,
    this.inbox = 0,
    this.stalePrices = 0,
    this.subsMonthly = 0,
    this.subsCount = 0,
    this.lastSavingRate,
    this.prevSavingRate,
    this.lastMonth,
    this.topWant,
  });

  int get saving => income - expenses;
  double get savingRate => income > 0 ? saving / income : 0;

  /// Liquidità che resta dopo le uscite già programmate del mese.
  int get liquidFree => math.max(0, liquid - due30);
  int get fund1 => expenses;
  int get fundFull => expenses * math.max(1, profile.emergencyMonths);

  /// Capitale che lavora per l'indipendenza: investimenti, beni "FI" e liquidità oltre il fondo.
  int get fiCapital => invested + fiAssets + math.max(0, liquidFree - (profile.foundations ? fundFull : fund1));

  /// Quanto si può mettere da parte al mese per gli obiettivi.
  int get monthlyContribution => math.max(0, saving);
}

enum PathState { done, current, todo, off }

class CoachStep {
  final String id;
  final String title;

  /// Cosa vuol dire completarla.
  final String goal;
  final double progress;

  /// Dove sei: "3.200 € su 9.000 €".
  final String status;
  PathState state;

  CoachStep(this.id, this.title, this.goal, this.progress, this.status, {this.state = PathState.todo});
  bool get done => state == PathState.done;
}

class NextMove {
  final String stepId;
  final String title;
  final String text;
  final String route;
  final String cta;
  const NextMove(this.stepId, this.title, this.text, this.route, this.cta);
}

enum AlertLevel { danger, warn, info, good }

class CoachAlert {
  final String id;
  final AlertLevel level;
  final String title;
  final String text;
  final String route;
  const CoachAlert(this.id, this.level, this.title, this.text, this.route);
}

/// Un obiettivo misurato: dove sei, dove vuoi arrivare e quando ci arrivi.
class Goal {
  final String id; // fi | passive | wealth
  final String title;
  final int target;
  final int current;
  final int monthly;

  /// Mesi per arrivarci in ciascuno scenario (null = oltre 80 anni).
  final List<int?> months;
  final List<double> rates;
  const Goal(this.id, this.title, this.target, this.current, this.monthly, this.months, this.rates);

  double get progress => target > 0 ? clamp01(current / target) : 0;
  bool get reached => target > 0 && current >= target;

  /// Scenario realistico (quello in mezzo).
  int? get monthsRealistic => months.length > 1 ? months[1] : (months.isEmpty ? null : months.first);
}

class CoachResult {
  final List<CoachStep> steps;
  final NextMove move;
  final List<CoachAlert> alerts;
  final List<Goal> goals;
  const CoachResult(this.steps, this.move, this.alerts, this.goals);

  List<CoachStep> get active => steps.where((s) => s.state != PathState.off).toList();
  CoachStep? get current => steps.where((s) => s.state == PathState.current).firstOrNull;

  /// "Tappa 3 di 6".
  int get level {
    final a = active;
    final i = a.indexWhere((s) => s.state == PathState.current);
    return i < 0 ? a.length : i + 1;
  }
}

String _months(int? m) => m == null ? 'oltre 80 anni' : fYearsMonths(m);

String _when(int? m) {
  if (m == null) return 'non in questa vita, con questi numeri';
  if (m == 0) return 'già raggiunto';
  final d = dateAfterMonths(m);
  return '${_months(m)} (${mesi[d.month - 1]} ${d.year})';
}

int? _monthsToSave(int missing, int perMonth) => perMonth <= 0 ? null : (missing / perMonth).ceil();

/// Mesi per chiudere un debito pagando [payment] al mese.
int? debtPayoffMonths(int left, double rate, int payment) {
  if (left <= 0) return 0;
  if (payment <= 0) return null;
  final r = rate / 100 / 12;
  var b = left.toDouble();
  for (var m = 1; m <= 600; m++) {
    b = b * (1 + r) - payment;
    if (b <= 0) return m;
  }
  return null;
}

List<Goal> coachGoals(CoachInput i) {
  final p = i.profile;
  final rates = p.returns.isEmpty ? const [2.0, 4.0, 6.0] : p.returns;
  final out = <Goal>[];
  final monthly = i.monthlyContribution;
  List<int?> monthsFor(int start, int target) => [for (final r in rates) monthsToTarget(start, monthly, r, target)];

  if (p.goalFi && i.expenses > 0) {
    final target = fiNumber(i.expenses * 12, p.swr);
    out.add(Goal('fi', 'Indipendenza finanziaria', target, i.fiCapital, monthly, monthsFor(i.fiCapital, target), rates));
  }
  if (p.targetPassive > 0) {
    final target = capitalForIncome(p.targetPassive, p.swr);
    out.add(Goal('passive', 'Rendita di ${fEuro(p.targetPassive)} al mese', target, i.fiCapital, monthly,
        monthsFor(i.fiCapital, target), rates));
  }
  if (p.targetWealth > 0) {
    out.add(Goal('wealth', 'Patrimonio di ${fEuro(p.targetWealth)}', p.targetWealth, i.netWorth, monthly,
        monthsFor(i.netWorth, p.targetWealth), rates));
  }
  return out;
}

/// Il coach: percorso a tappe, la prossima mossa e gli avvisi.
CoachResult runCoach(CoachInput i) {
  final p = i.profile;
  final e = i.expenses;
  final steps = <CoachStep>[];
  final goals = coachGoals(i);

  // 1. scadenze coperte
  final redOk = i.redDate == null;
  steps.add(CoachStep(
    'scadenze',
    'Scadenze coperte',
    'Nessun conto in rosso nei prossimi 90 giorni e niente scadenze in sospeso.',
    redOk && i.overdueCount == 0 ? 1 : 0,
    !redOk
        ? '${i.redAccount ?? 'Un conto'} va a ${fEuro(i.redAmount)} ${_dayLabel(i.redDate!)}'
        : i.overdueCount > 0
            ? '${i.overdueCount} ${i.overdueCount == 1 ? 'scadenza passata' : 'scadenze passate'} da segnare'
            : 'Tutto coperto per i prossimi 90 giorni',
    state: redOk && i.overdueCount == 0 ? PathState.done : PathState.todo,
  ));

  // 2. cuscinetto: un mese di spese
  final hasExpenses = e > 0;
  final p1 = hasExpenses ? clamp01(i.liquidFree / i.fund1) : 0.0;
  steps.add(CoachStep(
    'cuscinetto',
    'Primo cuscinetto',
    'Un mese di spese da parte, oltre alle scadenze del mese.',
    p1,
    hasExpenses ? '${fEuro(math.min(i.liquidFree, i.fund1))} su ${fEuro(i.fund1)}' : 'Servono le tue spese mensili',
    state: hasExpenses && p1 >= 1 ? PathState.done : PathState.todo,
  ));

  // 3. debiti costosi
  final costly = i.debts.where((d) => d.value > 0 && d.rate >= expensiveDebtRate).toList()..sort((a, b) => b.rate.compareTo(a.rate));
  final costlyLeft = costly.fold(0, (a, d) => a + d.value);
  steps.add(CoachStep(
    'debiti',
    'Debiti costosi azzerati',
    'Nessun prestito o carta con TAN dal ${fDec(expensiveDebtRate, 0)}% in su.',
    costly.isEmpty ? 1 : 0,
    costly.isEmpty ? 'Nessun debito costoso' : '${costly.length} da chiudere: ${fEuro(costlyLeft)}',
    state: costly.isEmpty ? PathState.done : PathState.todo,
  ));

  // 4. fondo emergenza pieno
  final pf = hasExpenses ? clamp01(i.liquidFree / i.fundFull) : 0.0;
  steps.add(CoachStep(
    'fondo',
    'Fondo emergenza',
    '${p.emergencyMonths} mesi di spese su un conto separato.',
    pf,
    hasExpenses ? '${fEuro(math.min(i.liquidFree, i.fundFull))} su ${fEuro(i.fundFull)}' : 'Servono le tue spese mensili',
    state: hasExpenses && pf >= 1 ? PathState.done : PathState.todo,
  ));

  // 5. investimento regolare
  final investTarget = (i.income * p.savingsTargetPct / 100).round();
  final excess = i.liquidFree - (p.foundations ? i.fundFull : i.fund1);
  final idleCash = hasExpenses && excess > math.max(3 * e, 300000);
  final pi = investTarget > 0 ? clamp01(i.investedMonthly / investTarget) : 0.0;
  steps.add(CoachStep(
    'investi',
    'Investimento regolare',
    'Ogni mese il ${fDec(p.savingsTargetPct, 0)}% delle entrate va a investimenti, in automatico.',
    pi,
    investTarget > 0 ? '${fEuro(i.investedMonthly)} al mese su ${fEuro(investTarget)}' : 'Servono le tue entrate mensili',
    state: investTarget > 0 && i.investedMonthly >= investTarget * 0.9 && !idleCash ? PathState.done : PathState.todo,
  ));

  // 6. obiettivi
  final g = goals.firstOrNull;
  steps.add(CoachStep(
    'obiettivi',
    'I tuoi obiettivi',
    g == null ? 'Scegli dove vuoi arrivare: rendita, patrimonio o indipendenza.' : g.title,
    g?.progress ?? 0,
    g == null ? 'Nessun obiettivo scelto' : '${fEuro(g.current)} su ${fEuro(g.target)} · ${fPct(g.progress, 0)}',
    state: g != null && goals.every((x) => x.reached) ? PathState.done : PathState.todo,
  ));

  if (!p.foundations) {
    for (final s in steps) {
      if (s.id == 'scadenze' || s.id == 'cuscinetto' || s.id == 'fondo') s.state = PathState.off;
    }
  }
  final firstOpen = steps.where((s) => s.state == PathState.todo).firstOrNull;
  firstOpen?.state = PathState.current;

  final move = _move(i, firstOpen?.id, costly, goals, idleCash, excess, investTarget);
  final alerts = _alerts(i, move, idleCash, excess, goals);
  return CoachResult(steps, move, alerts, goals);
}

String _dayLabel(String k) {
  final d = fromKey(k);
  final n = daysBetween(today(), d);
  return n <= 1 ? inDays(n) : 'il ${shortDate(d)}';
}

const _noData = NextMove(
      'start',
      'Dimmi quanto entra e quanto esce',
      'Senza entrate e spese mensili non posso calcolare né il fondo emergenza né la tua data di indipendenza. Bastano due cifre indicative: le correggo io con i movimenti veri.',
      CoachRoute.profilo,
      'Imposta il profilo',
    );

NextMove _move(CoachInput i, String? stepId, List<Asset> costly, List<Goal> goals, bool idleCash, int excess, int investTarget) {
  final p = i.profile;
  final saving = i.saving;
  if (i.expenses <= 0 && i.income <= 0) return _noData;

  // prima di tutto: spendere meno di quanto entra
  if (saving < 0 && stepId != 'scadenze') {
    final tw = i.topWant;
    return NextMove(
      'risparmio',
      'Smetti di andare sotto',
      'Ogni mese esce ${fEuro(-saving)} più di quanto entra: nessun piano regge così. '
          '${tw != null ? 'La voce più pesante tra i desideri è ${tw.$1} (${fEuro(tw.$2)} al mese): parti da lì. ' : ''}'
          'Obiettivo minimo: chiudere il mese in pari.',
      CoachRoute.budget,
      'Apri il budget',
    );
  }

  switch (stepId) {
    case 'scadenze':
      if (i.redDate != null) {
        return NextMove(
          'scadenze',
          'Copri ${i.redAccount ?? 'il conto'}',
          '${_dayLabel(i.redDate!)[0].toUpperCase()}${_dayLabel(i.redDate!).substring(1)} il saldo previsto scende a ${fEuro(i.redAmount)}. '
              'Sposta almeno ${fEuro(-i.redAmount)} su ${i.redAccount ?? 'quel conto'} prima di quella data.',
          CoachRoute.scadenze,
          'Vedi la previsione',
        );
      }
      return NextMove(
        'scadenze',
        'Segna le scadenze passate',
        '${i.overdueCount} ${i.overdueCount == 1 ? 'scadenza risulta' : 'scadenze risultano'} non pagate (${fEuro(i.overdueAmount.abs())}). '
            'Segnale come pagate o saltate: così la previsione dei conti resta vera.',
        CoachRoute.scadenze,
        'Apri le scadenze',
      );
    case 'cuscinetto':
      final missing = i.fund1 - i.liquidFree;
      final m = _monthsToSave(missing, saving);
      return NextMove(
        'cuscinetto',
        'Metti da parte ${fEuro(missing)}',
        'È il primo cuscinetto: un mese di spese pronto per gli imprevisti. '
            '${m != null ? 'Con il risparmio di ${fEuro(saving)} al mese ci arrivi in ${_months(m)}.' : 'Serve prima un mese chiuso in positivo.'}',
        CoachRoute.conti,
        'Vedi i conti',
      );
    case 'debiti':
      final d = costly.first;
      final extra = math.max(0, (saving * 0.7).round());
      final base = debtPayoffMonths(d.value, d.rate, d.monthly);
      final fast = debtPayoffMonths(d.value, d.rate, d.monthly + extra);
      final gain = base != null && fast != null ? base - fast : null;
      return NextMove(
        'debiti',
        'Chiudi ${d.name}',
        'Ha un TAN del ${fDec(d.rate, 1, true)}%: ogni euro restituito prima "rende" il ${fDec(d.rate, 1, true)}% sicuro, più di qualunque investimento prudente. '
            '${extra > 0 ? 'Aggiungi ${fEuro(extra)} al mese alla rata${gain != null && gain > 0 ? ': lo chiudi ${_months(gain)} prima' : ''}.' : 'Appena hai risparmio libero, va qui.'}',
        CoachRoute.debiti,
        'Vedi i debiti',
      );
    case 'fondo':
      final missing = i.fundFull - i.liquidFree;
      final m = _monthsToSave(missing, saving);
      return NextMove(
        'fondo',
        'Porta il fondo a ${p.emergencyMonths} mesi',
        'Mancano ${fEuro(missing)} per arrivare a ${fEuro(i.fundFull)}. Tienili su un conto separato, meglio se remunerato, e non toccarli. '
            '${m != null ? 'Al ritmo attuale: ${_months(m)}.' : ''}',
        CoachRoute.conti,
        'Vedi i conti',
      );
    case 'investi':
      if (idleCash) {
        final loss = (excess * p.inflation / 100).round();
        return NextMove(
          'investi',
          'Fai lavorare ${fEuro(excess)}',
          'Sono fermi oltre il fondo emergenza: con l\'inflazione al ${fDec(p.inflation, 1, true)}% perdono circa ${fEuro(loss)} di valore all\'anno. '
              'Valuta di investirne una parte con ingressi a rate (PAC), su strumenti diversificati e a basso costo.',
          CoachRoute.investimenti,
          'Vai agli investimenti',
        );
      }
      if (saving < investTarget) {
        final gap = investTarget - (saving > 0 ? saving : 0);
        final tw = i.topWant;
        return NextMove(
          'investi',
          'Libera ${fEuro(gap)} al mese',
          'Oggi risparmi ${fEuro(math.max(0, saving))} al mese (${fPct(i.savingRate, 0)}); l\'obiettivo è il ${fDec(p.savingsTargetPct, 0)}% delle entrate, ${fEuro(investTarget)}. '
              '${tw != null ? 'Tagliare del 30% ${tw.$1} vale ${fEuro((tw.$2 * 0.3).round())} al mese.' : ''}',
          CoachRoute.budget,
          'Apri il budget',
        );
      }
      return NextMove(
        'investi',
        'Automatizza ${fEuro(investTarget)} al mese',
        'Imposta un versamento automatico verso gli investimenti il giorno dopo lo stipendio: quello che non vedi non lo spendi. '
            'Poi registralo in Dollarz come scadenza, così te lo ricordo.',
        CoachRoute.scadenze,
        'Crea la scadenza',
      );
    case 'obiettivi':
      final g = goals.firstOrNull;
      if (g == null) {
        return const NextMove(
          'obiettivi',
          'Scegli un obiettivo',
          'Una cifra di rendita al mese, un patrimonio da raggiungere o l\'indipendenza finanziaria. Con una meta precisa ti dico ogni mese se sei in linea.',
          CoachRoute.futuro,
          'Imposta gli obiettivi',
        );
      }
      final rate = g.rates.length > 1 ? g.rates[1] : g.rates.first;
      final faster = monthsToTarget(g.current, g.monthly + 10000, rate, g.target);
      final m = g.monthsRealistic;
      final gain = m != null && faster != null ? m - faster : null;
      return NextMove(
        'obiettivi',
        g.title,
        'Con ${fEuro(g.monthly)} al mese ci arrivi in ${_when(m)}, nello scenario realistico (${fDec(rate, 1, true)}% reale). '
            '${gain != null && gain > 0 ? 'Con 100 € in più al mese: ${_months(gain)} prima.' : ''}',
        CoachRoute.futuro,
        'Vedi le proiezioni',
      );
  }
  return const NextMove(
    'fatto',
    'Tutto in ordine',
    'Fondamenta solide, investimento regolare e obiettivi raggiunti. Alza l\'asticella: un nuovo obiettivo o un tasso di risparmio più alto.',
    CoachRoute.futuro,
    'Nuovo obiettivo',
  );
}

List<CoachAlert> _alerts(CoachInput i, NextMove move, bool idleCash, int excess, List<Goal> goals) {
  final out = <CoachAlert>[];
  if (i.redDate != null && move.stepId != 'scadenze') {
    out.add(CoachAlert('red', AlertLevel.danger, '${i.redAccount ?? 'Un conto'} andrà in rosso',
        'Saldo previsto ${fEuro(i.redAmount)} ${_dayLabel(i.redDate!)}.', CoachRoute.scadenze));
  }
  if (i.overdueCount > 0 && move.stepId != 'scadenze') {
    out.add(CoachAlert('overdue', AlertLevel.warn, 'Scadenze da segnare',
        '${i.overdueCount} non risultano pagate: segnale per tenere vera la previsione.', CoachRoute.scadenze));
  }
  for (final b in i.budget) {
    if (b.over) {
      out.add(CoachAlert('over:${b.cat.id}', AlertLevel.danger, '${b.cat.name} fuori budget',
          '${fEuro(b.spent)} su ${fEuro(b.budget)}: ${fEuro(-b.left)} oltre.', CoachRoute.budget));
    } else if (b.atRisk) {
      out.add(CoachAlert('risk:${b.cat.id}', AlertLevel.warn, '${b.cat.name} sta correndo',
          'Al ritmo attuale arrivi a ${fEuro(b.projected)} su ${fEuro(b.budget)}.', CoachRoute.budget));
    }
  }
  final last = i.lastSavingRate, prev = i.prevSavingRate;
  if (last != null && prev != null && last < prev - 0.05) {
    out.add(CoachAlert('rate', AlertLevel.warn, 'Risparmio in calo',
        '${i.lastMonth != null ? 'A ${monthLabel(i.lastMonth!)}' : 'L\'ultimo mese'} hai risparmiato il ${fPct(math.max(0, last), 0)} delle entrate, contro il ${fPct(prev, 0)} dei mesi prima.',
        CoachRoute.budget));
  }
  if (idleCash && move.stepId != 'investi') {
    out.add(CoachAlert('idle', AlertLevel.info, 'Liquidità ferma',
        '${fEuro(excess)} oltre il fondo emergenza non rendono nulla.', CoachRoute.investimenti));
  }
  if (i.subsCount >= 3) {
    out.add(CoachAlert('subs', AlertLevel.info, '${i.subsCount} abbonamenti',
        '${fEuro(i.subsMonthly)} al mese, ${fEuro(i.subsMonthly * 12)} all\'anno: disdici quelli che non usi da un mese.',
        CoachRoute.scadenze));
  }
  if (i.inbox > 0) {
    out.add(CoachAlert('inbox', AlertLevel.info, 'Da confermare',
        '${i.inbox} ${i.inbox == 1 ? 'notifica' : 'notifiche'} della banca da controllare.', CoachRoute.inbox));
  }
  if (i.uncategorized > 0) {
    out.add(CoachAlert('uncat', AlertLevel.info, 'Senza categoria',
        '${i.uncategorized} movimenti del mese senza categoria: il budget non li vede.', CoachRoute.movimenti));
  }
  if (i.stalePrices > 0) {
    out.add(CoachAlert('prices', AlertLevel.info, 'Prezzi vecchi',
        '${i.stalePrices} titoli hanno il prezzo fermo da più di 5 giorni.', CoachRoute.investimenti));
  }
  for (final g in goals) {
    if (g.reached) {
      out.add(CoachAlert('goal:${g.id}', AlertLevel.good, 'Obiettivo raggiunto', '${g.title}: fatto. Ora scegli il prossimo.', CoachRoute.futuro));
    }
  }
  return out;
}
