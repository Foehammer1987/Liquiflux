import 'package:console_app/app_info.dart';
import 'package:console_app/platform.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/settings/updates_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

bool _inUpdates() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null && ctx.findAncestorWidgetOfExactType<UpdatesPanel>() != null;
}

/// On the Shield, Down from Settings' tabs went past the Updates buttons (left-aligned, outside
/// the tab's column) to the mpv box. A TV's Settings now has categories down the left, and the
/// Updates panel is the first thing in Advanced. Run as a TV: CONSOLE_TV=1 flutter test test/updates_focus_test.dart
void main() {
  // Only where the app updates itself: an Apple build (or a store build) has no Updates panel.
  testWidgets('Advanced opens on the Updates panel, and Down walks its controls in turn', skip: !isTv || !selfUpdates, (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const SettingsDest());
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    // The category opens as focus reaches it, and Right enters its settings at the top.
    for (var i = 0; i < 8 && focused() != 'Settings category Advanced'; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(), 'Settings category Advanced');
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(_inUpdates(), isTrue, reason: 'Right from Advanced went to ${focused()}');
    // Then Down walks the panel: the buttons, Check at Launch, and only then the mpv box.
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'Check at Launch');
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(_inUpdates(), isFalse);
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'Check at Launch');
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(_inUpdates(), isTrue);
    await t.pumpWidget(const SizedBox());
  });
}
