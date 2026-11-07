import 'dart:io';

import 'package:console_app/platform.dart';
import 'package:console_app/services/avplay_player.dart';
import 'package:console_app/services/network_watch.dart';
import 'package:console_app/ui/player/player_session.dart';
import 'package:console_app/ui/tv_popups.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tizen package', () {
    final manifest = File('tizen/tizen-manifest.xml').readAsStringSync();

    test('is Liquiflux in Seller Office, at the app version, for TVs', () {
      final version = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:')).split(':').last.trim().split('+').first;
      expect(manifest, contains('<manifest package="com.foehammer.liquiflux" version="$version" '));
      expect(manifest, contains('appid="com.foehammer.liquiflux"'));
      expect(manifest, contains('<label>Liquiflux</label>'));
      expect(manifest, contains('<profile name="tv"/>'));
      expect(manifest, contains('api-version="6.0"'));
    });

    test('asks for the internet and nothing else', () {
      final privileges = RegExp(r'<privilege>([^<]+)</privilege>').allMatches(manifest).map((m) => m[1]).toList();
      expect(privileges, ['http://tizen.org/privilege/internet']);
    });
  });

  test('a Tizen app is told apart by flutter-tizen\'s variable', () {
    expect(tizenEnvironment({'TIZEN_API_VERSION': '6.0', 'HOME': '/opt/usr/home/owner'}), isTrue);
    expect(tizenEnvironment({'HOME': '/home/me'}), isFalse);
    // The test run itself is not on a TV.
    expect(isTizen, isFalse);
  });

  group('AVPlay address', () {
    const url = 'https://10-0-0-2.abc.plex.direct:32400/library/parts/1/file.mkv?X-Plex-Token=tok&X-Plex-Client-Identifier=id';

    test('moves the Plex headers AVPlay can\'t send into the address', () {
      final out = Uri.parse(avPlayUrl('https://h.plex.direct:32400/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fmetadata%2F1', {
        'X-Plex-Token': 'tok',
        'X-Plex-Product': 'Liquiflux',
        'Accept': 'application/json',
      }));
      expect(out.queryParameters['X-Plex-Token'], 'tok');
      expect(out.queryParameters['X-Plex-Product'], 'Liquiflux');
      expect(out.queryParameters['path'], '/library/metadata/1');
      expect(out.queryParameters.containsKey('Accept'), isFalse);
    });

    test('leaves what\'s already there, and an address with no headers alone', () {
      expect(Uri.parse(avPlayUrl(url, {'X-Plex-Token': 'other'})).queryParameters['X-Plex-Token'], 'tok');
      expect(avPlayUrl(url, const {}), url);
      // An online trailer gets no headers from the app, so nothing is added.
      expect(avPlayUrl('https://example.com/t.mp4', const {}), 'https://example.com/t.mp4');
    });
  });

  group('what a Samsung TV leaves to Plex', () {
    PlexStream s(String codec, int type) => PlexStream.fromJson({'id': 1, 'streamType': type, 'codec': codec});

    test('DTS and TrueHD sound, which Samsung TVs don\'t play', () {
      for (final c in ['dca', 'dts', 'truehd']) {
        expect(PlayerSession.directNeedsServer(direct: true, audio: s(c, 2), video: s('hevc', 1), samsung: true), isTrue, reason: c);
        // Android plays them (or passes them through) itself.
        expect(PlayerSession.directNeedsServer(direct: true, audio: s(c, 2), video: s('hevc', 1)), isFalse, reason: c);
      }
      expect(PlayerSession.directNeedsServer(direct: true, audio: s('eac3', 2), video: s('hevc', 1), samsung: true), isFalse);
    });

    test('AV1 plays on the TV; VC-1 and picture subtitles still go through Plex', () {
      expect(PlayerSession.directNeedsServer(direct: true, video: s('av1', 1), samsung: true), isFalse);
      expect(PlayerSession.directNeedsServer(direct: true, video: s('av1', 1)), isTrue);
      expect(PlayerSession.directNeedsServer(direct: true, video: s('vc1', 1), samsung: true), isTrue);
      expect(PlayerSession.directNeedsServer(direct: true, video: s('h264', 1), subtitle: s('pgs', 3), samsung: true), isTrue);
    });
  });

  group('network watch', () {
    final w = NetworkWatch.instance;
    tearDown(w.reset);

    test('counts as lost after two looks without a network, and back after one with', () {
      w.observe(false);
      expect(w.online.value, isTrue);
      w.observe(false);
      expect(w.online.value, isFalse);
      w.observe(false);
      expect(w.online.value, isFalse);
      w.observe(true);
      expect(w.online.value, isTrue);
      // One miss after coming back isn't enough again.
      w.observe(false);
      expect(w.online.value, isTrue);
    });

    test('an address only counts if it can reach another machine', () {
      expect(usableAddress(InternetAddress('192.168.50.20')), isTrue);
      expect(usableAddress(InternetAddress('2001:db8::5')), isTrue);
      expect(usableAddress(InternetAddress('127.0.0.1')), isFalse);
      expect(usableAddress(InternetAddress('169.254.10.4')), isFalse);
      expect(usableAddress(InternetAddress('fe80::1')), isFalse);
    });
  });

  group('Samsung popups', () {
    Future<Future<bool>> openExit(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConsoleTheme.dark(glass: false),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      final result = confirmExit(ctx);
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('exit: No is focused first and keeps the app open', (tester) async {
      final result = await openExit(tester);
      expect(find.text('Exit Liquiflux?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.byType(ExitPopup), findsNothing);
    });

    testWidgets('exit: Yes closes the app', (tester) async {
      final result = await openExit(tester);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('exit: Return (Esc to Flutter on Tizen) closes the popup', (tester) async {
      final result = await openExit(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.byType(ExitPopup), findsNothing);
    });

    testWidgets('confirm: Cancel is focused first, so OK twice does nothing', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConsoleTheme.dark(glass: false),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      final result = confirmAction(ctx, title: 'Delete Toonami?', action: 'Delete');
      await tester.pumpAndSettle();
      expect(find.text('Delete Toonami?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('network: the popup closes itself when the connection is back', (tester) async {
      final w = NetworkWatch.instance;
      addTearDown(w.reset);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConsoleTheme.dark(glass: false),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      w
        ..observe(false)
        ..observe(false);
      final shown = showNetworkLost(ctx);
      await tester.pumpAndSettle();
      expect(find.text('No network connection'), findsOneWidget);
      w.observe(true);
      await tester.pumpAndSettle();
      expect(find.byType(NetworkLostPopup), findsNothing);
      await shown;
    });
  });
}
