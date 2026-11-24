// A collection's page and a person's page on a phone held upright: the poster (or photo)
// goes above the details, which get the full width, instead of squeezing them into a
// sliver beside it (the words wrapped a letter or two per line). On a phone on its side
// and on a tablet the details stay beside the poster.
//
// Run with CONSOLE_TOUCH=1 for the touch layout.
import 'package:console_app/platform.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

Franchise _series() => Franchise(
  name: 'Bad Boys Collection',
  overview: 'A franchise of action comedies about two Miami detectives.',
  parts: [
    for (final (i, y) in [(1, 1995), (2, 2003), (3, 2020), (4, 2024)])
      FranchisePart(
        title: 'Bad Boys $i',
        plex: PlexItem(ratingKey: '90$i', key: '/library/metadata/90$i', type: 'movie', title: 'Bad Boys $i', year: y, duration: 7200000, thumb: '/t/90$i'),
      ),
  ],
);

Future<void> _open(WidgetTester t, Dest d) async {
  final nav = ShellNav.of(t.element(find.descendant(of: find.byType(ShellNav), matching: find.byType(Navigator)).first));
  nav.go(d);
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('detail heroes on a phone', () {
    testWidgets('upright: the collection details get the full width, below the poster', (t) async {
      await touchApp(t);
      await _open(t, CollectionDest(_series()));
      expect(t.takeException(), isNull);
      final title = t.getRect(find.text('Bad Boys Collection').first);
      expect(title.width, greaterThan(300), reason: 'the title is not squeezed beside the poster');
      final watch = t.getRect(find.textContaining('to watch').first);
      expect(watch.width, greaterThan(200));
      // The back button sits below the status bar and the search strip.
      expect(t.getRect(find.text('Collections').first).top, greaterThan(62 + 44));
    });

    testWidgets('upright with the largest text: nothing overflows', (t) async {
      await touchApp(t, size: const Size(375, 667), padding: const EdgeInsets.only(top: 20), textScale: 3);
      await _open(t, CollectionDest(_series()));
      expect(t.takeException(), isNull);
      await _open(t, const PersonDest(name: 'Will Smith'));
      expect(t.takeException(), isNull);
    });

    testWidgets("upright: a person's name gets the full width, below the photo", (t) async {
      await touchApp(t);
      await _open(t, const PersonDest(name: 'Will Smith'));
      expect(t.takeException(), isNull);
      expect(t.getRect(find.text('Will Smith').first).width, greaterThan(100));
      expect(t.getRect(find.text('Will Smith').first).left, lessThan(80), reason: 'not pushed right of the photo');
    });

    for (final (name, size, padding) in [
      ('a phone on its side', const Size(874, 402), const EdgeInsets.only(left: 62, right: 62, bottom: 21)),
      ('a tablet upright', const Size(800, 1280), const EdgeInsets.only(top: 24, bottom: 20)),
    ]) {
      testWidgets('$name keeps the poster beside the details', (t) async {
        await touchApp(t, size: size, padding: padding);
        await _open(t, CollectionDest(_series()));
        expect(t.takeException(), isNull);
        final title = t.getRect(find.text('Bad Boys Collection').first);
        expect(title.right, lessThan(size.width - 300), reason: 'the poster sits to the right');
      });
    }
  }, skip: !isTouch);
}
