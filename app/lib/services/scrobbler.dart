import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import 'safe_file.dart';
import 'settings_store.dart' show OsSecretStore, SecretStore;

/// A Trakt app baked into a build with --dart-define (empty in the published builds, which
/// use the user's own Trakt app from Settings > Tracking). A secret baked in can be dug out
/// of the binary, so the official builds don't carry one and it never goes in the repo.
const builtInTraktId = String.fromEnvironment('LIQUIFLUX_TRAKT_CLIENT_ID');
const builtInTraktSecret = String.fromEnvironment('LIQUIFLUX_TRAKT_CLIENT_SECRET');

/// An AniList API client id (not a secret: the token sign-in AniList offers TVs needs only
/// the id). Empty unless a build sets it; Settings names the user's own.
const builtInAniListId = String.fromEnvironment('LIQUIFLUX_ANILIST_CLIENT_ID');

/// What's watched goes to Trakt (everything) and AniList (anime): playing, paused and
/// stopped as it happens, and a title counts as watched at [watchedAt] percent, Trakt's rule.
///
/// Sign-ins live in the OS credential store under one key, apart from settings.json; the
/// AniList entries each show maps to are cached in the support folder.
class Scrobbler extends ChangeNotifier {
  Scrobbler({SecretStore? secrets, Future<Directory> Function()? folder, JsonHttp Function()? http, String? traktBase, String? anilistEndpoint})
    : _secrets = secrets ?? const OsSecretStore(),
      _folder = folder ?? getApplicationSupportDirectory,
      _newHttp = http,
      _traktBase = traktBase ?? Platform.environment['CONSOLE_TRAKT_URL'] ?? 'https://api.trakt.tv',
      _anilistEndpoint = anilistEndpoint ?? 'https://graphql.anilist.co';

  final SecretStore _secrets;
  final Future<Directory> Function() _folder;
  final JsonHttp Function()? _newHttp;
  final String _traktBase;
  final String _anilistEndpoint;

  static const _key = 'scrobble_accounts';
  static const watchedAt = 80.0;

  /// The Trakt app in use: the user's own when Settings has both its Client ID and Secret,
  /// else the one built in, else none.
  TraktApp? get traktApp => _app;
  TraktApp? _app;
  String _anilistClientId = builtInAniListId;
  String get anilistClientId => _anilistClientId;

  TraktAccount? _trakt;
  String traktUser = '';
  AniListAccount? _anilist;
  String anilistUser = '';
  DateTime? _anilistExpires;

  bool get traktOn => _trakt?.tokens != null;
  bool get anilistOn => _anilist != null;

  /// The sign-in is for a different Trakt app than the one now in use: sign in again.
  bool traktAppChanged = false;

  /// The last thing sent, or what went wrong, for Settings.
  String? lastTrakt;
  String? lastAniList;

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    Map<String, dynamic> j = const {};
    try {
      final raw = await _secrets.read(_key);
      if (raw != null && raw.isNotEmpty) j = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (e) {
      debugPrint('scrobble accounts: ${e.runtimeType}');
    }
    final t = j['trakt'];
    if (t is Map) {
      final tokens = TraktTokens.fromJson(t['tokens']);
      _traktFor = '${t['clientId'] ?? ''}';
      if (tokens != null) {
        _tokens = tokens;
        traktUser = '${t['user'] ?? ''}';
      }
    }
    final a = j['anilist'];
    if (a is Map && a['token'] is String && (a['token'] as String).isNotEmpty) {
      _anilistExpires = DateTime.tryParse('${a['expires'] ?? ''}');
      if (_anilistExpires == null || _anilistExpires!.isAfter(DateTime.now())) {
        _anilist = AniListAccount(token: a['token'] as String, endpoint: _anilistEndpoint, http: _newHttp?.call());
        anilistUser = '${a['user'] ?? ''}';
        rememberSecret(_anilist!.token);
      } else {
        lastAniList = 'The AniList sign-in ran out after a year. Connect again.';
      }
    }
    _loaded = true;
    _makeTrakt();
    notifyListeners();
  }

  TraktTokens? _tokens;
  String _traktFor = '';

  /// Settings changed: the Trakt app (user's own pair, else built in) and AniList client id.
  void configure({required String traktClientId, required String traktClientSecret, required String anilistClientId}) {
    final own = TraktApp(clientId: traktClientId.trim(), clientSecret: traktClientSecret.trim());
    final built = const TraktApp(clientId: builtInTraktId, clientSecret: builtInTraktSecret);
    final app = own.ready ? own : (built.ready ? built : null);
    _anilistClientId = anilistClientId.trim().isNotEmpty ? anilistClientId.trim() : builtInAniListId;
    if (app?.clientId == _app?.clientId && app?.clientSecret == _app?.clientSecret) return;
    _app = app;
    if (app != null) rememberSecret(app.clientSecret);
    if (_loaded) _makeTrakt();
    notifyListeners();
  }

  void _makeTrakt() {
    _trakt?.close();
    _trakt = null;
    final app = _app;
    traktAppChanged = false;
    if (app == null) return;
    final tokens = _tokens;
    if (tokens != null && _traktFor.isNotEmpty && _traktFor != app.clientId) {
      // Tokens belong to the app that issued them.
      traktAppChanged = true;
    }
    _trakt = TraktAccount(
      app: app,
      tokens: traktAppChanged ? null : tokens,
      userAgent: '$appName/$appVersion',
      baseUrl: _traktBase,
      http: _newHttp?.call(),
      onTokens: (t) {
        _tokens = t;
        _traktFor = app.clientId;
        _remember(t);
        unawaited(_save());
      },
    );
    if (tokens != null) _remember(tokens);
  }

  void _remember(TraktTokens t) {
    rememberSecret(t.access);
    rememberSecret(t.refresh);
  }

  Future<void> _save() async {
    final j = {
      if (_tokens != null) 'trakt': {'clientId': _traktFor, 'user': traktUser, 'tokens': _tokens!.toJson()},
      if (_anilist != null) 'anilist': {'token': _anilist!.token, 'user': anilistUser, 'expires': ?_anilistExpires?.toUtc().toIso8601String()},
    };
    try {
      if (j.isEmpty) {
        await _secrets.delete(_key);
      } else {
        await _secrets.write(_key, jsonEncode(j));
      }
    } catch (e) {
      debugPrint('scrobble accounts save failed: ${errorText(e)}');
    }
  }

  // ---------------------------------------------------------------- signing in

  /// A Trakt code for the TV to show. Needs [traktApp].
  Future<TraktDeviceCode> traktCode() async {
    await load();
    final t = _trakt ?? (throw ApiException(0, 'Add a Trakt app first (Client ID and Client Secret).'));
    return t.deviceCode();
  }

  /// Waits for [code] to be approved, then keeps the sign-in.
  Future<void> traktWait(TraktDeviceCode code, {bool Function()? cancelled}) async {
    final t = _trakt ?? (throw ApiException(0, 'Add a Trakt app first (Client ID and Client Secret).'));
    await t.waitForApproval(code, cancelled: cancelled);
    traktAppChanged = false;
    try {
      traktUser = await t.username();
    } catch (e) {
      debugPrint('trakt user: ${errorText(e)}');
    }
    lastTrakt = null;
    await _save();
    notifyListeners();
  }

  Future<void> traktSignOut() async {
    final t = _trakt;
    if (t?.tokens != null) {
      try {
        await t!.revoke();
      } catch (e) {
        debugPrint('trakt revoke: ${errorText(e)}');
      }
    }
    t?.tokens = null;
    _tokens = null;
    _traktFor = '';
    traktUser = '';
    traktAppChanged = false;
    lastTrakt = null;
    await _save();
    notifyListeners();
  }

  /// Signs in with a token pasted from AniList's pin page; checks it first.
  Future<void> anilistSignIn(String pasted) async {
    await load();
    final token = AniListAccount.cleanToken(pasted) ?? (throw ApiException(0, "That doesn't look like an AniList token. Copy the whole token from AniList's page."));
    final account = AniListAccount(token: token, endpoint: _anilistEndpoint, http: _newHttp?.call());
    try {
      anilistUser = await account.viewer();
    } catch (e) {
      account.close();
      if (e is ApiException && (e.status == 400 || e.status == 401)) throw ApiException(e.status, 'AniList didn’t accept that token.');
      rethrow;
    }
    _anilist?.close();
    _anilist = account;
    rememberSecret(token);
    _anilistExpires = _jwtExpiry(token) ?? DateTime.now().add(const Duration(days: 365));
    lastAniList = null;
    await _save();
    notifyListeners();
  }

  Future<void> anilistSignOut() async {
    _anilist?.close();
    _anilist = null;
    anilistUser = '';
    lastAniList = null;
    await _save();
    notifyListeners();
  }

  /// The exp claim of a JWT, if it has one.
  static DateTime? _jwtExpiry(String token) {
    try {
      final part = token.split('.')[1];
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))));
      final exp = j is Map ? j['exp'] : null;
      return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000) : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- watching

  /// One play of one title; null when nothing is signed in.
  ScrobblePlay? play(PlexClient plex, PlexItem item, {String server = ''}) {
    if (!traktOn && !anilistOn) return null;
    if (item.type != 'movie' && item.type != 'episode') return null;
    return ScrobblePlay._(this, plex, item, server);
  }

  /// A title marked watched by hand: added to Trakt's history and AniList's progress.
  Future<void> markedWatched(PlexClient plex, PlexItem item, {String server = ''}) async {
    await load();
    if (item.type != 'movie' && item.type != 'episode') return;
    if (!traktOn && !anilistOn) return;
    if (item.guids.isEmpty) {
      try {
        item = await plex.metadata(item.ratingKey) ?? item;
      } catch (e) {
        debugPrint('scrobble item: ${errorText(e)}');
      }
    }
    final show = await _show(plex, item);
    final trakt = _trakt;
    if (traktOn && trakt != null) {
      final target = TraktTarget.of(item, show: show);
      if (target != null) {
        try {
          await trakt.addToHistory(target);
          _noteTrakt('Added ${_name(item)} to your history');
        } catch (e) {
          _noteTrakt('Couldn’t add ${_name(item)}: ${errorText(e)}');
        }
      }
    }
    await _aniListWatched(plex, item, show, server);
  }

  final _shows = <String, Future<PlexItem?>>{};

  /// The episode's show (for its ids and genres), read once per show.
  Future<PlexItem?> _show(PlexClient plex, PlexItem item) {
    final key = item.type == 'episode' ? item.grandparentRatingKey : null;
    if (key == null) return Future.value();
    return _shows.putIfAbsent('${plex.baseUrl} $key', () => plex.metadata(key).timeout(const Duration(seconds: 10)).then<PlexItem?>((v) => v, onError: (Object e) {
      _shows.remove('${plex.baseUrl} $key');
      debugPrint('scrobble show: ${errorText(e)}');
      return null;
    }));
  }

  static String _name(PlexItem i) => i.type == 'episode' ? '${i.grandparentTitle ?? ''} ${i.episodeCode}' : i.title;

  void _noteTrakt(String s) {
    debugPrint('trakt: $s');
    lastTrakt = s;
    notifyListeners();
  }

  void _noteAniList(String s) {
    debugPrint('anilist: $s');
    lastAniList = s;
    notifyListeners();
  }

  Future<void> _traktSend(String action, PlexItem item, PlexItem? show, double progress) async {
    final trakt = _trakt;
    if (!traktOn || trakt == null) return;
    final target = TraktTarget.of(item, show: show);
    if (target == null) {
      _noteTrakt('${_name(item)} has no IMDb, TMDB or TVDB id in Plex, so Trakt can’t match it');
      return;
    }
    try {
      await trakt.scrobble(action, target, progress);
      final what = switch (action) {
        'start' => 'Watching',
        'pause' => 'Paused',
        _ => progress >= watchedAt ? 'Watched' : 'Stopped',
      };
      _noteTrakt('$what ${_name(item)} (${progress.round()}%)');
    } on ApiException catch (e) {
      _noteTrakt(e.status == 404 ? 'Trakt doesn’t know ${_name(item)} ($target)' : 'Couldn’t reach Trakt: ${errorText(e)}');
    } catch (e) {
      _noteTrakt('Couldn’t reach Trakt: ${errorText(e)}');
    }
  }

  // ---------------------------------------------------------------- AniList

  /// Shows' and films' AniList entries, by Plex server and rating key.
  Map<String, dynamic>? _map;
  final _mapSaves = SaveQueue();

  Future<File> _mapFile() async => File('${(await _folder()).path}${Platform.pathSeparator}anilist-map.json');

  Future<Map<String, dynamic>> _loadMap() async {
    if (_map != null) return _map!;
    try {
      final f = await _mapFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) return _map = j;
      }
    } catch (e) {
      debugPrint('anilist map: ${e.runtimeType}');
    }
    return _map = {};
  }

  Future<void> _saveMap() => _mapSaves.run(() async => writeAtomically(await _mapFile(), jsonEncode(_map))).catchError((Object e) => debugPrint('anilist map save: ${e.runtimeType}'));

  /// A finished anime episode or film moves its AniList entry forward.
  Future<void> _aniListWatched(PlexClient plex, PlexItem item, PlexItem? show, String server) async {
    final account = _anilist;
    if (account == null) return;
    if (!isAnime(item.type == 'episode' ? show : item, library: item.librarySectionTitle)) return;
    try {
      final AniListPlace? place;
      if (item.type == 'movie') {
        final id = await _entryFor(account, '$server movie ${item.ratingKey}', () async => pickMatch(await account.search(item.title, movie: true), item.title, item.year) ?? (foldAccents(item.title) == item.title ? null : pickMatch(await account.search(foldAccents(item.title), movie: true), item.title, item.year)));
        place = id == null ? null : AniListPlace(AniListMedia(id: id.first.id, format: 'MOVIE'), 1);
      } else {
        final chain = await _entryFor(account, '$server show ${item.grandparentRatingKey}', () async {
          final title = show?.title ?? item.grandparentTitle ?? '';
          final found = pickMatch(await account.search(title), title, show?.year);
          final plain = foldAccents(title);
          // AniList's search can come back empty for an accented spelling (Shippūden).
          return found ?? (plain == title ? null : pickMatch(await account.search(plain), title, show?.year));
        });
        place = chain == null ? null : placeEpisode(chain, item, await plex.episodes(item.grandparentRatingKey!));
      }
      if (place == null) {
        _noteAniList('Couldn’t find ${_name(item)} on AniList');
        return;
      }
      final fresh = await account.media(place.media.id);
      if (fresh == null) return;
      final done = await account.watched(fresh, place.number);
      _noteAniList(done == null ? '${_name(item)} was already on your list (${fresh.title})' : '${fresh.title}: $done');
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 400 && e.message.toLowerCase().contains('invalid token')) {
        lastAniList = 'AniList signed Liquiflux out. Connect again.';
        await anilistSignOut();
        lastAniList = 'AniList signed Liquiflux out. Connect again.';
        notifyListeners();
        return;
      }
      _noteAniList('Couldn’t reach AniList: ${errorText(e)}');
    } catch (e) {
      _noteAniList('Couldn’t update AniList: ${errorText(e)}');
    }
  }

  /// The cached chain of entries for [key] (one entry for a film), found with [find] and
  /// walked through its prequels and sequels when missing or a week old. Misses are kept a day.
  Future<List<AniListMedia>?> _entryFor(AniListAccount account, String key, Future<AniListMedia?> Function() find) async {
    final map = await _loadMap();
    final had = map[key];
    if (had is Map) {
      final at = DateTime.tryParse('${had['at']}');
      final age = at == null ? null : DateTime.now().difference(at);
      final list = had['chain'];
      if (age != null && list is List && list.isEmpty && age < const Duration(days: 1)) return null;
      if (age != null && list is List && list.isNotEmpty && age < const Duration(days: 7)) {
        return [for (final m in list) ?_fromCache(m)];
      }
    }
    final found = await find();
    final chain = found == null ? const <AniListMedia>[] : (found.format == 'MOVIE' ? [found] : await seriesChain(found, account.media));
    map[key] = {'at': DateTime.now().toUtc().toIso8601String(), 'chain': [for (final m in chain) _toCache(m)]};
    await _saveMap();
    return chain.isEmpty ? null : chain;
  }

  static Map<String, Object?> _toCache(AniListMedia m) => {'id': m.id, 'format': m.format, 'episodes': m.episodes, 'start': m.start?.toIso8601String(), 'end': m.end?.toIso8601String(), 'title': m.titles.firstOrNull};

  static AniListMedia? _fromCache(Object? j) {
    if (j is! Map || j['id'] is! int) return null;
    return AniListMedia(
      id: j['id'] as int,
      format: '${j['format'] ?? 'TV'}',
      episodes: j['episodes'] is int ? j['episodes'] as int : null,
      start: DateTime.tryParse('${j['start'] ?? ''}'),
      end: DateTime.tryParse('${j['end'] ?? ''}'),
      titles: [if (j['title'] is String) j['title'] as String],
    );
  }

  /// Forgets which AniList entries the shows map to (after fixing a title in Plex).
  Future<void> forgetMatches() async {
    _map = {};
    await _saveMap();
  }

  @override
  void dispose() {
    _trakt?.close();
    _anilist?.close();
    super.dispose();
  }
}

extension on AniListMedia {
  String get title => titles.firstOrNull ?? 'AniList $id';
}

/// One play of one title. The player tells it playing, paused and stopped; it sends
/// Trakt's start, pause and stop (one at a time, the newest winning when they pile up),
/// and when the title ends up watched, moves AniList on too.
class ScrobblePlay {
  ScrobblePlay._(this._s, this._plex, this.item, this._server) : _showFuture = _s._show(_plex, item);

  final Scrobbler _s;
  final PlexClient _plex;
  final PlexItem item;
  final String _server;
  final Future<PlexItem?> _showFuture;

  String? _sentState;
  bool _ended = false;
  bool _counted = false;
  Future<void> _tail = Future.value();
  (String, double)? _next;

  /// Done with everything sent so far (for tests).
  Future<void> get idle => _tail;

  void playing(double progress) => _queue('start', progress);
  void paused(double progress) => _queue('pause', progress);

  /// The play is over at [progress] percent ([watched] counts it as finished whatever it is).
  Future<void> stopped(double progress, {bool watched = false}) {
    if (_ended) return _tail;
    _ended = true;
    final p = watched ? 100.0 : progress;
    _next = null;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      final show = await _showFuture;
      if (_sentState != null || p >= Scrobbler.watchedAt) await _s._traktSend('stop', item, show, p);
      if (p >= Scrobbler.watchedAt && !_counted) {
        _counted = true;
        await _s._aniListWatched(_plex, item, show, _server);
      }
    });
    return _tail;
  }

  void _queue(String action, double progress) {
    if (_ended || progress <= 0) return;
    final pending = _next != null;
    _next = (action, progress);
    if (pending) return;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      final job = _next;
      _next = null;
      if (job == null || _ended || job.$1 == _sentState) return;
      final show = await _showFuture;
      if (_ended) return;
      _sentState = job.$1;
      await _s._traktSend(job.$1, item, show, job.$2);
    });
  }
}
