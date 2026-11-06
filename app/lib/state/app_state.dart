import 'dart:async';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../services/channels.dart';
import '../services/collections_cache.dart';
import '../services/open_party.dart';
import '../services/scrobbler.dart';
import '../services/series_cache.dart';
import '../services/settings_store.dart';
import '../services/updater.dart';
import '../services/watch_together.dart';

/// One Seerr request with its title and live state.
class RequestRow {
  RequestRow(this.request, this.details) : state = requestStateWith(request.media, request, details);
  final SeerrRequest request;
  final SeerrResult? details;
  final RequestState state;
  String get title => details?.displayTitle ?? 'TMDB ${request.media?.tmdbId ?? ''}';
}

enum Conn { unknown, ok, failed, off }

/// App-wide state: settings, the Plex and Seerr clients, and the live request list.
class AppState extends ChangeNotifier {
  AppState(this._store, {Updater? updater, Scrobbler? scrobbler, ChannelStore? channels}) : updater = updater ?? Updater(), scrobbler = scrobbler ?? Scrobbler(), channels = channels ?? ChannelStore();
  final SettingsStore _store;

  /// Newer Liquiflux releases on GitHub (Settings > Advanced > Updates).
  final Updater updater;

  /// Trakt and AniList (Settings > Tracking).
  final Scrobbler scrobbler;

  Settings settings = const Settings(clientId: 'console');
  PlexClient? plex;
  SeerrClient? seerr;
  PlexServerInfo? server;
  List<PlexSection> sections = const [];
  Conn plexConn = Conn.unknown;
  Conn seerrConn = Conn.unknown;
  String? plexError;
  String? seerrError;
  String? seerrUser;

  List<RequestRow>? requests;
  Timer? _poll;
  final _details = <String, Future<SeerrResult?>>{};
  final _detailsAt = <String, DateTime>{};
  final _detailsKnown = <String, SeerrResult>{};
  bool loaded = false;

  /// Counts connects, so work started for an earlier one can tell it's out of date.
  int _gen = 0;
  Timer? _plexRetry;
  Timer? _seerrRetry;

  /// Every movie and show in Plex, best-rated first, with TMDB ids; shared by Home and Trending.
  Future<({List<List<PlexItem>> bySection, LibraryIndex index})>? _library;
  DateTime? _libraryAt;

  /// Kept for ten minutes; nothing is kept until Plex has answered with its libraries.
  Future<({List<List<PlexItem>> bySection, LibraryIndex index})> library() {
    final p = plex;
    if (p == null || plexConn != Conn.ok) return Future.error(StateError('Plex is not connected'));
    if (sections.isEmpty) return Future.value((bySection: const <List<PlexItem>>[], index: LibraryIndex(const [])));
    final had = _library;
    if (had != null && DateTime.now().difference(_libraryAt!) <= const Duration(minutes: 10)) return had;
    final secs = sections;
    final job = () async {
      // A big library is one long listing, so it gets longer than the usual request.
      final lists = await Future.wait([for (final s in secs) p.sectionItems(s.key, sort: 'audienceRating:desc', size: 20000, guids: true, timeout: const Duration(minutes: 2)).then((r) => r.items)]);
      return (bySection: lists, index: LibraryIndex([for (final l in lists) ...l]));
    }();
    _libraryAt = DateTime.now();
    _library = job;
    job.then(
      (_) {},
      onError: (Object _) {
        if (identical(_library, job)) _library = null;
      },
    );
    return job;
  }

  /// Film series you own at least one film of: the Plex libraries' collections matched to
  /// TMDB's, and every TMDB series a movie of yours belongs to. Opens from what was found
  /// last time (kept on disk) and catches up in the background; [franchiseVersion] ticks
  /// when a fresher list is ready.
  List<Franchise>? _franchiseList;
  DateTime? _franchisesAt;
  Future<List<Franchise>>? _franchiseJob;
  final franchiseVersion = ValueNotifier<int>(0);
  final _collections = CollectionsCache();

  /// Saved shuffle channels (Channels page).
  final ChannelStore channels;

  /// The channels for the server in use, read from disk the first time.
  Future<ChannelStore> channelList() async {
    await channels.load(server?.machineIdentifier ?? settings.plexMachineId);
    return channels;
  }

  /// The series already in hand, without waiting.
  List<Franchise>? get franchisesNow => _franchiseList;

  Future<List<Franchise>> franchises() async {
    final list = _franchiseList;
    if (list != null) {
      if (DateTime.now().difference(_franchisesAt!) > const Duration(minutes: 10)) unawaited(_refreshFranchises());
      return list;
    }
    final gen = _gen;
    if (plex != null) {
      await _collections.load(server?.machineIdentifier ?? '');
      if (gen == _gen && !_collections.isEmpty) {
        await _seriesCache.load();
        final built = _buildFranchises(await library());
        // Reconnected meanwhile: what was built belongs to the old server.
        if (gen != _gen) return built;
        _franchiseList = built;
        _franchisesAt = DateTime.now();
        unawaited(_refreshFranchises());
        return built;
      }
    }
    return _refreshFranchises();
  }

  /// One refresh at a time; a failed one keeps the list we had. One that finishes after a
  /// reconnect is dropped.
  Future<List<Franchise>> _refreshFranchises() {
    final running = _franchiseJob;
    if (running != null) return running;
    final gen = _gen;
    late final Future<List<Franchise>> job;
    job = () async {
      try {
        final fresh = await _loadFranchises(gen);
        if (gen != _gen) return fresh;
        _franchiseList = fresh;
        _franchisesAt = DateTime.now();
        franchiseVersion.value++;
        return fresh;
      } catch (e) {
        debugPrint('collections: $e');
        final had = _franchiseList;
        if (had == null || gen != _gen) rethrow;
        return had;
      } finally {
        if (identical(_franchiseJob, job)) _franchiseJob = null;
      }
    }();
    return _franchiseJob = job;
  }

  final _seriesCache = SeriesCache();

  /// Progress while film series are looked up for the first time (done, total).
  final seriesScan = ValueNotifier<(int, int)?>(null);

  /// Runs [job] over [items], [width] at a time.
  static Future<void> _pool<T>(Iterable<T> items, Future<void> Function(T) job, {int width = 6}) async {
    final it = items.iterator;
    Future<void> worker() async {
      while (it.moveNext()) {
        await job(it.current);
      }
    }

    await Future.wait([for (var k = 0; k < width; k++) worker()]);
  }

  /// Gathers the series for connect [gen], leaving the cache alone once a newer connect began.
  Future<List<Franchise>> _loadFranchises(int gen) async {
    final p = plex;
    if (p == null) return const [];
    final s = seerrConn == Conn.ok ? seerr : null;
    final secs = sections;
    final machine = server?.machineIdentifier ?? '';
    final lib = await library();
    if (gen != _gen) return const [];
    await _collections.load(machine);

    // Which series each movie you own belongs to (looked up once, then remembered).
    final ownedSeries = <int>{};
    await _seriesCache.load();
    final movies = {
      for (final l in lib.bySection)
        for (final i in l)
          if (i.type == 'movie' && i.tmdbId != null) i.tmdbId!,
    };
    if (s != null) {
      final todo = movies.where((m) => !_seriesCache.has(m)).toList();
      var done = 0;
      if (todo.isNotEmpty) seriesScan.value = (0, todo.length);
      await _pool(todo, (int m) async {
        if (gen != _gen) return;
        try {
          _seriesCache[m] = (await s.details('movie', m)).collectionId ?? 0;
        } on ApiException catch (e) {
          if (e.status == 404) _seriesCache[m] = 0;
        } catch (_) {}
        done++;
        if (done % 25 == 0) {
          seriesScan.value = (done, todo.length);
          unawaited(_seriesCache.save());
        }
      });
      seriesScan.value = null;
      await _seriesCache.save();
    }
    for (final m in movies) {
      final c = _seriesCache[m] ?? 0;
      if (c > 0) ownedSeries.add(c);
    }

    // The Plex collections (custom ones too), all listed side by side. A collection's
    // films are only fetched again when it changed since last time.
    final lists = await Future.wait([for (final sec in secs.where((x) => x.type == 'movie')) p.collections(sec.key)]);
    if (gen != _gen) return const [];
    final before = {for (final ps in _collections.plex) ps.collection.ratingKey: ps};
    final tmdbOf = <String, int>{
      for (final l in lib.bySection)
        for (final i in l)
          if (i.tmdbId != null) i.ratingKey: i.tmdbId!,
    };
    // The one TMDB series a collection's films belong to, if they agree.
    int? seriesOf(Iterable<int> movies) {
      final ids = {
        for (final t in movies)
          if ((_seriesCache[t] ?? 0) > 0) _seriesCache[t]!,
      };
      return ids.length == 1 ? ids.first : null;
    }

    final plexSeries = <PlexSeries>[];
    await _pool([for (final l in lists) ...l], (PlexItem c) async {
      final had = before[c.ratingKey];
      if (had != null && CollectionsCache.same(had.collection, c)) {
        plexSeries.add((collection: c, items: had.items, tmdbId: seriesOf(had.items.map((k) => tmdbOf[k]).whereType<int>()) ?? had.tmdbId));
        return;
      }
      final items = await p.collectionItems(c.ratingKey).then<List<PlexItem>?>((v) => v, onError: (Object _) => null);
      if (items == null) {
        // Couldn't fetch it: keep last time's (it's tried again next refresh).
        if (had != null) plexSeries.add(had);
        return;
      }
      if (items.isEmpty) return;
      plexSeries.add((collection: c, items: [for (final i in items) i.ratingKey], tmdbId: seriesOf(items.map((i) => i.tmdbId).whereType<int>())));
    });
    if (gen != _gen) return const [];
    _collections.plex = plexSeries;

    // TMDB's series: only the ones not fetched this week.
    if (s != null) {
      final want = {...ownedSeries, for (final ps in plexSeries) ?ps.tmdbId};
      await _pool(want.where((id) => _collections.fresh(id) == null), (int id) async {
        final t = await s.collection(id);
        if (t != null && gen == _gen) _collections.tmdb[id] = (at: DateTime.now(), series: t);
      });
    }
    if (gen != _gen) return const [];
    await _collections.save();
    return _buildFranchises(lib);
  }

  /// Puts the series together from the cached Plex collections and TMDB series.
  List<Franchise> _buildFranchises(({List<List<PlexItem>> bySection, LibraryIndex index}) lib) {
    final byKey = {
      for (final l in lib.bySection)
        for (final i in l) i.ratingKey: i,
    };
    PlexItem? lookup(String k) => byKey[k];
    final out = <Franchise>[];
    final seen = <int>{};
    for (final ps in _collections.plex) {
      final items = ps.items.map(lookup).whereType<PlexItem>().toList();
      if (items.isEmpty) continue;
      final tmdb = ps.tmdbId == null ? null : _collections.tmdb[ps.tmdbId]?.series;
      if (tmdb != null && !seen.add(tmdb.id)) continue;
      out.add(Franchise.from(tmdb: tmdb, collection: ps.collection, items: items, library: lib.index, lookup: lookup));
    }
    // Every other series you own at least one film of.
    final owned = {
      for (final i in byKey.values)
        if (i.type == 'movie' && i.tmdbId != null && (_seriesCache[i.tmdbId!] ?? 0) > 0) _seriesCache[i.tmdbId!]!,
    };
    for (final id in owned) {
      final t = _collections.tmdb[id]?.series;
      if (t != null && t.parts.length >= 2 && seen.add(t.id)) out.add(Franchise.from(tmdb: t, library: lib.index, lookup: lookup));
    }
    return out;
  }

  String get _platform => Platform.isWindows
      ? 'Windows'
      : Platform.isAndroid
      ? 'Android'
      : Platform.isMacOS
      ? 'macOS'
      : 'Linux';

  Future<void> init() async {
    settings = await _store.load();
    _makeTrakt();
    unawaited(scrobbler.useProfile(settings.profileKey));
    loaded = true;
    await connect();
  }

  Future<void> update(Settings next) async {
    settings = next;
    await _store.save(next);
    await connect();
  }

  Future<void> setGlass(bool on) async {
    settings = settings.copyWith(glass: on);
    notifyListeners();
    await _store.save(settings);
  }

  Future<void> setSpotlightTrailers(bool on) async {
    settings = settings.copyWith(spotlightTrailers: on);
    notifyListeners();
    await _store.save(settings);
  }

  Future<void> setHomeTrailers(bool on) async {
    settings = settings.copyWith(homeTrailers: on);
    notifyListeners();
    await _store.save(settings);
  }

  /// Saves a smaller preference change without reconnecting.
  Future<void> tweak(Settings Function(Settings s) change) async {
    settings = change(settings);
    notifyListeners();
    await _store.save(settings);
  }

  /// Thumbs up or down on a title for "Because You Watched"; the same thumb again clears it.
  Future<void> rate(String mediaType, int tmdbId, String title, {required bool up}) => tweak((s) => s.copyWith(taste: s.taste.rate(Taste.keyOf(mediaType, tmdbId), title, up: up)));

  Future<void> setPlayback(PlaybackPrefs p) async {
    settings = settings.copyWith(playback: p);
    notifyListeners();
    await _store.save(settings);
  }

  /// Forgets the Plex sign-in (and a Seerr login that rides on it).
  Future<void> signOut() {
    forgetHome();
    return update(settings.backToOwner().copyWith(plexToken: '', plexAccountToken: '', plexServerName: '', plexMachineId: '', seerrApiKey: settings.seerrUsePlexLogin ? '' : null));
  }

  // ---------------------------------------------------------------- Plex Home

  /// Everyone in the Plex Home, once listed (null before, empty when there's no Home).
  List<PlexHomeUser>? homeList;
  Future<List<PlexHomeUser>>? _homeJob;

  /// A new sign-in: the Home is listed afresh.
  void forgetHome() {
    homeList = null;
    _homeJob = null;
  }

  /// The Home user in use, when [homeList] knows them.
  PlexHomeUser? get profile {
    final id = settings.plexUserId.isNotEmpty ? settings.plexUserId : settings.plexOwnerId;
    return homeList?.where((u) => u.uuid == id).firstOrNull;
  }

  /// Lists the Plex Home (kept for the session unless [fresh]). The first time, it also
  /// learns which uuid is the account that signed in.
  Future<List<PlexHomeUser>> homeUsers({bool fresh = false}) {
    if (!settings.plexReady) return Future.value(const []);
    final had = _homeJob;
    if (had != null && !fresh) return had;
    final job = _listHome();
    _homeJob = job;
    job.then((_) {}, onError: (Object _) {
      if (identical(_homeJob, job)) _homeJob = null;
    });
    return job;
  }

  Future<List<PlexHomeUser>> _listHome() async {
    final s = settings;
    final home = PlexHome(clientId: s.clientId, product: appName, base: Platform.environment['CONSOLE_PLEXHOME_URL'] ?? 'https://clients.plex.tv/api/v2');
    try {
      final token = s.homeToken;
      final list = await home.users(token);
      var owner = s.plexOwnerId;
      if (owner.isEmpty) owner = (await home.me(token)).uuid;
      // Signed in again meanwhile: this list is someone else's.
      if (settings.homeToken != token) return list;
      if (owner != settings.plexOwnerId) {
        settings = settings.copyWith(plexOwnerId: owner);
        unawaited(_store.save(settings));
      }
      homeList = list;
      notifyListeners();
      return list;
    } finally {
      home.close();
    }
  }

  /// Switches to Home user [user] ([pin] when they have one): their plex.tv token, the
  /// server's token for them, their own thumbs, spoilers and Trakt/AniList sign-ins. Throws
  /// [PlexPinRejected] for a wrong PIN, or an [ApiException] the page can show.
  Future<void> switchProfile(PlexHomeUser user, {String? pin}) async {
    final s = settings;
    final opts = (clientId: s.clientId, product: appName);
    final home = PlexHome(clientId: opts.clientId, product: opts.product, base: Platform.environment['CONSOLE_PLEXHOME_URL'] ?? 'https://clients.plex.tv/api/v2');
    final auth = PlexAuth(clientId: opts.clientId, product: opts.product);
    try {
      final userToken = await home.switchTo(s.homeToken, user, pin: pin);
      rememberSecret(userToken);
      final servers = await auth.servers(userToken);
      final server = servers.where((x) => s.plexMachineId.isNotEmpty ? x.machineIdentifier == s.plexMachineId : x.name == s.plexServerName).firstOrNull;
      final name = s.plexServerName.isNotEmpty ? s.plexServerName : 'this server';
      if (server == null || server.accessToken.isEmpty) throw ApiException(0, "${user.name} doesn't have access to $name. Share it with them in Plex first.");
      rememberSecret(server.accessToken);
      final owner = s.plexOwnerId.isNotEmpty && user.uuid == s.plexOwnerId;
      final next = settings
          .swapProfile(owner ? '' : user.uuid)
          .copyWith(
            plexToken: server.accessToken,
            plexAccountToken: userToken,
            plexHomeToken: s.homeToken,
            plexUserId: owner ? '' : user.uuid,
            plexUserName: owner ? '' : user.name,
            plexUserThumb: owner ? '' : user.thumb,
          );
      await update(next);
    } finally {
      home.close();
      auth.close();
    }
  }

  /// True when the server is on this network, which picks the home or away streaming quality.
  bool get plexIsLocal => isLocalAddress(settings.plexUrl);

  Future<void> setDiscovery({String? traktClientId, String? region, String? xrayUrl}) async {
    settings = settings.copyWith(traktClientId: traktClientId, region: region, xrayUrl: xrayUrl);
    _makeTrakt();
    notifyListeners();
    await _store.save(settings);
  }

  /// The Trakt app (Client ID and Secret) and AniList client to sign in with.
  Future<void> setScrobbleApps({String? traktClientId, String? traktClientSecret, String? anilistClientId}) async {
    settings = settings.copyWith(traktClientId: traktClientId, traktClientSecret: traktClientSecret, anilistClientId: anilistClientId);
    rememberSecret(settings.traktClientSecret);
    _makeTrakt();
    notifyListeners();
    await _store.save(settings);
  }

  /// Trakt's live charts, when a client ID is set.
  TraktClient? trakt;

  /// A new Trakt client when the ID changed (the old one is closed).
  void _makeTrakt() {
    scrobbler.configure(traktClientId: settings.traktClientId, traktClientSecret: settings.traktClientSecret, anilistClientId: settings.anilistClientId);
    final id = settings.traktClientId.trim();
    if (trakt?.clientId == id && id.isNotEmpty) return;
    trakt?.close();
    trakt = id.isEmpty ? null : TraktClient(clientId: id, baseUrl: Platform.environment['CONSOLE_TRAKT_URL'] ?? 'https://api.trakt.tv');
  }

  Future<void> setTheme(String t) async {
    settings = settings.copyWith(theme: t);
    notifyListeners();
    await _store.save(settings);
  }

  /// Watch Together rooms (Plex's), and invitations to them.
  late final watchTogether = WatchTogether(this);

  /// Watch Together by room code (Open Watch Party, the rooms Plezy uses).
  late final openParty = OpenParty(this);

  /// Connects with the current settings. A connect started while another is still under
  /// way takes over: the earlier one's answers are dropped. Clients whose settings didn't
  /// change are kept (with any Seerr sign-in); replaced ones are closed.
  Future<void> connect() async {
    final gen = ++_gen;
    _poll?.cancel();
    _poll = null;
    _plexRetry?.cancel();
    _seerrRetry?.cancel();
    watchTogether.reset();
    unawaited(openParty.leave());
    final s = settings;
    // Scrubbed from anything logged or shown from here on.
    for (final secret in [s.plexToken, s.plexAccountToken, s.plexHomeToken, s.seerrApiKey, s.traktClientId, s.traktClientSecret]) {
      rememberSecret(secret);
    }
    // Each Home user has their own Trakt and AniList sign-ins.
    unawaited(scrobbler.useProfile(s.profileKey));

    final oldPlex = plex, oldSeerr = seerr;
    final keepPlex =
        s.plexReady && oldPlex != null && oldPlex.baseUrl == s.plexUrl.replaceAll(RegExp(r'/+$'), '') && oldPlex.token == s.plexToken && oldPlex.clientId == s.clientId && oldPlex.expectMachineId == s.plexMachineId;
    plex = keepPlex ? oldPlex : (s.plexReady ? PlexClient(baseUrl: s.plexUrl, token: s.plexToken, clientId: s.clientId, product: appName, platform: _platform, expectMachineId: s.plexMachineId) : null);
    // Seerr checks a Plex sign-in with plex.tv, which only knows the account token (a shared
    // user's server token is one only that server knows).
    final apiKey = s.seerrApiKey.isNotEmpty ? s.seerrApiKey : null, seerrPlex = s.seerrApiKey.isEmpty ? s.plexTvToken : null;
    final keepSeerr = s.seerrReady && oldSeerr != null && oldSeerr.baseUrl == s.seerrUrl.replaceAll(RegExp(r'/+$'), '') && oldSeerr.apiKey == apiKey && oldSeerr.plexToken == seerrPlex;
    seerr = keepSeerr ? oldSeerr : (s.seerrReady ? SeerrClient(baseUrl: s.seerrUrl, apiKey: apiKey, plexToken: seerrPlex) : null);
    if (!identical(plex, oldPlex)) oldPlex?.close();
    if (!identical(seerr, oldSeerr)) oldSeerr?.close();

    plexConn = plex == null ? Conn.off : Conn.unknown;
    seerrConn = seerr == null ? Conn.off : Conn.unknown;
    server = null;
    sections = const [];
    seerrUser = null;
    plexError = null;
    seerrError = null;
    _details.clear();
    _detailsAt.clear();
    _detailsKnown.clear();
    requests = null;
    _requestsSig = null;
    _requestsShown = _requestsSeq;
    _readySeen.clear();
    _readyPrimed = false;
    _library = null;
    _franchiseList = null;
    _franchisesAt = null;
    _franchiseJob = null;
    _collections.loaded = false;
    _makeTrakt();
    notifyListeners();

    await Future.wait([_checkPlex(gen), _checkSeerr(gen)]);
    if (gen != _gen) return;
    _afterPlex(gen, const Duration(seconds: 15));
    _afterSeerr(gen, const Duration(seconds: 15));
  }

  /// Once Plex answers, look for Watch Together invitations; while it doesn't, ask again
  /// after [wait] (doubling up to five minutes).
  void _afterPlex(int gen, Duration wait) {
    if (plexConn == Conn.ok) {
      watchTogether.watchInvites();
      // Whether there's a Plex Home to switch in (the rail shows its profile button then).
      if (homeList == null) unawaited(homeUsers().then((_) {}, onError: (Object e) => debugPrint('plex home: ${errorText(e)}')));
    } else if (plexConn == Conn.failed) {
      _plexRetry = Timer(wait, () async {
        if (gen != _gen) return;
        await _checkPlex(gen);
        if (gen == _gen) _afterPlex(gen, _backoff(wait));
      });
    }
  }

  /// Once Seerr answers, keep the request list current; while it doesn't, ask again later.
  void _afterSeerr(int gen, Duration wait) {
    if (seerrConn == Conn.ok) {
      unawaited(refreshRequests());
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => refreshRequests());
    } else if (seerrConn == Conn.failed) {
      _seerrRetry = Timer(wait, () async {
        if (gen != _gen) return;
        await _checkSeerr(gen);
        if (gen == _gen) _afterSeerr(gen, _backoff(wait));
      });
    }
  }

  static Duration _backoff(Duration d) => d * 2 > const Duration(minutes: 5) ? const Duration(minutes: 5) : d * 2;

  Future<void> _checkPlex(int gen) async {
    final p = plex;
    if (p == null) return;
    try {
      final r = await Future.wait([p.server(), p.sections()]);
      if (gen != _gen) return;
      server = r[0] as PlexServerInfo;
      sections = (r[1] as List<PlexSection>).where((x) => x.isVideo).toList();
      plexConn = Conn.ok;
      plexError = null;
      // A sign-in from before 0.9.49 didn't keep the server's id: learn it now, so from the
      // next launch the address is checked before the token goes to it.
      final id = server!.machineIdentifier;
      if (settings.plexMachineId.isEmpty && id.isNotEmpty && RegExp(r'^[\w.-]{1,128}$').hasMatch(id) && settings.plexUrl.replaceAll(RegExp(r'/+$'), '') == p.baseUrl) {
        settings = settings.copyWith(plexMachineId: id);
        unawaited(_store.save(settings));
      }
    } catch (e) {
      if (gen != _gen) return;
      plexConn = Conn.failed;
      plexError = errorText(e);
    }
    notifyListeners();
  }

  Future<void> _checkSeerr(int gen) async {
    final s = seerr;
    if (s == null) return;
    try {
      final name = (await s.me()).name;
      if (gen != _gen) return;
      seerrUser = name;
      seerrConn = Conn.ok;
      seerrError = null;
    } catch (e) {
      if (gen != _gen) return;
      seerrConn = Conn.failed;
      seerrError = errorText(e);
    }
    notifyListeners();
  }

  /// Seerr's details for a request's title, asked once per title from the client [s]
  /// the list came from, and again after six hours so a newly announced streaming date
  /// shows up. A 404 is remembered; any other failure is tried again next time.
  Future<SeerrResult?> _detailsFor(SeerrClient s, SeerrRequest r) {
    final m = r.media;
    if (m == null) return Future.value(null);
    final key = '${m.mediaType}:${m.tmdbId}';
    final current = identical(s, seerr);
    final at = _detailsAt[key];
    if (at != null && DateTime.now().difference(at) > const Duration(hours: 6)) _details.remove(key);
    final hit = current ? _details[key] : null;
    if (hit != null) return hit;
    late final Future<SeerrResult?> f;
    f = s
        .details(m.mediaType, m.tmdbId)
        .then<SeerrResult?>(
          (v) {
            if (identical(s, seerr)) _detailsKnown[key] = v;
            return v;
          },
          onError: (Object e) {
            final gone = e is ApiException && e.status == 404;
            if (!gone && identical(_details[key], f)) _details.remove(key);
            // A failed six-hourly look keeps what was found before.
            return gone ? null : _detailsKnown[key];
          },
        );
    if (current) {
      _details[key] = f;
      _detailsAt[key] = DateTime.now();
    }
    return f;
  }

  String? _requestsSig;

  /// Each refresh is numbered; one that lands after a newer one (or after a reconnect) is dropped.
  int _requestsSeq = 0;
  int _requestsShown = 0;

  Future<void> refreshRequests() async {
    final s = seerr;
    if (s == null) return;
    final seq = ++_requestsSeq;
    try {
      final list = await s.requests();
      final details = await Future.wait(list.map((r) => _detailsFor(s, r)));
      if (seq <= _requestsShown || !identical(s, seerr)) return;
      _requestsShown = seq;
      final rows = [for (var i = 0; i < list.length; i++) RequestRow(list[i], details[i])];
      _noticeReady(rows);
      // Every page listens to AppState, so only speak up when the list actually changed.
      final sig = [for (final r in rows) '${r.request.id}|${r.state.label}|${r.state.progress}|${r.state.detail}|${r.title}'].join('\n');
      if (requests != null && sig == _requestsSig) return;
      _requestsSig = sig;
      requests = rows;
      notifyListeners();
    } catch (e) {
      debugPrint('requests: $e');
    }
  }

  /// Requests that just became watchable, for "It's ready" notices.
  final readyEvents = StreamController<RequestRow>.broadcast();
  final _readySeen = <int>{};
  bool _readyPrimed = false;

  /// The first look only notes what's already available; after that, each request that
  /// turns Available is announced once (yours, or everyone's, per Settings).
  void _noticeReady(List<RequestRow> rows) {
    for (final r in rows) {
      if (r.state.label != 'Available' || !_readySeen.add(r.request.id) || !_readyPrimed) continue;
      final who = settings.notifyReady;
      final mine = r.request.requestedBy == null || seerrUser == null || r.request.requestedBy == seerrUser;
      if (who == 'everyone' || (who == 'mine' && mine)) readyEvents.add(r);
    }
    _readyPrimed = true;
  }

  /// The Plex item for a finished request: Seerr's match, else a look in the library
  /// (fetched again if it's more than a few seconds old). Null when Plex can't say.
  Future<String?> ratingKeyFor(RequestRow r) async {
    final k = r.request.media?.ratingKey;
    if (k != null && k.isNotEmpty) return k;
    final d = r.details;
    if (d == null) return null;
    try {
      final found = (await library()).index.ratingKeyFor(d);
      if (found != null) return found;
      // It may have only just arrived: look again, unless the library was fetched moments
      // ago (or is being fetched now, which several calls then share).
      if (DateTime.now().difference(_libraryAt ?? DateTime(0)) < const Duration(seconds: 30)) return null;
      _library = null;
      return (await library()).index.ratingKeyFor(d);
    } catch (e) {
      debugPrint('ratingKeyFor: $e');
      return null;
    }
  }

  /// Open requests, less those waiting on a streaming release (they can sit for months).
  int get activeRequestCount => requests?.where((r) => r.state.isActive && !r.state.notOnStreaming).length ?? 0;
  int get downloadingCount => requests?.where((r) => r.state.isDownloading).length ?? 0;

  /// False when there's no OS credential store (a Linux desktop without a keyring): sign-ins
  /// then last only until Liquiflux closes, since they're never saved in plain text.
  bool get credentialsSaved => _store.secureStorageOk;

  @override
  void dispose() {
    _gen++;
    _poll?.cancel();
    _plexRetry?.cancel();
    _seerrRetry?.cancel();
    plex?.close();
    seerr?.close();
    trakt?.close();
    updater.dispose();
    scrobbler.dispose();
    watchTogether.dispose();
    openParty.dispose();
    unawaited(readyEvents.close());
    super.dispose();
  }
}
