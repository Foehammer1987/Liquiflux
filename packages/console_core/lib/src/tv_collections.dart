import 'dart:convert';
import 'dart:math';

import 'plex/plex_models.dart';

/// One show in the TV collection pack (app/assets/collections/tv-pack.json): who it is
/// on TMDB, TVDB and IMDb, and TVmaze's rating and popularity for ranking missing shows.
class PackShow {
  const PackShow({required this.title, this.year, this.tmdb, this.tvdb, this.imdb, this.rating, this.weight, this.poster});
  final String title;
  final int? year;
  final int? tmdb;
  final int? tvdb;
  final String? imdb;

  /// TVmaze's average, 0..10.
  final double? rating;

  /// TVmaze's popularity, 0..100.
  final int? weight;

  /// Full poster URL (TVmaze), when known.
  final String? poster;

  /// Ranking score: the rating pulled toward an average when few people follow the show,
  /// so an obscure 9.4 doesn't beat a famous 8.6. Shows without a rating sit below average.
  double get score {
    const prior = 6.5, k = 25.0;
    final w = (weight ?? 0).toDouble();
    final r = rating ?? 6.0;
    return (w * r + k * prior) / (w + k) + w / 1000;
  }

  /// The id key used to tell two pack shows apart.
  String get key => tmdb != null ? 'tm$tmdb' : (tvdb != null ? 'tv$tvdb' : (imdb ?? 't:$title:$year'));
}

/// A programming block (Toonami, Nick at Nite) or a network (Adult Swim, HBO): a list of shows.
class PackCollection {
  const PackCollection({required this.id, required this.kind, required this.name, required this.shows, this.years, this.about, this.source});
  final String id;

  /// block or network.
  final String kind;
  final String name;
  final String? years;
  final String? about;
  final String? source;
  final List<PackShow> shows;

  bool get isBlock => kind == 'block';
}

/// Every collection in the pack, shared by every Liquiflux install: each one matches it
/// against its own library.
class CollectionPack {
  const CollectionPack({required this.built, required this.collections, this.credits});
  final DateTime built;
  final List<PackCollection> collections;
  final String? credits;

  static const _maxShows = 60000, _maxCollections = 500;

  /// Throws [FormatException] for anything that isn't a pack (it may come off the internet).
  factory CollectionPack.parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != 1) throw const FormatException('not a collection pack');
    final built = j['built'] is String ? DateTime.tryParse(j['built'] as String) : null;
    final rawShows = j['shows'], rawCols = j['collections'];
    if (built == null || rawShows is! List || rawCols is! List || rawShows.length > _maxShows || rawCols.length > _maxCollections) {
      throw const FormatException('not a collection pack');
    }
    final base = j['posterBase'] is String && _safeBase(j['posterBase'] as String) ? j['posterBase'] as String : null;
    final shows = <PackShow?>[
      for (final s in rawShows)
        if (s is Map && s['t'] is String)
          PackShow(
            title: _clip(s['t'] as String, 200),
            year: _int(s['y'], 1900, 2100),
            tmdb: _int(s['tm'], 1, 1 << 31),
            tvdb: _int(s['tv'], 1, 1 << 31),
            imdb: s['im'] is String && RegExp(r'^tt\d{5,10}$').hasMatch(s['im'] as String) ? s['im'] as String : null,
            rating: s['r'] is num && (s['r'] as num).isFinite ? (s['r'] as num).toDouble().clamp(0, 10).toDouble() : null,
            weight: _int(s['w'], 0, 100),
            poster: base != null && s['p'] is String && RegExp(r'^[\w./-]{1,120}$').hasMatch(s['p'] as String) && !(s['p'] as String).contains('..') ? '$base${s['p']}' : null,
          )
        else
          null,
    ];
    final cols = <PackCollection>[];
    for (final c in rawCols) {
      if (c is! Map || c['id'] is! String || c['name'] is! String || c['shows'] is! List) continue;
      final kind = c['kind'] == 'network' ? 'network' : 'block';
      final members = <PackShow>[];
      final seen = <int>{};
      for (final i in c['shows'] as List) {
        if (i is int && i >= 0 && i < shows.length && shows[i] != null && seen.add(i)) members.add(shows[i]!);
      }
      if (members.isEmpty) continue;
      cols.add(
        PackCollection(
          id: _clip(c['id'] as String, 64),
          kind: kind,
          name: _clip(c['name'] as String, 80),
          years: c['years'] is String ? _clip(c['years'] as String, 40) : null,
          about: c['about'] is String ? _clip(c['about'] as String, 400) : null,
          source: c['source'] is String && (c['source'] as String).startsWith('https://') ? _clip(c['source'] as String, 300) : null,
          shows: members,
        ),
      );
    }
    return CollectionPack(built: built, collections: cols, credits: j['credits'] is String ? _clip(j['credits'] as String, 300) : null);
  }

  PackCollection? byId(String id) => collections.where((c) => c.id == id).firstOrNull;

  static bool _safeBase(String s) => s.startsWith('https://static.tvmaze.com/') || s.startsWith('https://image.tmdb.org/');
  static int? _int(Object? v, int min, int max) => v is int && v >= min && v <= max ? v : null;
  static String _clip(String s, int n) => s.length <= n ? s : s.substring(0, n);
}

/// The library's shows by every id Plex knows them by, including the old agents'
/// (thetvdb, themoviedb, hama "tvdb-") and, last, by title and year.
class ShowMatcher {
  ShowMatcher(Iterable<PlexItem> items) {
    for (final i in items) {
      if (i.type != 'show') continue;
      final ids = showIds(i);
      if (ids.tmdb != null) _tmdb.putIfAbsent(ids.tmdb!, () => i);
      if (ids.tvdb != null) _tvdb.putIfAbsent(ids.tvdb!, () => i);
      if (ids.imdb != null) _imdb.putIfAbsent(ids.imdb!, () => i);
      _titles.putIfAbsent(_norm(i.title), () => []).add(i);
    }
  }

  final _tmdb = <int, PlexItem>{};
  final _tvdb = <int, PlexItem>{};
  final _imdb = <String, PlexItem>{};
  final _titles = <String, List<PlexItem>>{};

  /// TMDB / TVDB / IMDb ids of a Plex show, from its guids or its agent guid.
  static ({int? tmdb, int? tvdb, String? imdb}) showIds(PlexItem i) {
    int? tmdb = i.tmdbId, tvdb;
    var imdb = i.imdbId;
    for (final g in i.guids) {
      if (g.startsWith('tvdb://')) tvdb ??= int.tryParse(g.substring(7));
    }
    final agent = i.plexGuid ?? '';
    final m = RegExp(r'^com\.plexapp\.agents\.(\w+)://([\w-]+)').firstMatch(agent);
    if (m != null) {
      final (who, id) = (m.group(1)!, m.group(2)!);
      if (who == 'thetvdb') tvdb ??= int.tryParse(id);
      if (who == 'themoviedb') tmdb ??= int.tryParse(id);
      if (who == 'imdb' && RegExp(r'^tt\d+$').hasMatch(id)) imdb ??= id;
      if (who == 'hama' && id.startsWith('tvdb')) tvdb ??= int.tryParse(id.replaceFirst(RegExp(r'^tvdb\d?-'), ''));
    }
    return (tmdb: tmdb, tvdb: tvdb, imdb: imdb);
  }

  /// The library's copy of [s], if any.
  PlexItem? find(PackShow s) {
    final hit = (s.tvdb == null ? null : _tvdb[s.tvdb]) ?? (s.tmdb == null ? null : _tmdb[s.tmdb]) ?? (s.imdb == null ? null : _imdb[s.imdb]);
    if (hit != null) return hit;
    final named = _titles[_norm(s.title)];
    if (named == null) return null;
    if (s.year == null) return named.length == 1 ? named.first : null;
    return named.where((i) => i.year != null && (i.year! - s.year!).abs() <= 1).firstOrNull;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// A collection as one user sees it: every show of it they own, and, while they own
/// fewer than [TvShelf.target], the best-rated ones they're missing to fill it up to that.
class TvShelf {
  TvShelf({required this.collection, required this.owned, required this.missing, required this.allMissing});
  final PackCollection collection;

  /// Owned shows, best-rated first.
  final List<PlexItem> owned;

  /// The missing shows shown beside them (none once [owned] reaches [target]).
  final List<PackShow> missing;

  /// Every show of the collection that isn't in the library, best-rated first.
  final List<PackShow> allMissing;

  static const target = 10;

  int get total => collection.shows.length;

  /// Foehammer's rule: everything owned always shows; fewer than [target] owned → add the
  /// best-rated missing shows until there are [target]; [target] or more → only what's owned.
  factory TvShelf.build(PackCollection c, ShowMatcher library, {int target = TvShelf.target}) {
    final owned = <String, (PlexItem, double)>{};
    final missing = <PackShow>[];
    final seen = <String>{};
    for (final s in c.shows) {
      if (!seen.add(s.key)) continue;
      final hit = library.find(s);
      if (hit != null) {
        final had = owned[hit.ratingKey];
        owned[hit.ratingKey] = (hit, max(had?.$2 ?? double.negativeInfinity, s.score));
      } else {
        missing.add(s);
      }
    }
    final mine = owned.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    missing.sort((a, b) => b.score.compareTo(a.score));
    final room = max(0, target - mine.length);
    return TvShelf(collection: c, owned: [for (final m in mine) m.$1], missing: missing.take(room).toList(), allMissing: missing);
  }
}

/// Shelves for every collection in [pack]: those you own shows from first (most first),
/// blocks before networks within a tie, then the rest in pack order.
List<TvShelf> tvShelves(CollectionPack pack, ShowMatcher library, {String? kind}) {
  final shelves = [
    for (final c in pack.collections)
      if (kind == null || c.kind == kind) TvShelf.build(c, library),
  ];
  final order = {for (final (i, s) in shelves.indexed) s.collection.id: i};
  return shelves..sort((a, b) {
    final o = b.owned.length.compareTo(a.owned.length);
    return o != 0 ? o : order[a.collection.id]!.compareTo(order[b.collection.id]!);
  });
}
