import 'package:flutter/widgets.dart';

/// How tightly the design system lays out: [compact] on a phone, where Home rows, cards and
/// page margins shrink to fit a screen about 400 px wide. Desktop, tablet and TV leave it off
/// (there's no [ConsoleDensity] above them), so nothing changes there.
///
/// The app decides when it applies (a touch device with a narrow screen, see the app's
/// platform.dart), so this package stays free of platform checks.
class ConsoleDensity extends InheritedWidget {
  const ConsoleDensity({super.key, required this.compact, required super.child});

  /// The phone layout.
  final bool compact;

  /// Whether the phone layout applies at [context] (false when nothing says so).
  static bool compactOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ConsoleDensity>()?.compact ?? false;

  /// Phone sizes scale card widths by this.
  static const compactScale = 0.64;

  /// The page margin rows and headings line up on: 48 on wide screens, 16 on a phone.
  static double inset(BuildContext context, [double wide = 48]) => compactOf(context) ? 16 : wide;

  @override
  bool updateShouldNotify(ConsoleDensity old) => old.compact != compact;
}
