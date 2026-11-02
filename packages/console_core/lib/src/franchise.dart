import 'format.dart';
import 'library_index.dart';
import 'plex/plex_models.dart';
import 'seerr/seerr_models.dart';

/// One film of a series: TMDB's record, the Plex copy when you have it, or both.
class FranchisePart {
  FranchisePart({required this.title, this.tmdb, this.plex});
  final String title;
  final SeerrResult? tmdb;
  final PlexItem? plex;

  /// yyyy-mm-dd when known.
  String? get date => (tmdb?.releaseDate?.isNotEmpty ?? false) ? tmdb!.releaseDate : (plex?.originallyAvailableAt ?? (plex?.year == null ? null : '${plex!.year}'));
  int? get year => int.tryParse(yearOf(date));
  bool get owned => plex != null;
  bool get watched => plex?.isWatched ?? false;
  bool get started => (plex?.viewOffset ?? 0) > 0 && !watched;

  /// Out now (TMDB lists announced films too).
  bool get released {
    final d = date;
    if (d == null || d.isEmpty) return owned;
    final t = DateTime.tryParse(d.length == 4 ? '$d-01-01' : d);
    return owned || (t != null && t.isBefore(DateTime.now()));
  }

  /// Minutes.
  int? get runtime => plex?.duration != null ? (plex!.duration! / 60000).round() : tmdb?.runtime;

  /// 0..10
  double? get score => (tmdb?.voteAverage ?? 0) > 0 ? tmdb!.voteAverage : plex?.audienceRating;
}

/// A film series pulled together from TMDB's collection and what Plex has of it.
class Franchise {
  Franchise({required this.name, required this.parts, this.overview, this.tmdbId, this.plexKey, this.tmdb, this.plexCollection});

  /// Joins TMDB's list of films with the Plex collection's items (and anything else in the
  /// library, through [library] and [lookup]), in release order. Plex items TMDB doesn't
  /// list stay in, placed by their year.
  factory Franchise.from({SeerrCollection? tmdb, PlexItem? collection, List<PlexItem> items = const [], LibraryIndex? library, PlexItem? Function(String ratingKey)? lookup}) {
    final used = <String>{};
    final parts = <FranchisePart>[];
    for (final t in tmdb?.parts ?? const <SeerrResult>[]) {
      PlexItem? hit = items.where((i) => i.tmdbId == t.id).firstOrNull;
      if (hit == null && library != null && lookup != null) {
        final k = library.ratingKeyFor(t);
        if (k != null) hit = lookup(k);
      }
      if (hit != null) used.add(hit.ratingKey);
      parts.add(FranchisePart(title: t.displayTitle, tmdb: t, plex: hit));
    }
    for (final i in items) {
      if (used.add(i.ratingKey) && (i.type == 'movie' || i.type == 'show')) parts.add(FranchisePart(title: i.title, plex: i));
    }
    // Stable sort by date; undated films go last.
    final indexed = parts.indexed.toList()
      ..sort((a, b) {
        final da = a.$2.date ?? '9999', db = b.$2.date ?? '9999';
        final c = da.compareTo(db);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return Franchise(
      name: displayName(tmdb?.name ?? collection?.title ?? 'Collection'),
      overview: (tmdb?.overview?.isNotEmpty ?? false) ? tmdb!.overview : collection?.summary,
      tmdbId: tmdb?.id,
      plexKey: collection?.ratingKey,
      tmdb: tmdb,
      plexCollection: collection,
      parts: [for (final (_, p) in indexed) p],
    );
  }

  final String name;
  final String? overview;
  final int? tmdbId;
  final String? plexKey;
  final SeerrCollection? tmdb;
  final PlexItem? plexCollection;
  final List<FranchisePart> parts;

  /// "Star Wars Collection" → "Star Wars".
  static String displayName(String name) => name.replaceFirst(RegExp(r'\s+(Collection|Saga|Series|Trilogy Collection)$', caseSensitive: false), '').trim();

  String get key => tmdbId != null ? 'tmdb:$tmdbId' : 'plex:$plexKey';
  List<FranchisePart> get released => parts.where((p) => p.released).toList();

  /// Every film in the series, the announced ones too: "1 of 2" counts against this.
  int get total => parts.length;
  int get ownedCount => parts.where((p) => p.owned).length;
  int get watchedCount => parts.where((p) => p.watched).length;
  bool get complete => released.every((p) => p.owned);
  List<FranchisePart> get missing => released.where((p) => !p.owned && p.tmdb != null).toList();
  List<FranchisePart> get upcoming => parts.where((p) => !p.released).toList();

  /// Every released film back to back, in minutes.
  int get totalMinutes => released.fold(0, (a, p) => a + (p.runtime ?? 0));

  /// What's left of the films you have, in minutes.
  int get minutesLeft => released.where((p) => p.owned && !p.watched).fold(0, (a, p) => a + (p.runtime ?? 0));

  ({int from, int to})? get years {
    final ys = released.map((p) => p.year).whereType<int>().toList()..sort();
    return ys.isEmpty ? null : (from: ys.first, to: ys.last);
  }

  /// Where to pick the series up: a film you're partway through, else the first you
  /// haven't watched, in release order. Null when you've seen everything you have.
  FranchisePart? get upNext => parts.where((p) => p.started).firstOrNull ?? parts.where((p) => p.owned && !p.watched).firstOrNull;

  /// The owned films from [from] on, for a marathon.
  List<PlexItem> marathonFrom(FranchisePart? from) {
    final owned = parts.where((p) => p.owned).toList();
    final i = from == null ? 0 : owned.indexOf(from).clamp(0, owned.length);
    return [for (final p in owned.skip(i)) p.plex!];
  }

  double? get averageScore {
    final s = released.map((p) => p.score).whereType<double>().where((v) => v > 0).toList();
    return s.isEmpty ? null : s.reduce((a, b) => a + b) / s.length;
  }
}
