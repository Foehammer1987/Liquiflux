import 'package:console_app/ui/intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => IntroGate.played = false);

  Widget app({bool enabled = true, ValueChanged<KeyEvent>? onKey}) => MaterialApp(
    builder: (context, child) => IntroGate(enabled: enabled, child: child!),
    home: Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        onKey?.call(e);
        return KeyEventResult.handled;
      },
      child: const Text('home'),
    ),
  );

  testWidgets('plays once over the app, then leaves it', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(Intro), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2300));
    // The name's letters have surfaced.
    expect(find.text('Q'), findsOneWidget);
    await tester.pump(Intro.total);
    await tester.pump();
    expect(find.byType(Intro), findsNothing);

    // Rebuilt (a theme change), it doesn't play again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    expect(find.byType(Intro), findsNothing);
  });

  testWidgets('off: never shows', (tester) async {
    await tester.pumpWidget(app(enabled: false));
    expect(find.byType(Intro), findsNothing);
  });

  testWidgets('a key skips to the end and never reaches the app, key-up included', (tester) async {
    final seen = <KeyEvent>[];
    await tester.pumpWidget(app(onKey: seen.add));
    await tester.pump(const Duration(milliseconds: 300));
    // Handled means Android doesn't act on it either (web's key tables know a Back key).
    expect(await simulateKeyDownEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isTrue);
    // The send-off alone (650 ms), not the rest of the 3.4 s.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.byType(Intro), findsNothing);
    // Released after the intro has gone: still swallowed, so Android sees no stray Back.
    expect(await simulateKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isTrue);
    expect(seen, isEmpty);

    // Later keys reach the app as usual.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(seen.whereType<KeyDownEvent>().map((e) => e.logicalKey), [LogicalKeyboardKey.arrowDown]);
  });
}
