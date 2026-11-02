import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'nav.dart';

/// Seerr requests as rows: poster, title line, and live progress on the right.
class RequestList extends StatelessWidget {
  const RequestList({super.key, required this.rows});
  final List<RequestRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: Space.space2),
                decoration: BoxDecoration(
                  border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: c.border100)),
                ),
                child: _Row(row: rows[i], narrow: narrow),
              ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.narrow});
  final RequestRow row;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = row.request;
    final d = row.details;
    final type = (r.media?.mediaType ?? r.type) == 'tv' ? 'Series' : 'Movie';
    final meta = [
      yearOf(d?.date),
      type,
      if (r.seasonCount > 0) '${r.seasonCount} Season${r.seasonCount == 1 ? '' : 's'}',
      if (r.requestedBy != null) r.requestedBy!,
      formatAgo(r.createdAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    final poster = Container(
      width: 36,
      height: 54,
      decoration: BoxDecoration(
        color: c.surface300,
        borderRadius: BorderRadius.circular(Radii.radiusSm),
        border: Border.all(color: c.border200),
      ),
      clipBehavior: Clip.antiAlias,
      child: d?.posterUrl(size: 'w185') != null
          ? ArtImage(
              d!.posterUrl(size: 'w185')!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(),
            )
          : null,
    );
    final available = row.state.label == 'Available';
    final titleText = Text(
      row.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ConsoleText.bodyStrong.copyWith(color: c.text100),
    );
    final tmdb = r.media?.tmdbId;
    final plexKey = available ? r.media?.ratingKey : null;
    void open() => ShellNav.of(context).push(plexKey != null ? ItemDest(plexKey) : SeerrDest(r.media?.mediaType ?? r.type ?? 'movie', tmdb!));
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleText,
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ConsoleText.caption.copyWith(color: c.text300),
        ),
      ],
    );
    final canOpen = tmdb != null && tmdb > 0;
    // The whole row takes focus (not just the title), so Down from the filter lands on the
    // first row and the focus ring is plain to see on a TV.
    Widget focusable(Widget child) => !canOpen
        ? child
        : Focusable(
            onTap: open,
            semanticLabel: 'Open ${row.title}',
            builder: (context, hover, focus) => withFocusRing(
              context,
              focused: focus,
              radius: Radii.radiusSm,
              child: ColoredBox(color: hover || focus ? c.surface300.withValues(alpha: 0.5) : Colors.transparent, child: child),
            ),
          );
    final progress = row.state.wait != null ? _Waiting(state: row.state) : RequestProgress(state: row.state);
    if (narrow) {
      return focusable(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          poster,
          const SizedBox(width: Space.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: Space.space2),
                progress,
              ],
            ),
          ),
        ],
      ));
    }
    return focusable(Row(
      children: [
        poster,
        const SizedBox(width: Space.space3),
        Expanded(child: info),
        const SizedBox(width: Space.space3),
        SizedBox(width: 280, child: progress),
      ],
    ));
  }
}

/// For a title not out on streaming yet: no bar, just when it's due.
/// "Not on Streaming Yet" / "Nov 18, 2026" / "Digital release · in 25 days" / theaters note.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.state});
  final RequestState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = state.wait!;
    final d = w.date;
    final until = w.until();
    return Semantics(
      label: [state.label, ?state.detail, ?w.note].join('. '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConsoleBadge(state.label, tone: state.tone),
          const SizedBox(height: Space.space1),
          Text(
            d == null ? 'Date not announced' : formatShortDate(d),
            style: ConsoleText.titleMd.copyWith(color: c.text100),
          ),
          Text(
            [w.what, ?until].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.caption.copyWith(color: c.text300),
          ),
          if (w.note != null)
            Text(
              w.note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ConsoleText.caption.copyWith(color: c.text300),
            ),
        ],
      ),
    );
  }
}
