import 'package:console_app/platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Home with the TV's own behaviour, so these only run as a TV:
///   CONSOLE_TV=1 flutter test test/tv_home_test.dart
void main() {
  setUp(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  ScrollPosition page(WidgetTester t) => Scrollable.of(t.element(find.text('Continue Watching')), axis: Axis.vertical).position;

  testWidgets('Home opens at the top with Play focused, and Up from the rows goes back there in one move', skip: !isTv, (t) async {
    await tvApp(t);
    expect(focused(), 'spotlight play');
    final y = page(t);
    expect(y.pixels, 0);
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(y.pixels, greaterThan(300));
    await press(t, LogicalKeyboardKey.arrowUp);
    final seen = <double>[];
    void log() => seen.add(y.pixels);
    y.addListener(log);
    await press(t, LogicalKeyboardKey.arrowUp, wait: const Duration(milliseconds: 900));
    y.removeListener(log);
    expect(focused(), 'spotlight play');
    expect(y.pixels, 0);
    // Only ever towards the top: no glide to the middle first.
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], lessThanOrEqualTo(seen[i - 1]));
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Back in the rows returns to the top of Home, on Play', skip: !isTv, (t) async {
    await tvApp(t);
    for (var i = 0; i < 3; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
    }
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(page(t).pixels, greaterThan(300));
    await press(t, LogicalKeyboardKey.goBack, wait: const Duration(milliseconds: 900));
    expect(page(t).pixels, 0);
    expect(focused(), 'spotlight play');
    // From there Back leaves the app (on Android only, so not here).
    await t.pumpWidget(const SizedBox());
  });
}
