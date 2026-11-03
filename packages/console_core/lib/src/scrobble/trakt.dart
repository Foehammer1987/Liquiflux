import 'dart:async';

import '../http_json.dart';
import '../plex/plex_models.dart';
import 'external_ids.dart';

/// A Trakt app: its Client ID and Client Secret. Trakt's device sign-in and token refresh
/// both need the secret, so an open-source app can't ship one that stays secret: it comes
/// from the user's own Trakt app, or is put into release builds from CI secrets.
class TraktApp {
  const TraktApp({required this.clientId, required this.clientSecret});
  final String clientId;
  final String clientSecret;
  bool get ready => clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;
}

/// The tokens a Trakt sign-in gives. [expiresAt] is when the access token stops working;
/// the refresh token gets a new pair before then.
class TraktTokens {
  const TraktTokens({required this.access, required this.refresh, required this.expiresAt});
  final String access;
  final String refresh;
  final DateTime expiresAt;

  /// Due for a refresh: past, or less than a day left.
  bool get stale => DateTime.now().isAfter(expiresAt.subtract(const Duration(days: 1)));

  Map<String, Object> toJson() => {'access': access, 'refresh': refresh, 'expiresAt': expiresAt.toUtc().toIso8601String()};

  static TraktTokens? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = j['access'], r = j['refresh'], e = DateTime.tryParse('${j['expiresAt']}');
    if (a is! String || a.isEmpty || r is! String || r.isEmpty || e == null) return null;
    return TraktTokens(access: a, refresh: r, expiresAt: e);
  }

  /// From Trakt's token answer (access_token, refresh_token, created_at, expires_in).
  static TraktTokens? fromTrakt(Object? j) {
    if (j is! Map) return null;
    final a = j['access_token'], r = j['refresh_token'], left = j['expires_in'], at = j['created_at'];
    if (a is! String || a.isEmpty || r is! String || r.isEmpty) return null;
    final from = at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000) : DateTime.now();
    // Without a lifetime, assume Trakt's shortest (a day) so it refreshes early.
    return TraktTokens(access: a, refresh: r, expiresAt: from.add(Duration(seconds: left is num && left > 0 ? left.toInt() : 86400)));
  }
}

/// The code a TV shows: typed at [url] (trakt.tv/activate) on a phone or computer.
class TraktDeviceCode {
  const TraktDeviceCode({required this.deviceCode, required this.userCode, required this.url, required this.expiresAt, required this.interval});
  final String deviceCode;
  final String userCode;
  final String url;
  final DateTime expiresAt;
  final Duration interval;

  /// The activate page with the code filled in, for a QR code.
  String get directUrl => '${url.replaceAll(RegExp(r'/+$'), '')}/$userCode';
}

/// Why a device sign-in ended without tokens.
enum TraktSignInEnd { expired, denied, used, cancelled }

class TraktSignInException implements Exception {
  TraktSignInException(this.end);
  final TraktSignInEnd end;
  @override
  String toString() => switch (end) {
    TraktSignInEnd.expired => 'The code expired. Get a new one to try again.',
    TraktSignInEnd.denied => 'Trakt says the sign-in was turned down.',
    TraktSignInEnd.used => 'That code was already used. Get a new one.',
    TraktSignInEnd.cancelled => 'Cancelled',
  };
}

/// What a scrobble is about: a movie, or an episode of a show.
class TraktTarget {
  const TraktTarget.movie(this.ids) : show = null, season = null, number = null, episodeIds = null;
  const TraktTarget.episode({required ExternalIds this.show, required int this.season, required int this.number, this.episodeIds}) : ids = null;
  final ExternalIds? ids;
  final ExternalIds? show;
  final int? season;
  final int? number;
  final ExternalIds? episodeIds;
  bool get isMovie => ids != null;

  /// The movie, or the episode: by its show and number when the show's ids are known
  /// (anime numbering in an episode's own ids is often off), else by the episode's ids.
  /// Null with nothing Trakt can match on.
  static TraktTarget? of(PlexItem item, {PlexItem? show}) {
    if (item.type == 'movie') {
      final ids = ExternalIds.of(item);
      return ids.isEmpty ? null : TraktTarget.movie(ids);
    }
    if (item.type != 'episode') return null;
    final s = item.parentIndex, n = item.index;
    final showIds = ExternalIds.of(show);
    final own = ExternalIds.of(item);
    if (s == null || n == null || (showIds.isEmpty && own.isEmpty)) return null;
    return TraktTarget.episode(show: showIds, season: s, number: n, episodeIds: own.isEmpty ? null : own);
  }

  /// The body of a scrobble call.
  Map<String, Object> scrobbleBody() {
    if (isMovie) return {'movie': {'ids': ids!.toTrakt()}};
    if (!show!.isEmpty) {
      return {
        'show': {'ids': show!.toTrakt()},
        'episode': {'season': season!, 'number': number!},
      };
    }
    return {'episode': {'ids': episodeIds!.toTrakt()}};
  }

  /// The body of a /sync/history call.
  Map<String, Object> historyBody(DateTime watchedAt) {
    final at = watchedAt.toUtc().toIso8601String();
    if (isMovie) {
      return {
        'movies': [
          {'ids': ids!.toTrakt(), 'watched_at': at},
        ],
      };
    }
    if (!show!.isEmpty) {
      return {
        'shows': [
          {
            'ids': show!.toTrakt(),
            'seasons': [
              {
                'number': season!,
                'episodes': [
                  {'number': number!, 'watched_at': at},
                ],
              },
            ],
          },
        ],
      };
    }
    return {
      'episodes': [
        {'ids': episodeIds!.toTrakt(), 'watched_at': at},
      ],
    };
  }

  @override
  String toString() => isMovie ? 'movie ($ids)' : 'S$season E$number of ${show!.isEmpty ? 'episode ($episodeIds)' : 'show ($show)'}';
}

/// Trakt sign-in (the device code flow, made for TVs) and scrobbling.
class TraktAccount {
  TraktAccount({required this.app, this.tokens, this.onTokens, this.userAgent = 'Liquiflux', String baseUrl = 'https://api.trakt.tv', JsonHttp? http})
    : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _http = http ?? JsonHttp();

  final TraktApp app;
  final String userAgent;
  final String _base;
  final JsonHttp _http;

  /// Null until signed in.
  TraktTokens? tokens;

  /// Called with fresh tokens after a sign-in or refresh, to be kept.
  final void Function(TraktTokens)? onTokens;

  void close() => _http.close();

  Map<String, String> get _headers => {'trakt-api-version': '2', 'trakt-api-key': app.clientId, 'user-agent': userAgent};

  static const _odd = 'Trakt answered with something unexpected. Try again in a moment.';

  /// A new code for the TV to show.
  Future<TraktDeviceCode> deviceCode() async {
    final j = JsonHttp.object(await _http.send('POST', Uri.parse('$_base/oauth/device/code'), headers: _headers, body: {'client_id': app.clientId}), _odd);
    final device = j['device_code'], user = j['user_code'], url = j['verification_url'], left = j['expires_in'], every = j['interval'];
    if (device is! String || device.isEmpty || user is! String || user.isEmpty) throw ApiException(0, _odd);
    return TraktDeviceCode(
      deviceCode: device,
      userCode: user,
      url: url is String && url.startsWith('https://') ? url : 'https://trakt.tv/activate',
      expiresAt: DateTime.now().add(Duration(seconds: left is num && left > 0 ? left.toInt() : 600)),
      interval: Duration(seconds: every is num && every >= 1 ? every.toInt() : 5),
    );
  }

  /// Asks Trakt every [TraktDeviceCode.interval] until the code is entered and approved.
  /// Throws [TraktSignInException] when it expires, is turned down or [cancelled] says so.
  Future<TraktTokens> waitForApproval(TraktDeviceCode code, {bool Function()? cancelled, Duration? every}) async {
    var wait = every ?? code.interval;
    while (true) {
      if (cancelled?.call() ?? false) throw TraktSignInException(TraktSignInEnd.cancelled);
      if (DateTime.now().isAfter(code.expiresAt)) throw TraktSignInException(TraktSignInEnd.expired);
      try {
        final body = await _http.send('POST', Uri.parse('$_base/oauth/device/token'), headers: _headers, body: {'code': code.deviceCode, 'client_id': app.clientId, 'client_secret': app.clientSecret});
        final t = TraktTokens.fromTrakt(body);
        if (t != null) {
          _keep(t);
          return t;
        }
      } on ApiException catch (e) {
        switch (e.status) {
          case 0 || 400: // not entered yet, or the network blinked
            break;
          case 429:
            wait += const Duration(seconds: 1);
          case 404 || 410:
            throw TraktSignInException(TraktSignInEnd.expired);
          case 409:
            throw TraktSignInException(TraktSignInEnd.used);
          case 418:
            throw TraktSignInException(TraktSignInEnd.denied);
          case 401 || 403:
            throw ApiException(e.status, "Trakt didn't accept the app's Client ID and Secret. Check them in Settings.");
          default:
            rethrow;
        }
      }
      if (cancelled?.call() ?? false) throw TraktSignInException(TraktSignInEnd.cancelled);
      await Future<void>.delayed(wait);
    }
  }

  void _keep(TraktTokens t) {
    tokens = t;
    onTokens?.call(t);
  }

  Future<TraktTokens>? _refreshing;

  /// New tokens from the refresh token (Trakt hands out a new refresh token each time).
  Future<TraktTokens> refresh() => _refreshing ??= () async {
    try {
      final t = tokens;
      if (t == null) throw ApiException(401, 'Not signed in to Trakt');
      final body = await _http.send(
        'POST',
        Uri.parse('$_base/oauth/token'),
        headers: _headers,
        body: {'refresh_token': t.refresh, 'client_id': app.clientId, 'client_secret': app.clientSecret, 'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob', 'grant_type': 'refresh_token'},
      );
      final fresh = TraktTokens.fromTrakt(body) ?? (throw ApiException(0, _odd));
      _keep(fresh);
      return fresh;
    } finally {
      _refreshing = null;
    }
  }();

  /// A signed-in call; refreshes first when the token is due, and once more on a 401.
  Future<dynamic> _call(String method, String path, {Object? body}) async {
    if (tokens == null) throw ApiException(401, 'Not signed in to Trakt');
    if (tokens!.stale) await refresh();
    Future<dynamic> go() => _http.send(method, Uri.parse('$_base$path'), headers: {..._headers, 'authorization': 'Bearer ${tokens!.access}'}, body: body);
    try {
      return await go();
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      await refresh();
      return go();
    }
  }

  /// The signed-in user's name.
  Future<String> username() async {
    final j = JsonHttp.object(await _call('GET', '/users/settings'), _odd);
    final user = j['user'];
    final name = user is Map ? (user['username'] ?? user['name']) : null;
    return name is String ? name : '';
  }

  /// start, pause or stop at [progress] percent. A stop at 80% or more counts as watched.
  /// Trakt answers 409 when the same thing was just scrobbled; that's fine.
  Future<void> scrobble(String action, TraktTarget target, double progress) async {
    assert(const {'start', 'pause', 'stop'}.contains(action));
    try {
      await _call('POST', '/scrobble/$action', body: {...target.scrobbleBody(), 'progress': double.parse(progress.clamp(0, 100).toStringAsFixed(2))});
    } on ApiException catch (e) {
      if (e.status != 409) rethrow;
    }
  }

  /// Adds a watch to the history (for titles marked watched by hand).
  Future<void> addToHistory(TraktTarget target, {DateTime? at}) => _call('POST', '/sync/history', body: target.historyBody(at ?? DateTime.now()));

  /// Lets go of the tokens on Trakt's side too.
  Future<void> revoke() async {
    final t = tokens;
    if (t == null) return;
    await _http.send('POST', Uri.parse('$_base/oauth/revoke'), headers: _headers, body: {'token': t.access, 'client_id': app.clientId, 'client_secret': app.clientSecret});
  }
}
