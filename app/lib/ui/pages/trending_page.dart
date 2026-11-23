import 'dart:async';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../common.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../home/rows.dart';
import '../seerr_card.dart';

/// What's popular right now: Netflix's own Top 10, what's popular on each streaming
/// service, then one row per genre (Trakt's live charts when set up, else TMDB's daily
/// popularity). Titles you have open in the library; the rest can be requested.
class TrendingPage extends StatefulWidget {
  const TrendingPage({super.key});
  @override
  State<TrendingPage> createState() => _TrendingPageState();
}

class _TrendingPageState extends State<TrendingPage> {
  final _genres = <String, List<SeerrResult>>{};
  final _services = <String, List<SeerrResult>>{};
  final _netflix = <String, List<SeerrResult>>{}; // movie / tv
  final _resolved = <String, Future<SeerrResult?>>{};
  final _gate = _Gate(6);
  LibraryIndex _library = LibraryIndex(const []);
  String _kind = 'all';
  bool _started = false;

  /// Genre rows that couldn't load; when all of them fail the page says so.
  int _genresFailed = 0;
  bool _fromTrakt = false;
  BackdropController? _backdrop;

  @override
  void dispose() {
    final b = _backdrop;
    scheduleMicrotask(() => b?.clear(this));
    super.dispose();
  }

  Future<SeerrResult?> _resolve(SeerrClient seerr, ChartTitle t) => _resolved.putIfAbsent('${t.mediaType}:${t.tmdbId ?? t.title}', () => _gate.run(() => seerr.resolve(t)));

  Future<List<SeerrResult>> _resolveAll(SeerrClient seerr, List<ChartTitle> titles) async => [for (final r in await Future.wait(titles.map((t) => _resolve(seerr, t)))) ?r];

  void _load() {
    final app = AppScope.read(context);
    final seerr = app.seerr;
    if (seerr == null) return;
    _backdrop = BackdropScope.maybeOf(context);
    if (app.plex != null) {
      unawaited(
        app.library().then((l) {
          if (mounted) setState(() => _library = l.index);
        }, onError: (Object _) {}),
      );
    }

    // Netflix's official weekly Top 10, matched to titles by name. Not in the App Store build
    // (AppState.brandRows), nor the per-service rows below.
    if (app.brandRows) {
      unawaited(() async {
        try {
          final tsv = await NetflixTop10.fetch(from: Platform.environment['CONSOLE_NETFLIX_TOP10']);
          for (final kind in ['movie', 'tv']) {
            final list = await _resolveAll(seerr, NetflixTop10.parse(tsv, kind).take(10).toList());
            if (mounted) setState(() => _netflix[kind] = list);
          }
        } catch (e) {
          debugPrint('netflix top 10: $e');
        }
      }());

      // What's popular on each service where you live.
      for (final s in streamingServices) {
        Future.wait([seerr.popularOn('movie', s.provider, region: app.settings.region), seerr.popularOn('tv', s.provider, region: app.settings.region)]).then((r) {
          if (mounted) setState(() => _services[s.name] = mergeByPopularity(r[0], r[1], count: 40));
        }, onError: (Object e) => debugPrint('popular on ${s.name}: $e'));
      }
    }

    // Genre rows: Trakt when there's a client ID, falling back to TMDB per row.
    final trakt = app.trakt;
    _fromTrakt = trakt != null;
    for (final g in trendingGenres) {
      () async {
        List<SeerrResult>? items;
        if (trakt != null) {
          try {
            final slug = TraktClient.genreSlugs[g.name];
            final r = await Future.wait([trakt.trending('movie', genres: slug, limit: 12), trakt.trending('tv', genres: slug, limit: 12)]);
            final charts = [...r[0], ...r[1]]..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
            items = await _resolveAll(seerr, charts);
          } catch (e) {
            debugPrint('trakt ${g.name}: $e');
          }
        }
        if (items == null || items.isEmpty) {
          try {
            final r = await Future.wait([
              if (g.movie != null) seerr.popularInGenre('movie', g.movie!) else Future.value(const <SeerrResult>[]),
              if (g.tv != null) seerr.popularInGenre('tv', g.tv!) else Future.value(const <SeerrResult>[]),
            ]);
            items = mergeByPopularity(r[0], r[1], count: 40);
          } catch (e) {
            debugPrint('genre ${g.name}: $e');
            if (mounted) setState(() => _genresFailed++);
            return;
          }
        }
        if (!mounted) return;
        setState(() => _genres[g.name] = items!);
        if (g == trendingGenres.first && items.isNotEmpty) _backdrop?.set(this, items.first.backdropUrl());
      }();
    }
  }

  List<SeerrResult> _filter(List<SeerrResult> items, {int take = 20}) => items.where((r) => _kind == 'all' || r.mediaType == _kind).take(take).toList();

  Widget _shelf(String title, List<SeerrResult> items) => Shelf(
    key: ValueKey('$title:$_kind'),
    title: title,
    inset: 48,
    children: [for (final r in items) SeerrCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r, plexKey: _library.ratingKeyFor(r))],
  );

  Widget _heading(String title, String note) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(ConsoleDensity.inset(context), Space.space10, ConsoleDensity.inset(context), Space.space4),
      child: HeaderRow(
        children: [
          Text(
            title,
            style: ConsoleText.display.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: c.text100),
          ),
          const SizedBox(width: Space.space3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(note, style: ConsoleText.caption.copyWith(color: c.text300)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    if (app.seerrConn == Conn.off) {
      return const Padding(padding: EdgeInsets.all(Space.space6), child: ErrorNote('Connect Seerr in Settings to see what is trending.'));
    }
    if (app.seerrConn == Conn.failed) {
      return Padding(padding: const EdgeInsets.all(Space.space6), child: ErrorNote('Couldn’t reach Seerr${app.seerrError == null ? '' : ': ${app.seerrError}'}'));
    }
    if (!_started && app.seerrConn == Conn.ok) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    Widget gap() => const SizedBox(height: Space.space8);
    final netflix = [
      for (final (kind, label) in [('movie', 'Top 10 Movies on Netflix'), ('tv', 'Top 10 Series on Netflix')])
        if ((_kind == 'all' || _kind == kind) && (_netflix[kind]?.length ?? 0) >= 3) (label, _netflix[kind]!),
    ];
    final services = [
      for (final s in streamingServices)
        if (_services[s.name] case final items?)
          if (_filter(items) case final shown when shown.length >= 4) ('Popular on ${s.name}', shown),
    ];
    final genres = [
      for (final g in trendingGenres)
        if (_genres[g.name] case final items?)
          if (_filter(items) case final shown when shown.length >= 4) (g.name, shown),
    ];

    // A lazy list: rows below the fold (and their posters) load as you scroll to them.
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.space10),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(ConsoleDensity.inset(context), Space.space4, ConsoleDensity.inset(context), 0),
          child: HeaderRow(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trending',
                      style: ConsoleText.display.copyWith(fontSize: ConsoleDensity.compactOf(context) ? 30 : 40, height: 1.1, fontWeight: FontWeight.w800, color: c.text100),
                    ),
                    const SizedBox(height: Space.space1),
                    Text("What people are watching right now. Anything you don't have can be requested here.", style: ConsoleText.body.copyWith(color: c.text200)),
                  ],
                ),
              ),
              ConsoleSegmented<String>(options: const [('all', 'All'), ('movie', 'Movies'), ('tv', 'Series')], value: _kind, onChanged: (k) => setState(() => _kind = k)),
            ],
          ),
        ),
        if (netflix.isNotEmpty || services.isNotEmpty) ...[
          _heading('On Streaming', 'Netflix Top 10 from Netflix, updated weekly. Streaming availability from JustWatch via TMDB, updated daily (${app.settings.region}).'),
          for (final (i, (label, items)) in netflix.indexed) ...[
            if (i > 0) gap(),
            DistinctTints(
              urls: [for (final r in items) r.posterUrl()],
              child: Shelf(
                key: ValueKey('$label:$_kind'),
                title: label,
                itemWidth: null,
                spacing: Space.space6,
                inset: 48,
                children: [for (final (n, r) in items.indexed) RankedPoster.seerr(context, rank: n + 1, item: r, plexKey: _library.ratingKeyFor(r))],
              ),
            ),
          ],
          for (final (i, (label, items)) in services.indexed) ...[if (i > 0 || netflix.isNotEmpty) gap(), _shelf(label, items)],
        ],
        _heading('By Genre', _fromTrakt ? 'Live from Trakt: what people are watching right now.' : "TMDB's popularity, updated daily. Add a Trakt Client ID in Settings for live charts."),
        if (genres.isEmpty && _genresFailed >= trendingGenres.length)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ConsoleDensity.inset(context)),
            child: ErrorNote('Couldn’t load the genre charts from Seerr.'),
          )
        else if (genres.isEmpty)
          const LoadingNote(label: 'Finding what people are watching'),
        for (final (i, (name, items)) in genres.indexed) ...[if (i > 0) gap(), _shelf(name, items)],
      ],
    );
  }
}

/// Runs at most [limit] lookups at once, so a page of charts doesn't flood Seerr.
class _Gate {
  _Gate(this.limit);
  final int limit;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= limit) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}
