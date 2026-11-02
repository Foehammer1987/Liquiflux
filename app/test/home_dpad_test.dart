import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Home as the TV shows it, on a Plex and a Seerr in memory (see tv_harness.dart).
void main() {
  testWidgets('nothing on Home takes focus while invisible', (t) async {
    await tvApp(t);
    expect(find.textContaining('Because You Watched'), findsWidgets);
    // The page's own controls (on a desktop the closed sidebar stays reachable with Tab).
    expect(hiddenStops(FocusScope.of(t.element(find.byType(HomePage)))), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Left along a Because You Watched row moves one card per press, and the page holds still', (t) async {
    await tvApp(t);
    final row = find.ancestor(of: find.textContaining('Because You Watched').first, matching: find.byType(Shelf));
    final cards = find.descendant(of: row, matching: find.byType(PosterCard));
    final titles = [for (final e in cards.evaluate()) (e.widget as PosterCard).title];
    Focus.of(t.element(find.descendant(of: cards.at(4), matching: find.text(titles[4])))).requestFocus();
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.arrowLeft);
    final page = Scrollable.of(t.element(row), axis: Axis.vertical).position;
    final y = page.pixels;
    for (var i = 4; i > 0; i--) {
      expect(focused(), startsWith('${titles[i]} '));
      await press(t, LogicalKeyboardKey.arrowLeft);
      expect(focused(), startsWith('${titles[i - 1]} '));
      expect(page.pixels, y);
    }
    await t.pumpWidget(const SizedBox());
  });
}
