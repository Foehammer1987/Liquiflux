import 'dart:math';

import 'plex/plex_models.dart';

/// The best score Plex gives an item, 0..10 (audience first, then critics).
double scoreOf(PlexItem i) => i.audienceRating ?? i.rating ?? 0;

/// Picks [count] well-rated titles with background art for the Home spotlight.
///
/// Titles rated [minScore] or better qualify (the best-rated half of the pool when too few
/// do). Unwatched ones are picked first, at random, weighted toward higher scores, and
/// movies and series alternate so one library doesn't take every slot.
List<PlexItem> pickSpotlights(List<PlexItem> pool, {int count = 6, double minScore = 7, Random? random, Set<String> avoid = const {}}) {
  final rng = random ?? Random();
  final seen = <String>{};
  final withArt = [
    for (final i in pool)
      if ((i.type == 'movie' || i.type == 'show') && (i.art ?? '').isNotEmpty && seen.add(i.ratingKey)) i,
  ];
  if (withArt.isEmpty) return const [];
  var good = withArt.where((i) => scoreOf(i) >= minScore).toList();
  if (good.length < count) {
    final sorted = [...withArt]..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    good = sorted.take(max(count, sorted.length ~/ 2)).toList();
  }

  // Weighted shuffle: key = u^(1/w), higher scores and unwatched titles float up.
  double weight(PlexItem i) => (scoreOf(i) + 1) * (i.isWatched ? 0.35 : 1);
  // [avoid] (the last set, on a re-roll) sorts after everything else, so it only comes back when needed.
  final keyed = [for (final i in good) (i, pow(rng.nextDouble(), 1 / weight(i)).toDouble() - (avoid.contains(i.ratingKey) ? 1 : 0))]..sort((a, b) => b.$2.compareTo(a.$2));
  final movies = [
    for (final (i, _) in keyed)
      if (i.type == 'movie') i,
  ];
  final shows = [
    for (final (i, _) in keyed)
      if (i.type == 'show') i,
  ];
  final out = <PlexItem>[];
  var takeMovie = rng.nextBool();
  while (out.length < count && (movies.isNotEmpty || shows.isNotEmpty)) {
    final from = (takeMovie && movies.isNotEmpty) || shows.isEmpty ? movies : shows;
    out.add(from.removeAt(0));
    takeMovie = !takeMovie;
  }
  return out;
}

/// Highest-rated titles, for a Top 10 row.
List<PlexItem> topRated(List<PlexItem> pool, {int count = 10}) {
  final seen = <String>{};
  final list = [
    for (final i in pool)
      if (scoreOf(i) > 0 && seen.add(i.ratingKey)) i,
  ]..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
  return list.take(count).toList();
}

/// A fresh "Top in Your Library" set: [count] titles drawn at random (weighted like the
/// spotlight) from the best-rated part of the pool, leaving out [avoid] (what the spotlight
/// shows), then ranked by score.
List<PlexItem> pickTop(List<PlexItem> pool, {int count = 10, Set<String> avoid = const {}, Random? random}) {
  final rng = random ?? Random();
  final ranked = topRated([
    for (final i in pool)
      if ((i.type == 'movie' || i.type == 'show') && !avoid.contains(i.ratingKey)) i,
  ], count: pool.length);
  final best = ranked.take(max(count * 3, ranked.length ~/ 3)).toList();
  double weight(PlexItem i) => (scoreOf(i) + 1) * (i.isWatched ? 0.35 : 1);
  final keyed = [for (final i in best) (i, pow(rng.nextDouble(), 1 / weight(i)).toDouble())]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (i, _) in keyed.take(count)) i]..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
}

/// The [count] most-watched titles in [views], for a "Top 10 on" plus the server name row (movies and
/// shows together, as their ratingKeys). A title scores one per account per day it was
/// watched, so a binge of six episodes counts once and two people watching counts twice.
/// Ties go to more plays, then the more recent one.
List<String> mostWatched(List<PlexView> views, {int count = 10}) {
  final days = <String, Set<String>>{};
  final plays = <String, int>{};
  final last = <String, int>{};
  for (final v in views) {
    final day = DateTime.fromMillisecondsSinceEpoch(v.viewedAt * 1000);
    (days[v.titleKey] ??= {}).add('${v.accountId}:${day.year}-${day.month}-${day.day}');
    plays[v.titleKey] = (plays[v.titleKey] ?? 0) + 1;
    last[v.titleKey] = max(last[v.titleKey] ?? 0, v.viewedAt);
  }
  int score(String k) => days[k]!.length;
  final keys = days.keys.toList()
    ..sort((a, b) {
      final s = score(b) - score(a);
      if (s != 0) return s;
      final p = plays[b]! - plays[a]!;
      return p != 0 ? p : last[b]! - last[a]!;
    });
  return keys.take(count).toList();
}
