// The phone and tablet app on a simulator or device, page by page, for screenshots and a
// look at every screen: run it with tools/ios-tour.sh, which launches it on a simulator and
// takes a screenshot at each "SHOT name" line this prints.
//
// Signed in (the fake servers of tools/mock-servers.mjs, given through the environment as for
// any dev build): Home, a library, a title page, search, the More sheet, Settings and About,
// the player, then Home on its side. Signed out (TOUR=welcome): the welcome page, the link
// code page and the browser sign-in.
import 'dart:async';

import 'package:console_app/main.dart' as app;
import 'package:console_app/state/scope.dart';
import 'package:console_app/ui/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tour = String.fromEnvironment('TOUR', defaultValue: 'app');

/// The fake servers (tools/mock-servers.mjs). A simulator reaches the Mac at localhost.
const _plex = String.fromEnvironment('MOCK_PLEX', defaultValue: 'http://localhost:9001');
const _seerr = String.fromEnvironment('MOCK_SEERR', defaultValue: 'http://localhost:9002');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Real time passes (the app's own timers, the network) while frames are drawn.
  Future<void> wait(WidgetTester t, double seconds) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Asks tools/ios-tour.sh for a screenshot, and gives it time to take one.
  Future<void> shot(WidgetTester t, String name) async {
    await wait(t, 1.5);
    debugPrint('SHOT $name');
    await wait(t, 2.5);
  }

  Future<bool> tapText(WidgetTester t, String text) async {
    final f = find.text(text, skipOffstage: true);
    if (f.evaluate().isEmpty) {
      debugPrint('TOUR: no "$text" on screen');
      return false;
    }
    await t.tap(f.first, warnIfMissed: false);
    return true;
  }

  Size screen(WidgetTester t) => t.view.physicalSize / t.view.devicePixelRatio;

  /// A finger drag up the middle of the screen (the page scrolls).
  Future<void> scrollUp(WidgetTester t, double by) async {
    final s = screen(t);
    await t.dragFrom(Offset(s.width / 2, s.height * 0.7), Offset(0, -by));
  }

  ShellNav nav(WidgetTester t) => ShellNav.of(t.element(find.descendant(of: find.byType(ShellNav), matching: find.byType(Navigator)).first));

  testWidgets('signed out: welcome, link code, browser sign-in', (t) async {
    unawaited(app.main());
    await wait(t, 9);
    await shot(t, 'welcome');
    if (await tapText(t, 'Use a Link Code')) {
      await wait(t, 4);
      await shot(t, 'link-code');
      await tapText(t, 'Cancel');
      await wait(t, 2);
    }
    if (await tapText(t, 'Enter Address Manually')) {
      await wait(t, 2);
      await shot(t, 'welcome-manual');
      final field = find.byType(EditableText);
      if (field.evaluate().isNotEmpty) {
        await t.tap(field.first, warnIfMissed: false);
        await wait(t, 2);
        await shot(t, 'welcome-keyboard');
        FocusManager.instance.primaryFocus?.unfocus();
        await wait(t, 1);
      }
    }
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
    await wait(t, 2);
    await shot(t, 'welcome-landscape');
    await SystemChrome.setPreferredOrientations(const []);
  }, skip: _tour != 'welcome', timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('signed in: every page', (t) async {
    unawaited(app.main());
    await wait(t, 9);
    // Signed in as with Enter Address Manually.
    final state = AppScope.read(t.element(find.byType(Navigator).first));
    await state.update(state.settings.copyWith(plexUrl: _plex, plexToken: 'x', seerrUrl: _seerr, seerrApiKey: 'x', seerrEnabled: true));
    await wait(t, 8);
    await shot(t, 'home');
    await scrollUp(t, 600);
    await wait(t, 2);
    await shot(t, 'home-rows');

    nav(t).go(const LibraryDest('1'));
    await wait(t, 4);
    await shot(t, 'library');

    nav(t).push(const ItemDest('100'));
    await wait(t, 5);
    await shot(t, 'detail');
    await scrollUp(t, 500);
    await wait(t, 2);
    await shot(t, 'detail-more');

    nav(t).go(const SearchDest('the'));
    await wait(t, 4);
    await shot(t, 'search');
    // The search field and the keyboard.
    if (await tapText(t, 'Search')) {
      await wait(t, 2);
      await shot(t, 'search-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(t, 1);
    }

    nav(t).go(const HomeDest());
    await wait(t, 2);
    if (await tapText(t, 'More')) {
      await wait(t, 2);
      await shot(t, 'more-sheet');
      await t.tapAt(const Offset(20, 120));
      await wait(t, 1);
    }

    nav(t).go(const SettingsDest());
    await wait(t, 3);
    await shot(t, 'settings');
    if (await tapText(t, 'Advanced')) {
      await wait(t, 2);
      for (var i = 0; i < 6; i++) {
        await scrollUp(t, 500);
        await wait(t, 0.3);
      }
      await wait(t, 2);
      await shot(t, 'settings-about');
    }

    nav(t).push(const ItemDest('100'));
    await wait(t, 4);
    if (await tapText(t, 'Play') || await tapText(t, 'Resume')) {
      await wait(t, 8);
      await t.tapAt(t.view.physicalSize.center(Offset.zero) / t.view.devicePixelRatio);
      await wait(t, 1);
      await shot(t, 'player');
      // Leaves as its back button does.
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await wait(t, 4);
    }

    nav(t).go(const HomeDest());
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
    await wait(t, 3);
    await shot(t, 'home-landscape');
    nav(t).push(const ItemDest('100'));
    await wait(t, 4);
    await shot(t, 'detail-landscape');
    await SystemChrome.setPreferredOrientations(const []);
    await wait(t, 2);
  }, skip: _tour != 'app', timeout: const Timeout(Duration(minutes: 8)));
}
