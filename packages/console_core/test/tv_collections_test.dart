import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

PlexItem show(String key, String title, {int? year, List<String> guids = const [], String? agent}) =>
    PlexItem(ratingKey: key, key: '/library/metadata/$key', type: 'show', title: title, year: year, guids: guids, plexGuid: agent);

/// A pack with one block of [n] shows: show i has tvdb 100+i, tmdb 200+i, rating falling with i.
String packJson(int n, {Map<String, Object?> extra = const {}}) => jsonEncode({
  'format': 1,
  'built': '2026-11-06T00:00:00Z',
  'posterBase': 'https://static.tvmaze.com/uploads/images/medium_portrait/',
  'shows': [
    for (var i = 0; i < n; i++) {'t': 'Show $i', 'y': 1990 + i, 'tv': 100 + i, 'tm': 200 + i, 'r': 9.0 - i * 0.1, 'w': 90, 'p': '1/$i.jpg'},
  ],
  'collections': [
    {'id': 'toonami', 'kind': 'block', 'name': 'Toonami', 'shows': [for (var i = 0; i < n; i++) i]},
  ],
  ...extra,
});

void main() {
  group('pack parsing', () {
    test('reads shows and collections', () {
      final p = CollectionPack.parse(packJson(3));
      expect(p.collections.single.name, 'Toonami');
      final s = p.collections.single.shows.first;
      expect((s.title, s.year, s.tvdb, s.tmdb), ('Show 0', 1990, 100, 200));
      expect(s.poster, 'https://static.tvmaze.com/uploads/images/medium_portrait/1/0.jpg');
    });

    test('refuses things that are not a pack', () {
      expect(() => CollectionPack.parse('[]'), throwsFormatException);
      expect(() => CollectionPack.parse(jsonEncode({'format': 2, 'built': '2026-01-01', 'shows': [], 'collections': []})), throwsFormatException);
    });

    test('drops posters from other hosts, bad ids and out-of-range indexes', () {
      final p = CollectionPack.parse(jsonEncode({
        'format': 1,
        'built': '2026-11-06T00:00:00Z',
        'posterBase': 'https://evil.example/',
        'shows': [
          {'t': 'A', 'im': 'nm123', 'tv': -4, 'p': 'x.jpg'},
        ],
        'collections': [
          {'id': 'x', 'name': 'X', 'shows': [0, 5, -1, 'a']},
          {'id': 'empty', 'name': 'Empty', 'shows': [9]},
        ],
      }));
      final s = p.collections.single.shows.single;
      expect((s.poster, s.imdb, s.tvdb), (null, null, null));
    });
  });

  group('matching', () {
    test('by tvdb, tmdb, imdb, legacy agents and title + year', () {
      final lib = ShowMatcher([
        show('1', 'DBZ', guids: ['tvdb://100']),
        show('2', 'Other', guids: ['tmdb://201']),
        show('3', 'Third', guids: ['imdb://tt0000003']),
        show('4', 'Legacy', agent: 'com.plexapp.agents.thetvdb://103?lang=en'),
        show('5', 'Hama', agent: 'com.plexapp.agents.hama://tvdb-104?lang=en'),
        show('6', 'Cowboy Bebop', year: 1998),
      ]);
      expect(lib.find(const PackShow(title: 'x', tvdb: 100))?.ratingKey, '1');
      expect(lib.find(const PackShow(title: 'x', tmdb: 201))?.ratingKey, '2');
      expect(lib.find(const PackShow(title: 'x', imdb: 'tt0000003'))?.ratingKey, '3');
      expect(lib.find(const PackShow(title: 'x', tvdb: 103))?.ratingKey, '4');
      expect(lib.find(const PackShow(title: 'x', tvdb: 104))?.ratingKey, '5');
      expect(lib.find(const PackShow(title: 'Cowboy Bebop!', year: 1999))?.ratingKey, '6');
      expect(lib.find(const PackShow(title: 'Cowboy Bebop', year: 2021)), isNull, reason: 'a remake with the same name');
    });
  });

  group('the 10-show rule', () {
    final pack = CollectionPack.parse(packJson(30));
    final block = pack.collections.single;

    test('owning none shows the 10 best-rated missing shows', () {
      final s = TvShelf.build(block, ShowMatcher([]));
      expect(s.owned, isEmpty);
      expect(s.missing.map((m) => m.title), [for (var i = 0; i < 10; i++) 'Show $i']);
      expect(s.allMissing, hasLength(30));
    });

    test('owned shows come first even when rated low, and the rest is filled to 10', () {
      final s = TvShelf.build(block, ShowMatcher([show('a', 'Show 29', guids: ['tvdb://129']), show('b', 'Show 25', guids: ['tvdb://125']), show('c', 'Show 0', guids: ['tvdb://100'])]));
      expect(s.owned.map((o) => o.ratingKey), ['c', 'b', 'a'], reason: 'best-rated owned first');
      expect(s.missing, hasLength(7));
      expect(s.missing.first.title, 'Show 1');
      expect(s.missing.any((m) => m.title == 'Show 0'), isFalse);
    });

    test('owning 10 or more shows all of them and no missing ones', () {
      final mine = [for (var i = 0; i < 14; i++) show('k$i', 'Show ${i * 2}', guids: ['tvdb://${100 + i * 2}'])];
      final s = TvShelf.build(block, ShowMatcher(mine));
      expect(s.owned, hasLength(14));
      expect(s.missing, isEmpty);
      expect(s.allMissing, hasLength(16));
      final ten = TvShelf.build(block, ShowMatcher(mine.take(10)));
      expect((ten.owned.length, ten.missing.length), (10, 0));
    });

    test('a show listed twice counts once', () {
      final p = CollectionPack.parse(jsonEncode({
        'format': 1,
        'built': '2026-11-06T00:00:00Z',
        'shows': [
          {'t': 'A', 'tv': 1},
          {'t': 'A again', 'tv': 1},
        ],
        'collections': [
          {'id': 'x', 'name': 'X', 'shows': [0, 1]},
        ],
      }));
      expect(TvShelf.build(p.collections.single, ShowMatcher([])).missing, hasLength(1));
    });

    test('a popular show outranks an obscure one with a slightly higher rating', () {
      const famous = PackShow(title: 'F', rating: 8.6, weight: 99), obscure = PackShow(title: 'O', rating: 9.4, weight: 3);
      expect(famous.score, greaterThan(obscure.score));
    });
  });

  test('shelves list collections you own shows from first', () {
    final p = CollectionPack.parse(jsonEncode({
      'format': 1,
      'built': '2026-11-06T00:00:00Z',
      'shows': [
        {'t': 'A', 'tv': 1},
        {'t': 'B', 'tv': 2},
      ],
      'collections': [
        {'id': 'one', 'name': 'One', 'shows': [0]},
        {'id': 'two', 'name': 'Two', 'kind': 'network', 'shows': [1]},
      ],
    }));
    final shelves = tvShelves(p, ShowMatcher([show('x', 'B', guids: ['tvdb://2'])]));
    expect(shelves.map((s) => s.collection.id), ['two', 'one']);
    expect(tvShelves(p, ShowMatcher([]), kind: 'block').map((s) => s.collection.id), ['one']);
  });

  group('channels', () {
    test('a pack source reads and writes, and old rules still read', () {
      const s = ChannelSource(kind: 'pack', key: 'toonami', title: 'Toonami');
      expect(ChannelSource.fromJson(s.toJson()), s);
      expect(ChannelSource.fromJson({'kind': 'nonsense', 'key': 'x'}), isNull);
    });

    test('a pack source plays the episodes of the shows you own from it', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.path);
        final m = RegExp(r'^/library/metadata/(\w+)/allLeaves$').firstMatch(req.url.path);
        final eps = m == null
            ? <Map<String, Object>>[]
            : [
                for (var e = 1; e <= 3; e++) {'ratingKey': '${m[1]}-$e', 'key': '/x', 'type': 'episode', 'title': 'E$e', 'grandparentRatingKey': m[1]!, 'parentIndex': 1, 'index': e},
              ];
        return http.Response(jsonEncode({'MediaContainer': {'Metadata': eps}}), 200, headers: {'content-type': 'application/json'});
      });
      final plex = PlexClient(baseUrl: 'http://10.0.0.2:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: client));
      final titles = <String, String>{};
      final shows = await loadChannelSources(
        plex,
        const [ChannelSource(kind: 'pack', key: 'toonami', title: 'Toonami')],
        titles: titles,
        packShows: (id) async => id == 'toonami' ? [show('a', 'DBZ'), show('b', 'Gundam')] : const [],
      );
      expect(shows.keys.toSet(), {'a', 'b'});
      expect(shows['a'], hasLength(3));
      expect(titles, {'a': 'DBZ', 'b': 'Gundam'});
      // Without a pack in hand a pack source is just empty.
      expect(await loadChannelSources(plex, const [ChannelSource(kind: 'pack', key: 'toonami', title: 'Toonami')]), isEmpty);
    });
  });
}
