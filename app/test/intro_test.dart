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
    // The send-off alone (700 ms), not the rest of the 3.6 s.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(find.byType(Intro), findsNothing);
    // Released after the intro has gone: still swallowed, so Android sees no stray Back.
    expect(await simulateKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isTrue);
    expect(seen, isEmpty);

    // Later keys reach the app as usual.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(seen.whereType<KeyDownEvent>().map((e) => e.logicalKey), [LogicalKeyboardKey.arrowDown]);
  });

  testWidgets('the Exit key is never swallowed: on a Samsung TV it closes the app', (tester) async {
    final seen = <KeyEvent>[];
    await tester.pumpWidget(app(onKey: seen.add));
    await tester.pump(const Duration(milliseconds: 300));
    // As flutter-tizen sends it: the physical Exit key, with no logical key of its own.
    // ignore: deprecated_member_use
    final handler = ServicesBinding.instance.keyEventManager.keyMessageHandler!;
    const logical = LogicalKeyboardKey(0x1400000000);
    // ignore: deprecated_member_use
    handler(KeyMessage([const KeyDownEvent(logicalKey: logical, physicalKey: PhysicalKeyboardKey.exit, timeStamp: Duration.zero)], null));
    // ignore: deprecated_member_use
    handler(KeyMessage([const KeyUpEvent(logicalKey: logical, physicalKey: PhysicalKeyboardKey.exit, timeStamp: Duration.zero)], null));
    // It went on to the app (flutter-tizen closes the app when nothing handles it) ...
    expect(seen.map((e) => e.physicalKey), [PhysicalKeyboardKey.exit, PhysicalKeyboardKey.exit]);
    // ... and didn't skip the intro.
    expect(find.byType(Intro), findsOneWidget);
    await tester.pump(Intro.total);
    await tester.pump();
  });
}
