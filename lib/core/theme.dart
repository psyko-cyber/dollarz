import 'package:flutter/material.dart';

/// Colori "Blu notte" (solo tema scuro).
class TC {
  static const bg = Color(0xFF0C1326);
  static const accent = Color(0xFF6C8CFF);
  static const accentHi = Color(0xFF8FA8FF);
  static const onAccent = Color(0xFF0B1430);
  static const pos = Color(0xFF5FD3B0);
  static const neg = Color(0xFFFF7A85);
  static const warn = Color(0xFFF2C46D);
  static const danger = Color(0xFFFF7A85);

  /// Serie dei grafici (categorie, allocazione).
  static const series = [
    Color(0xFF6C8CFF),
    Color(0xFF5FD3B0),
    Color(0xFFF2C46D),
    Color(0xFFFF8F7A),
    Color(0xFFA78BFA),
    Color(0xFF56C8F5),
    Color(0xFFF58AC8),
    Color(0xFFB5E36C),
    Color(0xFF8592B0),
  ];
}

/// Token del tema.
@immutable
class TT extends ThemeExtension<TT> {
  final Color bg, surf, surf2, line, ink, soft, dim;

  const TT({
    required this.bg,
    required this.surf,
    required this.surf2,
    required this.line,
    required this.ink,
    required this.soft,
    required this.dim,
  });

  static const night = TT(
    bg: TC.bg,
    surf: Color(0xFF152039),
    surf2: Color(0xFF1C2948),
    line: Color(0xFF22304F),
    ink: Color(0xFFE7ECF7),
    soft: Color(0xFFB3BDD3),
    dim: Color(0xFF8592B0),
  );

  Color get accentInk => TC.accent;
  Color get accentTint => TC.accent.withValues(alpha: 0.10);
  Color get accentLine => TC.accent.withValues(alpha: 0.38);

  @override
  TT copyWith() => this;

  @override
  TT lerp(ThemeExtension<TT>? other, double t) => this;
}

extension TTx on BuildContext {
  TT get tt => Theme.of(this).extension<TT>()!;
}

const tabular = [FontFeature.tabularFigures()];

/// Colore di un importo: entrate verdi, uscite chiare (non tutto rosso: le spese sono normali).
Color amountColor(TT t, int cents, {bool strong = false}) =>
    cents > 0 ? TC.pos : (strong && cents < 0 ? TC.neg : t.ink);

/// Stili tipografici ricorrenti.
class TS {
  static TextStyle h1(TT t) => TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: t.ink, height: 1.15);
  static TextStyle h2(TT t) => TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink);
  static TextStyle title(TT t) => TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: t.ink);
  static TextStyle body(TT t) => TextStyle(fontSize: 14, color: t.ink, height: 1.4);
  static TextStyle muted(TT t, [double size = 13]) => TextStyle(fontSize: size, color: t.dim, height: 1.4);
  static TextStyle soft(TT t, [double size = 13]) => TextStyle(fontSize: size, color: t.soft, height: 1.45);
  static TextStyle label(TT t, [Color? c]) =>
      TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: c ?? t.dim);
  static TextStyle num(TT t, double size, {Color? color, FontWeight w = FontWeight.w600}) => TextStyle(
        fontSize: size,
        fontWeight: w,
        letterSpacing: size > 24 ? -size * 0.03 : -0.2,
        color: color ?? t.ink,
        height: 1.1,
        fontFeatures: tabular,
      );
}

ThemeData buildTheme() {
  const t = TT.night;
  final scheme = ColorScheme.fromSeed(seedColor: TC.accent, brightness: Brightness.dark).copyWith(
    primary: TC.accent,
    onPrimary: TC.onAccent,
    secondary: TC.pos,
    onSecondary: TC.onAccent,
    surface: t.surf,
    onSurface: t.ink,
    surfaceContainerHighest: t.surf2,
    surfaceContainerHigh: t.surf2,
    surfaceContainer: t.surf,
    outline: t.line,
    outlineVariant: t.line,
    error: TC.neg,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Sora',
    colorScheme: scheme,
  );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line));
  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    extensions: const [t],
    textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink, fontFamily: 'Sora'),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w600, color: t.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surf,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.dim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surf,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w600, color: t.ink),
      contentTextStyle: TextStyle(fontFamily: 'Sora', fontSize: 14, color: t.soft, height: 1.45),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surf2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: TC.accent, width: 1.5)),
      labelStyle: TextStyle(color: t.dim),
      hintStyle: TextStyle(color: t.dim),
      helperStyle: TextStyle(color: t.dim, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF243458),
      contentTextStyle: TextStyle(fontFamily: 'Sora', color: t.ink, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TC.onAccent : t.dim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TC.accent : t.surf2),
      trackOutlineColor: WidgetStateProperty.all(t.line),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TC.accent : Colors.transparent),
      checkColor: WidgetStateProperty.all(TC.onAccent),
      side: BorderSide(color: t.dim, width: 1.5),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: TC.accent,
      inactiveTrackColor: t.surf2,
      thumbColor: TC.accent,
      overlayColor: TC.accent.withValues(alpha: 0.15),
      trackHeight: 5,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: TC.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: TC.accent,
      selectionColor: TC.accent.withValues(alpha: 0.35),
      selectionHandleColor: TC.accent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surf,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.line)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: t.ink, fontSize: 12),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.surf,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: t.surf2,
      headerForegroundColor: t.ink,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
