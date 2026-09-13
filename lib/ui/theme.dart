import 'package:flutter/material.dart';

/// Design tokens from the Basis Precision System.
///
/// Rules this file exists to enforce:
///   1. Every numeral in the app is IBM Plex Mono with tabular figures.
///   2. Prose is never set in the mono face; it is for figures only.
///   3. Cards sit on a softly tinted ground, lifted by a hairline and one
///      very soft shadow, so what is tappable reads as an object.
class BasisColors {
  final Color ink;
  final Color inkMute;
  final Color ground;
  final Color surface;
  final Color line;
  final Color accent;
  final Color accentSoft;
  final Color positive;
  final Color negative;
  final Color warn;

  const BasisColors({
    required this.ink,
    required this.inkMute,
    required this.ground,
    required this.surface,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.positive,
    required this.negative,
    required this.warn,
  });

  static const light = BasisColors(
    ink: Color(0xFF0C1116),
    inkMute: Color(0xFF56655F),
    ground: Color(0xFFF5F7F6),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFE1E7E4),
    accent: Color(0xFF0F6E52),
    accentSoft: Color(0xFFE3F0EB),
    positive: Color(0xFF17876A),
    negative: Color(0xFFC6413F),
    warn: Color(0xFFB07515),
  );

  static const dark = BasisColors(
    ink: Color(0xFFE9EEEB),
    inkMute: Color(0xFF8E9E98),
    ground: Color(0xFF0B0F0D),
    surface: Color(0xFF151C19),
    line: Color(0xFF263230),
    accent: Color(0xFF46B48F),
    accentSoft: Color(0xFF14312A),
    positive: Color(0xFF4FC2A0),
    negative: Color(0xFFE8736F),
    warn: Color(0xFFD19A3E),
  );
}

class BasisTheme extends InheritedWidget {
  final BasisColors colors;
  final bool isDark;

  const BasisTheme({
    super.key,
    required this.colors,
    required this.isDark,
    required super.child,
  });

  static BasisTheme of(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<BasisTheme>();
    assert(t != null, 'BasisTheme missing from the widget tree');
    return t!;
  }

  @override
  bool updateShouldNotify(BasisTheme old) => old.isDark != isDark;
}

/// Convenience accessor: `context.c.accent`.
extension BasisContext on BuildContext {
  BasisColors get c => BasisTheme.of(this).colors;
  bool get isDark => BasisTheme.of(this).isDark;
}

// ---------------------------------------------------------------------------
// Type scale
// ---------------------------------------------------------------------------

const String kUiFace = 'InstrumentSans';
const String kFigureFace = 'IBMPlexMono';

/// Every figure style carries tabular lining figures. Proportional numerals
/// are prohibited anywhere in the interface.
const List<FontFeature> _tabular = [
  FontFeature.tabularFigures(),
  FontFeature.liningFigures(),
];

/// Instrument Sans ships as a variable font. Without an explicit weight axis
/// every style would render at the default instance, silently flattening the
/// hierarchy, so each UI style states its own.

class T {
  static const display = TextStyle(
    fontFamily: kUiFace,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.68,
    fontVariations: [FontVariation('wght', 600)],
  );
  static const title = TextStyle(
    fontFamily: kUiFace,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.22,
    fontVariations: [FontVariation('wght', 600)],
  );
  static const body = TextStyle(
    fontFamily: kUiFace,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const bodySm = TextStyle(
    fontFamily: kUiFace,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const label = TextStyle(
    fontFamily: kUiFace,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.96,
    fontVariations: [FontVariation('wght', 500)],
  );
  static const figureL = TextStyle(
    fontFamily: kFigureFace,
    fontSize: 40,
    height: 44 / 40,
    fontWeight: FontWeight.w500,
    letterSpacing: -1.2,
    fontFeatures: _tabular,
  );
  static const figureLMobile = TextStyle(
    fontFamily: kFigureFace,
    fontSize: 32,
    height: 36 / 32,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.64,
    fontFeatures: _tabular,
  );
  static const figure = TextStyle(
    fontFamily: kFigureFace,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.17,
    fontFeatures: _tabular,
  );
  static const figureSm = TextStyle(
    fontFamily: kFigureFace,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );
}

// ---------------------------------------------------------------------------
// Spacing and shape
// ---------------------------------------------------------------------------

class S {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double margin = 20;
  static const double gutter = 12;
  static const double cardPad = 16;
  static const double rowHeight = 52;
}

class R {
  static const card = BorderRadius.all(Radius.circular(18));
  static const input = BorderRadius.all(Radius.circular(12));
  static const pill = BorderRadius.all(Radius.circular(999));
  static const sheet = BorderRadius.vertical(top: Radius.circular(24));
}

/// One very soft shadow, the only elevation in the app. Dark mode drops it:
/// shadows vanish on a dark ground, and the hairline carries the edge alone.
List<BoxShadow> softShadow(BuildContext context) => context.isDark
    ? const []
    : const [
        BoxShadow(
          color: Color(0x0F0C1116),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ];

/// A colour pair for one question group: a soft tile and the icon on it.
@immutable
class Hue {
  final Color tile;
  final Color ink;
  const Hue(this.tile, this.ink);
}

ThemeData buildMaterialTheme(BasisColors c, bool dark) {
  return ThemeData(
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      shape: const RoundedRectangleBorder(borderRadius: R.input),
      actionTextColor: dark ? c.accentSoft : const Color(0xFF8FD9BE),
    ),
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(primary: c.accent, surface: c.surface, error: c.negative),
    fontFamily: kUiFace,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: c.line,
  );
}
