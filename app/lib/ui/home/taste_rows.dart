import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../platform.dart';
import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../nav.dart';

/// "Because You Watched…" rows: TMDB's recommendations for what you played lately and what
/// you gave a thumbs up, without what you've seen or turned down. Thumbs on every card tune
/// them: down hides a title for good, up makes it a starting point of its own.
class TasteRows extends StatefulWidget {
  const TasteRows({super.key, this.onHighlight});

  /// Called with a Plex item when you point at a title you have (Home previews it).
  final void Function(PlexItem item, bool on)? onHighlight;

  @override
  State<TasteRows> createState() => _TasteRowsState();
}

class _TasteRowsState extends State<TasteRows> {
  List<TasteSeed> _watched = const [];
  final _recs = <String, List<SeerrResult>>{};
  LibraryIndex? _index;
  Map<String, PlexItem> _byKey = const {};
  Taste? _builtFor;
  List<BecauseRow> _rows = const [];
  bool _started = false;

  Future<void> _load() async {
    final app = AppScope.read(context);
    final plex = app.plex;
    if (plex == null) return;
    try {
      final lib = await app.library();
      final lists = await Future.wait([for (final s in app.sections) plex.recentlyWatched(s.key, size: 8).catchError((Object _) => const <PlexItem>[])]);
      final recent = [for (final l in lists) ...l]..sort((a, b) => (b.lastViewedAt ?? 0).compareTo(a.lastViewedAt ?? 0));
      if (!mounted) return;
      _index = lib.index;
      _byKey = {
        for (final l in lib.bySection)
          for (final i in l) i.ratingKey: i,
      };
      _watched = [
        for (final i in recent)
          if (i.tmdbId != null) (mediaType: i.type == 'show' ? 'tv' : 'movie', tmdbId: i.tmdbId!, title: i.title, liked: false),
      ];
      await _build(app);
    } catch (e) {
      debugPrint('taste rows: $e');
    }
  }

  /// Fetches recommendations for any new starting points, then lays out the rows.
  Future<void> _build(AppState app) async {
    final seerr = app.seerr;
    if (seerr == null) return;
    final taste = app.settings.taste;
    _builtFor = taste;
    final seeds = tasteSeeds(_watched, taste);
    await Future.wait([
      for (final s in seeds)
        // One seed failing (a timeout, say) mustn't stop the others.
        if (!_recs.containsKey(Taste.keyOf(s.mediaType, s.tmdbId)))
          seerr.recommendations(s.mediaType, s.tmdbId).then<void>((r) => _recs[Taste.keyOf(s.mediaType, s.tmdbId)] = r, onError: (Object e) => debugPrint('recommendations: $e')),
    ]);
    // A newer thumbs change has started its own build.
    if (!mounted || !identical(taste, app.settings.taste)) return;
    final index = _index;
    bool seen(SeerrResult r) {
      final k = index?.ratingKeyFor(r);
      final item = k == null ? null : _byKey[k];
      if (item == null) return false;
      return item.type == 'movie' ? item.isWatched : (item.leafCount ?? 0) > 0 && (item.viewedLeafCount ?? 0) >= (item.leafCount ?? 0);
    }

    setState(() => _rows = becauseYouWatched(seeds, [for (final s in seeds) _recs[Taste.keyOf(s.mediaType, s.tmdbId)] ?? const []], taste, skip: seen));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!_started && app.plexConn == Conn.ok && app.seerrConn == Conn.ok) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    // A thumb changed: rebuild from what's cached (and fetch for a new thumbs-up).
    if (_index != null && !identical(_builtFor, app.settings.taste)) {
      _builtFor = app.settings.taste;
      WidgetsBinding.instance.addPostFrameCallback((_) => _build(app));
    }
    if (_rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in _rows) ...[
          const SizedBox(height: Space.space8),
          Shelf(
            key: ValueKey(row.heading),
            title: row.heading,
            children: [
              for (final r in row.items)
                TasteCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r, plexItem: _index?.ratingKeyFor(r) == null ? null : _byKey[_index!.ratingKeyFor(r)!], onHighlight: widget.onHighlight),
            ],
          ),
        ],
      ],
    );
  }
}

/// A recommended title with thumbs up and down that show when you point at it.
class TasteCard extends StatefulWidget {
  const TasteCard({super.key, required this.item, this.plexItem, this.onHighlight});
  final SeerrResult item;

  /// Set when it's already in the library.
  final PlexItem? plexItem;
  final void Function(PlexItem item, bool on)? onHighlight;

  @override
  State<TasteCard> createState() => _TasteCardState();
}

class _TasteCardState extends State<TasteCard> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final it = widget.item;
    final owned = widget.plexItem;
    final key = Taste.keyOf(it.mediaType, it.id);
    final liked = app.settings.taste.liked(key);
    final sub = [if (owned != null) 'In Your Library' else '★ ${(it.voteAverage ?? 0).toStringAsFixed(1)}', yearOf(it.date), it.isTv ? 'Series' : 'Movie'].where((s) => s.isNotEmpty).join('  ·  ');
    return MouseRegion(
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: Stack(
        children: [
          PosterCard(
            title: it.displayTitle,
            subtitle: sub,
            imageUrl: it.posterUrl(),
            onHighlight: owned == null ? null : (on) => widget.onHighlight?.call(owned, on),
            onTap: () => ShellNav.of(context).push(owned != null ? ItemDest(owned.ratingKey) : SeerrDest(it.mediaType, it.id)),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: AnimatedOpacity(
              opacity: _hot || liked ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              // They show for the pointer only. On a TV they were invisible D-pad stops: Left
              // from the next card landed on this card's thumbs-up, the page jumped to centre
              // it and nothing looked focused, and only a second Left reached the card.
              child: ExcludeFocus(
                excluding: isTv || !(_hot || liked),
                child: Column(
                  children: [
                    _Thumb(icon: LucideIcons.thumbsUp, on: liked, label: liked ? 'Remove thumbs up' : 'More like this', onTap: () => app.rate(it.mediaType, it.id, it.displayTitle, up: true)),
                    if (_hot) ...[
                      const SizedBox(height: 6),
                      _Thumb(icon: LucideIcons.thumbsDown, on: false, label: 'Not for me', onTap: () => app.rate(it.mediaType, it.id, it.displayTitle, up: false)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.icon, required this.on, required this.label, required this.onTap});
  final IconData icon;
  final bool on;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: label,
      child: Focusable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hover, focus) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? c.primaryFill : Colors.black.withValues(alpha: hover ? 0.85 : 0.6),
            border: Border.all(color: focus ? c.primary : Colors.white.withValues(alpha: hover ? 0.8 : 0.35)),
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}
