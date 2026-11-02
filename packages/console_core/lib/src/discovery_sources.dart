import 'package:http/http.dart' as http;

import 'http_json.dart';

/// A title from an outside chart (Trakt, Netflix), to be matched up through Seerr.
class ChartTitle {
  const ChartTitle({required this.mediaType, required this.title, this.year, this.tmdbId, this.rank, this.score});
  final String mediaType; // movie or tv
  final String title;
  final int? year;
  final int? tmdbId;
  final int? rank;

  /// Watchers right now (Trakt) or weekly views (Netflix).
  final num? score;
}

/// Trakt's public trending charts. Needs only an app client ID (no sign-in); see
/// https://trakt.tv/oauth/applications to make one.
class TraktClient {
  TraktClient({required this.clientId, String baseUrl = 'https://api.trakt.tv', JsonHttp? http}) : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''), _http = http ?? JsonHttp();
  final String clientId;
  final String _base;
  final JsonHttp _http;

  /// Trakt genre slugs for each Trending row (comma means either).
  static const genreSlugs = {
    'Action & Adventure': 'action,adventure',
    'Comedy': 'comedy',
    'Drama': 'drama',
    'Sci-Fi & Fantasy': 'science-fiction,fantasy',
    'Crime': 'crime',
    'Thriller': 'thriller',
    'Mystery': 'mystery',
    'Horror': 'horror',
    'Animation': 'animation,anime',
    'Family': 'family',
    'Romance': 'romance',
    'Documentary': 'documentary',
    'War & History': 'war,history',
  };

  /// What people are watching right now; [mediaType] is 'movie' or 'tv'.
  Future<List<ChartTitle>> trending(String mediaType, {String? genres, int limit = 20}) async {
    final kind = mediaType == 'tv' ? 'shows' : 'movies';
    final key = mediaType == 'tv' ? 'show' : 'movie';
    final uri = Uri.parse('$_base/$kind/trending').replace(queryParameters: {'limit': '$limit', 'genres': ?genres});
    final body = await _http.send('GET', uri, headers: {'trakt-api-key': clientId, 'trakt-api-version': '2'});
    return [
      for (final (i, row) in (body is List ? body : const []).whereType<Map<String, dynamic>>().indexed)
        if (row[key] case final Map<String, dynamic> t)
          ChartTitle(
            mediaType: mediaType,
            title: '${t['title'] ?? ''}',
            year: _int(t['year']),
            tmdbId: _int(t['ids'] is Map ? (t['ids'] as Map)['tmdb'] : null),
            rank: i + 1,
            score: _int(row['watchers']),
          ),
    ];
  }

  void close() => _http.close();
}

int? _int(Object? v) => v is int ? v : (v is num && v.isFinite ? v.toInt() : null);

/// Netflix's own weekly Top 10 (https://www.netflix.com/tudum/top10). Titles only, no ids.
abstract final class NetflixTop10 {
  static const url = 'https://www.netflix.com/tudum/top10/data/all-weeks-global.tsv';

  /// How long a download is reused; Netflix updates the chart once a week.
  static const keepFor = Duration(hours: 3);
  static ({String from, DateTime at, Future<String> tsv})? _fetched;
  static (String, Map<String, List<ChartTitle>>)? _parsed;

  /// The chart's TSV, downloaded at most once every [keepFor] (a failed download is tried
  /// again next time). A [client] of your own always downloads afresh.
  static Future<String> fetch({String? from, http.Client? client}) {
    final source = from ?? url;
    if (client != null) return _download(source, client);
    final hit = _fetched;
    if (hit != null && hit.from == source && DateTime.now().difference(hit.at) < keepFor) return hit.tsv;
    final tsv = _download(source, null);
    final entry = (from: source, at: DateTime.now(), tsv: tsv);
    _fetched = entry;
    tsv.then(
      (_) {},
      onError: (Object _) {
        if (identical(_fetched, entry)) _fetched = null;
      },
    );
    return tsv;
  }

  static Future<String> _download(String from, http.Client? client) async {
    final c = client ?? http.Client();
    try {
      final r = await c.get(Uri.parse(from)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw ApiException(r.statusCode, 'Netflix Top 10 returned ${r.statusCode}');
      return r.body;
    } finally {
      if (client == null) c.close();
    }
  }

  /// The latest week's English-language films or series ([mediaType] 'movie' or 'tv'), in
  /// rank order. Both kinds come from one read of [tsv], kept for the next call.
  static List<ChartTitle> parse(String tsv, String mediaType) {
    final last = _parsed;
    final all = last != null && identical(last.$1, tsv) ? last.$2 : _parseAll(tsv);
    _parsed = (tsv, all);
    return all[mediaType == 'tv' ? 'tv' : 'movie'] ?? const [];
  }

  static Map<String, List<ChartTitle>> _parseAll(String tsv) {
    final lines = tsv.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return const {};
    final cols = lines.first.split('\t').map((c) => c.trim()).toList();
    int col(String name) => cols.indexOf(name);
    final week = col('week'), cat = col('category'), rank = col('weekly_rank'), title = col('show_title'), views = col('weekly_views');
    if ([week, cat, rank, title].contains(-1)) return const {};
    final widest = [week, cat, rank, title].reduce((a, b) => a > b ? a : b);
    const kinds = {'Films (English)': 'movie', 'TV (English)': 'tv'};
    final rows = <String, List<List<String>>>{};
    final latest = <String, String>{};
    for (final l in lines.skip(1)) {
      final r = l.split('\t');
      if (r.length <= widest) continue;
      final kind = kinds[r[cat].trim()];
      if (kind == null) continue;
      rows.putIfAbsent(kind, () => []).add(r);
      final w = r[week].trim();
      if ((latest[kind] ?? '').compareTo(w) < 0) latest[kind] = w;
    }
    return {
      for (final e in rows.entries)
        e.key: List<ChartTitle>.unmodifiable(
          [
            for (final r in e.value)
              if (r[week].trim() == latest[e.key])
                ChartTitle(mediaType: e.key, title: r[title].trim(), rank: int.tryParse(r[rank].trim()), score: views >= 0 && views < r.length ? num.tryParse(r[views].trim()) : null),
          ]..sort((a, b) => (a.rank ?? 99).compareTo(b.rank ?? 99)),
        ),
    };
  }
}

/// Streaming services for "Popular on …" rows, with their TMDB watch-provider ids.
const streamingServices = <({String name, int provider})>[
  (name: 'Netflix', provider: 8),
  (name: 'Prime Video', provider: 9),
  (name: 'Max', provider: 1899),
  (name: 'Disney+', provider: 337),
  (name: 'Apple TV+', provider: 350),
  (name: 'Hulu', provider: 15),
];
