import 'package:console_app/ui/settings/plex_link_code.dart';
import 'package:console_app/ui/settings/settings_field.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final first = TextEditingController();
  final second = TextEditingController();
  final submitted = <String>[];

  Future<void> page(WidgetTester tester) async {
    submitted.clear();
    first.clear();
    second.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              ConsoleButton(label: 'Above', autofocus: true, onPressed: () {}),
              SettingsField(label: 'Address', controller: first, tv: true),
              SettingsField(label: 'Key', controller: second, tv: true, onSubmitted: submitted.add),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  EditableText editable(WidgetTester tester, int i) => tester.widget<EditableText>(find.byType(EditableText).at(i));

  testWidgets('on a TV the arrows move past a field without opening the keyboard', (tester) async {
    await page(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(editable(tester, 0).focusNode.hasFocus, isTrue);
    expect(editable(tester, 0).readOnly, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(editable(tester, 1).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(editable(tester, 0).focusNode.hasFocus, isTrue);
  });

  testWidgets('Select opens the keyboard, Next moves on and Done submits', (tester) async {
    await page(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(editable(tester, 0).readOnly, isFalse);
    expect(tester.testTextInput.isVisible, isTrue);
    tester.testTextInput.enterText('http://plex.lan:32400');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(first.text, 'http://plex.lan:32400');
    expect(editable(tester, 0).readOnly, isTrue);
    expect(editable(tester, 1).focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, ['secret']);
    expect(editable(tester, 1).readOnly, isTrue);
  });

  testWidgets('Back stops editing and keeps the text', (tester) async {
    await page(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('abc');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editable(tester, 0).readOnly, isTrue);
    expect(editable(tester, 0).focusNode.hasFocus, isTrue);
    expect(first.text, 'abc');
  });

  testWidgets('the link code shows the code, its time left and both buttons', (tester) async {
    var renewed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlexLinkCode(code: 'AB12', left: const Duration(minutes: 14, seconds: 5), expired: false, onNewCode: () => renewed++, onCancel: () {}),
          ),
        ),
      ),
    );
    expect(find.text('AB12'), findsOneWidget);
    expect(find.textContaining('14:05'), findsOneWidget);
    expect(find.textContaining('plex.tv/link'), findsOneWidget);
    await tester.tap(find.text('Get a New Code'));
    expect(renewed, 1);
  });
}
