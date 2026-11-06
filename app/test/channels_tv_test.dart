import 'package:console_app/platform.dart';
import 'package:console_app/ui/channels/channel_editor.dart';
import 'package:console_app/ui/channels/channels_page.dart';
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

/// Channels with the remote: New Channel, pick a show, see its share, save, and the card's
/// Watch button. Run as a TV: CONSOLE_TV=1 flutter test test/channels_tv_test.dart
void main() {
  testWidgets('make a channel and reach every control with the D-pad', skip: !isTv, (t) async {
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const ChannelsDest());
    await settle(t, 30);
    expect(find.byType(ChannelsPage), findsOneWidget);
    expect(find.text('No channels yet'), findsOneWidget);

    // The page lands on New Channel; Select opens the editor, on what the channel plays.
    expect(focused(), 'New Channel');
    await press(t, LogicalKeyboardKey.select);
    await settle(t);
    expect(find.byType(ChannelEditor), findsOneWidget);
    expect(focused(), 'Collection');
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Label');
    // No collections or labels on this server: the editor says so instead of an empty list.
    expect(find.text('No collections in your Plex libraries yet.'), findsOneWidget);

    await t.tap(find.text('Show').first);
    await settle(t);
    await t.tap(find.text('Pick one'));
    await settle(t);
    await t.tap(find.textContaining('Show 203').last);
    await settle(t, 30);
    expect(find.textContaining('1 show, 24 episodes'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await t.tap(find.text('Show').at(1));
    await settle(t);
    await t.tap(find.text('Pick one'));
    await settle(t);
    await t.tap(find.textContaining('Show 210').last);
    await settle(t);
    expect(find.text('After every episode'), findsOneWidget);

    // The remote can get around the editor and back without getting stuck.
    Focus.of(t.element(find.text('Save'))).requestFocus();
    await press(t, LogicalKeyboardKey.shiftLeft);
    final odd = await walk(t, limit: 40);
    expect(odd, isEmpty, reason: odd.join('\n'));

    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.byType(ChannelEditor), findsNothing);
    expect(find.text('Show 203'), findsOneWidget);
    expect(find.text('Bumpers from Show 210 between episodes'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
