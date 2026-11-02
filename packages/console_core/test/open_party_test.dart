import 'package:console_core/console_core.dart';
import 'package:openwatchparty/openwatchparty.dart' as owp;
import 'package:test/test.dart';

PlexItem _item(Map<String, dynamic> j) => PlexItem.fromJson(j);

final _dune = _item({
  'ratingKey': '101',
  'type': 'movie',
  'title': 'Dune: Part Two',
  'year': 2024,
  'guid': 'plex://movie/5d776c5f7a53e9001e74e4d1',
  'duration': 9960000,
  'Guid': [
    {'id': 'imdb://tt15239678'},
    {'id': 'tmdb://693134'},
  ],
  'Media': [
    {
      'id': 1,
      'Part': [
        {'id': 1, 'key': '/p/1', 'duration': 9961000, 'size': 40000000000, 'file': '/movies/Dune Part Two (2024)/Dune.Part.Two.2024.2160p.mkv'},
      ],
    },
  ],
});

final _show = _item({
  'ratingKey': '200',
  'type': 'show',
  'title': 'Severance',
  'year': 2022,
  'Guid': [
    {'id': 'tvdb://371980'},
    {'id': 'imdb://tt11280740'},
  ],
});

final _episode = _item({
  'ratingKey': '204',
  'type': 'episode',
  'title': 'Who Is Alive?',
  'grandparentTitle': 'Severance',
  'grandparentRatingKey': '200',
  'parentIndex': 2,
  'index': 4,
  'duration': 2940000,
  'Guid': [
    {'id': 'tvdb://10419133'},
  ],
});

void main() {
  group('describeForRoom', () {
    test('a movie carries its ids, length, file and our server', () {
      final m = describeForRoom(_dune, machineId: 'abc123')!;
      expect(m.kind, owp.MediaKind.movie);
      expect(m.title, 'Dune: Part Two');
      expect(m.year, 2024);
      expect(m.ids, {'imdb': 'tt15239678', 'tmdb': '693134', 'plex': 'plex://movie/5d776c5f7a53e9001e74e4d1'});
      expect(m.durationMs, 9961000, reason: 'the part that plays, not the item');
      expect(m.file?.name, 'Dune.Part.Two.2024.2160p.mkv');
      expect(m.file?.sizeBytes, 40000000000);
      expect(sharedCopy(m), (server: 'abc123', item: '101'));
      expect(owp.checkMedia(m), isNull);
    });

    test('an episode names its series, season and number', () {
      final m = describeForRoom(_episode, show: _show, machineId: 'abc123')!;
      expect(m.kind, owp.MediaKind.episode);
      expect(m.series?.title, 'Severance');
      expect(m.series?.ids, {'tvdb': '371980', 'imdb': 'tt11280740'});
      expect(m.season, 2);
      expect(m.episode, 4);
      expect(m.year, isNull);
      expect(owp.checkMedia(m), isNull);
    });

    test('nothing to share without a length, or for a show', () {
      expect(describeForRoom(_item({'ratingKey': '1', 'type': 'movie', 'title': 'X'}), machineId: 'a'), isNull);
      expect(describeForRoom(_show, machineId: 'a'), isNull);
    });

    test('control and direction characters are dropped from titles', () {
      expect(roomText('Am‎élie\n\t (2001)\u0007'), 'Amélie (2001)');
      expect(roomText('  \n '), isNull);
    });
  });

  group('matching a room to the library', () {
    final library = [
      _dune,
      _item({'ratingKey': '102', 'type': 'movie', 'title': 'Dune', 'year': 2021, 'Guid': [{'id': 'tmdb://438631'}]}),
      _item({'ratingKey': '103', 'type': 'movie', 'title': 'Dune', 'year': 1984}),
      _show,
    ];

    test('a shared id wins over the title', () {
      final found = sameTitles(library, type: 'movie', title: 'Something Else', ids: {'tmdb': '693134'});
      expect(found.map((i) => i.ratingKey), ['101']);
    });

    test('without ids, title and year (within one) decide', () {
      expect(sameTitles(library, type: 'movie', title: 'DUNE', year: 1985).map((i) => i.ratingKey), ['103']);
      expect(sameTitles(library, type: 'movie', title: 'Dune').map((i) => i.ratingKey), ['102', '103']);
    });

    test('ids from the room must be well formed to count', () {
      expect(trustedIds({'imdb': 'tt1 OR 1=1', 'tmdb': '../../etc', 'tvdb': '371980', 'plex': 'plex://movie/<x>'}), {'tvdb': '371980'});
      expect(sameTitles(library, type: 'show', title: 'nope', ids: {'tvdb': '371980'}).single.ratingKey, '200');
    });

    test('an episode by season and number, or by its own id', () {
      final eps = [
        _episode,
        _item({'ratingKey': '205', 'type': 'episode', 'title': 'Chikhai Bardo', 'parentIndex': 2, 'index': 5}),
      ];
      const byNumber = owp.Media(kind: owp.MediaKind.episode, title: 'x', series: owp.Series(title: 'Severance'), season: 2, episode: 5, durationMs: 1);
      expect(sameEpisode(eps, byNumber)?.ratingKey, '205');
      const byId = owp.Media(kind: owp.MediaKind.episode, title: 'x', series: owp.Series(title: 'Severance'), season: 9, episode: 9, ids: {'tvdb': '10419133'}, durationMs: 1);
      expect(sameEpisode(eps, byId)?.ratingKey, '204');
    });

    test('our server and item come from our member or Plezy’s, and only when they look right', () {
      owp.Media withExt(Map<String, Object?> ext) => owp.Media(kind: owp.MediaKind.movie, title: 'x', durationMs: 1, ext: ext);
      expect(sharedCopy(withExt({'app.plezy': {'server': 'abc', 'item': '55', 'version': '9'}})), (server: 'abc', item: '55'));
      expect(sharedCopy(withExt({liquifluxExt: {'server': 'abc', 'item': '../library/sections'}})), isNull);
      expect(sharedCopy(withExt({liquifluxExt: {'server': 'a/b', 'item': '5'}})), isNull);
      expect(sharedCopy(withExt({liquifluxExt: 'abc:5'})), isNull);
    });

    test('a candidate is our item with its length', () {
      final c = candidateFor(_dune);
      expect(c.ref, '101');
      expect(c.durationMs, 9961000);
    });
  });

  test('room codes as typed', () {
    expect(roomCode('k7m q2x'), 'K7M-Q2X');
    expect(roomCode('K7M-Q2X'), 'K7M-Q2X');
    expect(roomCode('hello world'), isNull);
  });
}
