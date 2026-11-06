import 'dart:math';

import '../http_json.dart';
import '../match.dart';
import '../security.dart';
import 'plex_models.dart';

/// Talks to one Plex Media Server.
class PlexClient {
  PlexClient({required String baseUrl, required this.token, required this.clientId, JsonHttp? http, this.product = 'Console', this.platform = 'Windows', this.expectMachineId = ''})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _http = http ?? JsonHttp();

  final String baseUrl;
  final String token;
  final String clientId;
  final String product;
  final String platform;
  final JsonHttp _http;

  /// The server the token belongs to. When set, nothing carrying the token goes out until
  /// [isServer] has shown that [baseUrl] is still that server (a laptop on another network
  /// can find someone else's machine at the same LAN address). Empty = no check.
  final String expectMachineId;
  Future<void>? _checked;

  static const wrongServer = 'The Plex address saved here now answers as a different server, so Liquiflux did not send it your sign-in. Sign in to Plex again in Settings.';

  /// Completes once [expectMachineId] is confirmed; a wrong server fails every call from
  /// then on, while a network failure is asked again next time.
  Future<void> _verified() {
    if (expectMachineId.isEmpty) return Future.value();
    return _checked ??= isServer(expectMachineId).then(
      (ok) {
        if (!ok) throw ApiException(0, wrongServer, uri: Uri.tryParse(baseUrl));
      },
      onError: (Object e, StackTrace st) {
        _checked = null;
        Error.throwWithStackTrace(e, st);
      },
    );
  }

  /// A request with the token, once the server is confirmed.
  Future<dynamic> _send(String method, Uri uri, {Duration? timeout}) async {
    await _verified();
    return _http.send(method, uri, headers: headers, timeout: timeout);
  }

  Map<String, String> get headers => {
    'X-Plex-Token': token,
    'X-Plex-Client-Identifier': clientId,
    'X-Plex-Product': product,
    'X-Plex-Platform': platform,
    'X-Plex-Device': platform,
    'X-Plex-Version': '0.1.0',
  };

  /// True when [url] points at this server, the only place the token may go.
  bool isOnServer(String url) {
    final u = Uri.tryParse(url), base = Uri.tryParse(baseUrl);
    return u != null && base != null && base.host.isNotEmpty && sameOrigin(u, base);
  }

  /// [headers] for a request to [url] when it's on this server; none for anywhere else
  /// (an online trailer, say), so the token never goes to another host.
  Map<String, String> headersFor(String url) => isOnServer(url) ? headers : const {};

  Uri _uri(String path, [Map<String, Object?> query = const {}]) {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    // A path from the server always lands on the server: without the slash, "@host/x"
    // would turn the address into one for another host.
    final u = Uri.parse('$baseUrl${path.startsWith('/') ? '' : '/'}$path');
    return u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, Object?> query = const {}, Duration? timeout]) async {
    final body = await _send('GET', _uri(path, query), timeout: timeout);
    return (body is Map && body['MediaContainer'] is Map<String, dynamic> ? body['MediaContainer'] as Map<String, dynamic> : null) ?? const {};
  }

  List<PlexItem> _items(Map<String, dynamic> c) => _list(c['Metadata']).whereType<Map<String, dynamic>>().map(PlexItem.fromJson).toList();

  /// Whether the server at [baseUrl] is the one with [machineId], asked before the token
  /// goes anywhere: /identity answers without one. A server set to want a token even there
  /// passes only over https, where its certificate vouches for it. A network failure throws
  /// as any other call would; a wrong server answers false.
  Future<bool> isServer(String machineId) async {
    try {
      final body = await _http.send('GET', _uri('/identity'), headers: {'X-Plex-Client-Identifier': clientId, 'X-Plex-Product': product});
      final c = body is Map ? body['MediaContainer'] : null;
      return c is Map && c['machineIdentifier'] == machineId;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) return baseUrl.startsWith('https://');
      if (e.status == 0) rethrow;
      return false;
    }
  }

  Future<PlexServerInfo> server() async {
    final c = await _get('/');
    return PlexServerInfo(name: '${c['friendlyName'] ?? 'Plex'}', version: '${c['version'] ?? ''}', machineIdentifier: '${c['machineIdentifier'] ?? ''}');
  }

  Future<List<PlexSection>> sections() async {
    final c = await _get('/library/sections');
    return _list(c['Directory']).whereType<Map<String, dynamic>>().map(PlexSection.fromJson).toList();
  }

  /// [guids] adds each title's TMDB/IMDb ids (used to tell what you already own); [timeout]
  /// gives a whole-library listing longer than the usual request.
  Future<({List<PlexItem> items, int total})> sectionItems(String key, {int start = 0, int size = 120, String sort = 'titleSort', bool guids = false, Duration? timeout}) async {
    final c = await _get('/library/sections/$key/all', {'sort': sort, 'X-Plex-Container-Start': start, 'X-Plex-Container-Size': size, if (guids) 'includeGuids': 1}, timeout);
    final items = _items(c);
    return (items: items, total: _toInt(c['totalSize']) ?? _toInt(c['size']) ?? items.length);
  }

  /// A library's collections (type "collection"), e.g. Plex's automatic franchise ones.
  Future<List<PlexItem>> collections(String sectionKey) async {
    try {
      return _items(await _get('/library/sections/$sectionKey/collections', {'includeGuids': 1}));
    } on ApiException {
      return const [];
    }
  }

  /// What's in one collection, with TMDB ids.
  Future<List<PlexItem>> collectionItems(String ratingKey) async => _items(await _get('/library/collections/$ratingKey/children', {'includeGuids': 1}));

  /// The titles in a section you played most recently, newest first.
  Future<List<PlexItem>> recentlyWatched(String sectionKey, {int size = 12}) async {
    final r = await sectionItems(sectionKey, sort: 'lastViewedAt:desc', size: size * 2, guids: true);
    return r.items.where((i) => (i.lastViewedAt ?? 0) > 0).take(size).toList();
  }

  /// Every account's plays since [since], newest first (the server's own watch history,
  /// which needs the owner's token). Music and anything unparseable are left out.
  Future<List<PlexView>> history({required DateTime since, int size = 2000}) async {
    final from = since.millisecondsSinceEpoch ~/ 1000;
    final c = await _get('/status/sessions/history/all', {'sort': 'viewedAt:desc', 'viewedAt>': from, 'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': size});
    return [
      for (final j in _list(c['Metadata']).whereType<Map<String, dynamic>>())
        if (PlexView.fromJson(j) case final v? when v.viewedAt >= from) v,
    ];
  }

  Future<List<PlexItem>> recentlyAdded({int size = 24}) async => _items(await _get('/library/recentlyAdded', {'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': size}));

  Future<List<PlexItem>> onDeck({int size = 12}) async => _items(await _get('/library/onDeck', {'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': size}));

  /// One item. [full] also asks for critic reviews (cast, crew, ratings and streams always come back here);
  /// [playback] adds intro/credits markers and chapters for the player.
  Future<PlexItem?> metadata(String ratingKey, {bool full = false, bool playback = false}) async {
    final items = _items(await _get('/library/metadata/$ratingKey', {'includeGuids': 1, if (full) 'includeReviews': 1, if (playback) 'includeMarkers': 1, if (playback) 'includeChapters': 1}));
    return items.isEmpty ? null : items.first;
  }

  /// Every episode of a show, in order (for Up Next and previous/next episode).
  Future<List<PlexItem>> episodes(String showRatingKey) async => _items(await _get('/library/metadata/$showRatingKey/allLeaves'));

  /// Remembers the audio and subtitle choice for a file on the server, the way Plex's own
  /// apps do, so it carries over to the next episode and other devices. [subtitleStreamId] 0 is off.
  Future<void> selectStreams(int partId, {int? audioStreamId, int? subtitleStreamId}) async {
    if (audioStreamId == null && subtitleStreamId == null) return;
    await _send('PUT', _uri('/library/parts/$partId', {'allParts': 1, 'audioStreamID': audioStreamId, 'subtitleStreamID': subtitleStreamId}));
  }

  /// Subtitles Plex can find online for a title, best first. [language] is a two-letter
  /// code (en, fr). [hearingImpaired] and [forced] use Plex's scale: 0 prefer without,
  /// 1 prefer with, 2 only with, 3 only without.
  Future<List<OnlineSubtitle>> searchSubtitles(String ratingKey, {required String language, int hearingImpaired = 0, int forced = 0}) async {
    final c = await _get('/library/metadata/${Uri.encodeComponent(ratingKey)}/subtitles', {'language': language, 'hearingImpaired': hearingImpaired, 'forced': forced}, const Duration(seconds: 30));
    final found = _list(c['Stream']).whereType<Map<String, dynamic>>().map(OnlineSubtitle.fromJson).nonNulls.take(200).toList();
    // Exact matches first, then Plex's score, keeping the server's order for ties.
    final ranked = found.indexed.toList()
      ..sort((a, b) {
        final m = (b.$2.perfectMatch ? 1 : 0) - (a.$2.perfectMatch ? 1 : 0);
        if (m != 0) return m;
        final s = b.$2.score - a.$2.score;
        return s != 0 ? s : a.$1 - b.$1;
      });
    return [for (final r in ranked) r.$2];
  }

  /// Asks the server to fetch [subtitle] and add it to the title. It returns before the file
  /// has arrived; the new track shows up in the title's streams shortly after.
  Future<void> downloadSubtitle(String ratingKey, OnlineSubtitle subtitle) async {
    await _send('PUT', _uri('/library/metadata/${Uri.encodeComponent(ratingKey)}/subtitles', {'key': subtitle.key}));
  }

  /// A server path (such as a sidecar subtitle's key) with the token, for the player.
  String fileUrl(String path) => _uri(path, {'X-Plex-Token': token}).toString();

  /// Trailers, featurettes, deleted scenes…
  Future<List<PlexItem>> extras(String ratingKey) async {
    try {
      return _items(await _get('/library/metadata/$ratingKey/extras'));
    } on ApiException {
      return const [];
    }
  }

  /// "More Like This" style hubs for an item.
  Future<List<({String title, List<PlexItem> items})>> related(String ratingKey) async {
    try {
      final c = await _get('/library/metadata/$ratingKey/related');
      return [
        for (final hub in _list(c['Hub']).whereType<Map<String, dynamic>>())
          if (_items(hub).isNotEmpty) (title: '${hub['title'] ?? 'Related'}', items: _items(hub)),
      ];
    } on ApiException {
      return const [];
    }
  }

  /// Everything in a section featuring the actor with Plex tag [tagId].
  Future<List<PlexItem>> withActor(String sectionKey, int tagId) async => _items(await _get('/library/sections/$sectionKey/all', {'actor': tagId, 'includeGuids': 1}));

  /// A library's labels (Plex's tags you set yourself), as id and name.
  Future<List<({String key, String title})>> labels(String sectionKey) async {
    try {
      final c = await _get('/library/sections/$sectionKey/label');
      return [
        for (final d in _list(c['Directory']).whereType<Map<String, dynamic>>())
          if (d['key'] != null && '${d['title'] ?? ''}'.isNotEmpty) (key: '${d['key']}', title: '${d['title']}'),
      ];
    } on ApiException {
      return const [];
    }
  }

  /// Everything in a library with label [labelKey].
  Future<List<PlexItem>> labelled(String sectionKey, String labelKey) async => _items(await _get('/library/sections/$sectionKey/all', {'label': labelKey}));

  Future<List<PlexItem>> children(String ratingKey) async => _items(await _get('/library/metadata/$ratingKey/children'));

  /// Movies and shows matching [query]. Matching episodes count as their show, listed once
  /// ([searchTitles]), with the show's full details where Plex has them.
  Future<List<PlexItem>> search(String query, {int limit = 30}) async {
    final c = await _get('/hubs/search', {'query': query, 'limit': limit});
    final hits = <PlexItem>[];
    for (final hub in _list(c['Hub']).whereType<Map<String, dynamic>>()) {
      if (!const ['movie', 'show', 'episode'].contains(hub['type'])) continue;
      hits.addAll(_items(hub));
    }
    final found = searchTitles(hits, query);
    if (found.shows.isEmpty) return found.items;
    final full = {
      for (final s in await Future.wait(found.shows.map((k) => metadata(k).catchError((Object _) => null))))
        if (s != null && s.type == 'show') s.ratingKey: s,
    };
    return [for (final i in found.items) found.shows.contains(i.ratingKey) ? full[i.ratingKey] ?? i : i];
  }

  /// Resized image through the Plex photo transcoder.
  String? imageUrl(String? path, {required int width, required int height}) {
    if (path == null || path.isEmpty) return null;
    return _uri('/photo/:/transcode', {'width': width, 'height': height, 'minSize': 1, 'upscale': 1, 'url': path, 'X-Plex-Token': token}).toString();
  }

  /// Direct-play URL of one version's first file (the desktop player decodes almost anything).
  String? directPlayUrl(PlexItem item, {int mediaIndex = 0}) {
    final media = mediaIndex < item.media.length ? item.media[mediaIndex] : null;
    final part = media != null && media.parts.isNotEmpty ? media.parts.first : null;
    if (part == null) return null;
    // Online extras live off-server; they get no token, and only web addresses are played.
    if (!part.key.startsWith('/')) return isWebUrl(part.key) ? part.key : null;
    return _uri(part.key, {'X-Plex-Token': token, 'X-Plex-Client-Identifier': clientId}).toString();
  }

  /// HLS through the universal transcoder, for clients that can't direct play or want a lower
  /// quality. The chosen subtitle is burned in, since HLS sidecar text is patchy across servers.
  String transcodeUrl(
    PlexItem item, {
    required String session,
    int offsetSec = 0,
    int maxBitrateKbps = 20000,
    String? resolution,
    int mediaIndex = 0,
    bool directStream = true,
    bool remote = false,
    int? audioStreamId,
    int? subtitleStreamId,
    int subtitleSize = 100,
  }) => _uri('/video/:/transcode/universal/start.m3u8', {
    'path': '/library/metadata/${item.ratingKey}',
    'mediaIndex': mediaIndex,
    'partIndex': 0,
    'protocol': 'hls',
    'fastSeek': 1,
    'directPlay': 0,
    'directStream': directStream ? 1 : 0,
    'directStreamAudio': directStream ? 1 : 0,
    'location': remote ? 'wan' : 'lan',
    'offset': offsetSec,
    'session': session,
    'videoQuality': 100,
    'maxVideoBitrate': maxBitrateKbps,
    'videoResolution': resolution,
    'audioStreamID': audioStreamId,
    'subtitleStreamID': subtitleStreamId,
    'subtitles': subtitleStreamId != null && subtitleStreamId > 0 ? 'burn' : 'none',
    'subtitleSize': subtitleSize,
    'X-Plex-Token': token,
    'X-Plex-Client-Identifier': clientId,
  }).toString();

  /// Ends a transcode session so the server stops encoding for it.
  Future<void> stopTranscode(String session) async {
    try {
      await _send('GET', _uri('/video/:/transcode/universal/stop', {'session': session}));
    } catch (_) {}
  }

  /// Reports playback position so Plex keeps watch progress and "Continue Watching" current.
  Future<void> timeline(PlexItem item, {required String state, required int timeMs}) async {
    try {
      await _send(
        'GET',
        _uri('/:/timeline', {'ratingKey': item.ratingKey, 'key': '/library/metadata/${item.ratingKey}', 'state': state, 'time': timeMs, 'duration': item.duration ?? 0}),
      );
    } catch (_) {
      /* best effort */
    }
  }

  Future<void> markWatched(PlexItem item) async {
    try {
      await _send('GET', _uri('/:/scrobble', {'key': item.ratingKey, 'identifier': 'com.plexapp.plugins.library'}));
    } catch (_) {}
  }

  Future<void> markUnwatched(PlexItem item) async {
    try {
      await _send('GET', _uri('/:/unscrobble', {'key': item.ratingKey, 'identifier': 'com.plexapp.plugins.library'}));
    } catch (_) {}
  }

  /// "Open in Plex Web" link for the same title.
  String webUrl(String machineId, String ratingKey) => 'https://app.plex.tv/desktop/#!/server/$machineId/details?key=${Uri.encodeComponent('/library/metadata/$ratingKey')}';

  void close() => _http.close();

  static String newSessionId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Server JSON is untrusted: a field of the wrong type reads as missing.
List<Object?> _list(Object? v) => v is List ? v : const [];
int? _toInt(Object? v) => v is num && v.isFinite ? v.toInt() : null;
