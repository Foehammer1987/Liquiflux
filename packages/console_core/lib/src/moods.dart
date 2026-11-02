import 'dart:math';

import 'plex/plex_models.dart';
import 'spotlight.dart' show scoreOf;

/// One title as a mood sees it: its genres boiled down to a few plain words, so Plex's
/// movie names ("Science Fiction"), its TV names ("Sci-Fi & Fantasy") and older agents'
/// ("Suspense") all count the same.
class MoodTitle {
  MoodTitle(this.item, this.now) : genres = moodGenres(item.genres);
  final PlexItem item;
  final DateTime now;
  final Set<String> genres;

  bool has(String g) => genres.contains(g);
  bool any(List<String> gs) => gs.any(genres.contains);
  bool get movie => item.type == 'movie';
  bool get show => item.type == 'show';
  double get score => scoreOf(item);

  /// Unknown scores pass: a title Plex has no rating for shouldn't drop out of every row.
  bool scored(double min) => score == 0 || score >= min;
  int get minutes => (item.duration ?? 0) ~/ 60000;
  int get year => item.year ?? 0;
}

/// Plain genre words for [genres] as Plex names them.
Set<String> moodGenres(List<String> genres) {
  final out = <String>{};
  for (final raw in genres) {
    final g = raw.toLowerCase().trim();
    out.addAll(switch (g) {
      'science fiction' || 'sci-fi' || 'scifi' => ['scifi'],
      'sci-fi & fantasy' => ['scifi', 'fantasy'],
      'action & adventure' => ['action', 'adventure'],
      'war & politics' => ['war'],
      'suspense' => ['thriller'],
      'kids' || 'children' => ['family'],
      'musical' => ['music'],
      'anime' => ['animation', 'anime'],
      'film-noir' || 'film noir' => ['crime', 'noir'],
      'romantic comedy' => ['romance', 'comedy'],
      'mini-series' || 'miniseries' => ['miniseries'],
      'biography' => ['history', 'biography'],
      _ => [g],
    });
  }
  return out;
}

/// A Netflix-style themed row ("Dark Sci-Fi", "Feel-Good Comedies") made from your own
/// library. Plex has no moods for movies and shows, so each one is a recipe over what it
/// does have: genres, year, length, score and whether you've watched it.
class Mood {
  const Mood(this.name, this.matches, {this.rewatch = false});
  final String name;
  final bool Function(MoodTitle t) matches;

  /// Watched titles come first instead of last.
  final bool rewatch;
}

const _dark = ['horror', 'thriller', 'crime', 'war'];

/// Every mood, in the order the Moods page lists them.
final moods = <Mood>[
  Mood('Feel-Good Comedies', (t) => t.has('comedy') && !t.any(_dark) && t.scored(6)),
  Mood('Laugh-Out-Loud Action', (t) => t.has('action') && t.has('comedy') && !t.has('horror')),
  Mood('Dark Sci-Fi', (t) => t.has('scifi') && t.any(['horror', 'thriller'])),
  Mood('Mind-Bending Mysteries', (t) => t.has('mystery') && !t.has('horror') && !t.has('comedy') && t.any(['scifi', 'thriller', 'fantasy', 'drama'])),
  Mood('Edge-of-Your-Seat Thrillers', (t) => t.has('thriller') && t.any(['action', 'crime']) && !t.any(['comedy', 'horror'])),
  Mood('Gritty Crime Dramas', (t) => t.has('crime') && t.has('drama') && !t.has('comedy')),
  Mood('Epic Adventures', (t) => t.has('adventure') && !t.has('animation') && (t.any(['fantasy', 'history', 'war']) || t.minutes >= 140)),
  // Fantasy on its own is too loose: TMDB files plenty of comedies there (Ted 2, Liar Liar).
  Mood('Magical Worlds', (t) => t.has('fantasy') && t.any(['adventure', 'family']) && !t.any(['horror', 'animation'])),
  Mood('Space and Beyond', (t) => t.has('scifi') && t.has('adventure') && !t.has('horror')),
  Mood('Animated Favorites', (t) => t.has('animation') && !t.has('horror')),
  Mood('Family Movie Night', (t) => t.movie && t.has('family') && !t.any(_dark)),
  Mood('Romance for Date Night', (t) => t.has('romance') && t.any(['comedy', 'drama']) && !t.any(['horror', 'war'])),
  Mood('Heartfelt Dramas', (t) => t.has('drama') && !t.any([..._dark, 'scifi', 'action', 'fantasy', 'comedy']) && t.scored(7)),
  Mood('Spine-Chilling Horror', (t) => t.has('horror')),
  Mood('History and War Stories', (t) => t.any(['history', 'war'])),
  Mood('Fascinating Documentaries', (t) => t.has('documentary')),
  Mood('The Wild West', (t) => t.has('western')),
  Mood('Music and Musicals', (t) => t.has('music') && !t.has('documentary')),
  Mood('Binge-Worthy Series', (t) => t.show && (t.item.leafCount ?? 0) >= 20 && t.scored(7.5) && (t.item.viewedLeafCount ?? 0) < (t.item.leafCount ?? 0)),
  Mood('Limited Series', (t) => t.show && (t.has('miniseries') || (t.item.childCount == 1 && (t.item.leafCount ?? 99) <= 10))),
  Mood('In 90 Minutes or Less', (t) => t.movie && t.minutes > 0 && t.minutes <= 90 && t.scored(6.5)),
  Mood('Timeless Classics', (t) => t.year > 0 && t.year < 1980 && t.scored(7)),
  Mood('Totally ’80s', (t) => t.year >= 1980 && t.year < 1990 && t.scored(6.5)),
  Mood('’90s Favorites', (t) => t.year >= 1990 && t.year < 2000 && t.scored(6.5)),
  Mood('Waiting on Your Shelf', (t) => !t.item.isWatched && (t.item.viewedLeafCount ?? 0) == 0 && _addedBefore(t, const Duration(days: 365)) && t.scored(7)),
  Mood('Worth a Rewatch', (t) => t.movie && t.item.isWatched && t.scored(8), rewatch: true),
];

bool _addedBefore(MoodTitle t, Duration age) {
  final at = t.item.addedAt;
  return at != null && at > 0 && t.now.difference(DateTime.fromMillisecondsSinceEpoch(at * 1000)) >= age;
}

/// One filled row: its name and the titles to show.
typedef MoodRow = ({String name, List<PlexItem> items});

/// Every mood with at least [minTitles] matches in [pool], in [moods] order, each with up to
/// [perRow] titles: drawn at random, weighted toward better scores and (except a rewatch
/// row) titles you haven't seen, so a visit shows a different slice of a big library.
/// [kind] 'movie' or 'show' keeps to one; anything else takes both.
List<MoodRow> moodRows(List<PlexItem> pool, {String kind = 'all', int perRow = 20, int minTitles = 8, Random? random, DateTime? now, List<Mood>? from}) {
  final rng = random ?? Random();
  final titles = _titles(pool, kind, now ?? DateTime.now());
  return [
    for (final m in from ?? moods)
      if (titles.where(m.matches).toList() case final hits when hits.length >= minTitles) (name: m.name, items: _draw(hits, perRow, rng, rewatch: m.rewatch)),
  ];
}

/// Plain genre rows (Plex's own names), biggest first, filled like [moodRows].
List<MoodRow> genreRows(List<PlexItem> pool, {String kind = 'all', int perRow = 20, int minTitles = 8, Random? random}) {
  final rng = random ?? Random();
  final by = <String, List<MoodTitle>>{};
  for (final t in _titles(pool, kind, DateTime.now())) {
    for (final g in t.item.genres) {
      (by[g] ??= []).add(t);
    }
  }
  final names = by.keys.where((g) => by[g]!.length >= minTitles).toList()..sort((a, b) => by[b]!.length.compareTo(by[a]!.length));
  return [for (final g in names) (name: g, items: _draw(by[g]!, perRow, rng))];
}

/// [count] mood rows for Home: picked at random from the ones that fill, leaving out [recent]
/// (the names Home showed last time) unless too few are left, and spreading titles so the
/// same one doesn't sit in several rows or repeat [avoid] (spotlight and Top 10).
List<MoodRow> homeMoods(List<PlexItem> pool, {int count = 4, int perRow = 16, Set<String> recent = const {}, Set<String> avoid = const {}, Random? random, DateTime? now}) {
  final rng = random ?? Random();
  final titles = _titles(pool, 'all', now ?? DateTime.now());
  final filled = [
    for (final m in moods)
      if (titles.where(m.matches).toList() case final hits when hits.length >= perRow) (m, hits),
  ]..shuffle(rng);
  // Fresh names first; last visit's only when there aren't enough others.
  filled.sort((a, b) => (recent.contains(a.$1.name) ? 1 : 0).compareTo(recent.contains(b.$1.name) ? 1 : 0));
  final used = {...avoid};
  final out = <MoodRow>[];
  for (final (m, hits) in filled.take(count)) {
    final fresh = [
      for (final t in hits)
        if (!used.contains(t.item.ratingKey)) t,
    ];
    final items = _draw(fresh.length >= perRow ~/ 2 ? fresh : hits, perRow, rng, rewatch: m.rewatch);
    used.addAll(items.map((i) => i.ratingKey));
    out.add((name: m.name, items: items));
  }
  // Keep the moods page's order, so related rows don't land next to each other at random.
  final order = {for (final (i, m) in moods.indexed) m.name: i};
  return out..sort((a, b) => order[a.name]!.compareTo(order[b.name]!));
}

List<MoodTitle> _titles(List<PlexItem> pool, String kind, DateTime now) {
  final seen = <String>{};
  return [
    for (final i in pool)
      if ((kind == 'movie' || kind == 'show' ? i.type == kind : i.type == 'movie' || i.type == 'show') && seen.add(i.ratingKey)) MoodTitle(i, now),
  ];
}

List<PlexItem> _draw(List<MoodTitle> hits, int count, Random rng, {bool rewatch = false}) {
  double weight(MoodTitle t) {
    final seen = t.item.isWatched || (t.show && (t.item.viewedLeafCount ?? 0) >= (t.item.leafCount ?? 1));
    return (t.score + 1) * (seen == rewatch ? 1 : 0.35);
  }

  final keyed = [for (final t in hits) (t.item, pow(rng.nextDouble(), 1 / weight(t)).toDouble())]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (i, _) in keyed.take(count)) i];
}
