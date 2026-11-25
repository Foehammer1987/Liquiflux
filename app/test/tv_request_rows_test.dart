import 'package:console_app/platform.dart';
import 'package:console_app/ui/seerr_card.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brand_rows_test.dart' show openTrending;
import 'tv_harness.dart';

/// On a TV the poster rows carry no Seerr Request button: Down from a poster landed on it
/// instead of on the next row. A title not in the library wears a "Not in Your Library"
/// badge (which takes no focus) and is requested from its own page.
///   CONSOLE_TV=1 flutter test test/tv_request_rows_test.dart
/// Without CONSOLE_TV the same rows keep their Request buttons (phones, tablets, desktop).
void main() {
  setUp(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  testWidgets('TV: Trending has no Request buttons, a badge instead, and Down goes row to row', skip: !isTv, (t) async {
    await tvApp(t);
    await openTrending(t);
    expect(find.widgetWithText(ConsoleButton, 'Request'), findsNothing);
    expect(find.text(notInLibrary), findsWidgets);
    expect(hiddenStops(), isEmpty);

    // From the first poster of the first row Down lands on a poster of another row, every
    // time, never on a button under the poster.
    final first = find.byType(SeerrCard).first;
    await t.ensureVisible(first);
    Focus.of(t.element(find.descendant(of: find.descendant(of: first, matching: find.byType(PosterCard)), matching: find.byType(Text)).first)).requestFocus();
    await press(t, LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 3; i++) {
      final from = focused();
      await press(t, LogicalKeyboardKey.arrowDown);
      final to = focused();
      expect(to, isNot(contains('Request')), reason: 'Down from $from');
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<PosterCard>(), isNotNull, reason: 'Down from $from landed on $to');
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('elsewhere the rows keep their Request buttons', skip: isTv, (t) async {
    await tvApp(t);
    await openTrending(t);
    expect(find.widgetWithText(ConsoleButton, 'Request'), findsWidgets);
    expect(find.text(notInLibrary), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
