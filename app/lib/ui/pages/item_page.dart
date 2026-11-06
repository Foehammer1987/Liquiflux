import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../services/links.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../detail/detail_view.dart';
import '../detail/episode_list.dart';
import '../detail/reviews.dart';
import '../nav.dart';
import '../play.dart';
import '../together/together_panel.dart';
import '../seerr_card.dart';
import 'player_page.dart';

/// A movie, show, season or episode that's in Plex.
class ItemPage extends StatefulWidget {
  const ItemPage({super.key, required this.ratingKey});
  final String ratingKey;
  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  PlexItem? _item;
  PlexItem? _show;
  List<PlexItem> _seasons = const [];
  String? _seasonKey;
  List<PlexItem>? _episodes;
  List<PlexItem> _extras = const [];
  List<({String title, List<PlexItem> items})> _related = const [];
  SeerrResult? _seerr;
  List<SeerrResult> _suggest = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// [refresh] is a return to the page (from the player, after marking watched): the
  /// season you were looking at stays put and the extras aren't fetched again.
  Future<void> _load({bool refresh = false}) async {
    final app = AppScope.read(context);
    final plex = app.plex!;
    if (_error != null) setState(() => _error = null);
    try {
      final item = await plex.metadata(widget.ratingKey, full: true);
      if (item == null) throw 'This title is no longer in Plex';
      final showKey = switch (item.type) {
        'episode' => item.grandparentRatingKey,
        'season' => item.parentRatingKey,
        _ => null,
      };
      final show = showKey != null ? await plex.metadata(showKey) : null;
      var seasons = <PlexItem>[];
      String? seasonKey;
      if (item.type == 'show') {
        seasons = await plex.children(item.ratingKey);
        final next = seasons.where((s) => (s.index ?? 0) > 0 && (s.viewedLeafCount ?? 0) < (s.leafCount ?? 0)).firstOrNull;
        seasonKey = (next ?? seasons.where((s) => (s.index ?? 0) > 0).firstOrNull ?? seasons.firstOrNull)?.ratingKey;
      } else if (item.type == 'season') {
        seasonKey = item.ratingKey;
        if (showKey != null) seasons = await plex.children(showKey);
      } else if (item.type == 'episode') {
        seasonKey = item.parentRatingKey;
        if (showKey != null) seasons = await plex.children(showKey);
      }
      if (!mounted) return;
      if (refresh && _seasonKey != null && seasons.any((s) => s.ratingKey == _seasonKey)) seasonKey = _seasonKey;
      setState(() {
        _item = item;
        _show = show;
        _seasons = seasons;
      });
      if (seasonKey != null) unawaited(_loadSeason(seasonKey, keep: refresh && seasonKey == _seasonKey));
      if (!refresh) unawaited(_loadExtras(item, show));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  /// Extras, related titles and Seerr suggestions load after the page is up.
  Future<void> _loadExtras(PlexItem item, PlexItem? show) async {
    final app = AppScope.read(context);
    final plex = app.plex!;
    final top = show ?? item;
    final extras = await plex.extras(top.ratingKey);
    final related = item.type == 'movie' || item.type == 'show' ? await plex.related(item.ratingKey) : const <({String title, List<PlexItem> items})>[];
    if (!mounted) return;
    setState(() {
      _extras = extras;
      _related = related;
    });
    final tmdb = top.tmdbId;
    if (app.seerrConn != Conn.ok || app.seerr == null || tmdb == null) return;
    final type = top.type == 'movie' ? 'movie' : 'tv';
    try {
      final results = await Future.wait([app.seerr!.details(type, tmdb), app.seerr!.recommendations(type, tmdb)]);
      if (!mounted) return;
      setState(() {
        _seerr = results[0] as SeerrResult;
        _suggest = (results[1] as List<SeerrResult>).where((r) => r.mediaInfo?.status != MediaStatus.available).take(20).toList();
      });
    } catch (_) {
      /* Seerr is optional here */
    }
  }

  /// [keep] leaves the current episodes showing while fresh ones load.
  Future<void> _loadSeason(String key, {bool keep = false}) async {
    setState(() {
      _seasonKey = key;
      if (!keep) _episodes = null;
    });
    final eps = await AppScope.read(context).plex!.children(key);
    if (mounted && _seasonKey == key) setState(() => _episodes = eps);
  }

  bool _starting = false;

  /// [choose] lets the resume setting decide (an episode's play button); the Resume and
  /// Play from Start buttons have already chosen.
  Future<void> _play(String ratingKey, {bool resume = true, bool choose = false}) async {
    // A double-click would otherwise open two players.
    if (_starting) return;
    _starting = true;
    try {
      final plex = AppScope.read(context).plex!;
      final full = await plex.metadata(ratingKey); // need Media/Part for direct play
      if (full == null || !mounted) return;
      await _playItem(full, resume: resume, choose: choose);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Couldn’t start playback: ${errorText(e)}')));
    } finally {
      _starting = false;
    }
  }

  Future<void> _playItem(PlexItem full, {bool resume = true, bool choose = false}) async {
    await openPlayer(context, (_) => PlayerPage(item: full, resume: resume, choose: choose));
    if (mounted) unawaited(_load(refresh: true)); // refresh watch state
  }

  Future<void> _toggleWatched(PlexItem item, bool watched) async {
    final app = AppScope.read(context);
    final plex = app.plex!;
    watched ? await plex.markUnwatched(item) : await plex.markWatched(item);
    // Marked watched by hand: Trakt's history and AniList hear about it too.
    if (!watched) unawaited(app.scrobbler.markedWatched(plex, item, server: app.server?.machineIdentifier ?? ''));
    if (mounted) unawaited(_load(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_error != null) return PageBody(children: [ErrorNote(_error!, onRetry: () => _load())]);
    final item = _item;
    if (item == null) return const PageBody(children: [LoadingNote()]);

    final plex = app.plex!;
    final base = TitleDetail.fromPlex(
      item,
      show: _show,
      image: (p, w, h) => plex.imageUrl(p, width: w, height: h),
    );
    final plexExtras = [for (final e in _extras) Extra(title: e.title, kind: extraKind(e.subtype), imageUrl: plex.imageUrl(e.thumb, width: 480, height: 270), durationMs: e.duration, plexItem: e)];
    // Plex has no trailers? Fall back to the ones Seerr (TMDB) lists.
    final extras = plexExtras.isNotEmpty ? plexExtras : (_seerr != null ? seerrExtras(_seerr!) : const <Extra>[]);
    final spoilers = app.settings.spoilers;
    final detail = base.copyWith(
      extras: extras,
      tagline: item.type == 'movie' || item.type == 'show' ? (base.tagline ?? _seerr?.tagline) : null,
      subtitle: spoilers.hideTitle(item) ? spoilers.titleOf(item) : null,
    );

    final next = _episodes?.where((e) => !e.isWatched).firstOrNull ?? _episodes?.firstOrNull;
    final playTarget = item.isPlayable ? item : next;
    final resumeMs = playTarget?.viewOffset ?? 0;
    final playLabel = resumeMs > 0
        ? (item.isPlayable ? 'Resume' : 'Resume ${next!.episodeCode}')
        : item.isPlayable
        ? 'Play'
        : next != null
        ? 'Play ${next.episodeCode}'
        : 'Play';
    final watched = item.isPlayable ? item.isWatched : (item.leafCount != null && item.leafCount! > 0 && item.viewedLeafCount == item.leafCount);
    final trailer = _extras.where((e) => e.subtype == 'trailer').firstOrNull;
    final webTrailer = trailer == null ? extras.where((e) => e.url != null && e.kind == 'Trailer').firstOrNull : null;
    final left = item.isPlayable && resumeMs > 0 && item.duration != null ? '${formatDuration(item.duration! - resumeMs)} left' : null;

    final actions = <Widget>[
      if (playTarget != null) ConsoleButton(label: playLabel, icon: LucideIcons.play, kind: ButtonKind.primary, size: ButtonSize.lg, autofocus: true, onPressed: () => _play(playTarget.ratingKey)),
      if (resumeMs > 0 && playTarget != null)
        ConsoleButton(label: 'Play from Start', icon: LucideIcons.rotateCcw, size: ButtonSize.lg, iconOnly: true, onPressed: () => _play(playTarget.ratingKey, resume: false)),
      if (playTarget != null)
        ConsoleButton(
          label: 'Watch Together',
          icon: LucideIcons.usersRound,
          size: ButtonSize.lg,
          iconOnly: true,
          onPressed: () async {
            final full = await plex.metadata(playTarget.ratingKey);
            if (full != null && context.mounted) await showTogether(context, full);
            if (mounted) unawaited(_load(refresh: true));
          },
        ),
      if (trailer != null) ConsoleButton(label: 'Play Trailer', icon: LucideIcons.clapperboard, size: ButtonSize.lg, iconOnly: true, onPressed: () => _playItem(trailer, resume: false)),
      if (webTrailer != null && canOpenLinks) ConsoleButton(label: 'Watch Trailer', icon: LucideIcons.clapperboard, size: ButtonSize.lg, iconOnly: true, onPressed: () => openExternal(webTrailer.url)),
      ConsoleButton(
        label: watched ? 'Mark as Unwatched' : 'Mark as Watched',
        icon: watched ? LucideIcons.checkCheck : LucideIcons.check,
        size: ButtonSize.lg,
        iconOnly: true,
        onPressed: () => _toggleWatched(item, watched),
      ),
      if (app.server != null && canOpenLinks)
        ConsoleButton(
          label: 'Open in Plex',
          icon: LucideIcons.externalLink,
          size: ButtonSize.lg,
          iconOnly: true,
          onPressed: () => openExternal(plex.webUrl(app.server!.machineIdentifier, item.ratingKey)),
        ),
    ];

    final seasonChoices = [for (final s in _seasons) (s.ratingKey, s.index == 0 ? 'Specials' : 'Season ${s.index}')];
    final episodes = item.type == 'movie'
        ? null
        : ConsolePanel(
            title: item.type == 'episode' ? 'More Episodes' : 'Episodes',
            meta: _episodes != null ? muted(context, '${_episodes!.length}') : null,
            trailing: seasonChoices.length > 1 ? ConsoleSegmented<String>(options: seasonChoices, value: _seasonKey ?? '', onChanged: _loadSeason) : null,
            child: _episodes == null
                ? const LoadingNote()
                : EpisodeList(
                    episodes: _episodes!,
                    current: item.type == 'episode' ? item.ratingKey : null,
                    spoilers: spoilers,
                    imageUrl: (e) => plex.imageUrl(e.thumb, width: 320, height: 180),
                    onOpen: (e) => ShellNav.of(context).push(ItemDest(e.ratingKey)),
                    onPlay: (e) => _play(e.ratingKey, choose: true),
                  ),
          );

    return TitleDetailView(
      detail: detail,
      actions: actions,
      artProgress: item.isPlayable ? item.watchProgress : null,
      blurArt: spoilers.hideImage(item),
      hideSummary: spoilers.hideSummary(item),
      artCaption: left,
      onPlayExtra: (e) => _playItem(e, resume: false),
      // A season is its episodes; elsewhere Cast & Crew comes first, as in Plex.
      sections: [if (item.type == 'season') ?episodes],
      moreSections: [
        if (item.type != 'season') ?episodes,
        if (item.reviews.isNotEmpty)
          ConsolePanel(
            title: 'Reviews',
            meta: muted(context, '${item.reviews.length}'),
            child: ReviewRow(reviews: item.reviews),
          ),
        for (final hub in _related.take(2))
          ConsolePanel(
            title: hub.title,
            padding: const EdgeInsets.fromLTRB(Space.space2, Space.space2, Space.space2, Space.space3),
            child: PosterRow(children: [for (final r in hub.items) PlexPoster(item: r)]),
          ),
        if (_suggest.isNotEmpty)
          ConsolePanel(
            title: 'Not in Your Library',
            meta: muted(context, 'Similar titles you can request'),
            padding: const EdgeInsets.fromLTRB(Space.space2, Space.space2, Space.space2, Space.space3),
            child: PosterRow(
              children: [for (final r in _suggest) SeerrCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r)],
            ),
          ),
      ],
    );
  }
}
