import 'package:console_app/platform.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/settings/tracking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

bool _inTracking() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null && ctx.findAncestorWidgetOfExactType<TrackingPanels>() != null;
}

/// The remote gets from Settings' tabs into the Tracking panels and through both of them.
/// Run as a TV: CONSOLE_TV=1 flutter test test/tracking_focus_test.dart
void main() {
  testWidgets('Down from the Tracking tab reaches Trakt and AniList', skip: !isTv, (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const SettingsDest());
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.tap(find.text('Tracking'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(TrackingPanels), findsOneWidget);
    Focus.of(t.element(find.text('Tracking'))).requestFocus();
    await t.pump(const Duration(milliseconds: 100));
    final seen = <String>{};
    for (var i = 0; i < 4; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
      if (_inTracking()) seen.add(focused());
    }
    // A source build has no Trakt app built in, so Trakt offers the phone page for its keys.
    expect(seen, containsAll(['Add Keys from My Phone', 'Connect AniList']));
    await t.pumpWidget(const SizedBox());
  });
}
