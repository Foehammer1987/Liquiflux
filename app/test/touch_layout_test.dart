// The phone and tablet layout (iPhone, iPad, the Android phone/tablet build): the welcome
// page's logo, the screen's safe areas (notch, Dynamic Island, home indicator, a phone on
// its side), larger text, the keyboard, and the swipe back from the left edge.
//
// Run with CONSOLE_TOUCH=1 for the touch layout; the BackSwipe tests run either way.
import 'package:console_app/platform.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/touch.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// An iPhone 18 Pro on its side: the Dynamic Island at the left, rounded corners both sides.
const _landscape = Size(874, 402);
const _landscapeInsets = EdgeInsets.only(left: 62, right: 62, bottom: 21);

/// The top bar's small logo (Home); the welcome page's big one and the Home spotlight's
/// badge are ConsoleLogos too.
final _barLogo = find.byWidgetPredicate((w) => w is ConsoleLogo && w.height == 24);
final _anyLogo = find.byType(ConsoleLogo);

void main() {
  group('phone and tablet layout', () {
    testWidgets('the welcome page has one logo, below the status bar', (t) async {
      await touchApp(t, settle: 20, before: (s) => s.settings = const Settings(clientId: 'c'));
      expect(find.text('Welcome'), findsOneWidget);
      // No small logo in the top bar over the welcome page's own big one.
      expect(_barLogo, findsNothing);
      expect(_anyLogo, findsOneWidget);
      expect(t.getRect(_anyLogo).top, greaterThanOrEqualTo(62));
      expect(t.takeException(), isNull);
    });

    testWidgets('signed in: the top bar keeps its logo and sits below the status bar', (t) async {
      await touchApp(t);
      expect(_barLogo, findsOneWidget);
      expect(t.getRect(_barLogo).top, greaterThanOrEqualTo(62));
      final bar = t.getRect(find.byType(TouchBar));
      expect(bar.bottom, 874, reason: 'the bar reaches the bottom edge, its buttons above the home indicator');
      expect(t.getRect(find.text('Home').last).bottom, lessThanOrEqualTo(874 - 34));
      expect(t.takeException(), isNull);
    });

    testWidgets('on its side, pages and both bars keep clear of the camera housing', (t) async {
      await touchApp(t, size: _landscape, padding: _landscapeInsets);
      expect(t.getRect(_barLogo).left, greaterThanOrEqualTo(62));
      expect(t.getRect(find.text('Home').last).left, greaterThanOrEqualTo(62));
      expect(t.getRect(find.text('More').last).right, lessThanOrEqualTo(874 - 62));
      // The first row's first card.
      final firstCard = find.text('Continue Watching');
      if (firstCard.evaluate().isNotEmpty) expect(t.getRect(firstCard.first).left, greaterThanOrEqualTo(62));
      expect(t.takeException(), isNull);
    });

    testWidgets('the welcome page on its side keeps clear of the camera housing too', (t) async {
      await touchApp(t, size: _landscape, padding: _landscapeInsets, settle: 20, before: (s) => s.settings = const Settings(clientId: 'c'));
      expect(t.getRect(_anyLogo).left, greaterThanOrEqualTo(62));
      expect(t.getRect(find.text('Sign In with Plex')).left, greaterThanOrEqualTo(62));
      expect(t.takeException(), isNull);
    });

    for (final (name, size) in [('the smallest iPhone', const Size(375, 667)), ('an iPad in Slide Over', const Size(320, 1024)), ('an iPad mini', const Size(744, 1133))]) {
      testWidgets('the largest text size lays out without overflowing on $name', (t) async {
        await touchApp(t, size: size, padding: const EdgeInsets.only(top: 24, bottom: 20), textScale: 3);
        expect(t.takeException(), isNull);
        // Text grows, up to the app's limit.
        final scaler = MediaQuery.textScalerOf(t.element(find.byType(TouchBar)));
        expect(scaler.scale(10), closeTo(10 * touchMaxTextScale, 0.01));
      });
    }

    testWidgets('every page lays out with the largest text on the smallest iPhone', (t) async {
      await touchApp(t, size: const Size(375, 667), padding: const EdgeInsets.only(top: 20), textScale: 3);
      final nav = ShellNav.of(t.element(find.descendant(of: find.byType(ShellNav), matching: find.byType(Navigator)).first));
      for (final d in const <Dest>[LibraryDest('1'), LibraryDest('2'), ItemDest('1'), SearchDest('Film'), CollectionsDest(), MoodsDest(), RequestsDest(), SettingsDest()]) {
        nav.go(d);
        for (var i = 0; i < 15; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(t.takeException(), isNull, reason: '$d');
      }
    });

    testWidgets('every page lays out on a phone on its side', (t) async {
      await touchApp(t, size: _landscape, padding: _landscapeInsets);
      final nav = ShellNav.of(t.element(find.descendant(of: find.byType(ShellNav), matching: find.byType(Navigator)).first));
      for (final d in const <Dest>[LibraryDest('1'), ItemDest('1'), ItemDest('201'), ItemDest('20101'), ItemDest('2010101'), SearchDest('Film'), CollectionsDest(), MoodsDest(), RequestsDest(), SettingsDest()]) {
        nav.go(d);
        for (var i = 0; i < 15; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(t.takeException(), isNull, reason: '$d');
      }
    });

    testWidgets('the bottom bar stays behind the keyboard while you type', (t) async {
      await touchApp(t, keyboard: 336);
      expect(find.byType(TouchBar), findsNothing);
      expect(t.takeException(), isNull);
    });
  }, skip: !isTouch);

  group('swipe back from the left edge', () {
    Future<List<String>> pages(WidgetTester t, {required bool enabled}) async {
      final nav = GlobalKey<NavigatorState>();
      final stack = <String>['first'];
      await t.pumpWidget(
        MaterialApp(
          home: BackSwipe(
            enabled: enabled,
            canGoBack: () => nav.currentState!.canPop(),
            onBack: () {
              nav.currentState!.pop();
              stack.removeLast();
            },
            child: Navigator(
              key: nav,
              onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (_, _, _) => const ColoredBox(color: Colors.black, child: Center(child: Text('first')))),
            ),
          ),
        ),
      );
      nav.currentState!.push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const ColoredBox(color: Colors.black, child: Center(child: Text('second')))));
      stack.add('second');
      await t.pumpAndSettle();
      return stack;
    }

    testWidgets('a swipe from the edge goes back', (t) async {
      final stack = await pages(t, enabled: true);
      await t.dragFrom(const Offset(4, 300), const Offset(400, 0));
      await t.pumpAndSettle();
      expect(stack, ['first']);
      expect(find.text('first'), findsOneWidget);
    });

    testWidgets('a short swipe springs back', (t) async {
      final stack = await pages(t, enabled: true);
      final gesture = await t.startGesture(const Offset(4, 300));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(40, 0));
      await t.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await t.pumpAndSettle();
      expect(stack, ['first', 'second']);
    });

    testWidgets('a swipe that starts mid-screen is the page\'s own', (t) async {
      final stack = await pages(t, enabled: true);
      await t.dragFrom(const Offset(200, 300), const Offset(400, 0));
      await t.pumpAndSettle();
      expect(stack, ['first', 'second']);
    });

    testWidgets('off (Android, TVs, computers), the edge does nothing', (t) async {
      final stack = await pages(t, enabled: false);
      await t.dragFrom(const Offset(4, 300), const Offset(400, 0));
      await t.pumpAndSettle();
      expect(stack, ['first', 'second']);
    });
  });
}
