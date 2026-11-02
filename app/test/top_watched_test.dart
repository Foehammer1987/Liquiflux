import 'package:console_app/ui/home/rows.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Home's "Top 10 on" plus the server name row, from the server's watch history (see tv_harness.dart).
void main() {
  testWidgets('Top 10 on the server ranks what was watched most, named after the server', (t) async {
    await tvApp(t);
    final row = find.ancestor(of: find.text('Top 10 on Homeserver'), matching: find.byType(Shelf));
    expect(row, findsOneWidget);
    final cards = [for (final e in find.descendant(of: row, matching: find.byType(RankedPoster)).evaluate()) e.widget as RankedPoster];
    expect([for (final c in cards) c.rank], [for (var i = 1; i <= 10; i++) i]);
    expect([for (final c in cards) c.title], ['Show 201', 'Film 12', 'Show 203', 'Film 14', 'Show 205', 'Film 16', 'Show 207', 'Film 18', 'Show 209', 'Film 20']);
    // It takes the ranked slot: no second ranked row from the library's ratings.
    expect(find.text('Top in Your Library'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
