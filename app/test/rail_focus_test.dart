import 'package:console_app/ui/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget card(String name, {double width = 60, double height = 44}) => Focus(
  debugLabel: name,
  child: SizedBox(width: width, height: height),
);

String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

/// The shell in miniature: the sidebar down the left (Home at the top, Settings at the
/// bottom), and the page beside it in its own scope, its rows running lower than Settings.
Future<List<TraversalDirection>> shell(WidgetTester t, {required bool panel}) async {
  t.view.physicalSize = const Size(1200, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final edges = <TraversalDirection>[];
  final rail = Column(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [card('home'), card('trending'), card('settings')],
  );
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 600,
              child: panel ? FocusPanel(onEdge: edges.add, child: FocusTraversalGroup(policy: TvTraversalPolicy(), child: rail)) : rail,
            ),
            Expanded(
              child: FocusScope(
                child: Column(children: [for (var i = 0; i < 8; i++) card('row $i', width: 200, height: 96)]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return edges;
}

void focus(WidgetTester t, String name) => t.binding.focusManager.rootScope.descendants.firstWhere((n) => n.debugLabel == name).requestFocus();

void main() {
  testWidgets('without a panel, Down from Settings leaves the sidebar for the page (the bug)', (t) async {
    await shell(t, panel: false);
    focus(t, 'settings');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), startsWith('row'));
  });

  testWidgets('Down from Settings stays on Settings', (t) async {
    final edges = await shell(t, panel: true);
    focus(t, 'settings');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'settings');
    expect(edges, [TraversalDirection.down]);
  });

  testWidgets('Up and Down still move within the sidebar, and Up from the top reports the edge', (t) async {
    final edges = await shell(t, panel: true);
    focus(t, 'settings');
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'trending');
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'home');
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'home');
    expect(edges, [TraversalDirection.up]);
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'trending');
  });
}
