import 'package:console_app/ui/back_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _BackIntent extends Intent {
  const _BackIntent();
}

/// Remote keys as the framework receives them; the result is whether the app handled the
/// event (Android acts on the unhandled ones itself). Web's key tables are the ones the test
/// simulator knows a Back key in.
PhysicalKeyboardKey _physical(LogicalKeyboardKey k) => k == LogicalKeyboardKey.goBack ? PhysicalKeyboardKey.browserBack : PhysicalKeyboardKey.keyQ;
Future<bool> down(LogicalKeyboardKey k) => simulateKeyDownEvent(k, physicalKey: _physical(k), platform: 'web');
Future<bool> up(LogicalKeyboardKey k) => simulateKeyUpEvent(k, physicalKey: _physical(k), platform: 'web');

void main() {
  Future<void> pump(WidgetTester tester, {required bool handleBelow, required void Function() onBack}) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BackKeyGuard(
          child: Shortcuts(
            shortcuts: {if (handleBelow) const SingleActivator(LogicalKeyboardKey.goBack): const _BackIntent()},
            child: Actions(
              actions: {_BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) => onBack())},
              child: Focus(focusNode: focus, autofocus: true, child: const SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a Back the app handled on key-down does not also reach Android on key-up', (tester) async {
    var backs = 0;
    await pump(tester, handleBelow: true, onBack: () => backs++);
    expect(await down(LogicalKeyboardKey.goBack), isTrue);
    // Handled here means Android never sees it, so no second (system) Back.
    expect(await up(LogicalKeyboardKey.goBack), isTrue);
    expect(backs, 1);
  });

  testWidgets('a Back nothing handled goes on to Android, which makes it a system Back', (tester) async {
    await pump(tester, handleBelow: false, onBack: () {});
    expect(await down(LogicalKeyboardKey.goBack), isFalse);
    expect(await up(LogicalKeyboardKey.goBack), isFalse);
  });

  testWidgets('each press is judged on its own', (tester) async {
    await pump(tester, handleBelow: false, onBack: () {});
    await down(LogicalKeyboardKey.goBack);
    await up(LogicalKeyboardKey.goBack);
    await down(LogicalKeyboardKey.goBack);
    expect(await up(LogicalKeyboardKey.goBack), isFalse);
  });

  testWidgets('other keys pass straight through', (tester) async {
    await pump(tester, handleBelow: true, onBack: () {});
    expect(await down(LogicalKeyboardKey.keyQ), isFalse);
    expect(await up(LogicalKeyboardKey.keyQ), isFalse);
  });
}
