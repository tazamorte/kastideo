import 'package:flutter/material.dart';

/// Thème de l'interface (mêmes valeurs que la clé « appearance » sur Mac).
enum AppearanceMode { dark, light, system }

/// Couleur d'accentuation (mêmes valeurs que AccentChoice sur Mac).
enum AccentChoice {
  system(Color(0xFF0A84FF), Color(0xFF007AFF)),
  blue(Color(0xFF0A84FF), Color(0xFF007AFF)),
  purple(Color(0xFFBF5AF2), Color(0xFFAF52DE)),
  pink(Color(0xFFFF375F), Color(0xFFFF2D55)),
  red(Color(0xFFFF453A), Color(0xFFFF3B30)),
  orange(Color(0xFFFF9F0A), Color(0xFFF08A00)),
  green(Color(0xFF30D158), Color(0xFF28A745)),
  teal(Color(0xFF40C8E0), Color(0xFF1F9DB5));

  const AccentChoice(this.dark, this.light);
  final Color dark;
  final Color light;
}

/// Densité des listes (interface Classique) : hauteur des lignes.
enum ListDensity {
  compact(0.8),
  standard(1.0),
  spacious(1.25);

  const ListDensity(this.factor);
  final double factor;
}

/// Taille des vignettes et affiches (interface Cinéma).
enum CardSize {
  small(0.82),
  medium(1.0),
  large(1.22);

  const CardSize(this.factor);
  final double factor;
}

/// Couleurs de Kastideo (mêmes valeurs que KastideoPalette sur Mac).
///
/// Les couleurs de la marque sont fixes ; celles de l'interface suivent le thème choisi (sombre ou clair).
/// Le lecteur, l'interface TV, la MultiVue, l'accueil, les fiches et le bandeau restent toujours sombres
/// (comme sur Mac) : ils utilisent les variantes « Dark ».
class KPalette {
  static const night = Color.fromRGBO(15, 5, 36, 1); // 0.06, 0.02, 0.14
  static const indigo = Color.fromRGBO(43, 33, 148, 1); // 0.17, 0.13, 0.58
  static const violet = Color.fromRGBO(87, 26, 140, 1); // 0.34, 0.10, 0.55
  static const magenta = Color.fromRGBO(204, 41, 133, 1); // 0.80, 0.16, 0.52
  static const orange = Color.fromRGBO(255, 153, 51, 1); // 1.00, 0.60, 0.20

  /// Thème clair en cours.
  static bool light = false;
  static AccentChoice accentChoice = AccentChoice.system;

  /// Densité des listes et taille des vignettes en cours (facteurs d'échelle).
  static double density = 1;
  static double cardScale = 1;

  // Variantes sombres fixes (zones toujours sombres).
  static const windowDark = Color(0xFF1E1E1E);
  static const separatorDark = Color(0x22FFFFFF);
  static const secondaryDark = Color(0x99FFFFFF);
  static const menuDark = Color(0xF02C2C2E);
  static const panelDark = Color(0xFF242426);

  // Interface (sombre façon macOS, ou claire).
  static Color get window => light ? const Color(0xFFF5F5F7) : windowDark;
  static Color get sidebar => light ? const Color(0xFFEDEBF0) : const Color(0xFF262328);
  static Color get list => light ? const Color(0xFFFFFFFF) : const Color(0xFF1B1B1D);
  static Color get separator => light ? const Color(0x1F000000) : separatorDark;
  static Color get panel => light ? const Color(0xFFFFFFFF) : panelDark;
  static Color get menu => light ? const Color(0xF8FAFAFC) : menuDark;
  static Color get accent => light ? accentChoice.light : accentChoice.dark;
  static Color get secondaryText => light ? const Color(0x99000000) : secondaryDark;

  /// Couleur du texte et des icônes (blanc en sombre, presque noir en clair), et ses nuances.
  static Color get ink => light ? const Color(0xFF1D1D1F) : Colors.white;
  static Color get ink70 => light ? const Color(0xB3000000) : Colors.white70;
  static Color get ink60 => light ? const Color(0x99000000) : Colors.white60;
  static Color get ink54 => light ? const Color(0x8A000000) : Colors.white54;
  static Color get ink38 => light ? const Color(0x61000000) : Colors.white38;
  static Color get ink30 => light ? const Color(0x4D000000) : Colors.white30;
  static Color get ink24 => light ? const Color(0x3D000000) : Colors.white24;
  static Color get ink12 => light ? const Color(0x1F000000) : Colors.white12;
  static Color get ink10 => light ? const Color(0x1A000000) : Colors.white10;

  /// Accent des zones toujours sombres.
  static Color get accentDark => accentChoice.dark;

  /// Texte lisible sur l'accent (sombre sur les accents clairs : orange, vert, turquoise).
  static Color get onAccent => onColor(accent);
}

/// Texte lisible sur un fond : blanc sur les fonds foncés, presque noir sur les fonds clairs.
Color onColor(Color background) =>
    background.computeLuminance() > 0.3 ? const Color(0xFF1D1D1F) : Colors.white;

/// Styles de texte : Nunito (arrondie, comme SF Pro Rounded) pour les titres, Inter pour le reste.
/// Sans couleur précisée, le texte prend la couleur du thème.
TextStyle kRounded(double size, FontWeight weight, {Color? color}) => TextStyle(
      fontFamily: 'Nunito',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color ?? KPalette.ink,
      height: 1.1,
    );

TextStyle kText(double size, {FontWeight weight = FontWeight.w400, Color? color}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color ?? KPalette.ink,
    );

/// Variantes pour les zones toujours sombres (texte blanc par défaut).
TextStyle kRoundedD(double size, FontWeight weight, {Color color = Colors.white}) => kRounded(size, weight, color: color);
TextStyle kTextD(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) => kText(size, weight: weight, color: color);

ThemeData buildTheme({bool? light}) {
  final isLight = light ?? KPalette.light;
  final ink = isLight ? const Color(0xFF1D1D1F) : Colors.white;
  final accent = isLight ? KPalette.accentChoice.light : KPalette.accentChoice.dark;
  final window = isLight ? const Color(0xFFF5F5F7) : KPalette.windowDark;
  final brightness = isLight ? Brightness.light : Brightness.dark;
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
        .copyWith(primary: accent, secondary: KPalette.orange, surface: window, onSurface: ink),
    scaffoldBackgroundColor: window,
    canvasColor: window,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: ink.withValues(alpha: 0.06),
    iconTheme: IconThemeData(color: ink),
    dialogTheme: DialogThemeData(backgroundColor: isLight ? Colors.white : KPalette.panelDark),
    popupMenuTheme: PopupMenuThemeData(color: isLight ? const Color(0xF8FAFAFC) : KPalette.menuDark),
    tooltipTheme: TooltipThemeData(
      textStyle: kText(12, color: Colors.white),
      decoration: BoxDecoration(color: const Color(0xEE2C2C2E), borderRadius: BorderRadius.circular(6)),
      waitDuration: const Duration(milliseconds: 600),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: onColor(accent), textStyle: kText(13, weight: FontWeight.w600, color: onColor(accent))),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : ink.withValues(alpha: 0.24)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    chipTheme: ChipThemeData(
      selectedColor: ink.withValues(alpha: 0.14),
      backgroundColor: Colors.transparent,
      side: BorderSide(color: ink.withValues(alpha: 0.15)),
      labelStyle: kText(13, color: ink),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? ink.withValues(alpha: 0.14) : null),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? ink.withValues(alpha: 0.3) : ink),
      ),
    ),
    dividerColor: isLight ? const Color(0x1F000000) : KPalette.separatorDark,
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(ink.withValues(alpha: 0.25)),
    ),
  );
  return base;
}

/// Zone toujours sombre (lecteur, interface TV, MultiVue, accueil, fiches, bandeau), même en thème clair.
class DarkZone extends StatelessWidget {
  const DarkZone({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!KPalette.light) return child;
    return Theme(
      data: buildTheme(light: false),
      child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
    );
  }
}

/// Dialogue au thème de l'application (clair ou sombre), même ouvert depuis une zone toujours sombre (lecteur, accueil…).
Future<T?> showKDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (c) => Theme(data: buildTheme(), child: Builder(builder: builder)),
    );
