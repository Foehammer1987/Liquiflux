import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Mood rows on Home and the Moods page, on the in-memory Plex library.
void main() {
  testWidgets('Home shows mood rows from the library, and the Moods page lists them all', (t) async {
    await tvApp(t);
    // The harness films are Drama/Action/Comedy plus Thriller, 1990-2019.
    const fill = ['Edge-of-Your-Seat Thrillers', 'Feel-Good Comedies', 'Laugh-Out-Loud Action', '’90s Favorites', 'Heartfelt Dramas'];
    final home = [for (final m in fill) if (find.text(m, skipOffstage: false).evaluate().isNotEmpty) m];
    expect(home, isNotEmpty);
    // Only names that really fit: comedies here are thrillers too, so not "feel-good".
    expect(find.text('Feel-Good Comedies', skipOffstage: false), findsNothing);

    ShellNav.of(t.element(find.byType(HomePage))).go(const MoodsDest());
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Moods'), findsWidgets);
    expect(find.text('By Mood'), findsOneWidget);
    expect(find.text('Edge-of-Your-Seat Thrillers'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    // As a TV, leaving the Moods page starts the shell's short focus timers; let them run out.
    await t.pump(const Duration(seconds: 1));
  });
}
