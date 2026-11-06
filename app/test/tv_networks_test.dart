import 'package:console_app/platform.dart';
import 'package:console_app/ui/collections/tv_collections_page.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The titles of the posters in the shelf called [title].
List<String> shelfTitles(WidgetTester t, String title) {
  final shelf = find.ancestor(of: find.text(title), matching: find.byType(Shelf)).first;
  return [for (final p in t.widgetList<PosterCard>(find.descendant(of: shelf, matching: find.byType(PosterCard)))) p.title];
}

void main() {
  testWidgets('blocks show your shows first, then the best-rated missing ones up to ten', (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const TvCollectionsDest());
    await settle(t, 30);
    expect(find.byType(TvCollectionsPage), findsOneWidget);
    // 3 of 23 owned → 3 owned + the 7 best-rated missing.
    final block = shelfTitles(t, 'Saturday Block  ·  3 of 23 yours');
    expect(block.take(3).toSet(), {'Show 201', 'Show 202', 'Show 203'});
    expect(block.skip(3), [for (var i = 0; i < 7; i++) 'Missing $i']);

    // Networks: 12 owned → all 12, nothing missing.
    await t.tap(find.text('Networks'));
    await settle(t);
    final net = shelfTitles(t, 'Test Network  ·  12 of 12 yours');
    expect(net, hasLength(12));
    expect(net.where((n) => n.startsWith('Missing')), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a block’s page requests its missing shows, and can list all of them', (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const TvCollectionDest('saturday'));
    await settle(t, 30);
    expect(find.text('Request 7 Missing'), findsOneWidget);
    expect(find.text('Show All 20 Missing'), findsOneWidget);
    await t.tap(find.text('Show All 20 Missing'));
    await settle(t);
    expect(find.text('Request 20 Missing'), findsOneWidget);
    await t.tap(find.text('Request 20 Missing'));
    await settle(t);
    expect(find.text('Request 20 shows?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the block page works with the remote alone', skip: !isTv, (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const TvCollectionDest('saturday'));
    await settle(t, 30);
    final seen = <String>[];
    for (var i = 0; i < 6 && focused() != 'Request 7 Missing'; i++) {
      await press(t, LogicalKeyboardKey.arrowUp, wait: const Duration(milliseconds: 250));
      seen.add(focused());
    }
    if (focused() != 'Request 7 Missing') {
      for (var i = 0; i < 6 && focused() != 'Request 7 Missing'; i++) {
        await press(t, LogicalKeyboardKey.arrowLeft, wait: const Duration(milliseconds: 250));
        seen.add(focused());
      }
    }
    expect(focused(), 'Request 7 Missing', reason: seen.join(' > '));
    await press(t, LogicalKeyboardKey.select);
    await settle(t);
    expect(find.text('Request 7 shows?'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
