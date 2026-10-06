import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Palette {
  final String name;
  final Color color;
  final bool mono;
  const Palette(this.name, this.color, {this.mono = false});
}

const palettes = [
  Palette('Blue', Color(0xFF2196F3)),
  Palette('Purple', Color(0xFF9C27B0)),
  Palette('Pink', Color(0xFFE91E63)),
  Palette('Red', Color(0xFFF44336)),
  Palette('Orange', Color(0xFFFF9800)),
  Palette('Amber', Color(0xFFFFC107)),
  Palette('Green', Color(0xFF4CAF50)),
  Palette('Cyan', Color(0xFF00BCD4)),
  Palette('Indigo', Color(0xFF3F51B5)),
  Palette('Mono', Color(0xFF757575), mono: true),
];

const fontNames = ['System', 'Roboto', 'Inter', 'Manrope', 'Nunito'];

TextTheme fontTheme(String font, TextTheme base) {
  switch (font) {
    case 'Roboto':
      return GoogleFonts.robotoTextTheme(base);
    case 'Inter':
      return GoogleFonts.interTextTheme(base);
    case 'Manrope':
      return GoogleFonts.manropeTextTheme(base);
    case 'Nunito':
      return GoogleFonts.nunitoTextTheme(base);
    default:
      return base;
  }
}

class SoftTransitions extends PageTransitionsBuilder {
  const SoftTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondary, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

ThemeData buildTheme(Brightness b, Color seed, bool mono, String font) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
    dynamicSchemeVariant: mono ? DynamicSchemeVariant.monochrome : DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    textTheme: fontTheme(font, base.textTheme),
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    navigationBarTheme: const NavigationBarThemeData(height: 72),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SoftTransitions(),
      TargetPlatform.iOS: SoftTransitions(),
    }),
  );
}
