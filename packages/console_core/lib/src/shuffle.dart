import 'dart:math';

import 'plex/plex_models.dart';
import 'spotlight.dart';

/// What Shuffle Play may pick.
class ShuffleFilter {
  const ShuffleFilter({this.kind = 'any', this.maxMinutes, this.unwatched = true, this.genre});

  /// any, movie or show.
  final String kind;

  /// Longest runtime (an episode's, for shows); null for any length.
  final int? maxMinutes;

  /// Only titles you haven't finished.
  final bool unwatched;
  final String? genre;

  ShuffleFilter copyWith({String? kind, int? Function()? maxMinutes, bool? unwatched, String? Function()? genre}) =>
      ShuffleFilter(kind: kind ?? this.kind, maxMinutes: maxMinutes != null ? maxMinutes() : this.maxMinutes, unwatched: unwatched ?? this.unwatched, genre: genre != null ? genre() : this.genre);

  bool accepts(PlexItem i) {
    if (i.type != 'movie' && i.type != 'show') return false;
    if (kind != 'any' && i.type != kind) return false;
    if (genre != null && !i.genres.contains(genre)) return false;
    final mins = i.duration == null ? null : i.duration! / 60000;
    if (maxMinutes != null && (mins == null || mins > maxMinutes!)) return false;
    if (unwatched) {
      if (i.type == 'movie' && i.isWatched) return false;
      if (i.type == 'show' && (i.leafCount ?? 1) > 0 && (i.viewedLeafCount ?? 0) >= (i.leafCount ?? 1)) return false;
    }
    return true;
  }
}

/// Everything [filter] allows, without repeats.
List<PlexItem> shuffleCandidates(List<PlexItem> pool, ShuffleFilter filter) {
  final seen = <String>{};
  return [
    for (final i in pool)
      if (filter.accepts(i) && seen.add(i.ratingKey)) i,
  ];
}

/// A random pick that leans toward better-rated titles, steering clear of [avoid]
/// (what was just offered) while anything else is left.
PlexItem? pickShuffle(List<PlexItem> pool, ShuffleFilter filter, {Random? random, Set<String> avoid = const {}}) {
  final rng = random ?? Random();
  var list = shuffleCandidates(pool, filter);
  final fresh = list.where((i) => !avoid.contains(i.ratingKey)).toList();
  if (fresh.isNotEmpty) list = fresh;
  if (list.isEmpty) return null;
  final weights = [for (final i in list) pow(scoreOf(i) + 1, 1.5).toDouble()];
  var r = rng.nextDouble() * weights.fold(0.0, (a, b) => a + b);
  for (final (k, w) in weights.indexed) {
    r -= w;
    if (r <= 0) return list[k];
  }
  return list.last;
}
