import 'package:console_app/ui/player/player_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desktop mini player's layer (PlayerDock): the app stays mounted under the player, is
/// hidden while the player fills the window, and is usable again while it sits in a corner.
void main() {
  final dock = PlayerDock.instance;
  const area = Size(1600, 900);

  setUp(() => dock.corner = Alignment.bottomRight);

  Future<int Function()> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = area;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PlayerDockHost(child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              TextButton(onPressed: () => taps++, child: const Text('Library')),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    return () => taps;
  }

  Widget player() => const ColoredBox(key: ValueKey('player'), color: Colors.black, child: SizedBox.expand());

  testWidgets('the player fills the window and hides the app once it has come in', (tester) async {
    await pumpApp(tester);
    expect(dock.active, isFalse);
    var closed = false;
    dock.open((_) => player()).then((_) => closed = true);
    await tester.pump();
    expect(dock.active, isTrue);
    // Still fading in: the app shows under it.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Library'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('player'))), area);
    expect(find.text('Library'), findsNothing, reason: 'offstage under a full-window player');
    expect(find.text('Library', skipOffstage: false), findsOneWidget, reason: 'but still mounted');
    dock.close();
    await tester.pumpAndSettle();
    expect(dock.active, isFalse);
    expect(closed, isTrue);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('minimized, the player sits in a corner and the app takes clicks and scrolls', (tester) async {
    final taps = await pumpApp(tester);
    dock.open((_) => player());
    await tester.pumpAndSettle();
    dock.minimize();
    await tester.pumpAndSettle();
    expect(dock.mini, isTrue);
    final rect = tester.getRect(find.byKey(const ValueKey('player')));
    expect(rect, PlayerDockHost.miniRect(area, Alignment.bottomRight));
    expect(rect.width / rect.height, closeTo(16 / 9, 0.01));
    await tester.tap(find.text('Library'));
    expect(taps(), 1);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels, greaterThan(200));
    // The player is still the same one, just smaller.
    expect(dock.active, isTrue);
    dock.expand();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('player'))), area);
    dock.close();
    await tester.pumpAndSettle();
  });

  testWidgets('dragging the mini player moves it to the nearest corner', (tester) async {
    await pumpApp(tester);
    dock.open((_) => player());
    await tester.pumpAndSettle();
    dock.minimize();
    await tester.pumpAndSettle();
    await tester.timedDrag(find.byKey(const ValueKey('player')), const Offset(-1000, -500), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(dock.corner, Alignment.topLeft);
    expect(tester.getRect(find.byKey(const ValueKey('player'))), PlayerDockHost.miniRect(area, Alignment.topLeft));
    dock.close();
    await tester.pumpAndSettle();
  });

  testWidgets('opening another title replaces the one playing, mini or not', (tester) async {
    await pumpApp(tester);
    var firstClosed = false;
    dock.open((_) => player()).then((_) => firstClosed = true);
    await tester.pumpAndSettle();
    dock.minimize();
    await tester.pumpAndSettle();
    dock.open((_) => const ColoredBox(key: ValueKey('second'), color: Colors.black, child: SizedBox.expand()));
    await tester.pumpAndSettle();
    expect(firstClosed, isTrue);
    expect(dock.mini, isFalse, reason: 'a new title opens full window');
    expect(find.byKey(const ValueKey('player')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('second'))), area);
    dock.close();
    await tester.pumpAndSettle();
  });

  test('the nearest corner follows where it is dropped and which way it is thrown', () {
    final mini = PlayerDockHost.miniSize(area);
    expect(PlayerDockHost.nearestCorner(area, const Offset(100, 100) & mini, Offset.zero), Alignment.topLeft);
    expect(PlayerDockHost.nearestCorner(area, const Offset(1100, 600) & mini, Offset.zero), Alignment.bottomRight);
    // Dropped just left of the middle but flung right.
    expect(PlayerDockHost.nearestCorner(area, Rect.fromCenter(center: const Offset(780, 700), width: mini.width, height: mini.height), const Offset(2000, 0)), Alignment.bottomRight);
  });

  test('the mini player keeps a sensible size in small and large windows', () {
    expect(PlayerDockHost.miniSize(const Size(800, 600)).width, 300);
    expect(PlayerDockHost.miniSize(const Size(3840, 2160)).width, 480);
  });
}
