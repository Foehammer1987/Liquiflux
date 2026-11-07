import 'package:console_app/ui/notice_toast.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bottom-right cards (Ready to Watch, a Watch Together invitation) on a TV: the arrows
/// can't reach the corner from a page, so the card takes the remote's focus as it comes in.
void main() {
  Future<({FocusNode page, ValueNotifier<bool> shown, List<String> taps})> pump(WidgetTester tester, {bool takeFocus = true}) async {
    final page = FocusNode(debugLabel: 'page');
    final shown = ValueNotifier(false);
    final taps = <String>[];
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(glass: false),
        home: Scaffold(
          body: Stack(
            children: [
              Focus(focusNode: page, autofocus: true, child: const SizedBox(width: 100, height: 100)),
              ValueListenableBuilder(
                valueListenable: shown,
                builder: (_, on, _) => !on
                    ? const SizedBox()
                    : Positioned(
                        right: 0,
                        bottom: 0,
                        child: NoticeToast(
                          eyebrow: 'READY TO WATCH',
                          icon: LucideIcons.circleCheck,
                          title: 'A Film',
                          body: 'In your library now.',
                          primary: 'Play',
                          onPrimary: () => taps.add('play'),
                          secondary: 'Details',
                          onSecondary: () => taps.add('details'),
                          onDismiss: () => shown.value = false,
                          takeFocus: takeFocus,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(page.hasPrimaryFocus, isTrue);
    return (page: page, shown: shown, taps: taps);
  }

  testWidgets('takes the focus on Play; OK plays', (tester) async {
    final t = await pump(tester);
    t.shown.value = true;
    await tester.pump();
    await tester.pump();
    expect(t.page.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(t.taps, ['play']);
    t.shown.value = false;
    await tester.pumpAndSettle();
  });

  testWidgets('Back closes it and the focus goes back to the page', (tester) async {
    final t = await pump(tester);
    t.shown.value = true;
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(t.shown.value, isFalse);
    expect(t.page.hasPrimaryFocus, isTrue);
    expect(t.taps, isEmpty);
  });

  testWidgets('without takeFocus (desktop, or the player is up) it leaves the focus alone', (tester) async {
    final t = await pump(tester, takeFocus: false);
    t.shown.value = true;
    await tester.pump();
    await tester.pump();
    expect(t.page.hasPrimaryFocus, isTrue);
    t.shown.value = false;
    await tester.pumpAndSettle();
  });
}
