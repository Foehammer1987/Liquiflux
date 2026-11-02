import 'dart:math' as math;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../nav.dart';
import 'series_art.dart';

/// Film series with at least one film on the server; the missing ones can be requested.
/// Opens from the last list found (kept on disk) and swaps in a fresher one when it lands.
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.plexConn == Conn.off) return const Center(child: ErrorNote('Connect Plex in Settings to see your collections.'));
    if (app.plexConn == Conn.failed) return Center(child: ErrorNote('Couldn’t reach Plex${app.plexError == null ? '' : ': ${app.plexError}'}'));
    if (app.plexConn != Conn.ok) return const Center(child: LoadingNote(label: 'Connecting to Plex'));
    return ListenableBuilder(
      listenable: Listenable.merge([app.seriesScan, app.franchiseVersion]),
      builder: (context, _) {
        final now = app.franchisesNow;
        if (now != null) return _page(context, now);
        final scan = app.seriesScan.value;
        return Loader<List<Franchise>>(
          loadingLabel: scan == null ? 'Gathering collections' : 'Finding the film series in your library: ${scan.$1} of ${scan.$2} (first time only)',
          load: app.franchises,
          builder: (context, all, _) => _page(context, all),
        );
      },
    );
  }

  /// A series needs two films or more, out or announced, and at least one of them on the server.
  static bool shown(Franchise f) => f.ownedCount > 0 && f.total >= 2;

  Widget _page(BuildContext context, List<Franchise> all) {
    final c = context.c;
    final yours = all.where(shown).toList()..sort((a, b) => _order(b).compareTo(_order(a)));
    const gap = Space.space6;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(48, Space.space4, 48, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collections',
                  style: ConsoleText.display.copyWith(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: c.text100),
                ),
                const SizedBox(height: Space.space1),
                Text('Film series you have, in release order. Request the films you’re missing.', style: ConsoleText.body.copyWith(color: c.text200)),
                if (yours.isEmpty) ...[const SizedBox(height: Space.space8), const EmptyState(title: 'No collections yet', body: 'A series shows up here once you have one of its films.')],
                if (yours.isNotEmpty) ...[
                  const SizedBox(height: Space.space8),
                  Text('${yours.length} Series in Your Library', style: ConsoleText.titleLg.copyWith(fontSize: 22, color: c.text100)),
                  const SizedBox(height: Space.space4),
                ],
              ],
            ),
          ),
        ),
        // As many columns as fit at about 400px each, filling the width. Only the cards in
        // view are built, so a long list costs no more than a short one.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(48, 0, 48, Space.space10),
          sliver: SliverLayoutBuilder(
            builder: (context, box) {
              final cols = ((box.crossAxisExtent + gap) / (400 + gap)).floor().clamp(1, 6);
              final w = (box.crossAxisExtent - gap * (cols - 1)) / cols;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: gap, crossAxisSpacing: gap, childAspectRatio: 1 / 0.5625),
                delegate: SliverChildBuilderDelegate(
                  childCount: yours.length,
                  findChildIndexCallback: (key) {
                    final i = yours.indexWhere((f) => ValueKey(f.key) == key);
                    return i < 0 ? null : i;
                  },
                  (context, i) {
                    final f = yours[i];
                    return SeriesCard(key: ValueKey(f.key), franchise: f, width: w, onTap: () => ShellNav.of(context).push(CollectionDest(f)));
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Series you're partway through first, then the most complete.
  static double _order(Franchise f) => (f.upNext != null && f.watchedCount > 0 ? 100 : 0) + f.ownedCount / (f.total == 0 ? 1 : f.total);
}

/// A series as a wide card: its backdrop, a fan of its posters that spreads when you
/// point at it, and a bar with one segment per film (lit when you have it, dim when you don't).
/// Pointing at it also brings in the series' story.
/// Every colour comes from the series' own poster.
class SeriesCard extends StatefulWidget {
  const SeriesCard({super.key, required this.franchise, required this.onTap, this.width = 440});
  final Franchise franchise;
  final VoidCallback onTap;
  final double width;

  @override
  State<SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<SeriesCard> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.franchise;
    final plex = AppScope.of(context).plex;
    final posters = [for (final p in f.released) SeriesArt.poster(p, plex, small: true)].whereType<String>().take(5).toList();
    final backdrop = SeriesArt.seriesBackdrop(f, plex, small: true);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final years = f.years;
    final films = f.total;
    final line = [
      if (f.ownedCount == 0) '$films films' else '${f.ownedCount} of $films in your library',
      if (years != null) years.from == years.to ? '${years.from}' : '${years.from}–${years.to}',
    ].join('  ·  ');
    // TMDB's or Plex's story of the series, else the films themselves.
    final about = (f.overview ?? '').trim().isNotEmpty ? f.overview!.trim() : 'The films: ${[for (final p in f.released) p.title].join(', ')}.';
    return RepaintBoundary(
      child: ArtTint(
        url: SeriesArt.seriesPoster(f, plex, small: true),
        fallback: context.c.primary,
        builder: (context, tint) => Focusable(
          onTap: widget.onTap,
          semanticLabel: f.name,
          onHighlight: (on) => setState(() => _hot = on),
          builder: (context, hover, focus) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: widget.width,
            height: widget.width * 0.5625,
            transform: Matrix4.translationValues(0, _hot ? -4 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.radiusLg + 4),
              border: Border.all(
                color: focus ? context.c.primary : tint.withValues(alpha: _hot ? 0.7 : 0.25),
                width: focus ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: _hot ? 0.35 : 0.12),
                  blurRadius: _hot ? 28 : 16,
                  offset: const Offset(0, 10),
                  spreadRadius: -6,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdrop != null)
                  AnimatedScale(
                    scale: _hot ? 1.06 : 1,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    child: ArtImage(backdrop, fit: BoxFit.cover, gaplessPlayback: true, decodeWidth: (widget.width * dpr).round(), errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color.alphaBlend(tint.withValues(alpha: 0.28), const Color(0xF0070809)), const Color(0xCC070809), const Color(0x33070809)],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
                // The fan of posters; it steps back when you point at the card, to make room for the story.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  right: _hot ? -40 : 18,
                  top: 22,
                  bottom: 22,
                  width: 200,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: _hot ? 0.22 : 1,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (i, url) in posters.indexed.toList().reversed)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutBack,
                            right: 14.0 * i,
                            top: 6 + i * 3.0,
                            child: AnimatedRotation(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutBack,
                              turns: -0.01 * i,
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 112,
                                height: 168,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(Radii.radiusMd),
                                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 5))],
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ArtImage(
                                  url,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  decodeWidth: (112 * dpr).round(),
                                  errorBuilder: (_, _, _) => ColoredBox(color: tint.withValues(alpha: 0.3)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // A darker wash behind the story while it shows.
                IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: _hot ? 1 : 0,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xE6070809), Color(0x66070809)]),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  left: Space.space5,
                  bottom: Space.space5,
                  // Beside the poster fan, then the whole card once the fan steps back.
                  width: _hot ? widget.width - Space.space5 * 2 : math.max(160.0, math.min(widget.width * 0.52, widget.width - Space.space5 - 200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ConsoleText.display.copyWith(fontSize: 24, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: Space.space1),
                      Text(line, style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.75))),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomLeft,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: _hot ? 1 : 0,
                          child: _hot
                              ? Padding(
                                  padding: const EdgeInsets.only(top: Space.space2),
                                  child: Text(
                                    about,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.88), height: 1.4),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ),
                      const SizedBox(height: Space.space3),
                      SeriesBar(franchise: f, color: tint),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One segment per film: lit when it's in your library, dim when it's missing, and an
/// outline for one that isn't out yet, so a series with everything released is fully lit.
class SeriesBar extends StatelessWidget {
  const SeriesBar({super.key, required this.franchise, required this.color, this.height = 5});
  final Franchise franchise;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final parts = franchise.parts;
    return Row(
      children: [
        for (final (i, p) in parts.indexed) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Tooltip(
              message: p.owned ? p.title : (p.released ? '${p.title} (missing)' : '${p.title} (${p.year ?? 'coming'})'),
              waitDuration: const Duration(milliseconds: 500),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  color: p.owned
                      ? color
                      : p.released
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.transparent,
                  border: p.owned || p.released ? null : Border.all(color: color.withValues(alpha: 0.55)),
                  boxShadow: [if (p.owned) BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
