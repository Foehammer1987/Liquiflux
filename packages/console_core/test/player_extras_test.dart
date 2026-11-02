import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'tamper_test.dart' show mutations;

PlexItem _ep({int? viewCount, int index = 4}) => PlexItem.fromJson({'ratingKey': '7', 'type': 'episode', 'title': 'The Reveal', 'index': index, 'viewCount': viewCount});

final _subtitleSample = <String, dynamic>{
  'id': 0,
  'key': '/library/streams/opensubtitles/abc123',
  'streamType': 3,
  'codec': 'srt',
  'language': 'English',
  'languageCode': 'eng',
  'title': 'Dune.Part.Two.2024.2160p.WEB-DL',
  'providerTitle': 'OpenSubtitles',
  'score': 87,
  'hearingImpaired': false,
  'forced': '0',
  'perfectMatch': 1,
  'downloaded': false,
};

void main() {
  group('startPoint', () {
    const mins = 25 * 60 * 1000;
    test('asks by default when there is a saved place', () {
      final p = startPoint(viewOffsetMs: mins, durationMs: 3 * mins);
      expect(p.ask, isTrue);
      expect(p.from, const Duration(minutes: 25));
    });
    test('follows the setting', () {
      expect(startPoint(viewOffsetMs: mins, mode: ResumeMode.resume), (from: const Duration(minutes: 25), ask: false));
      expect(startPoint(viewOffsetMs: mins, mode: ResumeMode.start), (from: Duration.zero, ask: false));
    });
    test('a choice already made wins over the setting', () {
      expect(startPoint(viewOffsetMs: mins, choose: false, mode: ResumeMode.start), (from: const Duration(minutes: 25), ask: false));
      expect(startPoint(viewOffsetMs: mins, resume: false), (from: Duration.zero, ask: false));
    });
    test('nothing to resume: no place, a few seconds, or past the end', () {
      for (final at in [null, 0, -5, 3000, 4 * mins]) {
        expect(startPoint(viewOffsetMs: at, durationMs: 3 * mins), (from: Duration.zero, ask: false), reason: '$at');
      }
    });
    test('ResumeMode.parse falls back to ask', () {
      expect(ResumeMode.parse('start'), ResumeMode.start);
      for (final v in [null, 1, 'nope', true]) {
        expect(ResumeMode.parse(v), ResumeMode.ask);
      }
    });
  });

  group('SpoilerPrefs', () {
    test('only unwatched episodes are covered', () {
      const all = SpoilerPrefs(images: true, summaries: true, titles: true);
      expect(all.covers(_ep()), isTrue);
      expect(all.covers(_ep(viewCount: 1)), isFalse);
      expect(all.covers(PlexItem.fromJson({'ratingKey': '1', 'type': 'movie', 'title': 'Dune'})), isFalse);
      expect(const SpoilerPrefs().covers(_ep()), isFalse);
    });
    test('each part on its own', () {
      const s = SpoilerPrefs(titles: true);
      expect(s.hideTitle(_ep()), isTrue);
      expect(s.hideImage(_ep()), isFalse);
      expect(s.hideSummary(_ep()), isFalse);
      expect(s.titleOf(_ep()), 'Episode 4');
      expect(s.titleOf(_ep(viewCount: 2)), 'The Reveal');
      expect(const SpoilerPrefs().titleOf(_ep()), 'The Reveal');
    });
    test('round trips, and anything odd in the file reads as off', () {
      const s = SpoilerPrefs(images: true, summaries: false, titles: true);
      final back = SpoilerPrefs.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect((back.images, back.summaries, back.titles), (true, false, true));
      for (final v in [null, 'x', 1, [], {'images': 'true', 'summaries': 1, 'titles': null}]) {
        expect(SpoilerPrefs.fromJson(v).any, isFalse, reason: '$v');
      }
    });
  });

  test('twoLetterLanguage', () {
    expect(twoLetterLanguage('eng'), 'en');
    expect(twoLetterLanguage('fra'), 'fr');
    expect(twoLetterLanguage('GER'), 'de');
    expect(twoLetterLanguage('xx'), isNull);
    expect(twoLetterLanguage(null), isNull);
  });

  group('online subtitles', () {
    test('reads a result', () {
      final s = OnlineSubtitle.fromJson(_subtitleSample)!;
      expect(s.key, '/library/streams/opensubtitles/abc123');
      expect(s.label, 'Dune.Part.Two.2024.2160p.WEB-DL');
      expect((s.codec, s.languageCode, s.provider, s.score, s.perfectMatch, s.forced), ('srt', 'eng', 'OpenSubtitles', 87, true, false));
    });

    test('a tampered result never throws, and odd values are cleaned', () {
      for (final (what, doc) in mutations(_subtitleSample)) {
        final s = OnlineSubtitle.fromJson(doc);
        if (s == null) continue;
        expect(s.score, inInclusiveRange(0, 100), reason: what);
        expect(s.label.length, lessThanOrEqualTo(121), reason: what);
        expect(s.label, isNot(contains('\n')), reason: what);
        expect(s.key, isNot(matches(RegExp(r'[\x00-\x1f]'))), reason: what);
        expect(s.codec == null || RegExp(r'^[a-z0-9]{1,10}$').hasMatch(s.codec!), isTrue, reason: what);
      }
      expect(OnlineSubtitle.fromJson({..._subtitleSample, 'key': 'a\nb', 'sourceKey': null}), isNull);
    });

    test('search asks this server only, ranks exact matches first, and download sends the key back', () async {
      final seen = <http.Request>[];
      final client = MockClient((req) async {
        seen.add(req);
        if (req.method == 'PUT') return http.Response('', 200);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Stream': [
                {..._subtitleSample, 'key': '/a', 'score': 99, 'perfectMatch': false},
                {..._subtitleSample, 'key': '/b', 'score': 50},
                'junk',
                {'title': 'no key'},
                {..._subtitleSample, 'key': '/c', 'score': 99, 'perfectMatch': false},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final plex = PlexClient(baseUrl: 'http://10.0.0.2:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: client));
      final found = await plex.searchSubtitles('42', language: 'en');
      expect(found.map((s) => s.key), ['/b', '/a', '/c']);
      expect(seen.single.url.path, '/library/metadata/42/subtitles');
      expect(seen.single.url.queryParameters, {'language': 'en', 'hearingImpaired': '0', 'forced': '0'});
      await plex.downloadSubtitle('42', found.first);
      expect(seen.last.method, 'PUT');
      expect(seen.last.url.host, '10.0.0.2');
      expect(seen.last.url.queryParameters['key'], '/b');
      // An odd rating key stays inside the path.
      await plex.searchSubtitles('../../x?y', language: 'en');
      expect(seen.last.url.path, startsWith('/library/metadata/'));
      expect(seen.last.url.queryParameters.keys, isNot(contains('y')));
    });
  });
}
