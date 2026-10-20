import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';

Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

// =================================================================== layout

/// Corpo pagina: colonna centrata con larghezza massima (desktop) e padding.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;
  final ScrollController? controller;
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 96), this.maxWidth = 760, this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.zero,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          ),
        ),
      ],
    );
  }
}

/// Due colonne su schermi larghi, una sola sul telefono.
class TwoCols extends StatelessWidget {
  final List<Widget> left;
  final List<Widget> right;
  final double breakpoint;
  const TwoCols({super.key, required this.left, required this.right, this.breakpoint = 1100});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, ...right]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 11, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
        const SizedBox(width: 20),
        Expanded(flex: 9, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
      ]);
    });
  }
}

/// Barra inferiore fissa con i bottoni di una schermata.
class BottomActions extends StatelessWidget {
  final List<Widget> children;
  const BottomActions({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.line))),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: children[i])],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Schermata secondaria con freccia indietro.
class SubPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;
  final Widget? fab;
  const SubPage({super.key, required this.title, required this.body, this.actions, this.bottom, this.fab});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: Navigator.canPop(context)
            ? Padding(padding: const EdgeInsets.only(left: 14), child: Center(child: BackSquare(onTap: () => Navigator.maybePop(context))))
            : null,
        title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
        actions: actions == null ? null : [...actions!, const SizedBox(width: 8)],
      ),
      body: SafeArea(top: false, bottom: bottom == null, child: body),
      bottomNavigationBar: bottom,
      floatingActionButton: fab,
    );
  }
}

class BackSquare extends StatelessWidget {
  final VoidCallback onTap;
  const BackSquare({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Tap(
      onTap: onTap,
      radius: 12,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Icon(Icons.chevron_left_rounded, color: t.ink, size: 26),
      ),
    );
  }
}

/// Titolo di una scheda principale, con azioni a destra.
class TabHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const TabHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TS.h1(t)),
            if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: TS.muted(t))],
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

// =================================================================== superfici

class Tap extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  const Tap({super.key, required this.child, this.onTap, this.onLongPress, this.radius = 14});
  @override
  Widget build(BuildContext context) {
    if (onTap == null && onLongPress == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, onLongPress: onLongPress, child: child),
    );
  }
}

class DCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  final EdgeInsets margin;
  const DCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.border,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? t.surf,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: border ?? t.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Riga di una lista: icona, titolo, sottotitolo, a destra un valore.
class RowTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color? titleColor;
  const RowTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Tap(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 12,
      child: Padding(
        padding: padding,
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: titleColor ?? t.ink)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TS.muted(t, 12.5)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  const SectionLabel(this.text, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 10)});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: TS.label(t))),
        if (action != null)
          Tap(
            onTap: onAction,
            radius: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(action!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TC.accent)),
            ),
          ),
      ]),
    );
  }
}

/// Riquadro di testo (suggerimenti, avvisi, note legali).
class NoteBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  const NoteBox(this.text, {super.key, this.icon = Icons.info_outline_rounded, this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final c = color ?? t.dim;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.25))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TS.soft(t, 13))),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(color: t.accentTint, shape: BoxShape.circle),
          child: Icon(icon, color: TC.accent, size: 28),
        ),
        const SizedBox(height: 14),
        Text(title, style: TS.title(t), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(body, style: TS.muted(t), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), SmallButton(label: action!, icon: Icons.add_rounded, onTap: onAction)],
      ]),
    );
  }
}

// =================================================================== bottoni

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;
  const PrimaryButton({super.key, required this.label, this.icon, this.onTap, this.busy = false, this.color});
  @override
  Widget build(BuildContext context) {
    final bg = color ?? TC.accent;
    return SizedBox(
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: TC.onAccent,
          disabledBackgroundColor: bg.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: TC.onAccent))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ]),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  const GhostButton({super.key, required this.label, this.icon, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final c = color ?? t.ink;
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: t.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        onPressed: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

class SmallButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;
  const SmallButton({super.key, required this.label, this.icon, this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Material(
      color: filled ? TC.accent : t.accentTint,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: filled ? TC.onAccent : TC.accent), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: filled ? TC.onAccent : TC.accent)),
          ]),
        ),
      ),
    );
  }
}

class IconSquare extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  const IconSquare({super.key, required this.icon, this.onTap, this.tooltip, this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final w = Tap(
      onTap: onTap,
      radius: 12,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Icon(icon, color: color ?? t.ink, size: 21),
      ),
    );
    return Padding(padding: const EdgeInsets.only(left: 8), child: tooltip == null ? w : Tooltip(message: tooltip!, child: w));
  }
}

class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const PillChip({super.key, required this.label, this.selected = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Material(
      color: selected ? TC.accent : t.surf2,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: selected ? TC.onAccent : t.soft), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? TC.onAccent : t.soft)),
          ]),
        ),
      ),
    );
  }
}

/// Scelta tra poche opzioni (segmentata).
class Seg<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const Seg({super.key, required this.options, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: Material(
              color: o.$1 == value ? t.surf : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(o.$1);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(o.$2,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: o.$1 == value ? t.ink : t.dim)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// =================================================================== indicatori

class BarTrack extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;
  final double? marker;
  const BarTrack({super.key, required this.value, this.color, this.height = 7, this.marker});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: height,
        child: Stack(children: [
          Container(decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(height))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: w * clamp01(value),
            decoration: BoxDecoration(color: color ?? TC.accent, borderRadius: BorderRadius.circular(height)),
          ),
          if (marker != null)
            Positioned(left: (w * clamp01(marker!) - 1).clamp(0, w - 2), top: 0, bottom: 0, child: Container(width: 2, color: t.ink.withValues(alpha: 0.6))),
        ]),
      );
    });
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill(this.text, {super.key, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );
}

class DollarzMark extends StatelessWidget {
  final double size;
  final Color color;
  const DollarzMark({super.key, this.size = 32, this.color = TC.accent});
  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/mark.png', width: size, height: size, color: color, colorBlendMode: BlendMode.srcIn);
}

/// Etichetta e valore su una riga.
class KV extends StatelessWidget {
  final String k;
  final String v;
  final Color? color;
  final bool strong;
  const KV(this.k, this.v, {super.key, this.color, this.strong = false});
  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(k, style: strong ? TS.title(t) : TS.soft(t, 13.5))),
        Text(v, style: TS.num(t, strong ? 16 : 14, color: color, w: strong ? FontWeight.w700 : FontWeight.w600)),
      ]),
    );
  }
}

// =================================================================== importi

/// Importo che rispetta "nascondi importi".
class Money extends StatelessWidget {
  final int cents;
  final double size;
  final Color? color;
  final String cur;
  final bool sign;
  final bool? dec;
  final FontWeight weight;
  final bool colored;
  const Money(this.cents,
      {super.key, this.size = 14.5, this.color, this.cur = 'EUR', this.sign = false, this.dec, this.weight = FontWeight.w600, this.colored = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final hide = context.app.prefs.hideAmounts;
    final txt = hide ? '•••• ${curSymbol(cur)}' : fMoney(cents, cur: cur, dec: dec, sign: sign);
    return Text(txt, maxLines: 1, style: TS.num(t, size, color: color ?? (colored ? amountColor(t, cents) : t.ink), w: weight));
  }
}

String moneyText(BuildContext context, int cents, {String cur = 'EUR', bool sign = false, bool? dec}) =>
    context.app.prefs.hideAmounts ? '•••• ${curSymbol(cur)}' : fMoney(cents, cur: cur, dec: dec, sign: sign);

// =================================================================== categorie

const catIcons = <String, IconData>{
  'home': Icons.home_rounded,
  'bolt': Icons.bolt_rounded,
  'cart': Icons.shopping_cart_rounded,
  'car': Icons.directions_car_rounded,
  'health': Icons.favorite_rounded,
  'wifi': Icons.wifi_rounded,
  'shield': Icons.shield_rounded,
  'bank': Icons.account_balance_rounded,
  'school': Icons.school_rounded,
  'pets': Icons.pets_rounded,
  'debt': Icons.credit_score_rounded,
  'food': Icons.restaurant_rounded,
  'bag': Icons.shopping_bag_rounded,
  'party': Icons.celebration_rounded,
  'subs': Icons.subscriptions_rounded,
  'flight': Icons.flight_rounded,
  'sport': Icons.fitness_center_rounded,
  'spa': Icons.spa_rounded,
  'gift': Icons.card_giftcard_rounded,
  'tech': Icons.devices_rounded,
  'more': Icons.more_horiz_rounded,
  'work': Icons.work_rounded,
  'plus': Icons.add_card_rounded,
  'refund': Icons.replay_rounded,
  'savings': Icons.savings_rounded,
  'swap': Icons.swap_horiz_rounded,
  'chart': Icons.show_chart_rounded,
  'tune': Icons.tune_rounded,
  'coffee': Icons.local_cafe_rounded,
  'baby': Icons.child_friendly_rounded,
  'game': Icons.sports_esports_rounded,
  'book': Icons.menu_book_rounded,
  'fuel': Icons.local_gas_station_rounded,
  'train': Icons.train_rounded,
  'beauty': Icons.content_cut_rounded,
  'tools': Icons.build_rounded,
};

Color catColor(Category? c) {
  if (c == null) return const Color(0xFF8592B0);
  if (c.isIncome) return TC.pos;
  if (c.isTransfer) return const Color(0xFF56C8F5);
  return c.bucket == Bucket.need ? TC.accent : const Color(0xFFA78BFA);
}

class CatIcon extends StatelessWidget {
  final Category? cat;
  final double size;
  final IconData? icon;
  const CatIcon(this.cat, {super.key, this.size = 38, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = catColor(cat);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size * 0.32)),
      alignment: Alignment.center,
      child: Icon(icon ?? (cat == null ? Icons.help_outline_rounded : catIcons[cat!.icon] ?? Icons.label_rounded), size: size * 0.5, color: c),
    );
  }
}

IconData accountIcon(String type) => switch (type) {
      AccountType.risparmio => Icons.savings_rounded,
      AccountType.contanti => Icons.payments_rounded,
      AccountType.carta => Icons.credit_card_rounded,
      AccountType.broker => Icons.candlestick_chart_rounded,
      AccountType.crypto => Icons.currency_bitcoin_rounded,
      _ => Icons.account_balance_wallet_rounded,
    };

// =================================================================== dialoghi

void toast(BuildContext context, String msg, {String? action, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    duration: Duration(milliseconds: action == null ? 2600 : 5000),
    action: action == null ? null : SnackBarAction(label: action, textColor: TC.accentHi, onPressed: onAction ?? () {}),
  ));
}

Future<bool> confirm(BuildContext context, {required String title, required String body, String ok = 'Conferma', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: TC.neg, foregroundColor: TC.onAccent) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context,
    {required String title, String initial = '', String? hint, String ok = 'Salva', int lines = 1, bool obscure = false, String? body}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (body != null) ...[Text(body), const SizedBox(height: 12)],
        TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: obscure,
          minLines: lines,
          maxLines: obscure ? 1 : lines,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: lines == 1 ? (v) => Navigator.pop(c, v) : null,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(ok)),
      ],
    ),
  );
}

/// Chiede un importo in euro: ritorna i centesimi.
Future<int?> askMoney(BuildContext context, {required String title, int? initial, String? body, String cur = 'EUR', bool allowNegative = false}) async {
  final ctrl = TextEditingController(text: initial == null ? '' : fDec(initial / 100, 2, true));
  String? err;
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (body != null) ...[Text(body), const SizedBox(height: 12)],
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: allowNegative),
            decoration: InputDecoration(suffixText: curSymbol(cur), errorText: err),
            style: TS.num(context.tt, 20),
            onSubmitted: (_) {
              final v = parseMoney(ctrl.text);
              if (v == null) return setS(() => err = 'Importo non valido');
              Navigator.pop(c, v);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
          FilledButton(
            onPressed: () {
              final v = parseMoney(ctrl.text);
              if (v == null) return setS(() => err = 'Importo non valido');
              Navigator.pop(c, v);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> pickDay(BuildContext context, String current, {String? first, String? last}) async {
  final d = await showDatePicker(
    context: context,
    initialDate: fromKey(current),
    firstDate: first != null ? fromKey(first) : DateTime(2000),
    lastDate: last != null ? fromKey(last) : DateTime(2100),
    locale: const Locale('it', 'IT'),
  );
  return d == null ? null : dayKey(d);
}

/// Scelta da una lista in un foglio dal basso.
Future<T?> pickFrom<T>(BuildContext context, {required String title, required List<(T, String, String?)> items, T? selected, Widget Function(T)? leading}) {
  final t = context.tt;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.75),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(title, style: TS.h2(t))),
        Flexible(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
            for (final it in items)
              RowTile(
                leading: leading?.call(it.$1),
                title: it.$2,
                subtitle: it.$3,
                trailing: it.$1 == selected ? const Icon(Icons.check_rounded, color: TC.accent) : null,
                onTap: () => Navigator.pop(c, it.$1),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              ),
          ]),
        ),
      ]),
    ),
  );
}

/// Campo importo con la tastiera numerica.
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String cur;
  final String? helper;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final bool signed;
  const MoneyField({super.key, required this.controller, required this.label, this.cur = 'EUR', this.helper, this.autofocus = false, this.onChanged, this.signed = false});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
        decoration: InputDecoration(labelText: label, suffixText: curSymbol(cur), helperText: helper),
        style: TS.num(context.tt, 16),
        onChanged: onChanged,
      );
}

String centsToField(int cents) => cents == 0 ? '' : fDec(cents / 100, 2, true);
