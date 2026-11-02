import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

PlexItem ep(int season, int index, {String? aired, String key = 'e'}) =>
    PlexItem(ratingKey: '$key$season-$index', key: '', type: 'episode', title: 'Ep', parentIndex: season, index: index, originallyAvailableAt: aired, grandparentTitle: 'Show');

AniListMedia media(int id, {String format = 'TV', int? episodes, DateTime? start, DateTime? end, List<String> titles = const [], List<int> sequels = const [], List<int> prequels = const [], int? progress, String? status}) =>
    AniListMedia(id: id, format: format, episodes: episodes, start: start, end: end, titles: titles, sequels: sequels, prequels: prequels, progress: progress, status: status);

void main() {
  group('external ids', () {
    test('new agent guids', () {
      final i = PlexItem(ratingKey: '1', key: '', type: 'movie', title: 'M', guids: const ['imdb://tt0111161', 'tmdb://278', 'tvdb://99']);
      final ids = ExternalIds.of(i);
      expect(ids.toTrakt(), {'imdb': 'tt0111161', 'tmdb': 278, 'tvdb': 99});
    });

    test('old agent guids, and junk ignored', () {
      expect(ExternalIds.of(PlexItem(ratingKey: '1', key: '', type: 'movie', title: 'M', plexGuid: 'com.plexapp.agents.imdb://tt0133093?lang=en')).imdb, 'tt0133093');
      expect(ExternalIds.of(PlexItem(ratingKey: '1', key: '', type: 'show', title: 'S', plexGuid: 'com.plexapp.agents.thetvdb://81189?lang=en')).tvdb, 81189);
      expect(ExternalIds.of(PlexItem(ratingKey: '1', key: '', type: 'show', title: 'S', plexGuid: 'com.plexapp.agents.hama://anidb-1234?lang=en')).isEmpty, isTrue);
      expect(ExternalIds.of(PlexItem(ratingKey: '1', key: '', type: 'movie', title: 'M', guids: const ['imdb://nonsense', 'tmdb://0'])).isEmpty, isTrue);
    });
  });

  group('trakt targets', () {
    final show = PlexItem(ratingKey: 's', key: '', type: 'show', title: 'S', guids: const ['tvdb://81189', 'tmdb://1396']);
    test('a movie by its ids', () {
      final t = TraktTarget.of(PlexItem(ratingKey: '1', key: '', type: 'movie', title: 'M', guids: const ['tmdb://278']))!;
      expect(t.scrobbleBody(), {
        'movie': {
          'ids': {'tmdb': 278},
        },
      });
    });

    test('an episode by its show and number', () {
      final e = PlexItem(ratingKey: '2', key: '', type: 'episode', title: 'E', parentIndex: 2, index: 5, guids: const ['tvdb://349232']);
      final t = TraktTarget.of(e, show: show)!;
      expect(t.scrobbleBody(), {
        'show': {
          'ids': {'tmdb': 1396, 'tvdb': 81189},
        },
        'episode': {'season': 2, 'number': 5},
      });
      expect(jsonEncode(t.historyBody(DateTime.utc(2026, 11, 2))), contains('"seasons":[{"number":2,"episodes":[{"number":5,"watched_at":"2026-11-02T00:00:00.000Z"}]}]'));
    });

    test('an episode without its show falls back to its own ids', () {
      final e = PlexItem(ratingKey: '2', key: '', type: 'episode', title: 'E', parentIndex: 1, index: 1, guids: const ['tvdb://349232']);
      expect(TraktTarget.of(e)!.scrobbleBody(), {
        'episode': {
          'ids': {'tvdb': 349232},
        },
      });
    });

    test('nothing to match on: null', () {
      expect(TraktTarget.of(PlexItem(ratingKey: '1', key: '', type: 'movie', title: 'M')), isNull);
      expect(TraktTarget.of(PlexItem(ratingKey: '1', key: '', type: 'clip', title: 'C', guids: const ['tmdb://1'])), isNull);
    });
  });

  group('trakt account', () {
    late List<http.Request> sent;
    late List<http.Response> answers;
    TraktAccount account({TraktTokens? tokens, void Function(TraktTokens)? onTokens}) {
      sent = [];
      return TraktAccount(
        app: const TraktApp(clientId: 'cid', clientSecret: 'csecret'),
        tokens: tokens,
        onTokens: onTokens,
        userAgent: 'Liquiflux/test',
        http: JsonHttp(
          client: MockClient((req) async {
            sent.add(req);
            return answers.removeAt(0);
          }),
        ),
      );
    }

    http.Response json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

    test('device code then polling until approved', () async {
      final kept = <TraktTokens>[];
      answers = [
        json({'device_code': 'dev', 'user_code': 'ABCD1234', 'verification_url': 'https://trakt.tv/activate', 'expires_in': 600, 'interval': 5}),
        http.Response('', 400),
        json({'access_token': 'acc', 'refresh_token': 'ref', 'created_at': 1700000000, 'expires_in': 86400}),
      ];
      final a = account(onTokens: kept.add);
      final code = await a.deviceCode();
      expect(code.userCode, 'ABCD1234');
      expect(code.directUrl, 'https://trakt.tv/activate/ABCD1234');
      expect(jsonDecode(sent[0].body), {'client_id': 'cid'});
      expect(sent[0].headers['trakt-api-key'], 'cid');
      expect(sent[0].headers['user-agent'], 'Liquiflux/test');
      final t = await a.waitForApproval(code, every: Duration.zero);
      expect(t.access, 'acc');
      expect(kept.single.refresh, 'ref');
      expect(jsonDecode(sent[2].body), {'code': 'dev', 'client_id': 'cid', 'client_secret': 'csecret'});
    });

    test('turned down and expired codes end the wait', () async {
      final code = TraktDeviceCode(deviceCode: 'd', userCode: 'u', url: 'https://trakt.tv/activate', expiresAt: DateTime.now().add(const Duration(minutes: 5)), interval: Duration.zero);
      answers = [http.Response('', 418)];
      await expectLater(account().waitForApproval(code), throwsA(isA<TraktSignInException>().having((e) => e.end, 'end', TraktSignInEnd.denied)));
      answers = [http.Response('', 410)];
      await expectLater(account().waitForApproval(code), throwsA(isA<TraktSignInException>().having((e) => e.end, 'end', TraktSignInEnd.expired)));
    });

    test('a stale token is refreshed before scrobbling; 409 is fine', () async {
      final kept = <TraktTokens>[];
      answers = [
        json({'access_token': 'new', 'refresh_token': 'ref2', 'expires_in': 86400 * 90}),
        json({'error': 'already scrobbled'}, 409),
      ];
      final a = account(tokens: TraktTokens(access: 'old', refresh: 'ref1', expiresAt: DateTime.now()), onTokens: kept.add);
      await a.scrobble('stop', const TraktTarget.movie(ExternalIds(tmdb: 278)), 91.234);
      expect(sent[0].url.path, '/oauth/token');
      expect(jsonDecode(sent[0].body)['refresh_token'], 'ref1');
      expect(sent[1].url.path, '/scrobble/stop');
      expect(sent[1].headers['authorization'], 'Bearer new');
      expect(jsonDecode(sent[1].body), {
        'movie': {
          'ids': {'tmdb': 278},
        },
        'progress': 91.23,
      });
      expect(kept.single.refresh, 'ref2');
    });

    test('a 401 refreshes once and tries again', () async {
      answers = [
        http.Response('', 401),
        json({'access_token': 'new', 'refresh_token': 'ref2', 'expires_in': 86400 * 90}),
        json({}, 201),
      ];
      final a = account(tokens: TraktTokens(access: 'old', refresh: 'ref1', expiresAt: DateTime.now().add(const Duration(days: 30))));
      await a.scrobble('start', const TraktTarget.movie(ExternalIds(tmdb: 1)), 3);
      expect(sent.map((r) => r.url.path), ['/scrobble/start', '/oauth/token', '/scrobble/start']);
      expect(sent.last.headers['authorization'], 'Bearer new');
    });

    test('tokens survive a save', () {
      final t = TraktTokens(access: 'a', refresh: 'r', expiresAt: DateTime.utc(2027));
      final back = TraktTokens.fromJson(jsonDecode(jsonEncode(t.toJson())))!;
      expect((back.access, back.refresh, back.expiresAt), ('a', 'r', DateTime.utc(2027)));
      expect(TraktTokens.fromJson({'access': '', 'refresh': 'r', 'expiresAt': '2027-01-01'}), isNull);
    });
  });

  group('anilist', () {
    test('a pasted token, bare or in its address', () {
      const jwt = 'eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl';
      expect(AniListAccount.cleanToken('  $jwt \n'), jwt);
      expect(AniListAccount.cleanToken('https://anilist.co/api/v2/oauth/pin#access_token=$jwt&token_type=Bearer&expires_in=31536000'), jwt);
      expect(AniListAccount.cleanToken('not a token'), isNull);
    });

    test('picks the right title and year, never a guess', () {
      final results = [
        media(2, titles: ['Hunter x Hunter'], start: DateTime.utc(1999, 10, 16)),
        media(11061, titles: ['Hunter x Hunter (2011)', 'HUNTER×HUNTER'], start: DateTime.utc(2011, 10, 2)),
      ];
      expect(pickMatch(results, 'Hunter x Hunter (2011)', null)!.id, 11061);
      expect(pickMatch(results, 'Hunter x Hunter', 1999)!.id, 2);
      expect(pickMatch([media(5, titles: ['Something Else'])], 'Hunter x Hunter', 2011), isNull);
      // Accents and macrons don't stop a match.
      expect(pickMatch([media(1735, titles: ['Naruto Shippuden', 'Naruto: Shippuuden'], start: DateTime.utc(2007, 2, 15))], 'Naruto Shippūden', 2007)!.id, 1735);
      expect(foldAccents('Naruto Shippūden'), 'Naruto Shippuden');
      // Only a loose title match and the wrong year: no.
      expect(pickMatch([media(6, titles: ['Hunter x Hunter Movie'], start: DateTime.utc(2013, 1, 1))], 'Hunter x Hunter', 2011), isNull);
    });

    test('progress only moves forward and leaves finished shows alone', () {
      expect(progressChange(media(1, episodes: 12, progress: 3, status: 'CURRENT'), 4), (progress: 4, status: 'CURRENT'));
      expect(progressChange(media(1, episodes: 12, progress: 5, status: 'CURRENT'), 4), isNull);
      expect(progressChange(media(1, episodes: 12, progress: 11, status: 'CURRENT'), 12), (progress: 12, status: 'COMPLETED'));
      expect(progressChange(media(1, episodes: 12, progress: 12, status: 'COMPLETED'), 12), isNull);
      expect(progressChange(media(1, episodes: 12), 1), (progress: 1, status: 'CURRENT'));
      expect(progressChange(media(1, episodes: 12, progress: 2, status: 'REPEATING'), 3), (progress: 3, status: 'REPEATING'));
      expect(progressChange(media(1), 40), (progress: 40, status: 'CURRENT'));
    });

    group('placing an episode', () {
      // Two seasons in Plex; AniList splits season 2 into two cours.
      final chain = [
        media(1, episodes: 12, start: DateTime.utc(2020, 1, 5), end: DateTime.utc(2020, 3, 22)),
        media(2, episodes: 12, start: DateTime.utc(2021, 1, 10), end: DateTime.utc(2021, 3, 28)),
        media(3, episodes: 12, start: DateTime.utc(2021, 7, 4), end: DateTime.utc(2021, 9, 19)),
      ];
      final plexEps = [
        for (var i = 1; i <= 12; i++) ep(1, i, aired: '2020-${(1 + (i + 3) ~/ 4).toString().padLeft(2, '0')}-05'),
        for (var i = 1; i <= 12; i++) ep(2, i, aired: '2021-0${1 + (i - 1) ~/ 4}-10'),
        for (var i = 13; i <= 24; i++) ep(2, i, aired: '2021-0${7 + (i - 13) ~/ 4}-04'),
      ];

      test('season 1 lines up', () {
        final p = placeEpisode(chain, ep(1, 7, aired: '2020-02-16'), plexEps)!;
        expect((p.media.id, p.number), (1, 7));
      });

      test('the second half of a split season counts from 1', () {
        final p = placeEpisode(chain, ep(2, 15, aired: '2021-07-18'), plexEps)!;
        expect((p.media.id, p.number), (3, 3));
        final q = placeEpisode(chain, ep(2, 2, aired: '2021-01-17'), plexEps)!;
        expect((q.media.id, q.number), (2, 2));
      });

      test('absolute numbering in one Plex season', () {
        final abs = [for (var i = 1; i <= 24; i++) ep(1, i, aired: i <= 12 ? '2020-01-${(4 + i).toString().padLeft(2, '0')}' : '2021-01-${(i - 2).toString().padLeft(2, '0')}')];
        final p = placeEpisode(chain, abs[13], abs)!; // episode 14
        expect((p.media.id, p.number), (2, 2));
      });

      test('an episode Plex has no date for does not shift the numbers after it', () {
        // One Piece style: one open-ended AniList entry, absolute numbers across Plex seasons,
        // and a gap in Plex's dates (the last of S1, and S2E6 itself).
        final one = [media(21, start: DateTime.utc(1999, 10, 20))];
        final eps = [
          for (var i = 1; i <= 4; i++) ep(1, i, aired: i == 4 ? null : '2000-01-0$i'),
          for (var i = 5; i <= 8; i++) ep(2, i, aired: i == 6 ? null : '2000-02-0$i'),
        ];
        final p = placeEpisode(one, eps[6], eps)!; // S2E7
        expect((p.media.id, p.number), (21, 7));
        final q = placeEpisode(one, eps[5], eps)!; // S2E6, undated
        expect((q.media.id, q.number), (21, 6));
      });

      test('a stray undated file with an odd number does not move the rest', () {
        // Naruto Shippuden style: absolute numbers, S1 1-4 plus a stray "Episode 100" with no date.
        final one = [media(1735, episodes: 500, start: DateTime.utc(2007, 2, 15))];
        final eps = [
          for (var i = 1; i <= 4; i++) ep(1, i, aired: '2007-03-0$i'),
          ep(1, 100),
          for (var i = 5; i <= 8; i++) ep(2, i, aired: '2008-01-0$i'),
          ep(2, 2),
        ];
        expect(placeEpisode(one, eps[7], eps)!.number, 7);
        // Per-season numbering with a stray in season 1.
        final two = [media(1, episodes: 4, start: DateTime.utc(2020, 1, 1)), media(2, episodes: 4, start: DateTime.utc(2021, 1, 1))];
        final per = [for (var i = 1; i <= 4; i++) ep(1, i, aired: '2020-01-0$i'), ep(1, 50), for (var i = 1; i <= 4; i++) ep(2, i, aired: '2021-01-0$i')];
        expect(placeEpisode(two, per[7], per)!.number, 3);
        expect(placeEpisode(two, per[7], per)!.media.id, 2);
      });

      test('without air dates season N is the Nth entry', () {
        final p = placeEpisode(chain, ep(2, 4), const [])!;
        expect((p.media.id, p.number), (2, 4));
        expect(placeEpisode(chain, ep(2, 13), const []), isNull);
        expect(placeEpisode(chain, ep(4, 1), const []), isNull);
      });

      test('specials, and seasons AniList has no entry for yet, are left out', () {
        expect(placeEpisode(chain, ep(0, 1, aired: '2020-05-01'), plexEps), isNull);
        expect(placeEpisode(chain, ep(3, 1, aired: '2023-04-01'), plexEps), isNull);
        expect(placeEpisode(chain, ep(1, 1, aired: '2019-01-01'), plexEps), isNull);
      });
    });

    test('the chain walks back to season 1 and on, past films', () async {
      final all = {
        1: media(1, sequels: [9]),
        9: media(9, format: 'MOVIE', prequels: [1], sequels: [2]),
        2: media(2, prequels: [9], sequels: [3]),
        3: media(3, prequels: [2]),
      };
      final chain = await seriesChain(all[2]!, (id) async => all[id]);
      expect(chain.map((m) => m.id), [1, 2, 3]);
    });

    test('reads AniList answers and errors', () async {
      final sent = <http.Request>[];
      final a = AniListAccount(
        token: 'tok',
        http: JsonHttp(
          client: MockClient((req) async {
            sent.add(req);
            final q = jsonDecode(req.body)['query'] as String;
            if (q.contains('Viewer')) return http.Response(jsonEncode({'errors': [{'message': 'Invalid token', 'status': 400}]}), 400, headers: {'content-type': 'application/json'});
            return http.Response(
              jsonEncode({
                'data': {
                  'Media': {
                    'id': 5,
                    'format': 'TV',
                    'episodes': 24,
                    'startDate': {'year': 2020, 'month': 4, 'day': 1},
                    'endDate': {'year': null, 'month': null, 'day': null},
                    'title': {'english': 'Show', 'romaji': 'Shou', 'native': null},
                    'synonyms': ['S'],
                    'relations': {
                      'edges': [
                        {'relationType': 'SEQUEL', 'node': {'id': 8, 'type': 'ANIME', 'format': 'MOVIE'}},
                        {'relationType': 'SEQUEL', 'node': {'id': 7, 'type': 'ANIME', 'format': 'TV'}},
                        {'relationType': 'ADAPTATION', 'node': {'id': 70, 'type': 'MANGA', 'format': 'MANGA'}},
                      ],
                    },
                    'mediaListEntry': {'progress': 3, 'status': 'CURRENT'},
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      final m = (await a.media(5))!;
      expect((m.episodes, m.start, m.end, m.progress), (24, DateTime.utc(2020, 4, 1), null, 3));
      expect(m.titles, ['Show', 'Shou', 'S']);
      expect(m.sequels, [7, 8]); // the series first
      expect(sent.single.headers['authorization'], 'Bearer tok');
      await expectLater(a.viewer(), throwsA(isA<ApiException>()));
    });
  });
}
