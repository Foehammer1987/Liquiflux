import 'dart:convert';
import 'dart:io';

import 'package:console_app/services/scrobbler.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:console_app/state/app_state.dart';
import 'package:console_app/state/scope.dart';
import 'package:console_app/ui/profiles.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'settings_store_test.dart' show FakeSecrets;

const _owner = 'aaaa1111', _kid = 'bbbb2222', _machine = 'machine-1';

/// plex.tv as far as Plex Home goes: Sam (the owner, PIN 1111) and Kid (PIN 4321), and
/// Neotower's resources for each of them.
http.Response _plexTv(http.Request r) {
  http.Response json(Object b, [int s = 200]) => http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});
  final token = r.headers['X-Plex-Token'];
  final p = r.url.path;
  if (r.url.host == 'clients.plex.tv' && p == '/api/v2/home/users') {
    return json({
      'users': [
        {'uuid': _owner, 'title': 'Sam', 'admin': true, 'protected': true},
        {'uuid': _kid, 'title': 'Kid', 'restricted': true, 'protected': true},
      ],
    });
  }
  if (r.url.host == 'clients.plex.tv' && p == '/api/v2/user') return json({'uuid': token == 'owner-acct' ? _owner : _kid, 'title': 'Sam'});
  if (r.url.host == 'clients.plex.tv' && p.endsWith('/switch')) {
    if (token != 'owner-acct') return json({'error': 'not in home'}, 401);
    final want = p.contains(_kid) ? '4321' : '1111';
    if (r.url.queryParameters['pin'] != want) {
      return json({
        'errors': [
          {'code': 1041, 'message': 'Invalid PIN'},
        ],
      }, 403);
    }
    return json({'authToken': p.contains(_kid) ? 'kid-acct' : 'owner-acct'}, 201);
  }
  if (r.url.host == 'plex.tv' && p == '/api/v2/resources') {
    return json([
      {
        'name': 'Neotower',
        'clientIdentifier': _machine,
        'provides': 'server',
        'accessToken': token == 'kid-acct' ? 'kid-server' : 'owner-server',
        'connections': const [],
      },
    ]);
  }
  // The Plex server itself: not needed here.
  return http.Response('', 404);
}

void main() {
  group('per-person settings', () {
    test('swapping profiles puts each person\'s things away and brings them back', () {
      final owner = const Settings(clientId: 'c', watchName: 'Sam', plexOwnerId: _owner).copyWith(taste: const Taste().rate('movie:1', 'Film 1', up: true));
      final asKid = owner.swapProfile(_kid).copyWith(plexUserId: _kid);
      expect(asKid.taste.likes.isEmpty, isTrue);
      expect(asKid.watchName, '');
      expect(asKid.profiles.keys, ['']);
      final kidRated = asKid.copyWith(taste: const Taste().rate('movie:2', 'Film 2', up: false), watchName: 'Kid');
      final back = kidRated.swapProfile('').copyWith(plexUserId: '');
      expect(back.taste.toJson(), owner.taste.toJson());
      expect(back.watchName, 'Sam');
      expect(back.profiles.keys, [_kid]);
      final kidAgain = back.swapProfile(_kid);
      expect(kidAgain.watchName, 'Kid');
      expect(kidAgain.taste.toJson(), kidRated.taste.toJson());
    });

    test('backToOwner forgets the Home user and the switching token', () {
      final s = const Settings(clientId: 'c', plexOwnerId: _owner, plexUserId: _kid, plexUserName: 'Kid', plexHomeToken: 'owner-acct', watchName: 'Kid', profiles: {
        '': {'watchName': 'Sam'},
      }).backToOwner();
      expect(s.plexUserId, '');
      expect(s.plexHomeToken, '');
      expect(s.plexOwnerId, '');
      expect(s.watchName, 'Sam');
      expect(s.profiles.keys, [_kid]);
    });
  });

  group('saved', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('liquiflux-home'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('the switching token goes to the credential store; profiles to settings.json', () async {
      final secrets = FakeSecrets();
      final store = SettingsStore(secrets: secrets, folder: () async => dir);
      final s = (await store.load()).copyWith(
        plexHomeToken: 'h0meTok3n',
        plexOwnerId: _owner,
        plexUserId: _kid,
        plexUserName: 'Kid',
        plexUserThumb: 'https://plex.tv/users/x/avatar',
        askProfile: true,
        profiles: {
          '': {'watchName': 'Sam'},
        },
      );
      await store.save(s);
      final text = await File('${dir.path}/settings.json').readAsString();
      expect(text, isNot(contains('h0meTok3n')));
      expect(secrets.values['plex_home_token'], 'h0meTok3n');
      final again = await SettingsStore(secrets: secrets, folder: () async => dir).load();
      expect(again.plexHomeToken, 'h0meTok3n');
      expect(again.plexUserId, _kid);
      expect(again.plexUserName, 'Kid');
      expect(again.plexUserThumb, startsWith('https://'));
      expect(again.askProfile, isTrue);
      expect(again.profiles['']?['watchName'], 'Sam');
      expect(again.profileKey, _kid);
    });

    test('a hand-edited file cannot slip in odd ids or pictures', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({'plexUserId': '../x', 'plexUserThumb': 'file:///etc/passwd', 'profiles': {'a/b': {}, 'ok-1': {}}}));
      final s = await SettingsStore(secrets: FakeSecrets(), folder: () async => dir).load();
      expect(s.plexUserId, '');
      expect(s.plexUserThumb, '');
      expect(s.profiles.keys, ['ok-1']);
    });
  });

  group('switching', () {
    late Directory dir;
    late FakeSecrets secrets;
    late AppState app;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('liquiflux-switch');
      secrets = FakeSecrets();
      final store = SettingsStore(secrets: secrets, folder: () async => dir);
      app = AppState(store, scrobbler: Scrobbler(secrets: secrets, folder: () async => dir));
      app.settings = Settings(
        clientId: 'c',
        plexUrl: 'http://plex.test:32400',
        plexToken: 'owner-server',
        plexAccountToken: 'owner-acct',
        plexServerName: 'Neotower',
        plexMachineId: _machine,
        watchName: 'Sam',
      ).copyWith(taste: const Taste().rate('movie:1', 'Film 1', up: true));
      secrets.values[Scrobbler.keyFor('')] = jsonEncode({
        'anilist': {'token': 'owner-anilist', 'user': 'sam_al'},
      });
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<T> net<T>(Future<T> Function() body) => http.runWithClient(body, () => MockClient((r) async => _plexTv(r)));

    test('to a kid with a PIN and back again', () async {
      await net(() async {
        final users = await app.homeUsers();
        expect(users.map((u) => u.name), ['Sam', 'Kid']);
        expect(app.settings.plexOwnerId, _owner);
        expect(app.profile?.name, 'Sam');
        final kid = users.last;

        await expectLater(app.switchProfile(kid, pin: '0000'), throwsA(isA<PlexPinRejected>()));
        expect(app.settings.plexToken, 'owner-server', reason: 'a wrong PIN changes nothing');

        await app.switchProfile(kid, pin: '4321');
        expect(app.settings.plexToken, 'kid-server');
        expect(app.settings.plexAccountToken, 'kid-acct');
        expect(app.settings.plexHomeToken, 'owner-acct');
        expect(app.settings.plexTvToken, 'kid-acct', reason: 'Seerr, Watch Together and X-Ray sign in as the kid');
        expect(app.settings.plexUserId, _kid);
        expect(app.profile?.name, 'Kid');
        expect(app.settings.taste.likes.isEmpty, isTrue);
        expect(app.settings.watchName, '');
        await app.scrobbler.load();
        expect(app.scrobbler.anilistOn, isFalse, reason: "the owner's AniList isn't the kid's");

        // Back: the owner's PIN, and the owner's things again.
        await app.switchProfile(users.first, pin: '1111');
        expect(app.settings.plexToken, 'owner-server');
        expect(app.settings.plexAccountToken, 'owner-acct');
        expect(app.settings.plexUserId, '');
        expect(app.settings.watchName, 'Sam');
        expect(app.settings.taste.likes.isEmpty, isFalse);
        await app.scrobbler.load();
        expect(app.scrobbler.anilistUser, 'sam_al');
      });
    });

    test('signing out goes back to the owner\'s things', () async {
      await net(() async {
        final users = await app.homeUsers();
        await app.switchProfile(users.last, pin: '4321');
        await app.signOut();
        expect(app.settings.plexHomeToken, '');
        expect(app.settings.plexUserId, '');
        expect(app.settings.watchName, 'Sam');
        expect(app.homeList, isNull);
      });
    });
  });

  group('picker', () {
    testWidgets('a PIN typed on the number keys, a wrong one, then the right one', (t) async {
      final app = _FakeHome();
      bool? result;
      await t.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: ConsoleTheme.dark(),
            home: Builder(
              builder: (context) => Center(
                child: TextButton(onPressed: () async => result = await showProfiles(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(find.text('Watching now'), findsOneWidget);
      await t.tap(find.text('Kid'));
      await t.pumpAndSettle();
      expect(find.text('Enter Kid’s PIN'), findsOneWidget);

      for (final k in [LogicalKeyboardKey.digit9, LogicalKeyboardKey.digit9, LogicalKeyboardKey.digit9, LogicalKeyboardKey.digit9]) {
        await t.sendKeyEvent(k);
      }
      await t.pumpAndSettle();
      expect(find.text('That PIN is not right. Try again.'), findsOneWidget);
      expect(app.tried, ['9999']);

      // The on-screen pad works too.
      for (final d in ['4', '3', '2', '1']) {
        await t.tap(find.text(d));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(app.tried, ['9999', '4321']);
      expect(find.text("Who's watching?"), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('Back from the PIN pad goes back to the profiles', (t) async {
      final app = _FakeHome();
      await t.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: ConsoleTheme.dark(),
            home: Builder(
              builder: (context) => TextButton(onPressed: () => showProfiles(context), child: const Text('open')),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.text('Kid'));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(find.text('Enter Kid’s PIN'), findsNothing);
    });
  });
}

class _FakeHome extends AppState {
  _FakeHome() : super(SettingsStore(secrets: FakeSecrets()), scrobbler: Scrobbler(secrets: FakeSecrets()));
  static const sam = PlexHomeUser(uuid: _owner, title: 'Sam', admin: true);
  static const kid = PlexHomeUser(uuid: _kid, title: 'Kid', protected: true);
  final tried = <String>[];

  @override
  PlexHomeUser? get profile => sam;

  @override
  Future<List<PlexHomeUser>> homeUsers({bool fresh = false}) async => const [sam, kid];

  @override
  Future<void> switchProfile(PlexHomeUser user, {String? pin}) async {
    tried.add(pin ?? '');
    if (pin != '4321') throw const PlexPinRejected();
  }
}
