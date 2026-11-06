import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../services/links.dart';
import '../common.dart';
import '../nav.dart';
import '../spoiler.dart';

/// The one detail layout for every title, in Plex or not: art, facts, ratings, actions,
/// then Cast & Crew, Extras and whatever [sections] the page adds.
class TitleDetailView extends StatefulWidget {
  const TitleDetailView({
    super.key,
    required this.detail,
    required this.actions,
    this.status,
    this.artProgress,
    this.artCaption,
    this.sections = const [],
    this.moreSections = const [],
    this.onPlayExtra,
    this.blurArt = false,
    this.hideSummary = false,
  });

  final TitleDetail detail;
  final List<Widget> actions;

  /// Request progress, shown under the actions.
  final Widget? status;
  final double? artProgress;
  final String? artCaption;

  /// Right under the hero (Episodes, Seasons).
  final List<Widget> sections;

  /// After Cast & Crew and Extras (More Like This, Recommendations).
  final List<Widget> moreSections;
  final void Function(PlexItem extra)? onPlayExtra;

  /// An unwatched episode with spoilers hidden: its still is blurred and its story held back.
  final bool blurArt;
  final bool hideSummary;

  @override
  State<TitleDetailView> createState() => _TitleDetailViewState();
}

class _TitleDetailViewState extends State<TitleDetailView> {
  BackdropController? _backdrop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backdrop ??= BackdropScope.maybeOf(context);
    _syncBackdrop();
  }

  @override
  void didUpdateWidget(TitleDetailView old) {
    super.didUpdateWidget(old);
    if (old.detail.backdropUrl != widget.detail.backdropUrl) _syncBackdrop();
  }

  void _syncBackdrop() {
    final url = widget.detail.backdropUrl ?? widget.detail.posterUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backdrop?.set(this, url);
    });
  }

  @override
  void dispose() {
    final b = _backdrop;
    scheduleMicrotask(() => b?.clear(this));
    super.dispose();
  }

  void _openCredit(Credit cr) => ShellNav.of(context).push(PersonDest(name: cr.name, plexTagId: cr.plexTagId, tmdbId: cr.tmdbId, photoUrl: cr.photoUrl));

  void _openExtra(Extra e) {
    if (e.plexItem != null) {
      widget.onPlayExtra?.call(e.plexItem!);
    } else if (e.url != null) {
      openExternal(e.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final credits = [...d.cast, ...d.crew];
    // Online extras open in a browser, which a Samsung TV build doesn't use.
    final extras = [for (final e in d.extras) if (e.plexItem != null || canOpenLinks) e];
    return PageBody(
      padding: const EdgeInsets.fromLTRB(Space.space6, Space.space3, Space.space6, Space.space8),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConsoleButton(label: 'Back', icon: LucideIcons.chevronLeft, kind: ButtonKind.tertiary, onPressed: ShellNav.of(context).back),
        ),
        _Hero(view: widget),
        ...widget.sections,
        if (credits.isNotEmpty)
          ConsolePanel(
            title: 'Cast & Crew',
            meta: muted(context, '${credits.length}'),
            padding: const EdgeInsets.fromLTRB(Space.space2, Space.space2, Space.space2, Space.space3),
            child: PosterRow(
              itemWidth: 112,
              children: [for (final cr in credits) CreditAvatar(credit: cr, onTap: () => _openCredit(cr))],
            ),
          ),
        if (extras.isNotEmpty)
          ConsolePanel(
            title: 'Extras',
            meta: muted(context, '${extras.length}'),
            padding: const EdgeInsets.fromLTRB(Space.space2, Space.space2, Space.space2, Space.space3),
            child: PosterRow(
              itemWidth: 240,
              children: [
                for (final e in extras)
                  PosterCard(
                    title: e.title,
                    subtitle: [e.kind, if (e.durationMs != null) formatDuration(e.durationMs), if (e.url != null && e.plexItem == null) 'YouTube'].where((s) => s.isNotEmpty).join(' · '),
                    imageUrl: e.imageUrl,
                    wide: true,
                    overlayIcon: LucideIcons.play,
                    onTap: () => _openExtra(e),
                  ),
              ],
            ),
          ),
        ...widget.moreSections,
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.view});
  final TitleDetailView view;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = view.detail;
    return GlassSurface(
      padding: const EdgeInsets.all(Space.space6),
      elevation: 1.5,
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 720;
          final art = ArtFrame(
            url: d.posterUrl,
            width: d.landscape ? (narrow ? 280 : 340) : (narrow ? 160 : 230),
            landscape: d.landscape,
            progress: view.artProgress,
            caption: view.artCaption,
            fallback: d.title,
            blur: view.blurArt,
          );
          final dot = Text('·', style: ConsoleText.body.copyWith(color: c.text300));
          final meta = [
            if (d.contentRating != null && d.contentRating!.isNotEmpty) RatingTag(d.contentRating!),
            for (final (i, m) in d.metaLine.indexed) ...[if (i > 0) dot, Text(m, style: ConsoleText.body.copyWith(color: c.text200))],
          ];
          final t = d.tracks;
          final trackRows = <(String, Widget)>[
            if (t?.video != null) ('Video', Text(t!.video!)),
            if (t?.audio != null) ('Audio', Text(t!.audioTracks > 1 ? '${t.audio}  ·  ${t.audioTracks - 1} more' : t.audio!)),
            if (t != null && t.subtitles.isNotEmpty) ('Subtitles', Text(t.subtitles.length > 3 ? '${t.subtitles.take(3).join(', ')} and ${t.subtitles.length - 3} more' : t.subtitles.join(', '))),
            if (t?.file != null) ('File', Text(t!.file!, style: ConsoleText.data.copyWith(fontSize: 11, color: c.text100))),
          ];
          final factRows = <(String, Widget)>[for (final (k, v) in d.facts) (k, Text(v)), if (d.released != null && d.kind == TitleKind.show) ('First Aired', Text(formatDate(d.released!)))];
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.title,
                style: ConsoleText.display.copyWith(fontSize: narrow ? 24 : 30, height: 1.2, color: c.text100),
              ),
              if (d.subtitle != null) ...[const SizedBox(height: Space.space1), Text(d.subtitle!, style: ConsoleText.titleLg.copyWith(color: c.text100.withValues(alpha: 0.86)))],
              if (d.eyebrow != null) ...[const SizedBox(height: Space.space2), Text(d.eyebrow!, style: ConsoleText.body.copyWith(color: c.text200))],
              if (meta.isNotEmpty) ...[const SizedBox(height: Space.space2), Wrap(spacing: Space.space2, runSpacing: Space.space1, crossAxisAlignment: WrapCrossAlignment.center, children: meta)],
              if (d.scores.isNotEmpty || d.genres.isNotEmpty) ...[
                const SizedBox(height: Space.space3),
                Wrap(
                  spacing: Space.space2,
                  runSpacing: Space.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final s in d.scores) ScoreChip(s),
                    if (d.scores.isNotEmpty && d.genres.isNotEmpty) const SizedBox(width: Space.space1),
                    for (final g in d.genres.take(4)) ConsoleBadge(g),
                  ],
                ),
              ],
              const SizedBox(height: Space.space5),
              Wrap(spacing: Space.space2, runSpacing: Space.space2, crossAxisAlignment: WrapCrossAlignment.center, children: view.actions),
              if (view.status != null) ...[const SizedBox(height: Space.space3), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: view.status!)],
              if ((d.tagline ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.space5),
                Text(
                  d.tagline!,
                  style: ConsoleText.bodyStrong.copyWith(fontStyle: FontStyle.italic, color: c.text100),
                ),
              ],
              if ((d.summary ?? '').isNotEmpty) ...[
                SizedBox(height: (d.tagline ?? '').isNotEmpty ? Space.space2 : Space.space5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: SpoilerText(hide: view.hideSummary, style: ConsoleText.body, builder: (_) => ExpandableText(d.summary!)),
                ),
              ],
              if (factRows.isNotEmpty || trackRows.isNotEmpty) ...[
                const SizedBox(height: Space.space5),
                Wrap(
                  spacing: Space.space8,
                  runSpacing: Space.space3,
                  children: [
                    if (factRows.isNotEmpty) SizedBox(width: 380, child: FactTable(rows: factRows)),
                    if (trackRows.isNotEmpty) SizedBox(width: 400, child: FactTable(rows: trackRows, labelWidth: 80)),
                  ],
                ),
              ],
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                art,
                const SizedBox(height: Space.space5),
                body,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              art,
              const SizedBox(width: Space.space8),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}
