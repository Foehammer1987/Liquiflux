import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

SeerrMediaInfo media(int status, {List<DownloadStatus> downloads = const [], List<SeerrRequest> requests = const []}) =>
    SeerrMediaInfo(id: 1, tmdbId: 1, mediaType: 'movie', status: status, downloads: downloads, requests: requests);

SeerrRequest req(int status) => SeerrRequest(id: 1, status: status, createdAt: DateTime(2026));

void main() {
  final now = DateTime(2026, 10, 13, 18, 0);

  group('requestStateOf', () {
    test('available wins', () {
      final s = requestStateOf(media(MediaStatus.available));
      expect(s.label, 'Available');
      expect(s.requestable, isFalse);
    });

    test('downloading reports percent, time left, finish time and size', () {
      final s = requestStateOf(
        media(
          MediaStatus.processing,
          downloads: [DownloadStatus(size: 1000, sizeLeft: 250, estimatedCompletionTime: now.add(const Duration(minutes: 18)), status: 'downloading')],
        ),
        null,
        now,
      );
      expect(s.label, 'Downloading');
      expect(s.progress, closeTo(0.75, 1e-9));
      expect(s.detail, startsWith('18m left · done 6:18 PM'));
    });

    test('several files finish with the last one', () {
      final s = requestStateOf(
        media(
          MediaStatus.processing,
          downloads: [
            DownloadStatus(size: 100, sizeLeft: 0, estimatedCompletionTime: now.add(const Duration(minutes: 5))),
            DownloadStatus(size: 100, sizeLeft: 100, estimatedCompletionTime: now.add(const Duration(hours: 2, minutes: 5))),
          ],
        ),
        null,
        now,
      );
      expect(s.progress, closeTo(0.5, 1e-9));
      expect(s.detail, contains('2h 5m left'));
      expect(s.detail, contains('2 files'));
    });

    test('stalled downloads read as queued', () {
      final s = requestStateOf(media(MediaStatus.processing, downloads: [DownloadStatus(size: 10, sizeLeft: 10, status: 'warning')]));
      expect(s.label, 'Queued');
    });

    test('pending approval', () {
      expect(requestStateOf(media(MediaStatus.pending), req(RequestStatus.pending)).label, 'Pending Approval');
    });

    test('approved with no download is waiting', () {
      final s = requestStateOf(media(MediaStatus.processing), req(RequestStatus.approved));
      expect(s.label, 'Requested');
      expect(s.waiting, isTrue);
    });

    test('declined can be requested again', () {
      expect(requestStateOf(media(MediaStatus.unknown), req(RequestStatus.declined)).requestable, isTrue);
    });

    test('nothing known is requestable', () {
      expect(requestStateOf(null).requestable, isTrue);
    });
  });

  group('requestableResults', () {
    test('drops available titles and ones Plex already has', () {
      final seerr = [
        SeerrResult(id: 1, mediaType: 'movie', title: 'Dune', releaseDate: '2021-09-15'),
        SeerrResult(id: 2, mediaType: 'movie', title: 'Dune: Part Two', releaseDate: '2024-02-27'),
        SeerrResult(id: 3, mediaType: 'movie', title: 'Arrival', releaseDate: '2016-11-10', mediaInfo: media(MediaStatus.available)),
      ];
      final plex = [PlexItem(ratingKey: '1', key: '', type: 'movie', title: 'Dune: Part Two', year: 2024)];
      expect(requestableResults(seerr, plex).map((r) => r.id), [1]);
    });
  });

  test('Seerr query encoding escapes characters it rejects', () {
    expect(SeerrClient.encodeQuery("Ocean's Eleven!"), 'Ocean%27s%20Eleven%21');
  });

  test('PlexItem parses tmdb guid and card text', () {
    final e = PlexItem.fromJson({
      'ratingKey': 5,
      'key': '/x',
      'type': 'episode',
      'title': 'Pilot',
      'grandparentTitle': 'Severance',
      'parentIndex': 1,
      'index': 2,
      'Guid': [
        {'id': 'imdb://tt1'},
        {'id': 'tmdb://95396'},
      ],
    });
    expect(e.tmdbId, 95396);
    expect(e.cardTitle, 'Severance');
    expect(e.cardSubtitle, 'S1 · E2 · Pilot');
  });

  test('formatters', () {
    expect(formatDuration(5400000), '1h 30m');
    expect(formatBytes(8.4e9), '7.82 GB');
    expect(formatClock(DateTime(2026, 10, 13, 19, 42), now: now), '7:42 PM');
  });

  group('title detail', () {
    test('reads Plex ratings, cast and tracks', () {
      final item = PlexItem.fromJson({
        'ratingKey': '1',
        'key': '/library/metadata/1',
        'type': 'movie',
        'title': 'Arrival',
        'year': 2016,
        'duration': 6960000,
        'Rating': [
          {'image': 'imdb://image.rating', 'value': 7.9, 'type': 'audience'},
          {'image': 'rottentomatoes://image.rating.ripe', 'value': 9.4, 'type': 'critic'},
          {'image': 'rottentomatoes://image.rating.spilled', 'value': 5.0, 'type': 'audience'},
        ],
        'Role': [
          {'id': 7, 'tag': 'Amy Adams', 'role': 'Louise Banks', 'thumb': 'https://x/a.jpg'},
        ],
        'Director': [
          {'tag': 'Denis Villeneuve'},
        ],
        'Media': [
          {
            'id': 1,
            'container': 'mkv',
            'bitrate': 8200,
            'Part': [
              {
                'id': 1,
                'key': '/p',
                'size': 2500000000,
                'Stream': [
                  {'streamType': 1, 'displayTitle': '1080p (HEVC Main 10)'},
                  {'streamType': 2, 'displayTitle': 'English (AAC 5.1)', 'selected': true},
                  {'streamType': 3, 'displayTitle': 'English (SRT)'},
                  {'streamType': 3, 'displayTitle': 'English (SRT)'},
                ],
              },
            ],
          },
        ],
      });
      final d = TitleDetail.fromPlex(item, image: (p, w, h) => p);
      expect(d.scores.map((s) => '${s.label} ${s.value} ${s.positive}'), ['IMDb 7.9 null', 'Critics 94% true', 'Audience 50% false']);
      expect(d.cast.single.role, 'Louise Banks');
      expect(d.cast.single.plexTagId, 7);
      expect(d.facts.first, ('Directed by', 'Denis Villeneuve'));
      expect(d.tracks!.video, '1080p (HEVC Main 10)');
      expect(d.tracks!.audio, 'English (AAC 5.1)');
      expect(d.tracks!.subtitles, ['English (SRT)']);
      expect(d.tracks!.file, 'MKV · 2.33 GB · 8.2 Mbps');
    });

    test('episodes borrow the show cast', () {
      final show = PlexItem.fromJson({
        'ratingKey': '9',
        'key': '',
        'type': 'show',
        'title': 'Silo',
        'Role': [
          {'tag': 'Rebecca Ferguson', 'role': 'Juliette'},
        ],
      });
      final ep = PlexItem.fromJson({'ratingKey': '91', 'key': '', 'type': 'episode', 'title': 'Freedom Day', 'grandparentTitle': 'Silo', 'index': 1, 'parentIndex': 1});
      final d = TitleDetail.fromPlex(ep, show: show, image: (p, w, h) => p);
      expect(d.title, 'Silo');
      expect(d.subtitle, 'Freedom Day');
      expect(d.eyebrow, 'Season 1 · Episode 1');
      expect(d.cast.single.name, 'Rebecca Ferguson');
      expect(d.cast.single.initials, 'RF');
    });

    test('reads Seerr details', () {
      final r = SeerrResult.fromJson({
        'id': 5,
        'title': 'Dune',
        'releaseDate': '2021-09-15',
        'runtime': 155,
        'voteAverage': 7.8,
        'genres': [
          {'name': 'Science Fiction'},
        ],
        'credits': {
          'cast': [
            {'id': 1, 'name': 'Timothée Chalamet', 'character': 'Paul', 'profilePath': '/t.jpg'},
          ],
          'crew': [
            {'id': 2, 'name': 'Denis Villeneuve', 'job': 'Director', 'department': 'Directing'},
          ],
        },
        'releases': {
          'results': [
            {
              'iso_3166_1': 'GB',
              'release_dates': [
                {'certification': '12A'},
              ],
            },
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'certification': ''},
                {'certification': 'PG-13'},
              ],
            },
          ],
        },
        'relatedVideos': [
          {'name': 'Clip', 'type': 'Clip', 'url': 'u1', 'site': 'YouTube', 'key': 'a'},
          {'name': 'Main Trailer', 'type': 'Trailer', 'url': 'u2', 'site': 'YouTube', 'key': 'b'},
        ],
        'mediaInfo': {'id': 1, 'tmdbId': 5, 'status': 5, 'ratingKey': 123},
      });
      final d = TitleDetail.fromSeerr(
        r,
        ratings: SeerrRatings.fromJson({
          'rt': {'criticsScore': 83, 'criticsRating': 'Certified Fresh', 'audienceScore': 90, 'audienceRating': 'Upright'},
          'imdb': {'criticsScore': 8.0},
        }),
      );
      expect(d.contentRating, 'PG-13');
      expect(d.runtimeMs, 155 * 60000);
      expect(d.scores.map((s) => '${s.label} ${s.value}'), ['IMDb 8.0', 'Critics 83%', 'Audience 90%', 'TMDB 78%']);
      expect(d.cast.single.photoUrl, 'https://image.tmdb.org/t/p/w185/t.jpg');
      expect(d.extras.first.title, 'Main Trailer');
      expect(d.plexRatingKey, '123');
      expect(d.metaLine, ['September 15, 2021', '2h 35m']);
    });
  });

  group('spotlight', () {
    PlexItem item(String key, String type, double score, {bool art = true, int views = 0}) =>
        PlexItem.fromJson({'ratingKey': key, 'key': '', 'type': type, 'title': key, 'audienceRating': score, if (art) 'art': '/a/$key', 'viewCount': views});

    test('picks well-rated titles with art and alternates movies and series', () {
      final pool = [
        item('m1', 'movie', 9),
        item('m2', 'movie', 8),
        item('m3', 'movie', 4),
        item('m4', 'movie', 9, art: false),
        item('s1', 'show', 8.5),
        item('s2', 'show', 7.5),
        item('e1', 'episode', 9),
      ];
      final picks = pickSpotlights(pool, count: 4, random: Random(1));
      expect(picks.length, 4);
      expect(picks.map((p) => p.ratingKey).toSet().intersection({'m3', 'm4', 'e1'}), isEmpty);
      for (var i = 1; i < picks.length; i++) {
        expect(picks[i].type == picks[i - 1].type, isFalse);
      }
    });

    test('falls back to the best of the pool when little is rated highly', () {
      final pool = [for (var i = 0; i < 6; i++) item('m$i', 'movie', i.toDouble())];
      final picks = pickSpotlights(pool, count: 3, random: Random(2));
      expect(picks.length, 3);
      expect(picks.every((p) => scoreOf(p) >= 2), isTrue);
    });

    test('a re-roll avoids the last set while there are others to pick', () {
      final pool = [for (var i = 0; i < 12; i++) item('t$i', i.isEven ? 'movie' : 'show', 8)];
      final first = pickSpotlights(pool, count: 5, random: Random(3)).map((p) => p.ratingKey).toSet();
      final next = pickSpotlights(pool, count: 5, random: Random(4), avoid: first).map((p) => p.ratingKey).toSet();
      expect(next.intersection(first), isEmpty);
    });

    test('Top in Your Library changes between picks, skips the spotlight and stays ranked', () {
      final pool = [for (var i = 0; i < 40; i++) item('t$i', i.isEven ? 'movie' : 'show', 6 + (i % 30) / 10)];
      final spot = {'t29', 't28', 't27'};
      final a = pickTop(pool, avoid: spot, random: Random(5));
      final b = pickTop(pool, avoid: spot, random: Random(6));
      expect(a.length, 10);
      expect(a.map((i) => i.ratingKey).toSet().intersection(spot), isEmpty);
      expect(a.map((i) => i.ratingKey).toList(), isNot(b.map((i) => i.ratingKey).toList()));
      for (var i = 1; i < a.length; i++) {
        expect(scoreOf(a[i - 1]) >= scoreOf(a[i]), isTrue);
      }
    });

    test('Top 10 Not in Your Library leaves out anything Plex or Seerr says you own', () {
      final lib = LibraryIndex([
        PlexItem.fromJson({
          'ratingKey': '1',
          'key': '',
          'type': 'movie',
          'title': 'Inception',
          'year': 2010,
          'Guid': [
            {'id': 'tmdb://27205'},
          ],
        }),
        PlexItem.fromJson({'ratingKey': '2', 'key': '', 'type': 'show', 'title': 'The Wire', 'year': 2002}),
      ]);
      SeerrResult r(int id, String type, String title, String date, double avg, int votes, {int? status}) => SeerrResult.fromJson({
        'id': id,
        'mediaType': type,
        if (type == 'tv') 'name': title else 'title': title,
        if (type == 'tv') 'firstAirDate': date else 'releaseDate': date,
        'voteAverage': avg,
        'voteCount': votes,
        if (status != null) 'mediaInfo': {'status': status},
      });
      final top = topMissing([
        r(27205, 'movie', 'Inception', '2010-07-15', 8.4, 37000), // owned, matched by TMDB id
        r(1438, 'tv', 'The Wire', '2002-06-02', 8.6, 2600), // owned, matched by title and year
        r(278, 'movie', 'The Shawshank Redemption', '1994-09-23', 8.7, 28000, status: MediaStatus.available),
        r(238, 'movie', 'The Godfather', '1972-03-14', 8.7, 21000),
        r(1396, 'tv', 'Breaking Bad', '2008-01-20', 8.9, 14000),
        r(9, 'movie', 'Tiny Cult Film', '2001-01-01', 9.6, 40),
        r(238, 'movie', 'The Godfather', '1972-03-14', 8.7, 21000),
      ], lib);
      expect(top.map((t) => t.id), [1396, 238, 9]);
      // Trending cards open owned titles in the library.
      expect(lib.ratingKeyFor(r(27205, 'movie', 'Inception', '2010-07-15', 8.4, 1)), '1');
      expect(lib.ratingKeyFor(r(1438, 'tv', 'The Wire', '2002-06-02', 8.6, 1)), '2');
      expect(lib.ratingKeyFor(r(238, 'movie', 'The Godfather', '1972-03-14', 8.7, 1)), isNull);
    });

    test('reads the clear logo and ranks the top titles', () {
      final a = PlexItem.fromJson({
        'ratingKey': '1',
        'key': '',
        'type': 'movie',
        'title': 'A',
        'audienceRating': 6,
        'Image': [
          {'type': 'coverPoster', 'url': '/p'},
          {'type': 'clearLogo', 'url': '/logo'},
        ],
      });
      expect(a.clearLogo, '/logo');
      expect(topRated([a, item('b', 'movie', 9), item('c', 'show', 7)]).map((i) => i.ratingKey), ['b', 'c', '1']);
    });
  });

  group('outside charts', () {
    test('Netflix Top 10 reads the latest week for one category, in rank order', () {
      const tsv =
          'week\tcategory\tweekly_rank\tshow_title\tseason_title\tweekly_hours_viewed\truntime\tweekly_views\n'
          '2026-10-04\tFilms (English)\t2\tB Film\tN/A\t1\t1\t500\n'
          '2026-10-04\tFilms (English)\t1\tA Film\tN/A\t1\t1\t900\n'
          '2026-09-27\tFilms (English)\t1\tOld Film\tN/A\t1\t1\t100\n'
          '2026-10-04\tTV (English)\t1\tA Show\tA Show: Season 2\t1\t1\t700\n';
      expect(NetflixTop10.parse(tsv, 'movie').map((t) => t.title), ['A Film', 'B Film']);
      expect(NetflixTop10.parse(tsv, 'tv').single.title, 'A Show');
      expect(NetflixTop10.parse('', 'tv'), isEmpty);
    });

    test('Trakt trending sends the client ID and reads TMDB ids', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode([
            {
              'watchers': 120,
              'movie': {
                'title': 'Dune',
                'year': 2021,
                'ids': {'trakt': 1, 'tmdb': 438631},
              },
            },
            {
              'watchers': 80,
              'movie': {
                'title': 'Heat',
                'year': 1995,
                'ids': {'trakt': 2, 'tmdb': 949},
              },
            },
          ]),
          200,
        );
      });
      final trakt = TraktClient(
        clientId: 'abc',
        http: JsonHttp(client: client),
      );
      final t = await trakt.trending('movie', genres: 'action,adventure');
      expect(seen.headers['trakt-api-key'], 'abc');
      expect(seen.url.queryParameters['genres'], 'action,adventure');
      expect(t.map((x) => (x.tmdbId, x.rank)), [(438631, 1), (949, 2)]);
    });
  });

  group('playback', () {
    PlexStream a(int id, String lang, {bool selected = false, String? title}) => PlexStream(streamType: 2, id: id, index: id, languageCode: lang, selected: selected, title: title);
    PlexStream s(int id, String lang, {bool forced = false, bool sdh = false, bool selected = false}) =>
        PlexStream(streamType: 3, id: id, index: id, languageCode: lang, forced: forced, hearingImpaired: sdh, selected: selected);

    test('keeps Plex selection with no preferences', () {
      final t = pickTracks([a(1, 'eng'), a(2, 'spa', selected: true), s(3, 'eng', selected: true)]);
      expect(t.audio?.id, 2);
      expect(t.subtitle?.id, 3);
    });

    test('prefers audio language, skipping commentary', () {
      final t = pickTracks(
        [a(1, 'jpn', selected: true), a(2, 'eng', title: 'Commentary'), a(3, 'eng')],
        audioLanguage: 'eng',
        mode: SubtitleMode.off,
      );
      expect(t.audio?.id, 3);
      expect(t.subtitle, isNull);
    });

    test('foreign audio turns on subtitles only when needed', () {
      final streams = [a(1, 'jpn', selected: true), s(2, 'eng', sdh: true), s(3, 'eng'), s(4, 'eng', forced: true)];
      expect(pickTracks(streams, subtitleLanguage: 'eng', mode: SubtitleMode.foreign).subtitle?.id, 3);
      final english = [a(1, 'eng', selected: true), s(3, 'eng'), s(4, 'eng', forced: true)];
      expect(pickTracks(english, subtitleLanguage: 'eng', mode: SubtitleMode.foreign).subtitle?.id, 4);
      expect(pickTracks(english, subtitleLanguage: 'eng', mode: SubtitleMode.forced).subtitle?.id, 4);
      expect(pickTracks(english, subtitleLanguage: 'eng', mode: SubtitleMode.always).subtitle?.id, 3);
    });

    test('treats fra and fre as the same language', () {
      expect(sameLanguage('fra', 'fre'), isTrue);
      expect(pickTracks([a(1, 'eng', selected: true), a(2, 'fra')], audioLanguage: 'fre').audio?.id, 2);
    });

    PlexStream named(int id, String lang, String title) => PlexStream(streamType: 3, id: id, index: id, languageCode: lang, title: title);

    test('a show\'s remembered choice wins where the file has it', () {
      // A typical anime release: Japanese first, English dub, full and signs-only English subtitles.
      final ep = [a(1, 'jpn', selected: true), a(2, 'eng'), named(3, 'eng', 'Full Subtitles'), named(4, 'eng', 'Signs & Songs')];
      const dub = TrackChoice(audio: 'eng', subtitles: true, subtitleLanguage: 'eng', forced: true);
      final t = pickTracks(ep, mode: SubtitleMode.always, subtitleLanguage: 'eng', remembered: dub);
      expect((t.audio?.id, t.subtitle?.id), (2, 4));
      expect(pickTracks(ep, mode: SubtitleMode.always, remembered: const TrackChoice(audio: 'eng')).subtitle, isNull);
      // An episode without a dub falls back to the usual rules.
      final noDub = [a(1, 'jpn', selected: true), named(3, 'eng', 'Full Subtitles')];
      final f = pickTracks(noDub, audioLanguage: 'eng', remembered: dub, mode: SubtitleMode.foreign, subtitleLanguage: 'eng');
      expect((f.audio?.id, f.subtitle?.id), (1, 3));
    });

    test('remembers what is playing and reads it back', () {
      final c = TrackChoice.of(a(2, 'eng'), named(4, 'eng', 'Signs/Songs'));
      expect(c, const TrackChoice(audio: 'eng', subtitles: true, subtitleLanguage: 'eng', forced: true));
      expect(TrackChoice.fromJson(c.toJson()), c);
      expect(TrackChoice.of(a(1, 'jpn'), null), const TrackChoice(audio: 'jpn'));
      expect(TrackChoice.fromJson('nope'), isNull);
      expect(isSignsOnly(named(5, 'eng', 'Full (Dialogue + Songs)')), isFalse);
    });

    test('Plex\'s full subtitles drop to signs once the audio moves to their language', () {
      final ep = [a(1, 'jpn', selected: true), a(2, 'eng'), s(3, 'eng', selected: true), named(4, 'eng', 'Signs')];
      final t = pickTracks(ep, audioLanguage: 'eng');
      expect((t.audio?.id, t.subtitle?.id), (2, 4));
      expect(pickTracks(ep).subtitle?.id, 3);
    });

    test('spots anime by genre or library', () {
      expect(isAnime(PlexItem(ratingKey: '1', key: '', type: 'show', title: 'X', genres: const ['Animation', 'Anime'])), isTrue);
      expect(isAnime(PlexItem(ratingKey: '1', key: '', type: 'show', title: 'X', genres: const ['Animation'])), isFalse);
      expect(isAnime(null, library: 'Anime Series'), isTrue);
    });

    test('tells local servers from remote ones', () {
      expect(isLocalAddress('http://192.168.1.10:32400'), isTrue);
      expect(isLocalAddress('https://192-168-1-10.abcdef.plex.direct:32400'), isTrue);
      expect(isLocalAddress('https://81-2-3-4.abcdef.plex.direct:32400'), isFalse);
      expect(isLocalAddress('http://localhost:9001'), isTrue);
      expect(isLocalAddress('https://plex.example.com'), isFalse);
    });

    test('finds neighbouring episodes and formats clocks', () {
      final eps = [
        for (final k in ['1', '2', '3']) PlexItem(ratingKey: k, key: k, type: 'episode', title: k),
      ];
      expect(neighbours(eps, '2').previous?.ratingKey, '1');
      expect(neighbours(eps, '3').next, isNull);
      expect(clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(clock(const Duration(minutes: 4, seconds: 5)), '4:05');
    });

    test('reads markers, chapters and stream ids', () {
      final it = PlexItem.fromJson({
        'ratingKey': '1',
        'key': '/1',
        'type': 'episode',
        'title': 'x',
        'Marker': [
          {'type': 'intro', 'startTimeOffset': 1000, 'endTimeOffset': 5000},
          {'type': 'credits', 'startTimeOffset': 9000, 'endTimeOffset': 10000, 'final': true},
        ],
        'Chapter': [
          {'tag': 'Opening', 'startTimeOffset': 0, 'endTimeOffset': 4000, 'index': 1},
        ],
        'Media': [
          {
            'id': 1,
            'Part': [
              {
                'id': 7,
                'key': '/p',
                'Stream': [
                  {'id': 31, 'streamType': 3, 'key': '/library/streams/31', 'codec': 'srt', 'languageCode': 'eng', 'forced': '1'},
                ],
              },
            ],
          },
        ],
      });
      expect(it.markers.last.isFinal, isTrue);
      expect(it.markers.first.contains(3000), isTrue);
      expect(it.chapters.single.title, 'Opening');
      final sub = it.media.first.streams.single;
      expect((sub.id, sub.isExternal, sub.forced), (31, true, true));
    });
  });
}
