import 'package:console_app/ui/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A card the D-pad can land on, found again by [name].
Widget card(String name, {double width = 120, double height = 80}) => Focus(
  debugLabel: name,
  child: SizedBox(width: width, height: height),
);

/// Two Home-style rows: [top] scrolled well to the right, [bottom] at its start.
Widget rows({required FocusTraversalPolicy policy, required VoidCallback onEdge}) => MaterialApp(
  home: FocusTraversalGroup(
    policy: policy,
    // Like the shell: Left with nowhere to go opens the rail.
    child: Actions(
      actions: {DirectionalFocusIntent: _Edge(onEdge)},
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in ['top', 'bottom'])
              SingleChildScrollView(
                key: ValueKey(r),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 48),
                child: Row(children: [for (var i = 0; i < 20; i++) card('$r $i')]),
              ),
          ],
        ),
      ),
    ),
  ),
);

class _Edge extends DirectionalFocusAction {
  _Edge(this.onEdge);
  final VoidCallback onEdge;
  @override
  void invoke(DirectionalFocusIntent intent) {
    final moved = FocusManager.instance.primaryFocus!.focusInDirection(intent.direction);
    if (!moved && intent.direction == TraversalDirection.left) onEdge();
  }
}

String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

void focus(WidgetTester t, String name) {
  final node = t.binding.focusManager.rootScope.descendants.firstWhere((n) => n.debugLabel == name);
  node.requestFocus();
}

Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

Future<void> setUp(WidgetTester t, FocusTraversalPolicy policy, VoidCallback onEdge) async {
  t.view.physicalSize = const Size(1440, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(rows(policy: policy, onEdge: onEdge));
  // The top row scrolled along, so its early cards sit off the left edge.
  final top = t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('top')), matching: find.byType(Scrollable)));
  top.position.jumpTo(600);
  focus(t, 'bottom 0');
  await t.pumpAndSettle();
}

void main() {
  testWidgets("Flutter's own policy climbs to the row above from the start of a row (the bug)", (t) async {
    var edges = 0;
    await setUp(t, ReadingOrderTraversalPolicy(), () => edges++);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), startsWith('top'));
    expect(edges, 0);
  });

  testWidgets('Left at the start of a row is an edge, so the rail opens', (t) async {
    var edges = 0;
    await setUp(t, TvTraversalPolicy(), () => edges++);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'bottom 0');
    expect(edges, 1);
  });

  testWidgets('Left and Right move along the row, and Right stops at its end', (t) async {
    await setUp(t, TvTraversalPolicy(), () {});
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'bottom 1');
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'bottom 0');
    focus(t, 'bottom 19');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'bottom 19');
  });

  testWidgets('Up and Down still move between rows', (t) async {
    await setUp(t, TvTraversalPolicy(), () {});
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), startsWith('top'));
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'bottom 0');
  });

  // The player's bar: Mute, a collapsed volume slider, then the panel buttons far to the right,
  // all over a picture that takes focus too. Above: the seek bar. The app keeps the picture out
  // of traversal ([skipPicture]).
  Future<void> bar(WidgetTester t, FocusTraversalPolicy policy, {bool skipPicture = true}) async {
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: policy,
          child: Scaffold(
            body: Focus(
              debugLabel: 'picture',
              skipTraversal: skipPicture,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [Expanded(child: card('seek', height: 20))]),
                    Row(
                      children: [
                        card('play', width: 44, height: 44),
                        card('mute', width: 38, height: 38),
                        card('slider', width: 0, height: 38),
                        const Expanded(child: SizedBox()),
                        card('subtitles', width: 38, height: 38),
                        card('settings', width: 38, height: 38),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    focus(t, 'mute');
    await t.pumpAndSettle();
  }

  testWidgets("Flutter's own policy takes Right from Mute to the picture, which then seeks (the bug)", (t) async {
    await bar(t, ReadingOrderTraversalPolicy(), skipPicture: false);
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'picture');
  });

  testWidgets('Right from Mute reaches the buttons on the right, not the picture or the seek bar', (t) async {
    await bar(t, TvTraversalPolicy());
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'subtitles');
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'settings');
    await press(t, LogicalKeyboardKey.arrowLeft);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'mute');
  });

  testWidgets("Left skips an invisible button in the next card's corner (the 0.9.27 Home bug)", (t) async {
    await tuckedRow(t, shown: false);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'card 2');
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'card 1');
  });

  testWidgets('Left and Right skip a button tucked inside another card, even a visible one', (t) async {
    await tuckedRow(t, shown: true);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'card 2');
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'card 3');
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'card 4');
  });

  testWidgets('Up straight after Down goes back to the card it came from, across rows', (t) async {
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Wide cards above narrow ones, so the nearest card back down isn't the one you left.
    Widget row(String r, double width, double left) => SingleChildScrollView(
      key: ValueKey(r),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(left: left, bottom: 40),
      child: Row(children: [for (var i = 0; i < 12; i++) card('$r $i', width: width, height: 100)]),
    );
    await t.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: TvTraversalPolicy(),
          child: Scaffold(
            body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [row('top', 200, 0), row('bottom', 120, 48)]),
          ),
        ),
      ),
    );
    focus(t, 'bottom 4');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowUp);
    final above = focused();
    expect(above, startsWith('top'));
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'bottom 4');
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), above);
    // A sideways move ends the trail: Down is then just the nearest card below.
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), startsWith('bottom'));
  });

  testWidgets('Up from a wide card under two buttons lands on the first', (t) async {
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: TvTraversalPolicy(),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(left: 48, top: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [card('play', width: 110, height: 46), const SizedBox(width: 12), card('info', width: 140, height: 46)]),
                  const SizedBox(height: 40),
                  card('wide', width: 340, height: 190),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    focus(t, 'wide');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'play');
  });

  testWidgets("Left from a row reaches the play button inside it, and Right comes back (an episode row)", (t) async {
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var edges = 0;
    Widget row(int i) => Focus(
      debugLabel: 'row $i',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [card('play $i', width: 192, height: 108), const SizedBox(width: 600, height: 108)]),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: TvTraversalPolicy(),
          child: Actions(
            actions: {DirectionalFocusIntent: _Edge(() => edges++)},
            child: Scaffold(body: Column(children: [row(1), row(2)])),
          ),
        ),
      ),
    );
    focus(t, 'row 1');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'play 1');
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'row 1');
    await press(t, LogicalKeyboardKey.arrowLeft);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'play 1');
    expect(edges, 1);
    // Down from the play button stays in its column.
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'play 2');
  });

  testWidgets('a control that gets focus glides to the middle, with no jump first', (t) async {
    await setUp(t, TvTraversalPolicy(), () {});
    final row = t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('bottom')), matching: find.byType(Scrollable))).position;
    // Far enough along that the next card is off the right edge.
    for (var i = 0; i < 9; i++) {
      await press(t, LogicalKeyboardKey.arrowRight);
    }
    final seen = <double>[];
    void log() => seen.add(row.pixels);
    row.addListener(log);
    final before = row.pixels;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    // Nothing moved in the same frame as the key: no jump.
    expect(row.pixels, before);
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    row.removeListener(log);
    expect(focused(), 'bottom 10');
    // Small even steps to the card's centre.
    expect(seen.length, greaterThan(3));
    final node = FocusManager.instance.primaryFocus!;
    expect((node.rect.center.dx - 720).abs(), lessThan(2));
  });
  // A settings page as it was: tabs at the top left, each setting's control at the right in
  // its own width (a wide dropdown, a small switch, a three-part segmented control).
  Future<void> offsetRows(WidgetTester t) async {
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget setting(Widget control) => SizedBox(
      width: 760,
      height: 60,
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [control]),
    );
    await t.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: TvTraversalPolicy(),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [card('tab 1', width: 80, height: 28), card('tab 2', width: 80, height: 28)]),
                setting(card('dropdown', width: 220, height: 32)),
                setting(card('switch', width: 36, height: 20)),
                setting(Row(mainAxisSize: MainAxisSize.min, children: [card('seg 1', width: 90, height: 28), card('seg 2', width: 90, height: 28), card('seg 3', width: 40, height: 28)])),
                setting(card('last switch', width: 36, height: 20)),
                Row(children: [card('save', width: 80, height: 32)]),
              ],
            ),
          ),
        ),
      ),
    );
    focus(t, 'tab 1');
    await t.pumpAndSettle();
  }

  testWidgets('Down goes to the next line however far across its control is, never past it', (t) async {
    await offsetRows(t);
    final stops = <String?>[];
    for (var i = 0; i < 5; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
      stops.add(focused());
    }
    expect(stops, ['dropdown', 'switch', startsWith('seg'), 'last switch', 'save']);
  });

  testWidgets('Up from the bottom stops on every line too, and ends on the tabs', (t) async {
    await offsetRows(t);
    focus(t, 'save');
    await t.pumpAndSettle();
    final stops = <String?>[];
    for (var i = 0; i < 5; i++) {
      await press(t, LogicalKeyboardKey.arrowUp);
      stops.add(focused());
    }
    expect(stops, ['last switch', startsWith('seg'), 'switch', 'dropdown', startsWith('tab')]);
  });

  testWidgets('a run of Down moves keeps its column across a line that has nothing in it', (t) async {
    await offsetRows(t);
    focus(t, 'switch');
    await t.pumpAndSettle();
    // The switch sits over the last part of the segmented control; the line after it has only a
    // switch in that column, and the one after that only a button at the far left.
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'seg 3');
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'last switch');
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'save');
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'last switch');
  });
}

/// One Home-style row of cards, each with a small button tucked in its top-right corner,
/// shown ([shown]) or faded out to nothing.
Widget tucked({required bool shown}) => MaterialApp(
  home: FocusTraversalGroup(
    policy: TvTraversalPolicy(),
    child: Scaffold(
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 48, top: 100),
        child: Row(
          children: [
            for (var i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Stack(
                  children: [
                    card('card $i', width: 120, height: 180),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Opacity(opacity: shown ? 1 : 0, child: card('thumb $i', width: 32, height: 32)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> tuckedRow(WidgetTester t, {required bool shown}) async {
  t.view.physicalSize = const Size(1440, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(tucked(shown: shown));
  focus(t, 'card 3');
  await t.pumpAndSettle();

}
