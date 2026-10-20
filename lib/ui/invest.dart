import 'dart:async';

import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../logic/invest.dart';
import '../services/prices.dart';
import '../services/services.dart';
import 'assets.dart';
import 'charts.dart';
import 'widgets.dart';

Color kindColor(String k) => switch (k) {
      HoldingKind.etf => TC.series[0],
      HoldingKind.stock => TC.series[4],
      HoldingKind.bond => TC.series[2],
      HoldingKind.crypto => TC.series[3],
      HoldingKind.deposit => TC.series[1],
      HoldingKind.fund => TC.series[5],
      _ => TC.series[8],
    };

IconData kindIcon(String k) => switch (k) {
      HoldingKind.crypto => Icons.currency_bitcoin_rounded,
      HoldingKind.deposit => Icons.savings_rounded,
      HoldingKind.bond => Icons.account_balance_rounded,
      HoldingKind.stock => Icons.business_rounded,
      _ => Icons.show_chart_rounded,
    };

/// Scheda Investimenti.
class InvestTab extends StatelessWidget {
  const InvestTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final pf = app.portfolio;
    final open = pf.open..sort((a, b) => b.value.compareTo(a.value));
    final closed = pf.positions.where((p) => !open.contains(p)).toList();
    final byKind = pf.byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final things = app.things.fold(0, (a, x) => a + x.value);
    final debts = app.debts.fold(0, (a, x) => a + x.value);
    return ListenableBuilder(
      listenable: Services.prices,
      builder: (context, _) {
        final ps = Services.prices;
        return PageBody(maxWidth: 820, children: [
          TabHeader(title: 'Investimenti', actions: [
            ps.busy
                ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconSquare(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Aggiorna prezzi',
                    onTap: () async {
                      final err = await ps.refresh(force: true);
                      if (context.mounted) toast(context, err ?? 'Prezzi aggiornati');
                    },
                  ),
            IconSquare(icon: Icons.add_rounded, tooltip: 'Nuovo investimento', onTap: () => push(context, const HoldingEditor())),
          ]),
          DCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('VALORE INVESTITO', style: TS.label(t)),
              const SizedBox(height: 6),
              Money(pf.value, size: 30, weight: FontWeight.w700, dec: false),
              const SizedBox(height: 4),
              if (pf.cost > 0)
                Text('${moneyText(context, pf.unrealized, sign: true, dec: false)} (${fPctSigned(pf.cost > 0 ? pf.unrealized / pf.cost : 0)}) non realizzati',
                    style: TextStyle(fontSize: 13.5, color: pf.unrealized >= 0 ? TC.pos : TC.neg, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              KV('Rendita netta prevista', '${moneyText(context, (pf.annualIncomeNet / 12).round(), dec: false)} al mese'),
              KV('Tasse se vendessi tutto oggi', moneyText(context, pf.taxIfSold, dec: false)),
              KV('Imposta di bollo stimata', '${moneyText(context, pf.stampDuty, dec: false)} all\'anno'),
              if (pf.realized != 0) KV('Plus/minus realizzate', moneyText(context, pf.realized, sign: true, dec: false)),
              const SizedBox(height: 6),
              Text(
                app.prefs.pricesAt == 0
                    ? 'Prezzi non ancora aggiornati'
                    : 'Prezzi aggiornati ${relDay(DateTime.fromMillisecondsSinceEpoch(app.prefs.pricesAt)).toLowerCase()} alle ${hhmm(DateTime.fromMillisecondsSinceEpoch(app.prefs.pricesAt))}',
                style: TS.muted(t, 11.5),
              ),
              if (ps.lastError != null) Text(ps.lastError!, style: const TextStyle(fontSize: 11.5, color: TC.warn)),
            ]),
          ),
          if (byKind.length > 1)
            DCard(
              child: Donut(
                items: [for (final e in byKind) (HoldingKind.labels[e.key] ?? e.key, e.value, kindColor(e.key))],
                centerTop: fCompact(pf.value),
                centerBottom: 'allocazione',
              ),
            ),
          if (open.isEmpty)
            EmptyState(
              icon: Icons.show_chart_rounded,
              title: 'Nessun investimento',
              body: 'ETF, azioni, crypto, BTP, conti deposito: aggiungili per vedere valore, rendimento e tasse.',
              action: 'Aggiungi',
              onAction: () => push(context, const HoldingEditor()),
            ),
          if (open.isNotEmpty) ...[
            const SectionLabel('Posizioni'),
            DCard(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Column(children: [for (final p in open) _PositionRow(p: p)]),
            ),
          ],
          const SectionLabel('Beni e debiti'),
          DCard(
            onTap: () => push(context, const AssetsScreen()),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.home_work_outlined, color: TC.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pensione, immobili, debiti', style: TS.title(t)),
                  Text('Beni ${moneyText(context, things, dec: false)} · debiti ${moneyText(context, debts, dec: false)}', style: TS.muted(t, 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: t.dim),
            ]),
          ),
          if (closed.isNotEmpty) ...[
            const SectionLabel('Chiuse'),
            DCard(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: Column(children: [for (final p in closed) _PositionRow(p: p)])),
          ],
          const SizedBox(height: 6),
          Text('Tasse stimate con le aliquote italiane (26%, 12,5% sui titoli di Stato, 33% sulle crypto dal 2026): verifica sempre con il tuo intermediario.',
              style: TS.muted(t, 11.5)),
        ]);
      },
    );
  }
}

class _PositionRow extends StatelessWidget {
  final Position p;
  const _PositionRow({required this.p});
  @override
  Widget build(BuildContext context) {
    final h = p.h;
    final pl = p.unrealized;
    final sub = h.isDeposit
        ? '${HoldingKind.labels[h.kind]} · ${fDec(h.rate, 2, true)}%${h.maturity != null ? ' · scade ${shortDateY(fromKey(h.maturity!))}' : ''}'
        : '${HoldingKind.labels[h.kind]} · ${fDec(p.qty, 4, true)} ${h.isBond ? 'nominale' : 'quote'}${p.stalePrice ? ' · prezzo vecchio' : ''}${p.priceSrc == 'manuale' ? ' · prezzo a mano' : ''}';
    return RowTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: kindColor(h.kind).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
        child: Icon(kindIcon(h.kind), size: 19, color: kindColor(h.kind)),
      ),
      title: h.name,
      subtitle: sub,
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Money(p.value, dec: false),
        if (p.cost > 0 && p.qty > 0)
          Text('${fPctSigned(p.unrealizedPct)} · ${moneyText(context, pl, sign: true, dec: false)}',
              style: TextStyle(fontSize: 11.5, color: pl >= 0 ? TC.pos : TC.neg, fontWeight: FontWeight.w600)),
      ]),
      onTap: () => push(context, HoldingScreen(holdingId: h.id)),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    );
  }
}

/// Dettaglio di un investimento: numeri, prezzo e operazioni.
class HoldingScreen extends StatelessWidget {
  final String holdingId;
  const HoldingScreen({super.key, required this.holdingId});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final h = app.holding(holdingId);
    if (h == null) return const SubPage(title: 'Investimento', body: SizedBox());
    final p = app.position(h);
    final trades = app.tradesByHolding[h.id] ?? const <Trade>[];
    final cur = h.currency;
    return SubPage(
      title: h.name,
      actions: [IconSquare(icon: Icons.edit_outlined, onTap: () => push(context, HoldingEditor(holding: h)))],
      bottom: h.isDeposit
          ? null
          : BottomActions(children: [
              GhostButton(
                label: 'Prezzo a mano',
                icon: Icons.edit_note_rounded,
                onTap: () async {
                  final v = await askText(context,
                      title: 'Prezzo attuale per ${h.isBond ? '100 di nominale' : 'quota'}',
                      initial: p.price == null ? '' : fDec(p.price!, 4, true),
                      body: 'Usalo se il prezzo online manca o è sbagliato. Vale finché non arriva un prezzo online più recente.');
                  final n = v == null ? null : parseNum(v);
                  if (n == null) return;
                  h
                    ..manualPrice = n
                    ..manualAt = DateTime.now().millisecondsSinceEpoch;
                  app.saveHolding(h);
                },
              ),
              PrimaryButton(label: 'Operazione', icon: Icons.add_rounded, onTap: () => push(context, TradeEditor(holding: h))),
            ]),
      body: PageBody(children: [
        DCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('VALORE', style: TS.label(t)),
            const SizedBox(height: 6),
            Money(p.value, size: 28, weight: FontWeight.w700),
            if (p.cost > 0)
              Text('${moneyText(context, p.unrealized, sign: true)} (${fPctSigned(p.unrealizedPct)})',
                  style: TextStyle(fontSize: 13.5, color: p.unrealized >= 0 ? TC.pos : TC.neg, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (!h.isDeposit) ...[
              KV('Quantità', fDec(p.qty, 6, true)),
              KV('Prezzo medio di carico', p.qty > 0 ? '${fDec(p.avgPrice * (h.isBond ? 100 : 1), 4, true)} €' : '–'),
              KV('Prezzo attuale', p.price == null ? 'non disponibile' : '${fDec(p.price!, 4, true)} ${curSymbol(cur)}'),
              if (p.priceAt > 0)
                Text('${p.priceSrc == 'manuale' ? 'Scritto a mano' : 'Online'} · ${shortDateY(DateTime.fromMillisecondsSinceEpoch(p.priceAt))} ${hhmm(DateTime.fromMillisecondsSinceEpoch(p.priceAt))}',
                    style: TS.muted(t, 11.5)),
            ] else ...[
              KV('Capitale', moneyText(context, h.principal)),
              KV('Tasso lordo', '${fDec(h.rate, 2, true)}%'),
              if (h.start != null) KV('Dal', shortDateY(fromKey(h.start!))),
              if (h.maturity != null) KV('Scadenza', shortDateY(fromKey(h.maturity!))),
              KV('Interessi netti maturati', moneyText(context, p.value - h.principal)),
            ],
            KV('Costo', moneyText(context, p.cost)),
            KV('Tasse se vendessi oggi (${fDec(h.taxRate, 1, true)}%)', moneyText(context, p.taxIfSold)),
            KV('Valore netto', moneyText(context, p.netValue), strong: true),
            if (p.realized != 0) KV('Realizzato', moneyText(context, p.realized, sign: true)),
            if (p.income != 0) KV('Dividendi e cedole incassati', moneyText(context, p.income)),
            KV('Rendita netta annua prevista', moneyText(context, annualIncome(p))),
          ]),
        ),
        if (h.isin.isNotEmpty || h.symbol.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text([if (h.isin.isNotEmpty) 'ISIN ${h.isin}', if (h.symbol.isNotEmpty) 'Simbolo ${h.symbol}'].join(' · '), style: TS.muted(t, 12)),
          ),
        if (!h.isDeposit) ...[
          SectionLabel('Operazioni (${trades.length})'),
          if (trades.isEmpty) Text('Nessuna operazione: aggiungi il primo acquisto.', style: TS.muted(t)),
          if (trades.isNotEmpty)
            DCard(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Column(children: [
                for (final tr in trades)
                  RowTile(
                    leading: Icon(
                      switch (tr.type) {
                        TradeType.buy => Icons.add_circle_outline_rounded,
                        TradeType.sell => Icons.remove_circle_outline_rounded,
                        TradeType.fee => Icons.receipt_outlined,
                        _ => Icons.payments_outlined,
                      },
                      color: tr.type == TradeType.sell || tr.type == TradeType.dividend || tr.type == TradeType.coupon ? TC.pos : t.soft,
                    ),
                    title: TradeType.labels[tr.type] ?? tr.type,
                    subtitle: '${shortDateY(fromKey(tr.date))}${tr.qty > 0 ? ' · ${fDec(tr.qty, 6, true)} a ${fDec(tr.price, 4, true)}' : ''}${tr.txId != null ? ' · dal conto' : ''}',
                    trailing: Text(fMoney(tr.amount), style: TS.num(t, 13.5)),
                    onTap: () => push(context, TradeEditor(holding: h, trade: tr)),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// Nuovo investimento o modifica.
class HoldingEditor extends StatefulWidget {
  final Holding? holding;
  const HoldingEditor({super.key, this.holding});
  @override
  State<HoldingEditor> createState() => _HoldingEditorState();
}

class _HoldingEditorState extends State<HoldingEditor> {
  String _kind = HoldingKind.etf;
  final _name = TextEditingController();
  final _symbol = TextEditingController();
  final _isin = TextEditingController();
  final _tax = TextEditingController();
  final _rate = TextEditingController();
  final _principal = TextEditingController();
  final _search = TextEditingController();
  // primo acquisto
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _fees = TextEditingController();
  String _buyDate = todayKey();
  String _cur = 'EUR';
  bool _pct = false;
  String? _start;
  String? _maturity;
  String? _acc;
  bool _archived = false;
  List<SymbolHit> _hits = [];
  bool _searching = false;
  Timer? _debounce;

  bool get _editing => widget.holding != null;

  @override
  void initState() {
    super.initState();
    final h = widget.holding;
    if (h != null) {
      _kind = h.kind;
      _name.text = h.name;
      _symbol.text = h.symbol;
      _isin.text = h.isin;
      _tax.text = fDec(h.taxRate, 2, true);
      _rate.text = h.rate == 0 ? '' : fDec(h.rate, 3, true);
      _principal.text = centsToField(h.principal);
      _cur = h.currency;
      _pct = h.pricePct;
      _start = h.start;
      _maturity = h.maturity;
      _acc = h.accountId;
      _archived = h.archived;
    } else {
      _tax.text = fDec(HoldingKind.defaultTax(_kind), 2, true);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _symbol, _isin, _tax, _rate, _principal, _search, _qty, _price, _fees]) {
      c.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (q.trim().length < 2) return setState(() => _hits = []);
      setState(() => _searching = true);
      final r = _kind == HoldingKind.crypto ? await PriceService.searchCrypto(q) : await PriceService.searchSecurities(q);
      if (!mounted) return;
      setState(() {
        _hits = r;
        _searching = false;
      });
    });
  }

  Future<void> _pickHit(SymbolHit h) async {
    setState(() {
      _symbol.text = h.symbol;
      if (_name.text.trim().isEmpty) _name.text = h.name;
      if (RegExp(r'^[A-Z]{2}[A-Z0-9]{9}\d$').hasMatch(_search.text.trim().toUpperCase())) _isin.text = _search.text.trim().toUpperCase();
      _hits = [];
    });
    if (_kind != HoldingKind.crypto) {
      final q = await PriceService.fetchYahoo(h.symbol);
      if (q != null && mounted) {
        setState(() {
          _cur = q.currency;
          if (_price.text.isEmpty) _price.text = fDec(q.price, 4, true);
        });
        context.appRead.saveQuote(q);
      }
    }
  }

  void _save() {
    final app = context.appRead;
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Dagli un nome');
      return;
    }
    final h = Holding(
      id: widget.holding?.id ?? newId(),
      name: name,
      kind: _kind,
      isin: _isin.text.trim().toUpperCase(),
      symbol: _symbol.text.trim(),
      currency: _cur,
      accountId: _acc,
      taxRate: parseNum(_tax.text) ?? HoldingKind.defaultTax(_kind),
      manualPrice: widget.holding?.manualPrice ?? 0,
      manualAt: widget.holding?.manualAt ?? 0,
      pricePct: _kind == HoldingKind.bond ? _pct : false,
      rate: parseNum(_rate.text) ?? 0,
      principal: _kind == HoldingKind.deposit ? (parseMoney(_principal.text) ?? 0).abs() : 0,
      start: _kind == HoldingKind.deposit ? (_start ?? todayKey()) : null,
      maturity: _maturity,
      archived: _archived,
    );
    app.store.batch(() {
      app.saveHolding(h);
      final qty = parseNum(_qty.text);
      final price = parseNum(_price.text);
      if (!_editing && _kind != HoldingKind.deposit && qty != null && qty > 0 && price != null && price > 0) {
        final unit = h.pricePct ? price / 100 : price;
        app.saveTrade(
          Trade(
            id: newId(),
            holdingId: h.id,
            date: _buyDate,
            type: TradeType.buy,
            qty: qty,
            price: price,
            amount: app.eur((qty * unit * 100).round(), _cur),
            fees: (parseMoney(_fees.text) ?? 0).abs(),
          ),
          cashAccountId: _acc,
        );
      }
    });
    unawaited(Services.prices.refresh(force: true));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final app = context.appRead;
    final ok = await confirm(context,
        title: 'Eliminare ${widget.holding!.name}?', body: 'Si eliminano anche le operazioni e i movimenti collegati sul conto.', ok: 'Elimina', danger: true);
    if (!ok || !mounted) return;
    app.deleteHolding(widget.holding!);
    Navigator.of(context)
      ..pop()
      ..maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final deposit = _kind == HoldingKind.deposit;
    final brokers = app.accounts.where((a) => a.type == AccountType.broker || a.type == AccountType.conto || a.type == AccountType.crypto).toList();
    return SubPage(
      title: _editing ? 'Modifica investimento' : 'Nuovo investimento',
      actions: [if (_editing) IconSquare(icon: Icons.delete_outline_rounded, color: TC.neg, onTap: _delete)],
      bottom: BottomActions(children: [PrimaryButton(label: 'Salva', icon: Icons.check_rounded, onTap: _save)]),
      body: PageBody(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in HoldingKind.labels.entries)
            PillChip(
              label: e.value,
              icon: kindIcon(e.key),
              selected: _kind == e.key,
              onTap: () => setState(() {
                _kind = e.key;
                _tax.text = fDec(HoldingKind.defaultTax(e.key), 2, true);
                _hits = [];
                if (e.key == HoldingKind.bond) _pct = true;
              }),
            ),
        ]),
        const SizedBox(height: 16),
        if (!deposit && _kind != HoldingKind.other) ...[
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: _kind == HoldingKind.crypto ? 'Cerca la crypto (es. bitcoin)' : 'Cerca per ISIN, ticker o nome',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
            onChanged: _onSearch,
          ),
          for (final h in _hits)
            RowTile(
              title: h.name,
              subtitle: '${h.symbol} · ${h.exchange}${h.type.isNotEmpty ? ' · ${h.type}' : ''}',
              onTap: () => _pickHit(h),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
          const SizedBox(height: 12),
        ],
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
        const SizedBox(height: 12),
        if (!deposit)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _symbol,
                decoration: InputDecoration(labelText: _kind == HoldingKind.crypto ? 'Id CoinGecko' : 'Simbolo Yahoo (es. VWCE.DE)'),
              ),
            ),
            const SizedBox(width: 10),
            if (_kind != HoldingKind.crypto) Expanded(child: TextField(controller: _isin, decoration: const InputDecoration(labelText: 'ISIN'))),
          ]),
        if (!deposit) ...[
          const SizedBox(height: 12),
          Row(children: [
            Text('Valuta del prezzo', style: TS.soft(t)),
            const SizedBox(width: 12),
            for (final c in ['EUR', 'USD', 'GBP', 'CHF']) ...[PillChip(label: c, selected: _cur == c, onTap: () => setState(() => _cur = c)), const SizedBox(width: 6)],
          ]),
        ],
        if (_kind == HoldingKind.bond)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Prezzo in % del nominale'),
            subtitle: const Text('Come si quotano BTP e obbligazioni (100 = alla pari). La quantità è il nominale in euro.'),
            value: _pct,
            onChanged: (v) => setState(() => _pct = v),
          ),
        if (deposit) ...[
          MoneyField(controller: _principal, label: 'Capitale versato'),
          const SizedBox(height: 12),
        ],
        if (deposit || _kind == HoldingKind.bond) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: deposit ? 'Tasso lordo annuo %' : 'Cedola lorda annua %'),
          ),
          const SizedBox(height: 6),
          if (deposit)
            RowTile(
              leading: Icon(Icons.event_rounded, color: t.soft),
              title: 'Data di apertura',
              subtitle: _start == null ? 'Oggi' : longDate(fromKey(_start!)),
              onTap: () async {
                final d = await pickDay(context, _start ?? todayKey());
                if (d != null) setState(() => _start = d);
              },
            ),
          RowTile(
            leading: Icon(Icons.event_available_rounded, color: t.soft),
            title: 'Scadenza',
            subtitle: _maturity == null ? 'Nessuna' : longDate(fromKey(_maturity!)),
            onTap: () async {
              final d = await pickDay(context, _maturity ?? addDaysKey(todayKey(), 365));
              if (d != null) setState(() => _maturity = d);
            },
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _tax,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Aliquota sulle plusvalenze %', helperText: '26% in generale, 12,5% titoli di Stato, 33% crypto'),
        ),
        if (brokers.isNotEmpty) ...[
          const SectionLabel('Conto della liquidità'),
          Text('Se scegli un conto, acquisti e vendite muovono il suo saldo (es. liquidità del broker).', style: TS.muted(t, 12.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            PillChip(label: 'Nessuno', selected: _acc == null, onTap: () => setState(() => _acc = null)),
            for (final a in brokers) PillChip(label: a.name, icon: accountIcon(a.type), selected: _acc == a.id, onTap: () => setState(() => _acc = a.id)),
          ]),
        ],
        if (!_editing && !deposit) ...[
          const SectionLabel('Quanto ne hai'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _kind == HoldingKind.bond ? 'Nominale' : 'Quantità'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Prezzo medio pagato', suffixText: _pct ? '%' : curSymbol(_cur)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: MoneyField(controller: _fees, label: 'Commissioni')),
            const SizedBox(width: 10),
            Expanded(
              child: RowTile(
                title: 'Data',
                subtitle: shortDateY(fromKey(_buyDate)),
                onTap: () async {
                  final d = await pickDay(context, _buyDate);
                  if (d != null) setState(() => _buyDate = d);
                },
              ),
            ),
          ]),
          Text('Se hai comprato in più volte, metti il prezzo medio: le altre operazioni le aggiungi dopo.', style: TS.muted(t, 12)),
        ],
        if (_editing)
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Archiviato'), value: _archived, onChanged: (v) => setState(() => _archived = v)),
      ]),
    );
  }
}

/// Acquisto, vendita, dividendo, cedola o costo.
class TradeEditor extends StatefulWidget {
  final Holding holding;
  final Trade? trade;
  const TradeEditor({super.key, required this.holding, this.trade});
  @override
  State<TradeEditor> createState() => _TradeEditorState();
}

class _TradeEditorState extends State<TradeEditor> {
  String _type = TradeType.buy;
  String _date = todayKey();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _amount = TextEditingController();
  final _fees = TextEditingController();
  String? _acc;
  bool _amountTouched = false;

  @override
  void initState() {
    super.initState();
    final tr = widget.trade;
    if (tr != null) {
      _type = tr.type;
      _date = tr.date;
      _qty.text = tr.qty == 0 ? '' : fDec(tr.qty, 6, true);
      _price.text = tr.price == 0 ? '' : fDec(tr.price, 4, true);
      _amount.text = centsToField(tr.amount);
      _fees.text = centsToField(tr.fees);
      _amountTouched = true;
      _acc = context.appRead.tx(tr.txId)?.accountId;
    } else {
      _acc = widget.holding.accountId;
    }
  }

  @override
  void dispose() {
    for (final c in [_qty, _price, _amount, _fees]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasQty => _type == TradeType.buy || _type == TradeType.sell;

  void _recalc() {
    if (_amountTouched || !_hasQty) return;
    final q = parseNum(_qty.text), p = parseNum(_price.text);
    if (q == null || p == null) return;
    final h = widget.holding;
    final unit = h.pricePct ? p / 100 : p;
    _amount.text = centsToField(context.appRead.eur((q * unit * 100).round(), h.currency));
  }

  void _save() {
    final app = context.appRead;
    final amount = (parseMoney(_amount.text) ?? 0).abs();
    if (amount == 0) {
      toast(context, 'Manca l\'importo');
      return;
    }
    final tr = Trade(
      id: widget.trade?.id ?? newId(),
      holdingId: widget.holding.id,
      date: _date,
      type: _type,
      qty: _hasQty ? (parseNum(_qty.text) ?? 0).abs() : 0,
      price: _hasQty ? (parseNum(_price.text) ?? 0).abs() : 0,
      amount: amount,
      fees: (parseMoney(_fees.text) ?? 0).abs(),
      txId: widget.trade?.txId,
    );
    app.saveTrade(tr, cashAccountId: _acc);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = context.tt;
    final h = widget.holding;
    return SubPage(
      title: widget.trade == null ? 'Nuova operazione' : 'Modifica operazione',
      actions: [
        if (widget.trade != null)
          IconSquare(
            icon: Icons.delete_outline_rounded,
            color: TC.neg,
            onTap: () async {
              final ok = await confirm(context, title: 'Eliminare l\'operazione?', body: 'Si elimina anche il movimento sul conto, se c\'è.', ok: 'Elimina', danger: true);
              if (!ok || !context.mounted) return;
              app.deleteTrade(widget.trade!);
              Navigator.pop(context);
            },
          ),
      ],
      bottom: BottomActions(children: [PrimaryButton(label: 'Salva', icon: Icons.check_rounded, onTap: _save)]),
      body: PageBody(children: [
        Text(h.name, style: TS.title(t)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in TradeType.labels.entries) PillChip(label: e.value, selected: _type == e.key, onTap: () => setState(() => _type = e.key)),
        ]),
        const SizedBox(height: 16),
        if (_hasQty)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: h.isBond ? 'Nominale' : 'Quantità'),
                onChanged: (_) => setState(_recalc),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Prezzo', suffixText: h.pricePct ? '%' : curSymbol(h.currency)),
                onChanged: (_) => setState(_recalc),
              ),
            ),
          ]),
        if (_hasQty) const SizedBox(height: 12),
        MoneyField(
          controller: _amount,
          label: switch (_type) {
            TradeType.buy => 'Controvalore pagato (senza commissioni)',
            TradeType.sell => 'Controvalore incassato (senza commissioni)',
            TradeType.fee => 'Costo',
            _ => 'Importo netto incassato',
          },
          onChanged: (_) => _amountTouched = true,
        ),
        if (_hasQty || _type == TradeType.fee) ...[const SizedBox(height: 12), MoneyField(controller: _fees, label: 'Commissioni')],
        const SizedBox(height: 6),
        RowTile(
          leading: Icon(Icons.event_rounded, color: t.soft),
          title: 'Data',
          subtitle: longDate(fromKey(_date)),
          onTap: () async {
            final d = await pickDay(context, _date);
            if (d != null) setState(() => _date = d);
          },
        ),
        const SectionLabel('Movimento sul conto'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillChip(label: 'Nessuno', selected: _acc == null, onTap: () => setState(() => _acc = null)),
          for (final a in app.accounts) PillChip(label: a.name, icon: accountIcon(a.type), selected: _acc == a.id, onTap: () => setState(() => _acc = a.id)),
        ]),
        const SizedBox(height: 8),
        Text('Con un conto, Dollarz registra anche l\'uscita o l\'entrata di liquidità (non conta come spesa).', style: TS.muted(t, 12)),
      ]),
    );
  }
}
