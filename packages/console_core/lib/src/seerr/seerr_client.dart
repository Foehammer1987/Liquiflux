import '../discovery_sources.dart';
import '../format.dart';
import '../http_json.dart';
import 'seerr_models.dart';

/// Talks to Seerr (or Overseerr / Jellyseerr).
///
/// Authenticates with an API key, or, when [plexToken] is given instead, signs in as the
/// Plex user so requests are filed under their own account and follow their approval rules.
class SeerrClient {
  SeerrClient({required String baseUrl, this.apiKey, this.plexToken, JsonHttp? http}) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''), _http = http ?? JsonHttp();

  final String baseUrl;
  final String? apiKey;
  final String? plexToken;
  final JsonHttp _http;

  /// The Plex sign-in every request shares, so several requests that find the session
  /// expired at once sign in again only once.
  Future<String>? _signIn;

  static const _notSeerr = "That address answered with something that isn't Seerr. Check the URL in Settings.";

  /// [j] as a JSON object, or a plain-words error when the address isn't Seerr.
  static Map<String, dynamic> _obj(Object? j) => JsonHttp.object(j, _notSeerr);

  Uri _u(String path) => Uri.parse('$baseUrl/api/v1$path');

  bool get _usesKey => apiKey != null && apiKey!.isNotEmpty;

  /// The session cookie, signing in when there is none yet.
  Future<String> _session() {
    final running = _signIn;
    if (running != null) return running;
    final f = _signInWithPlex();
    _signIn = f;
    // A failed sign-in is tried afresh next time.
    f.then(
      (_) {},
      onError: (Object _) {
        if (identical(_signIn, f)) _signIn = null;
      },
    );
    return f;
  }

  Future<String> _signInWithPlex() async {
    if (plexToken == null || plexToken!.isEmpty) throw ApiException(401, 'Seerr needs an API key or a Plex sign-in');
    final res = await _http.sendRaw('POST', _u('/auth/plex'), body: {'authToken': plexToken});
    final setCookie = res.headers['set-cookie'] ?? '';
    final m = RegExp(r'connect\.sid=[^;]+').firstMatch(setCookie);
    if (m == null) throw ApiException(401, 'Seerr did not accept the Plex sign-in');
    return m.group(0)!;
  }

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    if (_usesKey) return _http.send(method, _u(path), headers: {'X-Api-Key': apiKey!}, body: body);
    final session = _session();
    final cookie = await session;
    try {
      return await _http.send(method, _u(path), headers: {'cookie': cookie}, body: body);
    } on ApiException catch (e) {
      if (e.status != 401 && e.status != 403) rethrow;
      // Session expired: sign in again once. Another request may already have started that.
      if (identical(_signIn, session)) _signIn = null;
      return _http.send(method, _u(path), headers: {'cookie': await _session()}, body: body);
    }
  }

  void close() => _http.close();

  /// Seerr rejects some characters that Uri.encodeComponent leaves alone.
  static String encodeQuery(String s) => Uri.encodeComponent(s).replaceAllMapped(RegExp(r"[!'()*]"), (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}');

  Future<({int id, String name})> me() async {
    final j = _obj(await _send('GET', '/auth/me'));
    return (id: _toInt(j['id']) ?? 0, name: '${j['displayName'] ?? j['email'] ?? 'user'}');
  }

  Future<String?> version() async {
    try {
      final j = _obj(await _http.send('GET', _u('/status')));
      return j['version'] is String ? j['version'] as String : null;
    } catch (_) {
      return null;
    }
  }

  /// Movies and series only.
  Future<List<SeerrResult>> search(String query, {int page = 1}) async {
    final j = _obj(await _send('GET', '/search?query=${encodeQuery(query)}&page=$page'));
    return _list(j['results']).whereType<Map<String, dynamic>>().map(SeerrResult.fromJson).where((r) => r.mediaType == 'movie' || r.mediaType == 'tv').toList();
  }

  Future<SeerrResult> details(String mediaType, int tmdbId) async => SeerrResult.fromJson({..._obj(await _send('GET', '/$mediaType/$tmdbId')), 'mediaType': mediaType});

  Future<List<SeerrRequest>> requests({int take = 40}) async {
    final j = _obj(await _send('GET', '/request?take=$take&skip=0&filter=all&sort=added'));
    return _list(j['results']).whereType<Map<String, dynamic>>().map(SeerrRequest.fromJson).toList();
  }

  /// Rotten Tomatoes and IMDb scores; null when Seerr has none (or is too old to ask).
  Future<SeerrRatings?> ratings(String mediaType, int tmdbId) async {
    for (final path in [if (mediaType == 'movie') '/movie/$tmdbId/ratingscombined', '/$mediaType/$tmdbId/ratings']) {
      try {
        final j = await _send('GET', path);
        if (j is Map<String, dynamic>) return SeerrRatings.fromJson(j);
      } on ApiException {
        continue;
      }
    }
    return null;
  }

  Future<List<SeerrResult>> recommendations(String mediaType, int tmdbId) async {
    try {
      final j = _obj(await _send('GET', '/$mediaType/$tmdbId/recommendations?page=1'));
      return _list(j['results']).whereType<Map<String, dynamic>>().map((r) => SeerrResult.fromJson({'mediaType': mediaType, ...r})).toList();
    } on ApiException {
      return const [];
    }
  }

  /// A TMDB film series and its films; null when TMDB has no such collection.
  Future<SeerrCollection?> collection(int id) async {
    try {
      return SeerrCollection.fromJson(_obj(await _send('GET', '/collection/$id')));
    } on ApiException {
      return null;
    }
  }

  /// What's trending on TMDB this week, movies and series.
  Future<List<SeerrResult>> trending() async {
    try {
      final j = _obj(await _send('GET', '/discover/trending?page=1'));
      return _list(j['results']).whereType<Map<String, dynamic>>().map(SeerrResult.fromJson).where((r) => r.mediaType == 'movie' || r.mediaType == 'tv').toList();
    } on ApiException {
      return const [];
    }
  }

  /// TMDB's best-rated titles of one type ('movie' or 'tv'), with enough votes to mean it.
  Future<List<SeerrResult>> topRated(String mediaType, {int pages = 2, int minVotes = 1500}) async {
    final path = mediaType == 'tv' ? '/discover/tv' : '/discover/movies';
    final out = <SeerrResult>[];
    for (var page = 1; page <= pages; page++) {
      try {
        final j = _obj(await _send('GET', '$path?page=$page&sortBy=vote_average.desc&voteCountGte=$minVotes'));
        out.addAll(_list(j['results']).whereType<Map<String, dynamic>>().map((r) => SeerrResult.fromJson({'mediaType': mediaType, ...r})));
        if (page >= (_toInt(j['totalPages']) ?? page)) break;
      } on ApiException {
        break;
      }
    }
    return out;
  }

  /// What's popular right now on TMDB in one genre ('movie' or 'tv'). TMDB's popularity
  /// score is recomputed daily from views, votes and watchlists.
  Future<List<SeerrResult>> popularInGenre(String mediaType, int genreId, {int page = 1}) async {
    final path = mediaType == 'tv' ? '/discover/tv' : '/discover/movies';
    try {
      final j = _obj(await _send('GET', '$path?page=$page&genre=$genreId&sortBy=popularity.desc'));
      return _list(j['results']).whereType<Map<String, dynamic>>().map((r) => SeerrResult.fromJson({'mediaType': mediaType, ...r})).toList();
    } on ApiException {
      return const [];
    }
  }

  /// What's popular on one streaming service in [region] (TMDB watch-provider data from JustWatch).
  Future<List<SeerrResult>> popularOn(String mediaType, int provider, {String region = 'US'}) async {
    final path = mediaType == 'tv' ? '/discover/tv' : '/discover/movies';
    try {
      final j = _obj(await _send('GET', '$path?page=1&watchProviders=$provider&watchRegion=$region&sortBy=popularity.desc'));
      return _list(j['results']).whereType<Map<String, dynamic>>().map((r) => SeerrResult.fromJson({'mediaType': mediaType, ...r})).toList();
    } on ApiException {
      return const [];
    }
  }

  /// Turns an outside chart entry into a Seerr title: by TMDB id when the chart has one,
  /// otherwise the best title (and year) match from search.
  Future<SeerrResult?> resolve(ChartTitle t) async {
    try {
      if (t.tmdbId != null) return await details(t.mediaType, t.tmdbId!);
      final hits = (await search(t.title)).where((r) => r.mediaType == t.mediaType).toList();
      String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return hits.where((r) => norm(r.displayTitle) == norm(t.title) && (t.year == null || yearOf(r.date) == '${t.year}')).firstOrNull ??
          hits.where((r) => norm(r.displayTitle) == norm(t.title)).firstOrNull ??
          hits.firstOrNull;
    } on ApiException {
      return null;
    }
  }

  /// People matching [query] (Seerr's search mixes them in with titles).
  Future<List<SeerrPerson>> searchPeople(String query) async {
    final j = _obj(await _send('GET', '/search?query=${encodeQuery(query)}&page=1'));
    return _list(j['results']).whereType<Map<String, dynamic>>().where((r) => r['mediaType'] == 'person').map(SeerrPerson.fromJson).toList();
  }

  Future<SeerrPerson> person(int id) async => SeerrPerson.fromJson(_obj(await _send('GET', '/person/$id')));

  /// Movies and series a person acted in, most popular first.
  Future<List<SeerrResult>> personCredits(int id) async {
    final j = _obj(await _send('GET', '/person/$id/combined_credits'));
    final seen = <String>{};
    final out = [
      for (final c in _list(j['cast']).whereType<Map<String, dynamic>>())
        if (c['mediaType'] == 'movie' || c['mediaType'] == 'tv')
          if (seen.add('${c['mediaType']}:${c['id']}')) SeerrResult.fromJson(c),
    ];
    out.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
    return out;
  }

  /// Requests a movie, or a series' [seasons] (every season when null).
  Future<SeerrRequest> request(String mediaType, int tmdbId, {List<int>? seasons}) async {
    final body = <String, Object>{'mediaType': mediaType, 'mediaId': tmdbId};
    if (mediaType == 'tv') {
      if (seasons != null) {
        body['seasons'] = seasons;
      } else {
        final d = await details('tv', tmdbId);
        final status = d.mediaInfo?.seasonStatus ?? const {};
        // Skip seasons that are already in Plex or on their way.
        body['seasons'] = d.seasons.where((n) => n > 0 && (status[n] ?? MediaStatus.unknown) == MediaStatus.unknown).toList();
        if (body['seasons'] is! List || (body['seasons'] as List).isEmpty) body['seasons'] = d.seasons.where((n) => n > 0).toList();
      }
    }
    return SeerrRequest.fromJson(_obj(await _send('POST', '/request', body: body)));
  }

  Future<void> cancel(int requestId) async => _send('DELETE', '/request/$requestId');
}

/// Server JSON is untrusted: a field of the wrong type reads as missing.
List<Object?> _list(Object? v) => v is List ? v : const [];
int? _toInt(Object? v) => v is num && v.isFinite ? v.toInt() : null;
