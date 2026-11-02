import 'dart:convert';
import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Every way to spoil one value: the wrong type, nonsense numbers, huge text, a path.
final hostile = <Object?>[
  null,
  'oops',
  '',
  -1,
  -999999999999,
  0,
  9223372036854775807,
  -9223372036854775808,
  1e308,
  -1e308,
  double.infinity, // what jsonDecode makes of 1e400
  double.negativeInfinity,
  double.nan,
  2.5,
  true,
  <dynamic>[],
  <String, dynamic>{},
  [1, 'two', null],
  {'nested': 'map'},
  'x' * 100000,
  '../../../etc/passwd',
  'https://evil.example/x?token=1',
  'NaN',
  'Infinity',
  '-5',
  '99999-99-99',
  'line\nbreak\u202Ereversed',
];

/// Every path to a value inside [doc], maps and lists included.
List<List<Object>> _paths(Object? node, [List<Object> at = const []]) => [
  if (at.isNotEmpty) at,
  if (node is Map)
    for (final e in node.entries) ..._paths(e.value, [...at, e.key as Object]),
  if (node is List)
    for (var i = 0; i < node.length; i++) ..._paths(node[i], [...at, i]),
];

dynamic _copy(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': _copy(e.value)} : (v is List ? [for (final x in v) _copy(x)] : v);

/// [doc] with one value at a time swapped for each [hostile] value, or taken out. Each
/// mutation comes with a label naming what was changed, for a failing test's message.
Iterable<(String, Map<String, dynamic>)> mutations(Map<String, dynamic> doc) sync* {
  for (final path in _paths(doc)) {
    for (final (k, v) in [...hostile.indexed.map((e) => (e.$1, e.$2)), (-1, #remove)]) {
      final copy = _copy(doc) as Map<String, dynamic>;
      dynamic parent = copy;
      for (final key in path.take(path.length - 1)) {
        parent = parent[key];
      }
      final last = path.last;
      if (v == #remove) {
        if (parent is Map) {
          parent.remove(last);
        } else {
          (parent as List).removeAt(last as int);
        }
      } else {
        parent[last] = v;
      }
      yield ('${path.join('.')} = ${k < 0 ? 'removed' : (v is String && v.length > 40 ? '${v.length} chars' : v)}', copy);
    }
  }
}

final plexSample = <String, dynamic>{
  'ratingKey': '101',
  'key': '/library/metadata/101',
  'type': 'movie',
  'title': 'Dune',
  'year': 2021,
  'summary': 'Spice.',
  'thumb': '/library/metadata/101/thumb/1',
  'art': '/library/metadata/101/art/1',
  'duration': 9360000,
  'viewOffset': 120000,
  'viewCount': 1,
  'leafCount': 8,
  'viewedLeafCount': 3,
  'childCount': 2,
  'contentRating': 'PG-13',
  'audienceRating': 8.1,
  'rating': 8.3,
  'ratingImage': 'rottentomatoes://image.rating.ripe',
  'audienceRatingImage': 'rottentomatoes://image.rating.upright',
  'tagline': 'Beyond fear, destiny awaits.',
  'studio': 'Legendary',
  'originallyAvailableAt': '2021-10-22',
  'librarySectionID': 1,
  'addedAt': 1700000000,
  'updatedAt': 1700000500,
  'lastViewedAt': 1700000900,
  'Genre': [
    {'tag': 'Sci-Fi'},
  ],
  'Guid': [
    {'id': 'tmdb://438631'},
    {'id': 'imdb://tt1160419'},
  ],
  'Role': [
    {'id': 1, 'tag': 'Timothée Chalamet', 'role': 'Paul', 'thumb': 'https://metadata-static.plex.tv/p.jpg'},
  ],
  'Director': [
    {'id': 2, 'tag': 'Denis Villeneuve'},
  ],
  'Writer': [
    {'id': 3, 'tag': 'Jon Spaihts'},
  ],
  'Producer': [
    {'id': 4, 'tag': 'Mary Parent'},
  ],
  'Country': [
    {'tag': 'United States'},
  ],
  'Rating': [
    {'image': 'imdb://image.rating', 'value': 8.0, 'type': 'audience'},
    {'image': 'rottentomatoes://image.rating.ripe', 'value': 8.3, 'type': 'critic'},
  ],
  'Review': [
    {'tag': 'Critic', 'text': 'Good.', 'source': 'Paper', 'image': 'rottentomatoes://image.review.fresh'},
  ],
  'Image': [
    {'type': 'clearLogo', 'url': '/library/metadata/101/clearLogo/1'},
  ],
  'Marker': [
    {'type': 'credits', 'startTimeOffset': 9000000, 'endTimeOffset': 9360000, 'final': true},
  ],
  'Chapter': [
    {'tag': 'Opening', 'startTimeOffset': 0, 'endTimeOffset': 60000, 'index': 1},
  ],
  'Media': [
    {
      'id': 1,
      'bitrate': 8200,
      'audioChannels': 6,
      'videoResolution': '1080',
      'videoCodec': 'hevc',
      'audioCodec': 'eac3',
      'container': 'mkv',
      'Part': [
        {
          'id': 1,
          'key': '/library/parts/1/file.mkv',
          'container': 'mkv',
          'duration': 9360000,
          'file': '/media/Dune.mkv',
          'size': 4200000000,
          'Stream': [
            {'streamType': 1, 'id': 10, 'index': 0, 'codec': 'hevc', 'displayTitle': '1080p (HEVC)'},
            {'streamType': 2, 'id': 11, 'index': 1, 'codec': 'eac3', 'channels': 6, 'languageCode': 'eng', 'selected': true, 'default': true},
            {'streamType': 3, 'id': 12, 'key': '/library/streams/12', 'codec': 'srt', 'languageCode': 'eng', 'forced': '1', 'hearingImpaired': 1},
          ],
        },
      ],
    },
  ],
};

final seerrSample = <String, dynamic>{
  'id': 438631,
  'mediaType': 'movie',
  'title': 'Dune',
  'releaseDate': '2021-10-22',
  'posterPath': '/d5NXSklXo0qyIYkgV94XAgMIckC.jpg',
  'backdropPath': '/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg',
  'overview': 'Paul Atreides…',
  'tagline': 'Beyond fear.',
  'runtime': 156,
  'voteAverage': 7.8,
  'voteCount': 9000,
  'popularity': 120.5,
  'status': 'Released',
  'imdbId': 'tt1160419',
  'externalIds': {'imdbId': 'tt1160419'},
  'genres': [
    {'id': 878, 'name': 'Science Fiction'},
  ],
  'productionCompanies': [
    {'name': 'Legendary'},
  ],
  'belongsToCollection': {'id': 726871, 'name': 'Dune Collection'},
  'credits': {
    'cast': [
      {'id': 1, 'name': 'Timothée Chalamet', 'character': 'Paul', 'profilePath': '/a.jpg'},
    ],
    'crew': [
      {'id': 2, 'name': 'Denis Villeneuve', 'job': 'Director', 'department': 'Directing'},
      {'id': 3, 'name': 'Jon Spaihts', 'job': 'Screenplay', 'department': 'Writing'},
    ],
  },
  'relatedVideos': [
    {'name': 'Trailer', 'url': 'https://www.youtube.com/watch?v=n9xhJrPXop4', 'type': 'Trailer', 'site': 'YouTube', 'key': 'n9xhJrPXop4'},
  ],
  'releases': {
    'results': [
      {
        'iso_3166_1': 'US',
        'release_dates': [
          {'certification': 'PG-13'},
        ],
      },
    ],
  },
  'seasons': [
    {'seasonNumber': 1, 'name': 'Season 1', 'episodeCount': 8, 'airDate': '2021-01-01', 'posterPath': '/s.jpg'},
  ],
  'mediaInfo': {
    'id': 5,
    'tmdbId': 438631,
    'mediaType': 'movie',
    'status': 3,
    'ratingKey': '101',
    'seasons': [
      {'seasonNumber': 1, 'status': 5},
    ],
    'downloadStatus': [
      {'size': 1000, 'sizeLeft': 250, 'estimatedCompletionTime': '2026-10-14T21:00:00Z', 'status': 'downloading', 'title': 'Dune.mkv'},
    ],
    'requests': [
      {
        'id': 9,
        'status': 2,
        'createdAt': '2026-10-01T00:00:00Z',
        'requestedBy': {'displayName': 'Sam'},
        'seasons': [1],
        'type': 'movie',
      },
    ],
  },
};

final roomSample = <String, dynamic>{
  'id': 'room-1',
  'title': 'Dune',
  'sourceUri': TogetherRoom.sourceFor('abc123', '101'),
  'syncplayHost': 'relay.example',
  'syncplayPort': 7776,
  'endsAt': 1792000000,
  'createdBy': {'id': 9, 'title': 'Alex', 'username': 'alex', 'thumb': 'https://plex.tv/a.png'},
  'users': [
    {'id': 9, 'title': 'Alex'},
    {'id': 7, 'title': 'Me'},
  ],
};

String? _image(String? p, int w, int h) => p;

/// What the app does with a Plex item once it's read: none of it may throw, and the numbers
/// that drive layout stay in range.
void checkPlex(PlexItem i) {
  final p = i.watchProgress;
  if (p != null) expect(p, inInclusiveRange(0, 1));
  for (final n in [i.duration, i.viewOffset, i.viewCount, i.leafCount, i.viewedLeafCount, i.childCount]) {
    if (n != null) expect(n, greaterThanOrEqualTo(0));
  }
  for (final s in [i.rating, i.audienceRating, ...i.ratings.map((r) => r.value)]) {
    if (s != null) expect(s, inInclusiveRange(0, 10));
  }
  final id = i.imdbId;
  if (id != null) expect(isImdbId(id), isTrue);
  final d = TitleDetail.fromPlex(i, show: i, image: _image);
  d.metaLine;
  for (final s in d.scores) {
    expect(s.value, isNot(contains('NaN')));
  }
  plexTracks(i);
  i.cardTitle;
  i.cardSubtitle;
  i.posterPath;
  i.tmdbId;
  for (final m in i.media) {
    m.resolutionLabel;
    for (final s in m.streams) {
      s.label;
      s.isImageSubtitle;
    }
  }
  formatDuration(i.duration);
  LibraryIndex([i, i]);
  pickSpotlights([i, i], random: Random(1));
  pickTop([i], random: Random(1));
  pickShuffle([i], const ShuffleFilter(unwatched: false), random: Random(1));
  final f = Franchise.from(collection: i, items: [i, i]);
  expect(f.totalMinutes, greaterThanOrEqualTo(0));
  f.years;
  f.averageScore;
  f.upNext;
  f.marathonFrom(f.parts.firstOrNull);
  neighbours([i], i.ratingKey);
  pickTracks(i.media.firstOrNull?.streams ?? const [], audioLanguage: 'eng', mode: SubtitleMode.always);
}

void checkSeerr(SeerrResult r) {
  final d = TitleDetail.fromSeerr(r, ratings: SeerrRatings(rtCritics: 90, imdb: 7.5));
  d.metaLine;
  final state = requestStateOf(r.mediaInfo);
  final p = state.progress;
  if (p != null) expect(p, inInclusiveRange(0, 1));
  final v = r.voteAverage;
  if (v != null) expect(v, inInclusiveRange(0, 10));
  for (final url in [r.posterUrl(), r.backdropUrl(), for (final c in r.cast) c.profileUrl()]) {
    if (url != null) {
      expect(url, startsWith(SeerrImages.base));
      expect(url, isNot(contains('..')));
    }
  }
  final key = r.mediaInfo?.ratingKey;
  if (key != null) expect(key, matches(RegExp(r'^\w+$')));
  final id = r.imdbId;
  if (id != null) expect(isImdbId(id), isTrue);
  for (final x in r.videos) {
    final t = x.thumbUrl;
    if (t != null) expect(Uri.parse(t).host, 'img.youtube.com');
  }
  topMissing([r, r], LibraryIndex(const []));
  mergeByPopularity([r], [r]);
  requestableResults([r], const []);
  LibraryIndex(const []).owns(r);
  final f = Franchise.from(
    tmdb: SeerrCollection(id: 1, name: 'Dune Collection', parts: [r, r]),
  );
  expect(f.totalMinutes, greaterThanOrEqualTo(0));
  f.years;
  f.complete;
  tasteSeeds(const [], const Taste().rate(Taste.keyOf(r.mediaType, r.id), r.displayTitle, up: true));
}

void main() {
  group('Plex items survive hostile JSON', () {
    test('the sample reads as expected', () {
      final i = PlexItem.fromJson(plexSample);
      expect(i.tmdbId, 438631);
      expect(i.imdbId, 'tt1160419');
      checkPlex(i);
    });

    test('every value swapped for a wrong type, nonsense number or huge string', () {
      var n = 0;
      for (final (what, doc) in mutations(plexSample)) {
        try {
          checkPlex(PlexItem.fromJson(doc));
        } catch (e) {
          fail('$what: $e');
        }
        n++;
      }
      expect(n, greaterThan(2000));
    });

    test('negative and out-of-range numbers are dropped or clamped', () {
      final i = PlexItem.fromJson({...plexSample, 'viewOffset': 99999999999, 'duration': 1000, 'viewCount': -4, 'audienceRating': 1e9, 'rating': -3, 'childCount': '-2'});
      expect(i.watchProgress, 1);
      expect(i.viewCount, isNull);
      expect(i.audienceRating, 10);
      expect(i.rating, 0);
      expect(i.childCount, isNull);
      expect(PlexItem.fromJson({...plexSample, 'duration': double.infinity, 'audienceRating': 'NaN'}).duration, isNull);
      expect(PlexItem.fromJson({...plexSample, 'audienceRating': 'NaN'}).audienceRating, isNull);
    });

    test('ids that end up in links must look like ids', () {
      final i = PlexItem.fromJson({
        ...plexSample,
        'Guid': [
          {'id': 'imdb://tt1/../../evil'},
          {'id': 'tmdb://-5'},
        ],
      });
      expect(i.imdbId, isNull);
      expect(i.tmdbId, isNull);
    });

    test('huge arrays are read without trouble', () {
      final roles = [
        for (var k = 0; k < 50000; k++) {'id': k, 'tag': 'Actor $k', 'role': 'Role $k'},
      ];
      final i = PlexItem.fromJson({
        ...plexSample,
        'Role': roles,
        'Genre': [
          for (var k = 0; k < 50000; k++) {'tag': 'G$k'},
        ],
      });
      expect(i.roles, hasLength(50000));
      final d = TitleDetail.fromPlex(i, image: _image);
      expect(d.cast, hasLength(50000));
    });

    test('top-level oddities in a section and a marker', () {
      PlexSection.fromJson({'key': null, 'title': 5, 'type': []});
      expect(PlexMarker.fromJson({'startTimeOffset': -100, 'endTimeOffset': 'x'}).startMs, 0);
      expect(PlexStream.fromJson({'streamType': 'two', 'channels': -6, 'codec': 5}).channels, isNull);
    });
  });

  group('Seerr titles survive hostile JSON', () {
    test('the sample reads as expected', () {
      final r = SeerrResult.fromJson(seerrSample);
      expect(r.collectionId, 726871);
      expect(requestStateOf(r.mediaInfo).progress, 0.75);
      checkSeerr(r);
    });

    test('every value swapped for a wrong type, nonsense number or huge string', () {
      var n = 0;
      for (final (what, doc) in mutations(seerrSample)) {
        try {
          checkSeerr(SeerrResult.fromJson(doc));
        } catch (e) {
          fail('$what: $e');
        }
        n++;
      }
      expect(n, greaterThan(2000));
    });

    test('requests, ratings, people and series too', () {
      final request = seerrSample['mediaInfo']['requests'][0] as Map<String, dynamic>;
      final ratings = <String, dynamic>{
        'rt': {'criticsScore': 91, 'criticsRating': 'Certified Fresh', 'audienceScore': 88, 'audienceRating': 'Upright'},
        'imdb': {'criticsScore': 8.0},
      };
      final person = <String, dynamic>{'id': 1, 'name': 'Zendaya', 'biography': 'Bio', 'birthday': '1996-09-01', 'profilePath': '/z.jpg', 'knownForDepartment': 'Acting'};
      final series = <String, dynamic>{
        'id': 726871,
        'name': 'Dune Collection',
        'overview': 'x',
        'posterPath': '/p.jpg',
        'parts': [seerrSample],
      };
      for (final (what, doc) in mutations(request)) {
        expect(() => SeerrRequest.fromJson(doc), returnsNormally, reason: what);
      }
      for (final (what, doc) in mutations(ratings)) {
        final r = SeerrRatings.fromJson(doc);
        if (r.rtCritics != null) expect(r.rtCritics, inInclusiveRange(0, 100), reason: what);
        if (r.imdb != null) expect(r.imdb, inInclusiveRange(0, 10), reason: what);
        seerrScores(SeerrResult.fromJson(seerrSample), r);
      }
      for (final (what, doc) in mutations(person)) {
        expect(() => SeerrPerson.fromJson(doc).profileUrl(), returnsNormally, reason: what);
      }
      var n = 0;
      for (final (what, doc) in mutations(series)) {
        try {
          final s = SeerrCollection.fromJson(doc);
          Franchise.from(tmdb: s).released;
          s.posterUrl();
        } catch (e) {
          fail('$what: $e');
        }
        if (++n > 3000) break;
      }
    });

    test('a download with nonsense sizes still shows 0..1 progress', () {
      for (final (size, left) in [(1e308, 1e308), (-5, 10), (10, -5), (double.infinity, 1), ('big', 'small'), (0, 0)]) {
        final m = SeerrMediaInfo.fromJson({
          'status': 3,
          'downloadStatus': [
            {'size': size, 'sizeLeft': left, 'estimatedCompletionTime': '+275760-09-13T00:00:00Z'},
          ],
        });
        final s = requestStateOf(m);
        expect(s.progress, inInclusiveRange(0, 1));
        expect(s.detail, isNot(contains('NaN')));
      }
    });

    test('artwork paths and Plex keys that try to escape are dropped', () {
      final r = SeerrResult.fromJson({
        ...seerrSample,
        'posterPath': '/../../secret',
        'backdropPath': 'https://evil.example/x.jpg',
        'mediaInfo': {'status': 5, 'ratingKey': '../../accounts?X-Plex-Token=1'},
        'imdbId': 'tt1/../../x',
        'externalIds': {'imdbId': 'javascript:alert(1)'},
        'relatedVideos': [
          {'name': 'x', 'url': 'u', 'site': 'YouTube', 'key': '../../x'},
        ],
      });
      expect(r.posterUrl(), isNull);
      expect(r.backdropUrl(), isNull);
      expect(r.mediaInfo?.ratingKey, isNull);
      expect(r.imdbId, isNull);
      expect(r.videos.single.thumbUrl, isNull);
      expect(SeerrResult.fromJson({...seerrSample, 'posterPath': '/p/dune-part-two.png'}).posterUrl(), endsWith('/p/dune-part-two.png'));
    });
  });

  group('Watch Together rooms survive hostile JSON', () {
    test('every value swapped', () {
      for (final (what, doc) in mutations(roomSample)) {
        try {
          final r = TogetherRoom.fromJson(doc);
          expect(r.port, inInclusiveRange(1, 65535), reason: what);
          expect(r.title, isNot(contains('\n')), reason: what);
          expect(r.title.runes.length, lessThanOrEqualTo(120), reason: what);
          r.machineId;
          r.ratingKey;
          r.expired;
        } catch (e) {
          fail('$what: $e');
        }
      }
    });

    test('a room only names our server when its source says exactly that', () {
      TogetherRoom room(String uri) => TogetherRoom.fromJson({...roomSample, 'sourceUri': uri});
      expect(room('server://abc123/com.plexapp.plugins.library/library/metadata/101').machineId, 'abc123');
      expect(room('server://abc123/com.plexapp.plugins.library/library/metadata/101').ratingKey, '101');
      expect(room('server://ev il/x/library/metadata/101').machineId, isNull);
      expect(room('https://evil.example/library/metadata/101').machineId, isNull);
      expect(room('server://abc123/x/library/metadata/../../x').ratingKey, isNull);
    });

    test('an end time outside what a date can hold is no end time', () {
      expect(TogetherRoom.fromJson({...roomSample, 'endsAt': 9223372036854775807}).endsAt, isNull);
      expect(TogetherRoom.fromJson({...roomSample, 'endsAt': -9223372036854775807}).endsAt, isNull);
      expect(TogetherRoom.fromJson({...roomSample, 'endsAt': -9223372036854775808}).endsAt, isNull);
      expect(TogetherRoom.fromJson({...roomSample, 'endsAt': 'soon'}).endsAt, isNull);
    });

    test('names from a stranger are cleaned for display', () {
      final r = TogetherRoom.fromJson({
        ...roomSample,
        'title': 'Free\nmovie\u202E${'!' * 500}',
        'createdBy': {'id': 3, 'title': '\u0000\u0007'},
        'users': [
          for (var k = 0; k < 5000; k++) {'id': k, 'title': 'u$k'},
        ],
      });
      expect(r.title, startsWith('Free movie'));
      expect(r.title.runes.length, 120);
      expect(r.createdBy?.title, 'Friend');
      expect(r.users, hasLength(100));
    });

    test('lists that aren\'t lists read as empty', () async {
      for (final body in ['{"rooms": "nope"}', '{"rooms": {"a": 1}}', '"text"', '[1, 2, "x"]', '{"MediaContainer": "x"}', '{"MediaContainer": {"User": 5}}']) {
        final c = TogetherClient(
          token: 't',
          clientId: 'c',
          http: JsonHttp(client: MockClient((_) async => http.Response(body, 200, headers: {'content-type': 'application/json'}))),
        );
        expect(await c.rooms(), isEmpty, reason: body);
        expect(await c.friends(), isEmpty, reason: body);
      }
    });

    test('room ids are escaped in addresses', () async {
      final urls = <String>[];
      final c = TogetherClient(
        token: 't',
        clientId: 'c',
        http: JsonHttp(
          client: MockClient((req) async {
            urls.add(req.url.toString());
            return http.Response('{}', 200, headers: {'content-type': 'application/json'});
          }),
        ),
      );
      await c.leave('../users/me?x=1');
      expect(urls.single, 'https://together.plex.tv/rooms/..%2Fusers%2Fme%3Fx%3D1');
    });
  });

  group('Taste from disk', () {
    test('only well-formed keys and titles are kept', () {
      final t = Taste.fromJson({
        'likes': {'movie:603': 'The Matrix', 'movie:abc': 'x', '../../x': 'y', 'tv:1': 5, 'tv:2': null},
        'dislikes': ['not', 'a', 'map'],
      });
      expect(t.likes, {'movie:603': 'The Matrix'});
      expect(t.dislikes, isEmpty);
      for (final (_, doc) in mutations({
        'likes': {'movie:1': 'A'},
        'dislikes': {'tv:2': 'B'},
      })) {
        tasteSeeds(const [], Taste.fromJson(doc));
      }
    });
  });

  group('Charts survive hostile data', () {
    test('Trakt rows of the wrong shape are skipped', () async {
      for (final body in [
        '{"not": "a list"}',
        '[1, "x", null]',
        '[{"watchers": 1e400, "movie": {"title": 5, "year": "x", "ids": "nope"}}]',
        '[{"watchers": "lots", "movie": {"title": "Dune", "year": 1e400, "ids": {"tmdb": "438631"}}}]',
      ]) {
        final t = TraktClient(
          clientId: 'c',
          http: JsonHttp(client: MockClient((_) async => http.Response(body, 200, headers: {'content-type': 'application/json'}))),
        );
        final rows = await t.trending('movie');
        for (final r in rows) {
          expect(r.score, anyOf(isNull, isA<int>()));
        }
      }
    });

    test('Netflix TSV with missing columns, junk rows and huge lines', () {
      expect(NetflixTop10.parse('', 'movie'), isEmpty);
      expect(NetflixTop10.parse('week\tcategory\n2026-01-01\tFilms (English)', 'movie'), isEmpty);
      final head = 'week\tcategory\tweekly_rank\tshow_title\tweekly_views';
      final junk = [
        head,
        '2026-10-05\tFilms (English)\tx\t${'A' * 100000}\tNaN',
        '2026-10-05\tFilms (English)',
        '\t\t\t\t',
        '2026-10-05\tFilms (English)\t1\tDune\t1e999',
        for (var k = 0; k < 20000; k++) '2026-10-04\tFilms (English)\t$k\tOld $k\t$k',
      ].join('\r\n');
      final rows = NetflixTop10.parse(junk, 'movie');
      expect(rows.map((r) => r.title), contains('Dune'));
      expect(rows.length, 2);
    });
  });

  group('Server addresses', () {
    test('tidied and checked', () {
      expect(tidyServerUrl('  http://192.168.1.10:32400///  '), 'http://192.168.1.10:32400');
      expect(tidyServerUrl('192.168.1.10:32400'), 'http://192.168.1.10:32400');
      expect(tidyServerUrl('https://example.com/seerr/'), 'https://example.com/seerr');
      expect(tidyServerUrl(''), '');
      for (final ok in ['', 'http://192.168.1.10:32400', 'https://plex.example.com', 'https://example.com/seerr', 'http://[::1]:5055']) {
        expect(serverUrlProblem(ok), isNull, reason: ok);
      }
      for (final bad in [
        'ftp://example.com',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'http://user:pass@example.com',
        'http://:32400',
        'http:///path',
        'http://my server',
        'http://example.com:0',
        'http://example.com:99999',
        'http://example.com/?x=1',
        'http://example.com/#frag',
      ]) {
        expect(serverUrlProblem(bad), isNotNull, reason: bad);
      }
    });
  });

  group('cleanLabel', () {
    test('one short line of printable text', () {
      expect(cleanLabel('  Alex\n\tSmith  '), 'Alex Smith');
      expect(cleanLabel('evil\u202Etxt.exe'), 'evil txt.exe');
      expect(cleanLabel('\u0000\u001b[31m'), '[31m');
      expect(cleanLabel(null, fallback: 'Someone'), 'Someone');
      expect(cleanLabel('\u200B\uFEFF', fallback: 'Someone'), 'Someone');
      expect(cleanLabel('x' * 1000000, max: 10), '${'x' * 9}…');
      expect(cleanLabel('😀' * 50, max: 5), '${'😀' * 4}…');
      expect(cleanLabel('Zoë'), 'Zoë');
    });
  });

  test('JSON that decodes to non-finite numbers is safe to read', () {
    final j = jsonDecode('{"duration": 1e400, "viewOffset": -1e400, "year": 1e400, "audienceRating": 1e400}') as Map<String, dynamic>;
    final i = PlexItem.fromJson({...plexSample, ...j});
    expect(i.duration, isNull);
    expect(i.year, isNull);
    expect(i.audienceRating, isNull);
  });
}
