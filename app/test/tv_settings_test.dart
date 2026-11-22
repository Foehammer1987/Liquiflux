import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/pages/settings_page.dart';
import 'package:console_app/platform.dart';
import 'package:console_app/services/playback_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Settings by remote, as a TV lays it out: categories down the left, one column of settings.
/// Run with CONSOLE_TV=1 (without it the page is the desktop's, and these are skipped).
void main() {
  final tv = isTv;
  setUp(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  Future<void> open(WidgetTester t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const SettingsDest());
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  double scrolled(WidgetTester t) => t.state<ScrollableState>(find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first).position.pixels;

  /// Down until focus stops moving: every stop's name, starting with the one in focus.
  Future<List<String>> walk(WidgetTester t, LogicalKeyboardKey key) async {
    final stops = [focused()];
    for (var i = 0; i < 40; i++) {
      final before = FocusManager.instance.primaryFocus;
      await press(t, key, wait: const Duration(milliseconds: 300));
      if (FocusManager.instance.primaryFocus == before) break;
      stops.add(focused());
    }
    return stops;
  }

  const playback = [
    'On Your Network',
    'Away From Home',
    'Allow Direct Play',
    'Allow Direct Stream',
    'Skip Back',
    'Skip Forward',
    'Skip Intro',
    'Skip Credits',
    'When You Come Back',
    'Play the Next Episode',
    'Countdown',
    'Pause Screen',
  ];

  testWidgets('Down walks every Playback setting in order, and Up walks them back', skip: !tv, (t) async {
    await open(t);
    expect(focused(), 'Settings category Servers');
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'Settings category Playback');
    // The category in focus is the one that's open.
    expect(find.text('Skip Intro'), findsOneWidget);
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(await walk(t, LogicalKeyboardKey.arrowDown), playback);
    expect(await walk(t, LogicalKeyboardKey.arrowUp), playback.reversed);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('every category walks the same way down and up, with no stop left out', skip: !tv, (t) async {
    await open(t);
    for (var i = 0; i < 8; i++) {
      final category = focused();
      expect(category, startsWith('Settings category'));
      await press(t, LogicalKeyboardKey.arrowRight);
      expect(focused(), isNot(category), reason: 'Right from $category enters its settings');
      final down = await walk(t, LogicalKeyboardKey.arrowDown);
      final up = await walk(t, LogicalKeyboardKey.arrowUp);
      expect(up, down.reversed, reason: category);
      // Every control of the category was a stop.
      final pane = FocusManager.instance.primaryFocus!.nearestScope!;
      final all = [
        for (final n in pane.traversalDescendants)
          if (n is! FocusScopeNode && n.context?.mounted == true && !n.rect.isEmpty && hiddenStop(n) == null) n,
      ];
      expect(down.length, all.length, reason: '$category: $down');
      await press(t, LogicalKeyboardKey.arrowLeft);
      expect(focused(), category, reason: 'Left comes back to the category');
      await press(t, LogicalKeyboardKey.arrowDown);
    }
    // Left from the categories opens the rail, as from the edge of any page.
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), startsWith('rail:'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the page stays still until focus nears its edge', skip: !tv, (t) async {
    await open(t);
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 5; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
      expect(scrolled(t), 0, reason: 'press ${i + 1}');
    }
    await walk(t, LogicalKeyboardKey.arrowDown);
    expect(scrolled(t), greaterThan(0));
    final r = FocusManager.instance.primaryFocus!.rect;
    expect(r.bottom, lessThanOrEqualTo(540));
    await walk(t, LogicalKeyboardKey.arrowUp);
    expect(scrolled(t), 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Select flips a switch, and opens the choices of a segmented control', skip: !tv, (t) async {
    final app = await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const SettingsDest());
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'Allow Direct Play');
    expect(app.settings.playback.allowDirectPlay, isTrue);
    await press(t, LogicalKeyboardKey.select);
    expect(app.settings.playback.allowDirectPlay, isFalse);
    await press(t, LogicalKeyboardKey.select);
    expect(app.settings.playback.allowDirectPlay, isTrue);

    for (var i = 0; i < 4; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(), 'Skip Intro');
    final was = app.settings.playback.skipIntro;
    await press(t, LogicalKeyboardKey.select);
    // The list opens on the choice in use, and Up and Down stay inside it.
    expect(focused(), was.label);
    final choices = await walk(t, LogicalKeyboardKey.arrowUp);
    expect(await walk(t, LogicalKeyboardKey.arrowDown), [for (final m in SkipMode.values) m.label]);
    expect(choices.last, SkipMode.values.first.label);
    await press(t, LogicalKeyboardKey.select);
    expect(app.settings.playback.skipIntro, SkipMode.values.last);
    // Back on the row it was opened from.
    expect(focused(), 'Skip Intro');
    expect(find.text(SkipMode.values.last.label), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
