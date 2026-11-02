import 'format.dart';
import 'plex/plex_models.dart';
import 'seerr/seerr_models.dart';

/// What's already in the Plex libraries, for telling owned titles from missing ones.
/// Matches on TMDB id first, then on title and year for items Plex hasn't matched to TMDB.
class LibraryIndex {
  LibraryIndex(Iterable<PlexItem> items) {
    for (final i in items) {
      final kind = i.type == 'show' ? 'tv' : (i.type == 'movie' ? 'movie' : null);
      if (kind == null) continue;
      final tmdb = i.tmdbId;
      if (tmdb != null) _tmdb['$kind:$tmdb'] = i.ratingKey;
      _titles['$kind:${_norm(i.title)}:${i.year ?? ''}'] = i.ratingKey;
    }
  }

  final _tmdb = <String, String>{};
  final _titles = <String, String>{};

  bool get isEmpty => _tmdb.isEmpty && _titles.isEmpty;

  /// True when the title is in Plex, or Seerr says it is (fully or partly).
  bool owns(SeerrResult r) {
    final s = r.mediaInfo?.status;
    return s == MediaStatus.available || s == MediaStatus.partiallyAvailable || ratingKeyFor(r) != null;
  }

  /// The Plex item for a Seerr title, when Plex has it.
  String? ratingKeyFor(SeerrResult r) => _tmdb['${r.mediaType}:${r.id}'] ?? _titles['${r.mediaType}:${_norm(r.displayTitle)}:${yearOf(r.date)}'] ?? r.mediaInfo?.ratingKey;

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// The [count] best-rated titles that aren't in the library, movies and series together.
/// Scores are pulled toward the average when few people voted, so a 9.5 from 40 votes
/// doesn't beat a 8.7 from 20,000.
List<SeerrResult> topMissing(Iterable<SeerrResult> candidates, LibraryIndex library, {int count = 10}) {
  const prior = 7.0, weight = 1500;
  double score(SeerrResult r) {
    final v = (r.voteCount ?? weight).toDouble();
    return (v * (r.voteAverage ?? 0) + weight * prior) / (v + weight);
  }

  final seen = <String>{};
  final out = [
    for (final r in candidates)
      if ((r.mediaType == 'movie' || r.mediaType == 'tv') && (r.voteAverage ?? 0) > 0 && !library.owns(r) && seen.add('${r.mediaType}:${r.id}')) r,
  ]..sort((a, b) => score(b).compareTo(score(a)));
  return out.take(count).toList();
}

/// Genres for the Trending page, with TMDB's movie and series genre ids (TMDB groups some
/// series genres, e.g. "Sci-Fi & Fantasy").
const trendingGenres = <({String name, int? movie, int? tv})>[
  (name: 'Action & Adventure', movie: 28, tv: 10759),
  (name: 'Comedy', movie: 35, tv: 35),
  (name: 'Drama', movie: 18, tv: 18),
  (name: 'Sci-Fi & Fantasy', movie: 878, tv: 10765),
  (name: 'Crime', movie: 80, tv: 80),
  (name: 'Thriller', movie: 53, tv: null),
  (name: 'Mystery', movie: 9648, tv: 9648),
  (name: 'Horror', movie: 27, tv: null),
  (name: 'Animation', movie: 16, tv: 16),
  (name: 'Family', movie: 10751, tv: 10751),
  (name: 'Romance', movie: 10749, tv: null),
  (name: 'Documentary', movie: 99, tv: 99),
  (name: 'War & History', movie: 10752, tv: 10768),
];

/// Movies and series for one genre row, most popular first, without repeats.
List<SeerrResult> mergeByPopularity(Iterable<SeerrResult> a, Iterable<SeerrResult> b, {int count = 20}) {
  final seen = <String>{};
  final all = [
    for (final r in [...a, ...b])
      if (seen.add('${r.mediaType}:${r.id}')) r,
  ]..sort((x, y) => (y.popularity ?? 0).compareTo(x.popularity ?? 0));
  return all.take(count).toList();
}
