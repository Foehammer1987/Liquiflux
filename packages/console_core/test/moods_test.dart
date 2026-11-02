import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

PlexItem item(int n, List<String> genres, {String type = 'movie', double? score = 7.5, int? year = 2010, int minutes = 110, bool watched = false, int? addedAt, int? leafCount, int? viewedLeafCount, int? childCount}) => PlexItem(
  ratingKey: '$n',
  key: '/library/metadata/$n',
  type: type,
  title: 'Title $n',
  genres: genres,
  audienceRating: score,
  year: year,
  duration: minutes * 60000,
  viewCount: watched ? 1 : null,
  addedAt: addedAt,
  leafCount: leafCount,
  viewedLeafCount: viewedLeafCount,
  childCount: childCount,
);

List<String> names(List<MoodRow> rows) => [for (final r in rows) r.name];

void main() {
  test('genre names from movie and TV agents count the same', () {
    expect(moodGenres(['Science Fiction']), {'scifi'});
    expect(moodGenres(['Sci-Fi & Fantasy']), {'scifi', 'fantasy'});
    expect(moodGenres(['Action & Adventure', 'Suspense']), {'action', 'adventure', 'thriller'});
    expect(moodGenres(['Kids']), {'family'});
  });

  test('a mood needs enough titles to show', () {
    final pool = [for (var i = 0; i < 7; i++) item(i, ['Science Fiction', 'Thriller'])];
    expect(names(moodRows(pool)), isNot(contains('Dark Sci-Fi')));
    pool.add(item(7, ['Sci-Fi & Fantasy', 'Horror']));
    expect(names(moodRows(pool)), contains('Dark Sci-Fi'));
  });

  test('feel-good comedies leave out dark comedies', () {
    final pool = [
      for (var i = 0; i < 10; i++) item(i, ['Comedy', 'Romance']),
      for (var i = 10; i < 20; i++) item(i, ['Comedy', 'Crime']),
    ];
    final row = moodRows(pool).firstWhere((r) => r.name == 'Feel-Good Comedies');
    expect(row.items.map((i) => int.parse(i.ratingKey)), everyElement(lessThan(10)));
  });

  test('magical worlds needs more than a fantasy tag', () {
    final pool = [
      for (var i = 0; i < 8; i++) item(i, ['Adventure', 'Fantasy']),
      item(8, ['Comedy', 'Fantasy']),
    ];
    final row = moodRows(pool).firstWhere((r) => r.name == 'Magical Worlds');
    expect(row.items.map((i) => i.ratingKey), isNot(contains('8')));
  });

  test('kind keeps to movies or series', () {
    final pool = [
      for (var i = 0; i < 10; i++) item(i, ['Horror']),
      for (var i = 10; i < 20; i++) item(i, ['Horror'], type: 'show'),
    ];
    final row = moodRows(pool, kind: 'show').firstWhere((r) => r.name == 'Spine-Chilling Horror');
    expect(row.items.map((i) => i.type), everyElement('show'));
    expect(row.items, hasLength(10));
  });

  test('waiting on your shelf: unwatched, well rated, added over a year ago', () {
    final now = DateTime(2026, 10, 30);
    final old = now.subtract(const Duration(days: 400)).millisecondsSinceEpoch ~/ 1000;
    final fresh = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final pool = [
      for (var i = 0; i < 8; i++) item(i, ['Drama'], addedAt: old),
      for (var i = 8; i < 16; i++) item(i, ['Drama'], addedAt: old, watched: true),
      for (var i = 16; i < 24; i++) item(i, ['Drama'], addedAt: fresh),
    ];
    final row = moodRows(pool, now: now).firstWhere((r) => r.name == 'Waiting on Your Shelf');
    expect(row.items.map((i) => int.parse(i.ratingKey)).toSet(), {for (var i = 0; i < 8; i++) i});
  });

  test('unwatched titles come first, except in Worth a Rewatch', () {
    final pool = [
      for (var i = 0; i < 30; i++) item(i, ['Western'], watched: i < 15, score: 8.5),
    ];
    final rows = moodRows(pool, perRow: 5, random: Random(1));
    final west = rows.firstWhere((r) => r.name == 'The Wild West').items;
    final again = rows.firstWhere((r) => r.name == 'Worth a Rewatch').items;
    expect(west.where((i) => i.isWatched).length, lessThan(3));
    expect(again, everyElement(predicate<PlexItem>((i) => i.isWatched)));
  });

  test('binge-worthy series: long, well rated, not finished', () {
    final pool = [
      for (var i = 0; i < 8; i++) item(i, ['Drama'], type: 'show', leafCount: 40, viewedLeafCount: 3, score: 8.2),
      item(8, ['Drama'], type: 'show', leafCount: 40, viewedLeafCount: 40, score: 8.2),
      item(9, ['Drama'], type: 'show', leafCount: 6, score: 8.2),
    ];
    final row = moodRows(pool).firstWhere((r) => r.name == 'Binge-Worthy Series');
    expect(row.items, hasLength(8));
  });

  test('home picks other moods than last time and spreads titles out', () {
    final pool = [
      for (var i = 0; i < 40; i++) item(i, ['Comedy', 'Romance', 'Drama']),
      for (var i = 40; i < 80; i++) item(i, ['Horror', 'Science Fiction', 'Thriller']),
      for (var i = 80; i < 120; i++) item(i, ['Western', 'History']),
      for (var i = 120; i < 160; i++) item(i, ['Animation', 'Family', 'Documentary']),
    ];
    // Nine moods fill here, so two visits of four never need to repeat one.
    final first = homeMoods(pool, random: Random(3));
    expect(first, hasLength(4));
    final second = homeMoods(pool, random: Random(4), recent: {for (final m in first) m.name});
    expect(names(second).toSet().intersection(names(first).toSet()), isEmpty);
    final keys = [for (final m in first) ...m.items.map((i) => i.ratingKey)];
    expect(keys.toSet().length, keys.length);
  });

  test('genre rows use Plex names, biggest first', () {
    final pool = [
      for (var i = 0; i < 12; i++) item(i, ['Comedy']),
      for (var i = 12; i < 21; i++) item(i, ['Science Fiction']),
      for (var i = 21; i < 24; i++) item(i, ['Western']),
    ];
    expect(names(genreRows(pool)), ['Comedy', 'Science Fiction']);
  });
}
