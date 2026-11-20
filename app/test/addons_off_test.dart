import 'package:console_app/services/settings_store.dart';
import 'package:console_app/state/app_state.dart';
import 'package:console_app/ui/nav.dart';
import 'package:flutter/widgets.dart';
import 'package:console_ui/console_ui.dart' show LucideIcons;
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Seerr and the Riptide server are add-ons for people who run them. Turned off (the default),
/// the app is Plex alone: no Seerr rows, tabs or prompts, and nothing asks either server.
void main() {
  void addonsOff(AppState s) => s
    ..settings = const Settings(clientId: 'c', plexUrl: 'http://plex.test:32400', plexToken: 'tok', seerrUrl: 'http://seerr.test', seerrApiKey: 'key', riptideUrl: 'http://riptide.test')
    ..seerr = null
    ..seerrConn = Conn.off;

  testWidgets('Home has no Seerr rows or tabs when Seerr is off', (t) async {
    await tvApp(t, before: addonsOff);
    expect(find.text('Continue Watching'), findsWidgets);
    expect(find.byIcon(LucideIcons.flame), findsNothing, reason: 'the Trending tab');
    for (final text in ['Trending, Not in Your Library', 'Top 10 Not in Your Library']) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(find.textContaining('Seerr'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Settings shows the add-ons as switches, off, with their fields hidden', (t) async {
    await tvApp(t, before: addonsOff);
    ShellNav.of(t.element(find.text('Continue Watching').first)).go(const SettingsDest());
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Use Seerr'), findsOneWidget);
    expect(find.text('Use a Riptide Server'), findsOneWidget);
    for (final text in ['Seerr Address', 'Riptide Server Address', 'Discovery', 'Notifications']) {
      expect(find.text(text), findsNothing, reason: text);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  test('saved addresses are kept but unused while switched off', () {
    const s = Settings(clientId: 'c', plexUrl: 'http://plex.test:32400', plexToken: 'tok', seerrUrl: 'http://seerr.test', seerrApiKey: 'key', riptideUrl: 'http://riptide.test');
    expect(s.seerrReady, isFalse);
    expect(s.riptideServer, '');
    final on = s.copyWith(seerrEnabled: true, riptideEnabled: true);
    expect(on.seerrReady, isTrue);
    expect(on.riptideServer, 'http://riptide.test');
  });
}
