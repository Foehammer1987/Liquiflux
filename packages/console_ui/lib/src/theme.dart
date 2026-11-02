import 'package:flutter/material.dart';

import 'glass.dart';
import 'tokens.dart';

const _sans = 'Inter';
const _pkg = 'console_ui';

/// Console type scale (title-lg … data).
abstract final class ConsoleText {
  static const display = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w600, letterSpacing: -0.56);
  static const titleLg = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600);
  static const titleMd = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600);
  static const titleSm = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w400);
  static const bodyStrong = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w500);
  static const small = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w400);
  static const metric = TextStyle(fontFamily: _sans, package: _pkg, fontSize: 24, height: 28 / 24, fontWeight: FontWeight.w500, letterSpacing: -0.24);
  static const data = TextStyle(fontFamily: 'JetBrains Mono', package: _pkg, fontSize: 12, height: 20 / 12);
}

extension ConsoleContext on BuildContext {
  ConsoleColors get c => Theme.of(this).extension<ConsoleColors>() ?? ConsoleColors.dark;
}

abstract final class ConsoleTheme {
  // The same instance each time, so a rebuild above MaterialApp doesn't animate the theme
  // or rebuild everything that reads it.
  static final _cache = <(Brightness, bool), ThemeData>{};

  static ThemeData dark({bool glass = true}) =>
      _cache.putIfAbsent((Brightness.dark, glass), () => _build(ConsoleColors.dark, Brightness.dark, ConsoleEffects.darkFor(ConsoleColors.dark, glass: glass)));
  static ThemeData light({bool glass = true}) =>
      _cache.putIfAbsent((Brightness.light, glass), () => _build(ConsoleColors.light, Brightness.light, ConsoleEffects.lightFor(ConsoleColors.light, glass: glass)));

  static ThemeData _build(ConsoleColors c, Brightness b, ConsoleEffects fx) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.chartDownload,
      onSecondary: c.onPrimary,
      error: c.danger,
      onError: c.onPrimary,
      surface: c.surface100,
      onSurface: c.text100,
      outline: c.border200,
    );
    final text = TextTheme(
      bodyMedium: ConsoleText.body.copyWith(color: c.text100),
      bodySmall: ConsoleText.caption.copyWith(color: c.text300),
      bodyLarge: ConsoleText.body.copyWith(color: c.text100),
      titleSmall: ConsoleText.titleSm.copyWith(color: c.text100),
      titleMedium: ConsoleText.titleMd.copyWith(color: c.text100),
      titleLarge: ConsoleText.titleLg.copyWith(color: c.text100),
      labelLarge: ConsoleText.bodyStrong.copyWith(color: c.text100),
      labelMedium: ConsoleText.small.copyWith(color: c.text200),
      labelSmall: ConsoleText.caption.copyWith(color: c.text200),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: fx.glass ? Colors.transparent : c.surface000,
      canvasColor: c.surface000,
      fontFamily: _sans,
      package: _pkg,
      textTheme: text,
      dividerColor: c.border200,
      focusColor: c.primaryTint,
      hoverColor: c.surface200,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      iconTheme: IconThemeData(color: c.text200, size: Sizes.iconMd),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.border300.withValues(alpha: 0.6)),
        radius: const Radius.circular(Radii.radiusFull),
        thickness: const WidgetStatePropertyAll(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surface200,
          borderRadius: BorderRadius.circular(Radii.radiusSm),
          border: Border.all(color: c.border200),
        ),
        textStyle: ConsoleText.caption.copyWith(color: c.text100),
        waitDuration: const Duration(milliseconds: 400),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: c.primary, selectionColor: c.primaryTint),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      extensions: [c, fx],
    );
  }
}
