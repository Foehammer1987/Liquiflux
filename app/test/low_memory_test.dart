import 'package:console_app/platform.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/player/player_session.dart' show ptsWrap, sanePosition;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// The Fire TV fixes of 1.0.4: low-memory mode by RAM, the transcode clock, Movies' sort buttons.
void main() {
  group('low-memory mode', () {
    test('reads the RAM from /proc/meminfo', () {
      expect(memTotalMb('MemTotal:        2011420 kB\nMemFree:          301204 kB\n'), 1964);
      expect(memTotalMb('MemFree: 1 kB\n'), isNull);
    });

    test('takes in 64-bit TVs with 2 or 3 GB, not 4 GB ones', () {
      expect(lowMemoryRam(1964), isTrue); // a "2 GB" Fire TV stick
      expect(lowMemoryRam(2860), isTrue); // 3 GB
      expect(lowMemoryRam(3700), isFalse); // 4 GB
      expect(lowMemoryRam(null), isFalse);
    });
  });

  group('transcode clock', () {
    const length = Duration(hours: 3, minutes: 12);

    test('a sensible position passes through', () {
      expect(sanePosition(const Duration(minutes: 42), length: length), const Duration(minutes: 42));
      expect(sanePosition(Duration.zero, length: length), Duration.zero);
    });

    test('a clock that wrapped below zero is unwrapped', () {
      // The cloud Fire TV showed 26:30:43 elapsed into Avatar after a pause and resume.
      expect(ptsWrap.inSeconds, 95443);
      expect(sanePosition(ptsWrap - const Duration(milliseconds: 300), length: length), Duration.zero);
      expect(sanePosition(ptsWrap + const Duration(minutes: 5), length: length), const Duration(minutes: 5));
    });

    test('nonsense past the end is refused, so the last good position stays', () {
      expect(sanePosition(const Duration(hours: 10), length: length), isNull);
      expect(sanePosition(ptsWrap - const Duration(hours: 2), length: length), isNull);
      // A little past Plex's figure is fine.
      expect(sanePosition(length + const Duration(seconds: 20), length: length), length + const Duration(seconds: 20));
    });
  });

  testWidgets('Down from the sort buttons on Movies goes to the first poster', skip: !isTv, (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const LibraryDest('1'));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    // Onto the sort buttons: the last one is furthest right.
    Focus.of(t.element(find.text('Rating'))).requestFocus();
    await t.pump();
    expect(focused(), contains('Rating'));
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), startsWith('Film 1 '));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
