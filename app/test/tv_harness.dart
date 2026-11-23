import 'dart:convert';

import 'package:console_app/main.dart' show TvCanvas;
import 'package:console_app/services/channels.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:console_app/services/tv_pack.dart';
import 'package:console_app/state/app_state.dart';
import 'package:console_app/state/scope.dart';
import 'package:console_app/ui/nav.dart' show rootRoutes, rootStack;
import 'package:console_app/ui/shell.dart';
import 'package:console_app/ui/tv_focus.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A Plex server and a Seerr in memory: a movie and a TV library, Continue Watching,
/// Recently Added, some history, cast, seasons and episodes, trending and recommendations.
Map<String, dynamic> movie(int i) => {
  'ratingKey': '$i',
  'key': '/library/metadata/$i',
  'type': 'movie',
  'title': 'Film $i',
  'year': 1990 + i % 30,
  'summary': 'A film about $i things.',
  'thumb': '/library/metadata/$i/thumb/1',
  'art': '/library/metadata/$i/art/1',
  'audienceRating': 9.5 - (i % 40) / 10,
  'contentRating': 'PG-13',
  'duration': 6000000,
  'librarySectionID': 1,
  if (i <= 6) 'lastViewedAt': 1700000000 + i,
  if (i <= 6) 'viewCount': 1,
  'Guid': [
    {'id': 'tmdb://$i'},
  ],
  'Genre': [
    {'tag': ['Drama', 'Action', 'Comedy'][i % 3]},
    {'tag': 'Thriller'},
  ],
  'Role': [
    for (var r = 0; r < 12; r++) {'id': 7000 + r, 'tag': 'Actor $r', 'role': 'Part $r', 'thumb': 'https://img.test/p$r.jpg'},
  ],
  'Director': [
    {'id': 8000, 'tag': 'Director A'},
  ],
  'Media': [
    {
      'id': i,
      'videoResolution': '1080',
      'Part': [
        {'id': i, 'key': '/library/parts/$i/file.mkv', 'duration': 6000000},
      ],
    },
  ],
};

Map<String, dynamic> show(int i) => {
  ...movie(i),
  'type': 'show',
  'title': 'Show $i',
  'librarySectionID': 2,
  'leafCount': 20,
  'viewedLeafCount': 3,
  'childCount': 3,
  'Media': const [],
};

Map<String, dynamic> season(int show, int n) => {
  'ratingKey': '${show * 100 + n}',
  'type': 'season',
  'title': 'Season $n',
  'index': n,
  'parentRatingKey': '$show',
  'parentTitle': 'Show $show',
  'leafCount': 8,
  'thumb': '/library/metadata/$show/thumb/1',
};

Map<String, dynamic> episode(int show, int s, int e) => {
  ...movie(show * 10000 + s * 100 + e),
  'type': 'episode',
  'title': 'Episode $e',
  'grandparentTitle': 'Show $show',
  'grandparentRatingKey': '$show',
  'parentRatingKey': '${show * 100 + s}',
  'parentIndex': s,
  'index': e,
  if (e == 1) 'viewOffset': 600000,
};

Map<String, dynamic> seerrTitle(int id, {String type = 'movie'}) => {
  'id': id,
  'mediaType': type,
  if (type == 'movie') 'title': 'Seerr $id' else 'name': 'Seerr $id',
  if (type == 'movie') 'releaseDate': '2020-01-01' else 'firstAirDate': '2020-01-01',
  'posterPath': '/p$id.jpg',
  'backdropPath': '/b$id.jpg',
  'overview': 'Something you might like.',
  'voteAverage': 8.1,
  'voteCount': 5000,
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

http.Response _plex(List<Map<String, dynamic>> items, {List<Map<String, dynamic>>? hubs, List<Map<String, dynamic>>? dirs}) => _json({
  'MediaContainer': {'size': items.length, 'totalSize': items.length, 'Metadata': items, 'Hub': ?hubs, 'Directory': ?dirs},
});

http.Client fakeServers() => MockClient((req) async {
  final u = req.url;
  final p = u.path;
  if (u.host == 'seerr.test') {
    final api = p.replaceFirst('/api/v1', '');
    if (api == '/auth/me') return _json({'id': 1, 'displayName': 'Me'});
    if (api == '/request') return _json({'results': []});
    if (api == '/discover/trending') return _json({'results': [for (var i = 0; i < 20; i++) seerrTitle(5000 + i)]});
    if (api == '/discover/movies') return _json({'results': [for (var i = 0; i < 20; i++) seerrTitle(6000 + i)]});
    if (api == '/discover/tv') return _json({'results': [for (var i = 0; i < 20; i++) seerrTitle(7000 + i, type: 'tv')]});
    final rec = RegExp(r'^/(movie|tv)/(\d+)/recommendations$').firstMatch(api);
    if (rec != null) return _json({'results': [for (var i = 0; i < 15; i++) seerrTitle(int.parse(rec[2]!) * 100 + i)]});
    final det = RegExp(r'^/(movie|tv)/(\d+)$').firstMatch(api);
    if (det != null) return _json(seerrTitle(int.parse(det[2]!), type: det[1]!));
    return _json({});
  }
  final parts = p.split('/');
  if (p == '/') return _json({'MediaContainer': {'friendlyName': 'Homeserver', 'machineIdentifier': 'm'}});
  if (p == '/library/sections') {
    return _plex(const [], dirs: [
      {'key': '1', 'title': 'Movies', 'type': 'movie'},
      {'key': '2', 'title': 'TV Shows', 'type': 'show'},
    ]);
  }
  if (p == '/status/sessions/history/all') {
    // Title i watched by 13 - i people a minute ago: odd ones are shows (an episode each), even ones movies.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
    return _plex([
      for (var i = 1; i <= 12; i++)
        for (var a = 1; a <= 13 - i; a++)
          i.isOdd
              ? {'type': 'episode', 'ratingKey': '${(200 + i) * 10000 + 101}', 'grandparentKey': '/library/metadata/${200 + i}', 'viewedAt': now, 'accountID': a}
              : {'type': 'movie', 'ratingKey': '${i + 10}', 'viewedAt': now, 'accountID': a},
    ]);
  }
  if (p == '/library/onDeck') return _plex([for (var i = 1; i <= 8; i++) episode(200 + i, 1, 1)]);
  if (p == '/library/recentlyAdded') return _plex([for (var i = 100; i < 130; i++) movie(i)]);
  if (p == '/library/sections/1/all') return _plex([for (var i = 1; i <= 80; i++) movie(i)]);
  if (p == '/library/sections/2/all') return _plex([for (var i = 201; i <= 230; i++) show(i)]);
  if (p == '/hubs/search') {
    return _plex(const [], hubs: [
      {'type': 'movie', 'title': 'Movies', 'Metadata': [for (var i = 1; i <= 12; i++) movie(i)]},
    ]);
  }
  if (p.startsWith('/library/metadata/')) {
    final id = int.tryParse(parts[3]) ?? 1;
    final sub = parts.length > 4 ? parts[4] : '';
    final isShow = id > 200 && id <= 230;
    final isSeason = id > 20000 && id < 24000;
    if (sub == '') return _plex([isShow ? show(id) : isSeason ? season(id ~/ 100, id % 100) : id > 2000000 ? episode(id ~/ 10000, id % 10000 ~/ 100, id % 100) : movie(id)]);
    if (sub == 'children') {
      if (isShow) return _plex([for (var n = 1; n <= 3; n++) season(id, n)]);
      if (isSeason) return _plex([for (var e = 1; e <= 8; e++) episode(id ~/ 100, id % 100, e)]);
    }
    if (sub == 'allLeaves' && isShow) return _plex([for (var n = 1; n <= 3; n++) for (var e = 1; e <= 8; e++) episode(id, n, e)]);
    if (sub == 'related') {
      return _plex(const [], hubs: [
        {'title': 'More Like This', 'Metadata': [for (var i = 1; i <= 14; i++) movie(i + 40)]},
      ]);
    }
  }
  return _plex(const []);
});

/// A collection pack: "Saturday Block" (3 shows you have, 20 you don't, rated from high to
/// low) and "Test Network" (12 you have).
String fakePackJson() => jsonEncode({
  'format': 1,
  'built': '2026-11-06T00:00:00Z',
  'credits': 'Test data.',
  'shows': [
    for (var i = 201; i <= 215; i++) {'t': 'Show $i', 'tm': i, 'r': 7.0, 'w': 50},
    for (var i = 0; i < 20; i++) {'t': 'Missing $i', 'tm': 900 + i, 'y': 2000 + i, 'r': 9.0 - i * 0.1, 'w': 80},
  ],
  'collections': [
    {'id': 'saturday', 'kind': 'block', 'name': 'Saturday Block', 'years': '1998–2004', 'about': 'Cartoons on Saturday.', 'shows': [0, 1, 2, for (var i = 15; i < 35; i++) i]},
    {'id': 'testnet', 'kind': 'network', 'name': 'Test Network', 'shows': [for (var i = 3; i < 15; i++) i]},
  ],
});

TvPackStore fakeTvPack() => TvPackStore(bundled: () async => fakePackJson(), client: MockClient((_) async => http.Response('', 404)), folder: () async => throw UnsupportedError('no disk in widget tests'));

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

/// The app as a TV lays it out (1920x1080 at 2x, drawn on the 1440-wide canvas), on Home with
/// everything loaded. Run with CONSOLE_TV=1 for the TV's own behaviour too (focus on arrival,
/// the rail hidden until Left); without it the shell behaves as on a desktop.
/// [tvNetworks] false is the Samsung or Apple store build (no TV Networks page or pack sources);
/// [brandRows] false is the Apple one (no streaming-service rows on Trending).
Future<AppState> tvApp(WidgetTester t, {int settle = 60, void Function(AppState)? before, bool tvNetworks = true, bool brandRows = true}) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final state = AppState(SettingsStore(secrets: _NoSecrets()), channels: ChannelStore(disk: false), tvPack: fakeTvPack(), tvNetworks: tvNetworks, brandRows: brandRows)
    ..settings = const Settings(clientId: 'c', plexUrl: 'http://plex.test:32400', plexToken: 'tok', seerrUrl: 'http://seerr.test', seerrApiKey: 'key', seerrEnabled: true)
    ..plex = PlexClient(baseUrl: 'http://plex.test:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: fakeServers()))
    ..seerr = SeerrClient(baseUrl: 'http://seerr.test', apiKey: 'key', http: JsonHttp(client: fakeServers()))
    ..plexConn = Conn.ok
    ..seerrConn = Conn.ok
    ..server = PlexServerInfo(name: 'Homeserver', version: '1.42', machineIdentifier: 'm')
    ..sections = [PlexSection(key: '1', title: 'Movies', type: 'movie'), PlexSection(key: '2', title: 'TV Shows', type: 'show')]
    ..loaded = true;
  before?.call(state);
  await t.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        theme: ConsoleTheme.dark(),
        darkTheme: ConsoleTheme.dark(),
        themeMode: ThemeMode.dark,
        navigatorObservers: [rootRoutes, rootStack],
        builder: (context, child) => FocusTraversalGroup(policy: TvTraversalPolicy(), child: TvCanvas(child: child!)),
        home: const Shell(),
      ),
    ),
  );
  for (var i = 0; i < settle; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  return state;
}

/// A readable name for a focus node: a card's title and row, or a button's label.
String label(FocusNode? n) {
  if (n == null) return 'none';
  if (n.debugLabel != null) return n.debugLabel!;
  final ctx = n.context;
  if (ctx == null || !ctx.mounted) return '${n.runtimeType}(unmounted)';
  final card = ctx.findAncestorWidgetOfExactType<PosterCard>();
  if (card != null) {
    final r = n.rect;
    return '${card.title} [${ctx.findAncestorWidgetOfExactType<Shelf>()?.title}] @${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()}';
  }
  final s = ctx.findAncestorWidgetOfExactType<Focusable>()?.semanticLabel ?? ctx.findAncestorWidgetOfExactType<Semantics>()?.properties.label;
  return s ?? n.runtimeType.toString();
}

String focused() => label(FocusManager.instance.primaryFocus);

/// A remote press: key down and up, then frames as they come.
Future<void> press(WidgetTester t, LogicalKeyboardKey k, {Duration wait = const Duration(milliseconds: 600)}) async {
  // The remote's Back has no Android key code in the simulator (back_key_test does the same).
  final back = k == LogicalKeyboardKey.goBack;
  await t.sendKeyEvent(k, physicalKey: back ? PhysicalKeyboardKey.browserBack : null, platform: back ? 'web' : 'android');
  for (var ms = 0; ms < wait.inMilliseconds; ms += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// Why [n] is a D-pad stop nobody can see, or null when it's a fair one.
String? hiddenStop(FocusNode n) {
  final ctx = n.context;
  if (ctx == null || !ctx.mounted) return null;
  final ro = ctx.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize || ro.size.isEmpty) return null;
  for (RenderObject? r = ro; r != null; r = r.parent) {
    if (r is RenderOpacity && r.opacity == 0) return 'opacity 0';
    if (r is RenderAnimatedOpacity && r.opacity.value == 0) return 'animated opacity 0';
    if (r is RenderSliverOpacity && r.opacity == 0) return 'sliver opacity 0';
    if (r is RenderOffstage && r.offstage) return 'offstage';
  }
  return null;
}

/// Every control in [scope] (the whole app by default) that takes focus while nobody can see it.
List<String> hiddenStops([FocusScopeNode? scope]) => [
  for (final n in (scope ?? FocusManager.instance.rootScope).traversalDescendants)
    if (n is! FocusScopeNode && hiddenStop(n) != null) '${label(n)}: ${hiddenStop(n)}',
];

/// Pairs of moves that should undo each other, tried from every visible control on the page.
/// Reports moves that don't come back, and moves that end on a control off the screen.
Future<List<String>> walk(WidgetTester t, {int limit = 80, Size screen = const Size(960, 540)}) async {
  final page = FocusManager.instance.primaryFocus?.nearestScope;
  if (page == null) return ['nothing has focus'];
  final nodes = [
    for (final n in page.traversalDescendants)
      if (n is! FocusScopeNode && n.context?.mounted == true && !n.rect.isEmpty && hiddenStop(n) == null) n,
  ];
  final out = <String>[];
  const pairs = [
    (LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft),
    (LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight),
    (LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp),
  ];
  var tried = 0;
  for (final n in nodes) {
    if (tried++ >= limit) break;
    for (final (go, back) in pairs) {
      if (n.context?.mounted != true) continue;
      n.requestFocus();
      // A key first, so focus shows (and scrolls) as it does on a remote.
      await press(t, LogicalKeyboardKey.shiftLeft, wait: const Duration(milliseconds: 300));
      final from = label(n);
      if (FocusManager.instance.primaryFocus != n) continue;
      await press(t, go, wait: const Duration(milliseconds: 300));
      final m = FocusManager.instance.primaryFocus;
      if (m == null || m == n) continue;
      final to = label(m);
      final r = m.rect;
      if (hiddenStop(m) != null) out.add('$from -${go.keyLabel}-> $to: lands on a hidden control');
      if (r.bottom < 0 || r.top > screen.height || r.right < 0 || r.left > screen.width) out.add('$from -${go.keyLabel}-> $to: lands off screen ${r.left.round()},${r.top.round()}');
      // Off the page (the rail, search) has its own rules.
      if (m.nearestScope != page) continue;
      await press(t, back, wait: const Duration(milliseconds: 300));
      final b = FocusManager.instance.primaryFocus;
      if (b != n) out.add('$from -${go.keyLabel}-> $to -${back.keyLabel}-> ${label(b)}');
    }
  }
  return out;
}
