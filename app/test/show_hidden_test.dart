import 'dart:async';

import 'package:console_app/ui/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nav = GlobalKey<NavigatorState>();
  const below = Key('below');

  Future<void> twoPages(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [rootStack],
        home: const SizedBox.expand(key: below),
      ),
    );
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ColoredBox(color: Colors.black))));
    await tester.pumpAndSettle();
  }

  tearDown(() => rootStack.routes.clear());

  testWidgets('the pages hidden behind another are drawn while shown, and hidden again after', (tester) async {
    await twoPages(tester);
    expect(rootStack.routes, hasLength(2));
    expect(find.byKey(below), findsNothing);
    expect(find.byKey(below, skipOffstage: false), findsOneWidget);

    showHidden(true);
    await tester.pump();
    expect(find.byKey(below), findsOneWidget);

    showHidden(false);
    await tester.pump();
    expect(find.byKey(below), findsNothing);
    expect(find.byKey(below, skipOffstage: false), findsOneWidget);
  });

  group('drawn again', () {
    // A page that changes once hidden (as artwork lets go), and counts its drawing.
    Future<int Function()> under(WidgetTester tester, Route<void> Function(WidgetBuilder) route) async {
      var paints = 0;
      final change = ValueNotifier(0);
      addTearDown(change.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()})),
          navigatorKey: nav,
          navigatorObservers: [rootStack],
          home: ValueListenableBuilder(
            valueListenable: change,
            builder: (_, _, _) => CustomPaint(painter: _Count(() => paints++), child: const SizedBox.expand()),
          ),
        ),
      );
      unawaited(nav.currentState!.push(route((_) => const ColoredBox(color: Colors.black))));
      await tester.pumpAndSettle();
      change.value++;
      await tester.pump();
      return () => paints;
    }

    testWidgets('under a page that fades in over it', (tester) async {
      final paints = await under(
        tester,
        (b) => PageRouteBuilder<void>(pageBuilder: (c, _, _) => b(c), transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child)),
      );
      final before = paints();
      showHidden(true);
      await tester.pump();
      expect(paints(), greaterThan(before));
      showHidden(false);
      await tester.pump();
    });

    // Why the player opens with its own fade on a 32-bit TV.
    testWidgets('not under a page that faded it out', (tester) async {
      final paints = await under(tester, (b) => MaterialPageRoute<void>(builder: b));
      final before = paints();
      showHidden(true);
      await tester.pump();
      expect(paints(), before);
      showHidden(false);
      await tester.pump();
    });
  });

  testWidgets('closed pages are forgotten', (tester) async {
    await twoPages(tester);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    showHidden(true);
    await tester.pump();
    expect(rootStack.routes, hasLength(1));
    showHidden(false);
    await tester.pump();
    expect(find.byKey(below), findsOneWidget);
  });
}

class _Count extends CustomPainter {
  _Count(this.painted);
  final VoidCallback painted;
  @override
  void paint(Canvas canvas, Size size) => painted();
  @override
  bool shouldRepaint(_Count old) => true;
}
