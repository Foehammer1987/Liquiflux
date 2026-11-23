import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: ConsoleTheme.dark(),
  home: Scaffold(body: SizedBox(width: 300, child: child)),
);

void main() {
  testWidgets('downloading shows badge, percent and detail', (t) async {
    await t.pumpWidget(
      wrap(
        const RequestProgress(
          state: RequestState(label: 'Downloading', tone: Tone.info, progress: 0.42, detail: '18m left · done 7:42 PM', requestable: false),
        ),
      ),
    );
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('18m left · done 7:42 PM'), findsOneWidget);
  });

  testWidgets('available hides the bar', (t) async {
    await t.pumpWidget(
      wrap(
        const RequestProgress(
          state: RequestState(label: 'Available', tone: Tone.success, progress: 1, requestable: false),
        ),
      ),
    );
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('a narrow card (a phone) cuts the badge short instead of overflowing', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 96,
              child: RequestProgress(
                state: RequestState(label: 'Partially Available', tone: Tone.info, progress: 0.42, requestable: false),
              ),
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('42%'), findsOneWidget);
    final badge = t.getRect(find.text('Partially Available'));
    expect(badge.right, lessThanOrEqualTo(t.getRect(find.text('42%')).left));
  });

  testWidgets('button activates from the keyboard', (t) async {
    var taps = 0;
    await t.pumpWidget(wrap(ConsoleButton(label: 'Request', autofocus: true, onPressed: () => taps++)));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    expect(taps, 2);
  });
}
