import 'package:console_app/platform.dart';
import 'package:console_app/ui/channels/channel_editor.dart';
import 'package:console_app/ui/channels/channels_page.dart';
import 'package:console_app/ui/channels/source_picker.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const down = LogicalKeyboardKey.arrowDown, up = LogicalKeyboardKey.arrowUp, select = LogicalKeyboardKey.select;

/// Presses [key] until focus is on [target] (by its label), failing after [max] presses.
Future<void> until(WidgetTester t, LogicalKeyboardKey key, bool Function(String) target, {int max = 40}) async {
  final seen = <String>[];
  for (var i = 0; i < max && !target(focused()); i++) {
    await press(t, key, wait: const Duration(milliseconds: 250));
    seen.add(focused());
  }
  expect(target(focused()), isTrue, reason: 'never reached it; went ${seen.join(' > ')}');
}

/// The control with focus is on screen (the list scrolled to it).
void onScreen() {
  final r = FocusManager.instance.primaryFocus!.rect;
  expect(r.top >= 0 && r.bottom <= 540, isTrue, reason: '${focused()} is off screen at $r');
}

/// Channels with only the remote: New Channel, several shows ticked in the picker, one taken
/// out again, bumpers picked, saved. Run as a TV: CONSOLE_TV=1 flutter test test/channels_tv_test.dart
void main() {
  testWidgets('make a channel of several shows with the remote alone', skip: !isTv, (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const ChannelsDest());
    await settle(t, 30);
    expect(find.text('No channels yet'), findsOneWidget);

    // The page lands on New Channel; Select opens the editor, on Add.
    expect(focused(), 'New Channel');
    await press(t, select);
    await settle(t);
    expect(find.byType(ChannelEditor), findsOneWidget);
    expect(focused(), 'Add Shows and Collections');

    // The picker opens on its tabs; Down reaches Search, then the list.
    await press(t, select);
    await settle(t);
    expect(find.byType(SourcePicker), findsOneWidget);
    expect(focused(), startsWith('Shows'));
    await until(t, down, (f) => f.startsWith('Show 201'));
    await press(t, select);
    await press(t, down);
    await press(t, select);
    await press(t, down);
    await press(t, select);
    expect(find.text('3 chosen'), findsOneWidget);
    // Far down the list, focus stays on screen as the list scrolls.
    await until(t, down, (f) => f.startsWith('Show 225'));
    onScreen();
    await press(t, select);
    // Every control in the picker can be left and come back to.
    final pickerOdd = await walk(t, limit: 30);
    expect(pickerOdd, isEmpty, reason: pickerOdd.join('\n'));
    // Down off the end of the list reaches the buttons; Done is beside Cancel.
    await until(t, down, (f) => f == 'Done' || f == 'Cancel');
    await until(t, LogicalKeyboardKey.arrowRight, (f) => f == 'Done', max: 1);
    await press(t, select);
    await settle(t, 30);
    expect(find.byType(SourcePicker), findsNothing);
    expect(focused(), 'Add or Remove');
    expect(find.textContaining('4 shows, 96 episodes'), findsOneWidget);

    // Up from Add reaches the list of shows; Remove takes one out and focus comes back to Add.
    await until(t, up, (f) => f.startsWith('Remove Show 225'), max: 3);
    await press(t, select);
    await settle(t, 20);
    expect(focused(), 'Add or Remove');
    expect(find.textContaining('3 shows, 72 episodes'), findsOneWidget);

    // On down to the bumpers, and pick a show of clips (picking one closes the picker).
    await until(t, down, (f) => f == 'Choose Bumpers');
    await press(t, select);
    await settle(t);
    expect(find.text('Choose Bumpers'), findsWidgets);
    await until(t, down, (f) => f.startsWith('Show 230'));
    onScreen();
    await press(t, select);
    await settle(t, 20);
    expect(find.byType(SourcePicker), findsNothing);
    expect(focused(), 'Change Bumpers');
    expect(find.text('After every episode'), findsOneWidget);

    // Weights: + on a show changes its share.
    await until(t, down, (f) => f.startsWith('Less of Show 201'));
    await until(t, LogicalKeyboardKey.arrowRight, (f) => f.startsWith('More of Show 201'), max: 1);
    await press(t, select);
    expect(find.textContaining('(×1.5)'), findsOneWidget);

    // Every control in the editor can be left and come back to.
    final odd = await walk(t, limit: 40);
    expect(odd, isEmpty, reason: odd.join('\n'));

    // Save is at the bottom.
    Focus.of(t.element(find.text('Change Bumpers'))).requestFocus();
    await press(t, LogicalKeyboardKey.shiftLeft);
    await until(t, down, (f) => f == 'Save' || f == 'Cancel');
    await until(t, LogicalKeyboardKey.arrowRight, (f) => f == 'Save', max: 1);
    await press(t, select);
    await settle(t);
    expect(find.byType(ChannelEditor), findsNothing);
    expect(find.text('From Show 201, Show 202 and Show 203'), findsOneWidget);
    expect(find.text('Bumpers from Show 230 between episodes'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.byType(ChannelsPage), findsOneWidget);

    // Editing it again: Right from Watch to Edit; the picker's search narrows the list.
    Focus.of(t.element(find.text('Watch'))).requestFocus();
    await press(t, LogicalKeyboardKey.shiftLeft);
    await until(t, LogicalKeyboardKey.arrowRight, (f) => f == 'Edit', max: 2);
    await press(t, select);
    await settle(t, 30);
    expect(focused(), 'Add or Remove');
    expect(find.text('Delete'), findsOneWidget);
    await press(t, select);
    await settle(t);
    expect(find.text('3 chosen'), findsOneWidget);
    await until(t, down, (f) => f == 'SettingsField', max: 3);
    await press(t, select);
    await t.enterText(find.descendant(of: find.byType(SourcePicker), matching: find.byType(TextField)), 'show 222');
    await settle(t, 5);
    Finder inPicker(String t) => find.descendant(of: find.byType(SourcePicker), matching: find.textContaining(t));
    expect(inPicker('Show 2').evaluate().length, 1); // any case
    expect(inPicker('Show 222'), findsOneWidget);
    expect(inPicker('Show 201'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
