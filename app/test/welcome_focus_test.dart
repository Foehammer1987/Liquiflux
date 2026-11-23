// The welcome (sign-in) page on a TV: focus starts on Sign In with Plex, and the remote can
// never get stuck above it. Before 1.0.18 the search pill sat over the welcome page; once focus
// reached it (Up from Sign In, or focus lost on launch, seen on Fire TV), Down did nothing,
// because the shell's "back to the page" step only knew routed pages.
//
// Run with CONSOLE_TV=1 (TV behaviour).
import 'package:console_app/platform.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

void main() {
  Future<void> welcome(WidgetTester t) async {
    await tvApp(t, settle: 20, before: (s) => s.settings = const Settings(clientId: 'c'));
  }

  testWidgets('signed out on a TV: Sign In has focus and there is no search pill', (t) async {
    await welcome(t);
    expect(find.text('Welcome'), findsOneWidget);
    expect(focused(), contains('Sign In with Plex'));
    expect(find.text('Search movies and shows'), findsNothing);
  }, skip: !isTv);

  testWidgets('signed out on a TV: Up, Down and Left never strand focus', (t) async {
    await welcome(t);
    for (final k in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
      await press(t, k);
      expect(focused(), isNot('none'), reason: 'after $k');
      expect(focused(), isNot('Search'), reason: 'after $k');
    }
    // Down reaches the other sign-in controls.
    var reached = false;
    for (var i = 0; i < 6 && !reached; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
      reached = focused().contains('Enter Address Manually') || !focused().contains('Sign In with Plex');
    }
    expect(reached, isTrue, reason: 'Down/Right should leave Sign In for the next control');
  }, skip: !isTv);

  testWidgets('signed out on a TV: focus lost on launch comes back to the welcome page', (t) async {
    await welcome(t);
    FocusManager.instance.primaryFocus?.unfocus(disposition: UnfocusDisposition.scope);
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(focused(), contains('Sign In with Plex'));
  }, skip: !isTv);

  testWidgets('signed out on a computer: no focus ring until a key is pressed', (t) async {
    await welcome(t);
    expect(find.text('Welcome'), findsOneWidget);
    expect(focused(), isNot(contains('Sign In with Plex')));
  }, skip: !isDesktop || isTv);
}
