import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../nav.dart';

/// TV networks and programming blocks (Adult Swim, Toonami, Nick at Nite...), one row each:
/// every show of it you have, and while that's fewer than ten, the best-rated ones you're
/// missing, to request.
class TvCollectionsPage extends StatefulWidget {
  const TvCollectionsPage({super.key});
  @override
  State<TvCollectionsPage> createState() => _TvCollectionsPageState();
}

class _TvCollectionsPageState extends State<TvCollectionsPage> {
  String _kind = 'block';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.plexConn == Conn.off) return const Center(child: ErrorNote('Connect Plex in Settings to see TV networks and blocks.'));
    if (app.plexConn == Conn.failed) return Center(child: ErrorNote('Couldn’t reach Plex${app.plexError == null ? '' : ': ${app.plexError}'}'));
    if (app.plexConn != Conn.ok) return const Center(child: LoadingNote(label: 'Connecting to Plex'));
    return Loader<({CollectionPack pack, ShowMatcher shows})>(
      loadingLabel: 'Matching TV networks and blocks to your library',
      load: app.tvCollections,
      builder: (context, t, _) => _page(context, t.pack, tvShelves(t.pack, t.shows, kind: _kind)),
    );
  }

  Widget _page(BuildContext context, CollectionPack pack, List<TvShelf> shelves) {
    final c = context.c;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Space.space10),
      // A lazy list: rows below the fold (and their posters) load as you scroll to them.
      itemCount: shelves.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(48, Space.space4, 48, Space.space6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TV Networks', style: ConsoleText.display.copyWith(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: c.text100)),
                      const SizedBox(height: Space.space1),
                      Text(
                        'Shows by the channel or programming block they aired on. Yours come first; request the ones you’re missing.',
                        style: ConsoleText.body.copyWith(color: c.text200),
                      ),
                    ],
                  ),
                ),
                ConsoleSegmented<String>(options: const [('block', 'Blocks'), ('network', 'Networks')], value: _kind, onChanged: (k) => setState(() => _kind = k)),
              ],
            ),
          );
        }
        if (i == shelves.length + 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(48, Space.space8, 48, 0),
            child: Text(pack.credits ?? '', style: ConsoleText.caption.copyWith(color: c.text300)),
          );
        }
        final s = shelves[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.space8),
          child: Shelf(
            key: ValueKey(s.collection.id),
            title: shelfTitle(s),
            trailing: ConsoleButton(label: 'See All', size: ButtonSize.sm, onPressed: () => ShellNav.of(context).push(TvCollectionDest(s.collection.id))),
            children: [
              for (final o in s.owned) PlexPoster(item: o),
              for (final m in s.missing) MissingShowPoster(show: m),
            ],
          ),
        );
      },
    );
  }

  static String shelfTitle(TvShelf s) => '${s.collection.name}  ·  ${s.owned.length} of ${s.total} yours';
}

/// A show you don't have: its poster, dimmed, opening its Seerr page to request it.
class MissingShowPoster extends StatelessWidget {
  const MissingShowPoster({super.key, required this.show, this.requested = false});
  final PackShow show;
  final bool requested;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tmdb = show.tmdb;
    return PosterCard(
      title: show.title,
      subtitle: [if (show.year != null) '${show.year}', requested ? 'Requested' : 'Not in your library'].join(' · '),
      imageUrl: show.poster,
      dimmed: true,
      overlayIcon: requested ? LucideIcons.check : LucideIcons.download,
      onTap: tmdb != null && app.seerr != null
          ? () => ShellNav.of(context).push(SeerrDest('tv', tmdb))
          : () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(app.seerr == null ? 'Connect Seerr in Settings to request shows.' : 'Seerr can’t find ${show.title} to request it.')),
            ),
    );
  }
}

/// One network or block: what you have, what you're missing, and Request Missing.
class TvCollectionPage extends StatefulWidget {
  const TvCollectionPage({super.key, required this.id});
  final String id;
  @override
  State<TvCollectionPage> createState() => _TvCollectionPageState();
}

class _TvCollectionPageState extends State<TvCollectionPage> {
  bool _all = false;
  bool _requesting = false;
  final _requested = <int>{};

  Future<void> _request(List<PackShow> shows) async {
    final app = AppScope.read(context);
    final seerr = app.seerr;
    final todo = [for (final s in shows) if (s.tmdb != null && !_requested.contains(s.tmdb)) s];
    if (seerr == null || todo.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request ${todo.length} ${todo.length == 1 ? 'show' : 'shows'}?'),
        content: Text(todo.map((s) => '•  ${s.title}${s.year == null ? '' : ' (${s.year})'}').join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Request All')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _requesting = true);
    var failed = 0;
    for (final s in todo) {
      try {
        await seerr.request('tv', s.tmdb!);
        _requested.add(s.tmdb!);
      } catch (e) {
        failed++;
        debugPrint('request ${s.title}: ${e.runtimeType}');
      }
    }
    unawaited(app.refreshRequests());
    if (!mounted) return;
    setState(() => _requesting = false);
    if (failed > 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Seerr turned down $failed of ${todo.length} requests (some may be requested already). Try those again from their pages.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader<({CollectionPack pack, ShowMatcher shows})>(
      loadingLabel: 'Matching to your library',
      load: app.tvCollections,
      builder: (context, t, _) {
        final col = t.pack.byId(widget.id);
        if (col == null) return const Center(child: ErrorNote('This network or block is no longer in Liquiflux’s list.'));
        return _page(context, app, TvShelf.build(col, t.shows));
      },
    );
  }

  Widget _page(BuildContext context, AppState app, TvShelf s) {
    final c = context.c;
    final col = s.collection;
    final missing = _all ? s.allMissing : s.missing;
    final requestable = [for (final m in missing) if (m.tmdb != null && !_requested.contains(m.tmdb)) m];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(48, Space.space4, 48, Space.space10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(col.name, style: ConsoleText.display.copyWith(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: c.text100)),
          const SizedBox(height: Space.space1),
          Text(
            [
              col.isBlock ? 'Programming block' : 'Network',
              ?col.years,
              '${s.owned.length} of ${s.total} shows in your library',
            ].join('  ·  '),
            style: ConsoleText.body.copyWith(color: c.text200),
          ),
          if (col.about != null) ...[const SizedBox(height: Space.space2), Text(col.about!, style: ConsoleText.body.copyWith(color: c.text200))],
          const SizedBox(height: Space.space5),
          Wrap(
            spacing: Space.space3,
            runSpacing: Space.space3,
            children: [
              if (app.seerr != null && requestable.isNotEmpty)
                ConsoleButton(
                  label: _requesting ? 'Requesting…' : 'Request ${requestable.length} Missing',
                  icon: LucideIcons.download,
                  kind: ButtonKind.primary,
                  onPressed: _requesting ? null : () => _request(requestable),
                ),
              if (s.allMissing.length > s.missing.length)
                ConsoleButton(
                  label: _all ? 'Show Fewer' : 'Show All ${s.allMissing.length} Missing',
                  icon: _all ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  onPressed: () => setState(() => _all = !_all),
                ),
            ],
          ),
          if (s.owned.isNotEmpty) ...[
            const SizedBox(height: Space.space8),
            Text('In Your Library', style: ConsoleText.titleLg.copyWith(fontSize: 22, color: c.text100)),
            const SizedBox(height: Space.space4),
            PosterGrid(minWidth: 160, children: [for (final o in s.owned) PlexPoster(item: o)]),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: Space.space8),
            Text(_all ? 'Missing' : 'Top Rated You’re Missing', style: ConsoleText.titleLg.copyWith(fontSize: 22, color: c.text100)),
            const SizedBox(height: Space.space4),
            PosterGrid(minWidth: 160, children: [for (final m in missing) MissingShowPoster(show: m, requested: _requested.contains(m.tmdb))]),
          ],
          if (col.source != null) ...[
            const SizedBox(height: Space.space8),
            Text('Show list: ${col.source}', style: ConsoleText.caption.copyWith(color: c.text300)),
          ],
        ],
      ),
    );
  }
}
