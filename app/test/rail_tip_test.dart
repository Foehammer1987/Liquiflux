import 'package:console_app/platform.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'tv_harness.dart';

/// The sidebar's name labels: each button's name shows beside the rail while it has D-pad /
/// keyboard focus or the pointer is over it.
///   flutter test test/rail_tip_test.dart              (desktop: the mouse)
///   CONSOLE_TV=1 flutter test test/rail_tip_test.dart (TV: the D-pad)

/// How visible [label]'s tip is: 0 hidden, 1 shown, null when there's no such rail button.
double? tip(WidgetTester t, String label) {
  final box = find.byKey(ValueKey('rail-tip:$label'));
  if (box.evaluate().isEmpty) return null;
  return t.widget<AnimatedOpacity>(find.ancestor(of: box, matching: find.byType(AnimatedOpacity)).first).opacity;
}

/// The labels showing right now.
List<String> shown(WidgetTester t) => [
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('rail-tip:')).evaluate())
    if (t.widget<AnimatedOpacity>(find.ancestor(of: find.byWidget(e.widget), matching: find.byType(AnimatedOpacity)).first).opacity == 1)
      (e.widget.key as ValueKey<String>).value.substring('rail-tip:'.length),
];

void main() {
  setUp(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  testWidgets('every rail button has a label, all hidden until something is pointed at or focused', (t) async {
    await tvApp(t);
    for (final l in ['Home', 'Trending', 'Collections', 'TV Networks', 'Moods', 'Shuffle Play', 'Channels', 'Movies', 'TV Shows', 'Requests', 'Settings']) {
      expect(tip(t, l), isNotNull, reason: l);
    }
    expect(shown(t), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the mouse over a rail button shows its name, and moving off hides it', skip: isTv, (t) async {
    await tvApp(t);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    // The rail slides in from the edge.
    await mouse.addPointer(location: const Offset(600, 270));
    await mouse.moveTo(const Offset(4, 270));
    await t.pump();
    await mouse.moveTo(const Offset(6, 270));
    await t.pump(const Duration(milliseconds: 500));
    await mouse.moveTo(t.getCenter(find.byIcon(LucideIcons.layers).first));
    await t.pump(const Duration(milliseconds: 300));
    expect(shown(t), ['Collections']);
    await mouse.moveTo(t.getCenter(find.byIcon(LucideIcons.sparkles).first));
    await t.pump(const Duration(milliseconds: 300));
    expect(shown(t), ['Moods']);
    // Off the rail, onto the page.
    await mouse.moveTo(const Offset(600, 300));
    await t.pump(const Duration(milliseconds: 800));
    expect(shown(t), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the D-pad shows the focused button\'s name as it moves, and leaving the rail hides it', skip: !isTv, (t) async {
    await tvApp(t);
    expect(shown(t), isEmpty);
    await press(t, LogicalKeyboardKey.arrowLeft);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'rail:home');
    expect(shown(t), ['Home']);
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(shown(t), ['Trending']);
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(shown(t), ['Collections']);
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), isNot(startsWith('rail:')));
    expect(shown(t), isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
