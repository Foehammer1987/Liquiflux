import '../plex/plex_models.dart';

/// The outside ids Plex keeps for a title: imdb://, tmdb:// and tvdb:// from the new
/// agents, or the old agents' com.plexapp.agents.imdb://tt… style guid.
class ExternalIds {
  const ExternalIds({this.imdb, this.tmdb, this.tvdb});
  final String? imdb;
  final int? tmdb;
  final int? tvdb;

  bool get isEmpty => imdb == null && tmdb == null && tvdb == null;

  /// Trakt's `ids` object.
  Map<String, Object> toTrakt() => {'imdb': ?imdb, 'tmdb': ?tmdb, 'tvdb': ?tvdb};

  factory ExternalIds.of(PlexItem? item) {
    if (item == null) return const ExternalIds();
    String? imdb;
    int? tmdb, tvdb;
    int? number(String s) {
      final n = int.tryParse(s);
      return n != null && n > 0 ? n : null;
    }

    for (final g in [...item.guids, ?item.plexGuid]) {
      final m = RegExp(r'^(?:com\.plexapp\.agents\.)?(imdb|tmdb|themoviedb|tvdb|thetvdb)://([^/?#]+)').firstMatch(g);
      if (m == null) continue;
      final v = m[2]!;
      switch (m[1]) {
        case 'imdb':
          if (isImdbId(v)) imdb ??= v;
        case 'tmdb' || 'themoviedb':
          tmdb ??= number(v);
        case 'tvdb' || 'thetvdb':
          tvdb ??= number(v);
      }
    }
    return ExternalIds(imdb: imdb, tmdb: tmdb, tvdb: tvdb);
  }

  @override
  String toString() => [if (imdb != null) 'imdb $imdb', if (tmdb != null) 'tmdb $tmdb', if (tvdb != null) 'tvdb $tvdb'].join(', ');
}
