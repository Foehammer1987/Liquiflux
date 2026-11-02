import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  // Noon on 2026-10-20, local time, in seconds.
  final noon = DateTime(2026, 10, 20, 12).millisecondsSinceEpoch ~/ 1000;
  const hour = 3600, day = 86400;
  PlexView view(String key, int at, {int account = 1, String type = 'movie'}) => PlexView(titleKey: key, type: type, viewedAt: at, accountId: account);

  group('Top 10 on the server', () {
    test('reads movies and episodes (as their show), skips music and junk', () {
      final v = [
        {'type': 'movie', 'ratingKey': '12', 'viewedAt': noon, 'accountID': 1},
        {'type': 'episode', 'ratingKey': '900', 'grandparentRatingKey': '40', 'viewedAt': noon, 'accountID': 2},
        {'type': 'episode', 'ratingKey': '901', 'grandparentKey': '/library/metadata/41', 'viewedAt': '$noon'},
        {'type': 'track', 'ratingKey': '5', 'viewedAt': noon},
        {'type': 'movie', 'ratingKey': '../x', 'viewedAt': noon},
        {'type': 'movie', 'ratingKey': '13'},
        {'type': 'episode', 'grandparentKey': '/elsewhere/41', 'viewedAt': noon},
      ].map(PlexView.fromJson).nonNulls.toList();
      expect([for (final x in v) '${x.type}:${x.titleKey}:${x.accountId}'], ['movie:12:1', 'show:40:2', 'show:41:null']);
    });

    test('a binge counts once a day, another viewer counts again', () {
      final views = [
        // Show 1: one person, six episodes in one evening.
        for (var i = 0; i < 6; i++) view('1', noon + i * hour ~/ 2, type: 'show'),
        // Movie 2: watched by two people.
        view('2', noon, account: 1),
        view('2', noon + day, account: 2),
        // Show 3: one person, three different days.
        for (var d = 0; d < 3; d++) view('3', noon - d * day, type: 'show'),
      ];
      expect(mostWatched(views), ['3', '2', '1']);
    });

    test('ties go to more plays, then the most recent, and it stops at the count', () {
      final views = [
        view('a', noon),
        view('b', noon + 10),
        view('c', noon),
        view('c', noon + 60),
        for (var i = 0; i < 20; i++) view('x$i', noon - day * 2 - i),
      ];
      final top = mostWatched(views);
      expect(top.take(3), ['c', 'b', 'a']);
      expect(top, hasLength(10));
      expect(mostWatched(const []), isEmpty);
    });

    test('history asks for every account since the date, newest first, and drops older plays', () async {
      late Uri seen;
      final since = DateTime.fromMillisecondsSinceEpoch(noon * 1000);
      final plex = PlexClient(
        baseUrl: 'http://plex.test:32400',
        token: 't',
        clientId: 'c',
        http: JsonHttp(
          client: MockClient((req) async {
            seen = req.url;
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'Metadata': [
                    {'type': 'movie', 'ratingKey': '7', 'viewedAt': noon + 5},
                    {'type': 'movie', 'ratingKey': '8', 'viewedAt': noon - 5},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      final h = await plex.history(since: since);
      expect(seen.path, '/status/sessions/history/all');
      expect(seen.queryParameters['viewedAt>'], '$noon');
      expect(seen.queryParameters['sort'], 'viewedAt:desc');
      expect([for (final v in h) v.titleKey], ['7']);
    });
  });
}
