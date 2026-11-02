import 'dart:convert';
import 'dart:io';

import 'package:console_app/services/scrobbler.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'settings_store_test.dart' show FakeSecrets;

void main() {
  late Directory dir;
  late List<http.Request> sent;
  late FakeSecrets secrets;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('liquiflux-scrobble');
    sent = [];
    secrets = FakeSecrets()
      ..values['scrobble_accounts'] = jsonEncode({
        'trakt': {
          'clientId': 'cid',
          'user': 'sam',
          'tokens': {'access': 'acc', 'refresh': 'ref', 'expiresAt': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String()},
        },
        'anilist': {'token': 'aa.bb.cc', 'user': 'sam'},
      });
  });
  tearDown(() => dir.deleteSync(recursive: true));

  http.Response json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

  Map<String, Object?> container(List<Map<String, Object?>> items) => {
    'MediaContainer': {'Metadata': items},
  };

  // One server for everything: Trakt, AniList and Plex.
  final client = MockClient((req) async {
    sent.add(req);
    switch (req.url.host) {
      case 'api.trakt.tv':
        return json({}, 201);
      case 'graphql.anilist.co':
        final q = jsonDecode(req.body)['query'] as String;
        Map<String, Object?> entry(int progress) => {
          'id': 77,
          'format': 'TV',
          'episodes': 12,
          'startDate': {'year': 2024, 'month': 1, 'day': 7},
          'endDate': {'year': 2024, 'month': 3, 'day': 24},
          'title': {'english': 'Frieren', 'romaji': 'Sousou no Frieren'},
          'synonyms': <String>[],
          'relations': {'edges': <Object>[]},
          'mediaListEntry': {'progress': progress, 'status': 'CURRENT'},
        };
        if (q.contains('Page')) {
          return json({
            'data': {
              'Page': {
                'media': [entry(1)],
              },
            },
          });
        }
        if (q.startsWith('mutation')) return json({'data': {'SaveMediaListEntry': {'id': 1, 'progress': 3, 'status': 'CURRENT'}}});
        return json({
          'data': {'Media': entry(2)},
        });
      default: // Plex
        if (req.url.path.endsWith('/allLeaves')) {
          return json(container([
            for (var i = 1; i <= 12; i++)
              {'ratingKey': 'e$i', 'type': 'episode', 'title': 'E$i', 'parentIndex': 1, 'index': i, 'originallyAvailableAt': '2024-0${1 + (i - 1) ~/ 4}-${(7 + (i - 1) % 4 * 7).toString().padLeft(2, '0')}'},
          ]));
        }
        return json(container([
          {
            'ratingKey': 'show1',
            'type': 'show',
            'title': 'Frieren',
            'year': 2024,
            'Genre': [
              {'tag': 'Anime'},
            ],
            'Guid': [
              {'id': 'tvdb://424536'},
            ],
          },
        ]));
    }
  });

  Scrobbler make() => Scrobbler(secrets: secrets, folder: () async => dir, http: () => JsonHttp(client: client), anilistEndpoint: 'https://graphql.anilist.co');
  final plex = PlexClient(baseUrl: 'http://plex.test:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: client));
  final episode = PlexItem(ratingKey: 'e3', key: '', type: 'episode', title: 'E3', parentIndex: 1, index: 3, grandparentRatingKey: 'show1', grandparentTitle: 'Frieren', originallyAvailableAt: '2024-01-21');

  test('a play goes to Trakt as start, pause and stop, and a finished anime episode to AniList', () async {
    final s = make()..configure(traktClientId: 'cid', traktClientSecret: 'sec', anilistClientId: '');
    await s.load();
    expect((s.traktOn, s.anilistOn, s.traktUser), (true, true, 'sam'));
    final play = s.play(plex, episode, server: 'srv')!;
    play.playing(10);
    await play.idle;
    play.paused(40);
    await play.idle;
    await play.stopped(85);
    final trakt = sent.where((r) => r.url.host == 'api.trakt.tv').toList();
    expect(trakt.map((r) => r.url.path), ['/scrobble/start', '/scrobble/pause', '/scrobble/stop']);
    expect(jsonDecode(trakt.last.body), {
      'show': {
        'ids': {'tvdb': 424536},
      },
      'episode': {'season': 1, 'number': 3},
      'progress': 85.0,
    });
    expect(trakt.first.headers['authorization'], 'Bearer acc');
    final save = sent.where((r) => r.url.host == 'graphql.anilist.co' && (jsonDecode(r.body)['query'] as String).startsWith('mutation')).single;
    expect(jsonDecode(save.body)['variables'], {'id': 77, 'p': 3, 's': 'CURRENT'});
    expect(s.lastAniList, contains('CURRENT 3/12'));
    // The match is kept for next time.
    expect(File('${dir.path}/anilist-map.json').readAsStringSync(), contains('"id":77'));
  });

  test('stopping early sends a stop to Trakt but leaves AniList alone', () async {
    final s = make()..configure(traktClientId: 'cid', traktClientSecret: 'sec', anilistClientId: '');
    await s.load();
    final play = s.play(plex, episode)!;
    play.playing(5);
    await play.idle;
    await play.stopped(30);
    expect(sent.where((r) => r.url.host == 'api.trakt.tv').map((r) => r.url.path), ['/scrobble/start', '/scrobble/stop']);
    expect(sent.where((r) => r.url.host == 'graphql.anilist.co'), isEmpty);
    // A second stop does nothing.
    await play.stopped(100, watched: true);
    expect(sent.where((r) => r.url.host == 'api.trakt.tv').length, 2);
  });

  test('another Trakt app means connecting again; nothing is sent meanwhile', () async {
    final s = make()..configure(traktClientId: 'other', traktClientSecret: 'sec2', anilistClientId: '');
    await s.load();
    expect((s.traktOn, s.traktAppChanged), (false, true));
    await s.anilistSignOut();
    expect(s.play(plex, episode), isNull);
  });

  test('without any Trakt app there is nothing to connect', () async {
    final s = make()..configure(traktClientId: 'cid', traktClientSecret: '', anilistClientId: '');
    await s.load();
    // Source builds have no built-in app.
    expect(s.traktApp, builtInTraktId.isEmpty ? isNull : isNotNull);
  });

  test('the Trakt secret is kept in the credential store, the AniList id in settings.json', () async {
    final store = SettingsStore(secrets: secrets, folder: () async => dir);
    final loaded = await store.load();
    await store.save(loaded.copyWith(traktClientId: 'traktId1', traktClientSecret: 'traktS3cret', anilistClientId: '12345'));
    final text = File('${dir.path}/settings.json').readAsStringSync();
    expect(text, isNot(contains('traktS3cret')));
    expect(secrets.values['trakt_client_secret'], 'traktS3cret');
    expect(jsonDecode(text)['anilistClientId'], '12345');
    final back = await SettingsStore(secrets: secrets, folder: () async => dir).load();
    expect((back.traktClientSecret, back.anilistClientId), ('traktS3cret', '12345'));
  });
}
