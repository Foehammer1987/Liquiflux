import 'dart:async';

import 'http_json.dart';
import 'security.dart';

/// Reads timelines from a Liquiflux Riptide server (tools/riptide-server). It signs in with a
/// Plex token Liquiflux already has, the way Seerr's Plex sign-in works, so there's nothing
/// to set up beyond the address: the server checks with Plex that the account can use this
/// Plex server and gives back a session, which every timeline request then carries. The
/// plex.tv account token is best (the server then knows who it is, so allow lists work);
/// the Plex server's own token also works where the server allows it.
///
/// A plain folder of `<ratingKey>.json` files behind any web server (the setup before the
/// Riptide server) still works: when the server has no sign-in, files are read directly.
///
/// The Plex token only ever goes over https, or over http to an address on this network;
/// never in a URL, and only to the sign-in endpoint.
class RiptideServer {
  RiptideServer._(this.base, this._plexToken, {JsonHttp? http, DateTime Function()? now}) : _http = http ?? JsonHttp(timeout: const Duration(seconds: 8)), _now = now ?? DateTime.now;

  /// The server's address, without a trailing slash.
  final String base;
  final String _plexToken;
  final JsonHttp _http;
  final DateTime Function() _now;

  String? _session;
  DateTime? _expires;
  bool _plainFiles = false;
  DateTime? _refusedUntil;
  String? _refusal;
  Future<void>? _signingIn;

  static final _shared = <String, RiptideServer>{};

  /// One per server address and Plex account, kept for the app's life so the session is
  /// shared by every title played. Null when [server] isn't a usable web address.
  static RiptideServer? shared(String server, String plexToken, {JsonHttp? http, DateTime Function()? now}) {
    final base = server.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || safeExternalUri(base) == null) return null;
    final key = '$base|${plexToken.hashCode}';
    return _shared.putIfAbsent(key, () {
      // A new account (signed out and in again) doesn't need the old one's sessions.
      _shared.removeWhere((k, _) => k.startsWith('$base|'));
      return RiptideServer._(base, plexToken, http: http, now: now);
    });
  }

  /// Forgets every server's session (tests; sign-out).
  static void reset() => _shared.clear();

  /// Why the server last turned us away, for the log (null when it didn't).
  String? get refusal => _refusal;

  Uri _uri(String path) => Uri.parse('$base$path');

  /// Signs in now (Settings' Save): true when signed in, false for a plain file server
  /// (or an http address outside this network, which never gets the Plex token). Throws
  /// ApiException with the server's reason when it can't be reached or refuses the account.
  Future<bool> check() async {
    _session = null;
    _plainFiles = false;
    _refusedUntil = null;
    await (_signingIn ??= _signIn().whenComplete(() => _signingIn = null));
    return !_plainFiles;
  }

  /// The timeline for [ratingKey]: null when it hasn't been scanned. Throws ApiException when
  /// the server can't be reached or won't let this account in.
  Future<Map<String, dynamic>?> timeline(String ratingKey) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(ratingKey)) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_plainFiles && !_signedIn) {
        await (_signingIn ??= _signIn().whenComplete(() => _signingIn = null));
      }
      if (_plainFiles) return _file(ratingKey);
      try {
        final body = await _http.send('GET', _uri('/api/v1/timeline/$ratingKey'), headers: {'authorization': 'Bearer $_session'});
        return body is Map<String, dynamic> ? body : null;
      } on ApiException catch (e) {
        if (e.status == 404) return null;
        if (e.status == 401 && attempt == 0) {
          _session = null; // the server restarted (sessions don't survive that) or it expired
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  bool get _signedIn => _session != null && _expires != null && _expires!.isAfter(_now().add(const Duration(minutes: 5)));

  Future<void> _signIn() async {
    final until = _refusedUntil;
    if (until != null && _now().isBefore(until)) throw ApiException(403, _refusal ?? 'Riptide server refused this account');
    if (sendsCredentialsInClear(base) || _plexToken.isEmpty) {
      // Never send a Plex token in the clear across the internet: plain files only.
      _plainFiles = true;
      return;
    }
    try {
      final j = JsonHttp.object(await _http.send('POST', _uri('/api/v1/auth/plex'), body: {'plexToken': _plexToken}), 'The Riptide server answered with something unexpected');
      final token = j['token'], exp = DateTime.tryParse('${j['expiresAt']}');
      if (token is! String || !token.startsWith('xr1.') || exp == null) throw ApiException(0, 'The Riptide server answered with something unexpected');
      _session = token;
      _expires = exp;
      _refusal = null;
    } on ApiException catch (e) {
      // A plain web server over the folder: no sign-in there (nginx 405, python 501, others 404).
      if (e.status == 404 || e.status == 405 || e.status == 501) {
        _plainFiles = true;
        return;
      }
      if (e.status == 401 || e.status == 403 || e.status == 429) {
        // Not allowed (or too many tries): don't ask again for every title, or the server
        // would lock this address out.
        _refusal = e.message;
        _refusedUntil = _now().add(const Duration(minutes: 30));
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _file(String ratingKey) async {
    try {
      final body = await _http.send('GET', _uri('/$ratingKey.json'));
      return body is Map<String, dynamic> ? body : null;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }
}
