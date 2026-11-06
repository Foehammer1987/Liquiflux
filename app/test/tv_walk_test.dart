import 'dart:io';

import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// The D-pad audit: from every control on each page, Right then Left (and Left then Right,
/// Down then Up) must come back, and no move may land on something hidden or off screen.
/// Slow (about ten minutes), so it only runs when asked:
///   CONSOLE_TV=1 TV_WALK=1 flutter test test/tv_walk_test.dart
void main() {
  final skip = Platform.environment['TV_WALK'] != '1';
  for (final (name, dest) in <(String, Dest?)>[
    ('home', null),
    ('movie', ItemDest('5')),
    ('show', ItemDest('205')),
    ('seerr title', SeerrDest('movie', 5001)),
    ('library', LibraryDest('1')),
    ('trending', const TrendingDest()),
    ('moods', const MoodsDest()),
    ('channels', const ChannelsDest()),
    ('requests', const RequestsDest()),
    ('settings', const SettingsDest()),
    ('search', const SearchDest('film')),
  ]) {
    testWidgets('D-pad walk: $name', skip: skip, (t) async {
      await tvApp(t);
      if (dest != null) {
        ShellNav.of(t.element(find.byType(HomePage))).go(dest);
        for (var i = 0; i < 40; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
      }
      final odd = await walk(t, limit: 70);
      expect(odd, isEmpty, reason: odd.join('\n'));
      await t.pumpWidget(const SizedBox());
    });
  }
}
