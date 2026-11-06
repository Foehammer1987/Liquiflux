import 'dart:async';
import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../platform.dart';
import '../../services/probe.dart';
import '../../services/trailers.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../home/rows.dart';
import '../home/spotlight.dart';
import '../home/taste_rows.dart';
import '../nav.dart';
import '../seerr_card.dart';
import '../play.dart';
import '../player/player_dock.dart';

/// Netflix-style Home: a full-bleed spotlight of well-rated titles with trailer clips,
/// then rows. Pointing at any title in a row previews it in the spotlight.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  final _preview = ValueNotifier<PlexItem?>(null);
  final _scroll = ScrollController();
  Trailers? _trailers;
  List<PlexItem> _spot = const [];
  List<PlexItem> _top = const [];
  List<PlexItem> _mostWatched = const [];
  DateTime? _mostWatchedAt;
  List<PlexItem>? _onDeck;
  List<PlexItem>? _recent;
  List<PlexItem> _pool = const [];
  List<PlexItem> _all = const [];
  List<MoodRow> _moods = const [];
  List<SeerrResult> _trending = const [];
  List<SeerrResult> _missing = const [];
  LibraryIndex? _library;
  bool _rerolling = false;
  bool _covered = false;
  bool _started = false;
  bool _seerrStarted = false;
  bool _heroOnScreen = true;
  Timer? _refresh;
  ModalRoute<void>? _route;

  /// The player (or anything else) open over the whole shell, however it was started.
  bool _rootCovered = false;
  late final _rootCover = RouteCover((on) {
    if (!mounted) return;
    setState(() => _rootCovered = on);
    if (!on) _loadRows();
  });
  ModalRoute<dynamic>? _rootRoute;
  final _rng = Random();

  /// On a desktop the player has its own layer (see [PlayerDock]), so it doesn't cover Home
  /// as a page would: no trailers while it's open, even when it's in its corner.
  bool get _dockBusy => PlayerDock.enabled && PlayerDock.instance.active;
  bool _wasDockFull = false;

  void _dockChanged() {
    if (!mounted) return;
    final dock = PlayerDock.instance;
    final full = dock.active && !dock.mini;
    setState(() {});
    // Back from a full-window player (closed or in its corner): progress has moved on.
    if (_wasDockFull && !full) _loadRows();
    _wasDockFull = full;
  }

  @override
  void initState() {
    super.initState();
    if (PlayerDock.enabled) PlayerDock.instance.addListener(_dockChanged);
    _scroll.addListener(_onScroll);
    // Not while covered: coming back reloads anyway.
    _refresh = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_covered && !_rootCovered && !(_dockBusy && !PlayerDock.instance.mini)) _loadRows();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (r != _route && r is ModalRoute<void>) {
      if (_route != null) pageRoutes.unsubscribe(this);
      _route = r;
      pageRoutes.subscribe(this, r);
    }
    // The route holding the shell's own navigator, on the app's top-level one.
    final root = ModalRoute.of(Navigator.of(context).context);
    if (root != null && root != _rootRoute) {
      if (_rootRoute != null) rootRoutes.unsubscribe(_rootCover);
      _rootRoute = root;
      rootRoutes.subscribe(_rootCover, root);
    }
  }

  @override
  void dispose() {
    pageRoutes.unsubscribe(this);
    rootRoutes.unsubscribe(_rootCover);
    if (PlayerDock.enabled) PlayerDock.instance.removeListener(_dockChanged);
    _refresh?.cancel();
    _scroll.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  void didPushNext() => setState(() => _covered = true);

  @override
  void didPopNext() {
    setState(() => _covered = false);
    _loadRows();
  }

  void _onScroll() {
    final on = _scroll.offset < 260;
    if (on != _heroOnScreen) setState(() => _heroOnScreen = on);
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final plex = app.plex;
    if (plex == null) return;
    unawaited(_loadRows());
    // The best-rated titles in every library feed the spotlight and Top 10; mood rows draw on all of it.
    try {
      // Whole libraries, best-rated first, with TMDB ids so "Not in Your Library" can check against them.
      final lib = await app.library();
      final pool = [for (final l in lib.bySection) ...l.take(80)];
      final library = lib.index;
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _all = [for (final l in lib.bySection) ...l];
        _library = library;
      });
      if (_seerrStarted) unawaited(_loadSeerrRows());
      await _reroll();
      _pickMoods();
    } catch (e) {
      debugPrint('home: $e');
    }
  }

  /// A fresh spotlight, steering clear of the titles showing now.
  Future<void> _reroll() async {
    final plex = AppScope.read(context).plex;
    if (plex == null || _rerolling) return;
    final picks = pickSpotlights([..._pool, ...?_recent], count: 7, random: _rng, avoid: {for (final s in _spot) s.ratingKey});
    if (picks.isEmpty) return;
    setState(() => _rerolling = true);
    // Full metadata adds the clear logo and every rating.
    final full = await Future.wait(picks.map((p) => plex.metadata(p.ratingKey).catchError((Object _) => null)));
    if (!mounted) return;
    setState(() {
      _spot = [for (var i = 0; i < picks.length; i++) full[i] ?? picks[i]];
      // Top in Your Library re-rolls with it and never repeats a spotlight title.
      _top = pickTop(_pool, avoid: {for (final s in _spot) s.ratingKey}, random: _rng);
      _rerolling = false;
    });
  }

  /// Four mood rows, different from the last visit's where the library allows, and clear of
  /// the spotlight and Top 10 titles.
  void _pickMoods() {
    if (!mounted || _all.isEmpty) return;
    final picked = homeMoods(_all, random: _rng, recent: _lastMoods, avoid: {for (final t in [..._spot, ..._top, ..._mostWatched]) t.ratingKey});
    _lastMoods = {for (final m in picked) m.name};
    setState(() => _moods = picked);
  }

  /// Trending and Top 10 Not in Your Library, both checked against what Plex has.
  Future<void> _loadSeerrRows() async {
    final seerr = AppScope.read(context).seerr;
    final library = _library;
    if (seerr == null || library == null) return;
    try {
      final r = await Future.wait([seerr.trending(), seerr.topRated('movie'), seerr.topRated('tv')]);
      if (!mounted) return;
      setState(() {
        _trending = r[0].where((t) => !library.owns(t)).take(20).toList();
        _missing = topMissing([...r[1], ...r[2]], library);
      });
    } catch (e) {
      debugPrint('home seerr rows: $e');
    }
  }

  Future<void> _loadRows() async {
    final plex = AppScope.read(context).plex;
    if (plex == null) return;
    try {
      final r = await Future.wait([plex.onDeck(size: 20), plex.recentlyAdded(size: 30)]);
      if (mounted) {
        setState(() {
          _onDeck = r[0];
          _recent = r[1];
        });
      }
    } catch (e) {
      debugPrint('home rows: $e');
    }
    unawaited(_loadMostWatched());
  }

  /// "Top 10 on" plus the server name: what every account on the server watched most this week (the last
  /// 30 days when the week is quiet). Rankings move slowly, so at most every 10 minutes.
  Future<void> _loadMostWatched() async {
    final plex = AppScope.read(context).plex;
    final at = _mostWatchedAt;
    if (plex == null || (at != null && DateTime.now().difference(at) < const Duration(minutes: 10))) return;
    _mostWatchedAt = DateTime.now();
    try {
      var keys = mostWatched(await plex.history(since: DateTime.now().subtract(const Duration(days: 7))));
      if (keys.length < 5) keys = mostWatched(await plex.history(since: DateTime.now().subtract(const Duration(days: 30))));
      // Full metadata for the art and rating; a title deleted since it was watched drops out.
      final items = await Future.wait(keys.map((k) => plex.metadata(k).catchError((Object _) => null)));
      if (!mounted) return;
      setState(() {
        _mostWatched = items.nonNulls.toList();
        // The mood rows may have been picked first: they don't repeat a Top 10 title either.
        final top = {for (final t in _mostWatched) t.ratingKey};
        _moods = [for (final m in _moods) (name: m.name, items: [for (final i in m.items) if (!top.contains(i.ratingKey)) i])];
      });
    } catch (e) {
      // Only the server's owner can read its history; the best-rated row stays instead.
      debugPrint('home most watched: $e');
    }
  }

  /// Movies and episodes play straight away; a show plays its next episode.
  Future<void> _play(PlexItem item) async {
    setState(() => _covered = true);
    await playTitle(context, item);
    if (!mounted) return;
    setState(() => _covered = false);
    _loadRows();
  }

  void _info(PlexItem item) => ShellNav.of(context).push(ItemDest(item.ratingKey));

  void Function(bool) _hoverFor(PlexItem item) => (on) {
    if (on) {
      _preview.value = item;
    } else if (_preview.value == item) {
      _preview.value = null;
    }
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final plex = app.plex;
    if (plex == null) return const SizedBox();
    // Start once Plex (and later Seerr) report in; Home can open before they do.
    if (!_started && app.plexConn == Conn.ok) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (!_seerrStarted && app.seerrConn == Conn.ok) {
      _seerrStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSeerrRows());
    }
    final seerrOk = app.seerrConn == Conn.ok;
    if (_trailers == null || _trailers!.plex != plex || (_trailers!.seerr == null) == seerrOk) {
      _trailers = Trailers(plex: plex, seerr: seerrOk ? app.seerr : null);
    }

    return LayoutBuilder(
      builder: (context, box) {
        final heroH = (box.maxHeight * 0.74).clamp(440.0, 820.0).roundToDouble();
        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: Space.space10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Spotlight(
                items: _spot,
                preview: _preview,
                height: heroH,
                active: !_covered && !_rootCovered && !_dockBusy && _heroOnScreen,
                plex: plex,
                trailers: _trailers!,
                trailersOn: trailersSupported && (homeTrailersSupported ? app.settings.homeTrailers : app.settings.spotlightTrailers || Probe.has('trailers')),
                focusOnly: !homeTrailersSupported,
                onPlay: _play,
                onInfo: _info,
                onReroll: _reroll,
                rerolling: _rerolling,
              ),
              // Rows ride up over the bottom of the spotlight.
              Transform.translate(
                offset: Offset(0, -heroH * 0.14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_onDeck?.isNotEmpty ?? false)
                      Shelf(
                        title: 'Continue Watching',
                        itemWidth: 340,
                        children: [for (final i in _onDeck!) PlexPoster(item: i, wide: true, onHighlight: _hoverFor(i))],
                      ),
                    // Top 10 on the server takes the ranked slot when there's enough watching to rank.
                    if (_mostWatched.length >= 5) ...[
                      const SizedBox(height: Space.space8),
                      DistinctTints(
                        urls: [for (final t in _mostWatched) app.plex?.imageUrl(t.posterPath, width: 240, height: 360)],
                        child: Shelf(
                          key: ValueKey(_mostWatched.map((t) => t.ratingKey).join()),
                          title: 'Top 10 on ${app.server?.name ?? 'Your Server'}',
                          itemWidth: null,
                          spacing: Space.space6,
                          children: [for (final (i, t) in _mostWatched.indexed) RankedPoster.plex(context, rank: i + 1, item: t, onHighlight: _hoverFor(t))],
                        ),
                      ),
                    ] else if (_top.length >= 5) ...[
                      // Keyed by the set so a re-roll scrolls back to the start.
                      const SizedBox(height: Space.space8),
                      // Each number gets its own colour from its poster, clearly apart from its neighbours.
                      DistinctTints(
                        urls: [for (final t in _top) app.plex?.imageUrl(t.posterPath, width: 240, height: 360)],
                        child: Shelf(
                          key: ValueKey(_top.map((t) => t.ratingKey).join()),
                          title: 'Top in Your Library',
                          itemWidth: null,
                          spacing: Space.space6,
                          children: [for (final (i, t) in _top.indexed) RankedPoster.plex(context, rank: i + 1, item: t, onHighlight: _hoverFor(t))],
                        ),
                      ),
                    ],
                    if (_missing.length >= 5) ...[
                      const SizedBox(height: Space.space8),
                      DistinctTints(
                        urls: [for (final t in _missing) t.posterUrl()],
                        child: Shelf(
                          title: 'Top 10 Not in Your Library',
                          itemWidth: null,
                          spacing: Space.space6,
                          children: [for (final (i, t) in _missing.indexed) RankedPoster.seerr(context, rank: i + 1, item: t)],
                        ),
                      ),
                    ],
                    // Because You Watched… (sits out until Seerr and your history are in).
                    TasteRows(onHighlight: (item, on) => _hoverFor(item)(on)),
                    if (_recent?.isNotEmpty ?? false) ...[
                      const SizedBox(height: Space.space8),
                      Shelf(
                        title: 'Recently Added',
                        children: [for (final i in _recent!) PlexPoster(item: i, onHighlight: _hoverFor(i))],
                      ),
                    ],
                    // Feel-Good Comedies, Dark Sci-Fi… (more on the Moods page).
                    for (final m in _moods) ...[
                      const SizedBox(height: Space.space8),
                      Shelf(
                        key: ValueKey(m.name),
                        title: m.name,
                        children: [for (final i in m.items) PlexPoster(item: i, onHighlight: _hoverFor(i))],
                      ),
                    ],
                    if (_trending.isNotEmpty) ...[
                      const SizedBox(height: Space.space8),
                      Shelf(
                        title: 'Trending, Not in Your Library',
                        children: [for (final r in _trending) SeerrCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r)],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The mood rows Home showed last, so the next visit picks others.
Set<String> _lastMoods = const {};
