import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

PlexItem movie(String key, String title, {int? tmdb, int year = 2000, int viewCount = 0, int? viewOffset, double rating = 7, int minutes = 120, List<String> genres = const []}) => PlexItem(
  ratingKey: key,
  key: '/library/metadata/$key',
  type: 'movie',
  title: title,
  year: year,
  originallyAvailableAt: '$year-05-01',
  guids: [if (tmdb != null) 'tmdb://$tmdb'],
  viewCount: viewCount,
  viewOffset: viewOffset,
  audienceRating: rating,
  duration: minutes * 60000,
  genres: genres,
);

SeerrResult film(int id, String title, String date, {int runtime = 120, double vote = 7}) =>
    SeerrResult(id: id, mediaType: 'movie', title: title, releaseDate: date, runtime: runtime, voteAverage: vote);

void main() {
  group('franchise', () {
    final tmdb = SeerrCollection(
      id: 119,
      name: 'The Lord of the Rings Collection',
      overview: 'The saga.',
      parts: [
        film(122, 'The Return of the King', '2003-12-01', runtime: 201),
        film(120, 'The Fellowship of the Ring', '2001-12-18', runtime: 178),
        film(121, 'The Two Towers', '2002-12-18', runtime: 179),
        film(999, 'The Hunt for Gollum', '2099-01-01'),
      ],
    );

    test('joins TMDB and Plex in release order', () {
      final f = Franchise.from(tmdb: tmdb, items: [movie('1', 'Fellowship', tmdb: 120, year: 2001, viewCount: 1), movie('2', 'Two Towers', tmdb: 121, year: 2002, viewOffset: 60000)]);
      expect(f.name, 'The Lord of the Rings');
      expect(f.parts.map((p) => p.title).take(3), ['The Fellowship of the Ring', 'The Two Towers', 'The Return of the King']);
      expect((f.ownedCount, f.watchedCount, f.complete), (2, 1, false));
      expect(f.missing.single.tmdb!.id, 122);
      expect(f.upcoming.single.title, 'The Hunt for Gollum');
      expect(f.upNext!.title, 'The Two Towers'); // partway through wins
      expect(f.years, (from: 2001, to: 2003));
      expect(f.marathonFrom(f.upNext).map((i) => i.ratingKey), ['2']);
    });

    test('finds library copies through the index and keeps Plex-only items', () {
      final lib = [movie('7', 'The Return of the King', tmdb: 122, year: 2003)];
      final f = Franchise.from(tmdb: tmdb, items: [movie('8', 'Extended Edition Extras', year: 2004)], library: LibraryIndex(lib), lookup: (k) => lib.where((i) => i.ratingKey == k).firstOrNull);
      expect(f.parts.firstWhere((p) => p.title == 'The Return of the King').plex?.ratingKey, '7');
      expect(f.parts.map((p) => p.title), contains('Extended Edition Extras'));
    });
  });

  group('because you watched', () {
    final recs = [
      [film(1, 'A', '2000'), film(2, 'B', '2000'), film(3, 'C', '2000'), film(4, 'D', '2000'), film(5, 'E', '2000'), film(50, 'Seed2', '2000')],
      [film(5, 'E', '2000'), film(6, 'F', '2000'), film(7, 'G', '2000'), film(8, 'H', '2000'), film(9, 'I', '2000'), film(10, 'J', '2000')],
    ];
    const seeds = <TasteSeed>[(mediaType: 'movie', tmdbId: 40, title: 'Seed1', liked: false), (mediaType: 'movie', tmdbId: 50, title: 'Seed2', liked: false)];

    test('drops thumbs-down titles and seeds, shows each title once and lifts shared ones', () {
      final taste = const Taste().rate('movie:2', 'B', up: false);
      final rows = becauseYouWatched(seeds, recs, taste);
      expect(rows.first.heading, 'Because You Watched Seed1');
      expect(rows.first.items.map((r) => r.title), ['E', 'A', 'C', 'D']); // E is recommended twice
      expect(rows[1].items.map((r) => r.title), ['F', 'G', 'H', 'I', 'J']);
    });

    test('thumbs up becomes a seed first and toggles off', () {
      var taste = const Taste().rate('movie:77', 'Liked One', up: true);
      final s = tasteSeeds(seeds, taste);
      expect((s.first.title, s.first.liked), ('Liked One', true));
      taste = taste.rate('movie:77', 'Liked One', up: true);
      expect(taste.likes, isEmpty);
      expect(Taste.fromJson(const Taste().rate('tv:3', 'X', up: false).toJson()).disliked('tv:3'), isTrue);
    });
  });

  group('shuffle', () {
    final pool = [
      movie('1', 'Short', minutes: 85, genres: ['Comedy']),
      movie('2', 'Long', minutes: 170),
      movie('3', 'Seen', minutes: 80, viewCount: 1),
    ];
    test('respects length, watched and genre', () {
      expect(shuffleCandidates(pool, const ShuffleFilter(maxMinutes: 90)).map((i) => i.title), ['Short']);
      expect(shuffleCandidates(pool, const ShuffleFilter(maxMinutes: 90, unwatched: false)).length, 2);
      expect(shuffleCandidates(pool, const ShuffleFilter(genre: 'Comedy')).single.title, 'Short');
      expect(pickShuffle(pool, const ShuffleFilter(kind: 'show')), isNull);
    });
    test('avoids the last pick while it can', () {
      final rng = Random(3);
      for (var k = 0; k < 20; k++) {
        expect(pickShuffle(pool, const ShuffleFilter(), random: rng, avoid: {'1'})!.ratingKey, '2');
      }
    });
  });
}
