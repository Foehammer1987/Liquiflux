import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../nav.dart';
import '../seerr_card.dart';

/// Searches Plex and Seerr together. Plex hits come first; anything Plex lacks gets a Request button.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.query});
  final String query;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  List<PlexItem>? _plex;
  List<SeerrResult>? _seerr;
  String? _plexError;
  String? _seerrError;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _run();
      // Keep request progress on these cards live.
      _poll = Timer.periodic(const Duration(seconds: 15), (_) {
        // Not while another page or the player covers this one.
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _runSeerr();
      });
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _run() {
    final q = widget.query.trim();
    if (q.isEmpty) return;
    AppScope.read(context).plex
        ?.search(q)
        .then(
          (v) {
            if (mounted) setState(() => _plex = v);
          },
          onError: (Object e) {
            if (mounted) setState(() => _plexError = errorText(e));
          },
        );
    _runSeerr();
  }

  void _runSeerr() {
    final q = widget.query.trim();
    final app = AppScope.read(context);
    if (q.isEmpty || app.seerrConn != Conn.ok) return;
    app.seerr!
        .search(q)
        .then(
          (v) {
            if (mounted) {
              setState(() {
                _seerr = v;
                _seerrError = null;
              });
            }
          },
          // A failed refresh keeps the results already showing.
          onError: (Object e) {
            if (mounted && _seerr == null) setState(() => _seerrError = errorText(e));
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = widget.query.trim();
    if (q.isEmpty) {
      return const PageBody(
        children: [
          ConsolePanel(
            title: 'Search',
            child: EmptyState(title: 'Search your library', body: "Use the search box at the top (Ctrl+F). Anything Plex doesn't have can be requested from the same results."),
          ),
        ],
      );
    }
    final seerrOn = app.seerrConn == Conn.ok;
    final plexItems = _plex ?? const <PlexItem>[];
    final noPlexHits = _plex != null && plexItems.isEmpty;
    final requestable = _seerr != null && _plex != null ? requestableResults(_seerr!, plexItems) : null;

    final library = ConsolePanel(
      title: 'In Your Library',
      meta: _plex != null ? muted(context, '${plexItems.length} ${plexItems.length == 1 ? 'Result' : 'Results'}') : null,
      child: _plexError != null
          ? ErrorNote(_plexError!)
          : _plex == null
          ? const LoadingNote(label: 'Searching Plex')
          : plexItems.isEmpty
          ? EmptyState(title: 'No matches for “$q” in Plex', body: seerrOn ? 'You can request it above.' : null)
          : PosterGrid(
              children: [for (var i = 0; i < plexItems.length; i++) PlexPoster(item: plexItems[i], autofocus: i == 0)],
            ),
    );

    final Widget? request = seerrOn
        ? ConsolePanel(
            title: noPlexHits ? 'Not in Your Library' : 'Request Something Else',
            meta: requestable != null ? muted(context, '${requestable.length} ${requestable.length == 1 ? 'Result' : 'Results'}') : null,
            child: _seerrError != null
                ? ErrorNote(_seerrError!)
                : requestable == null
                ? const LoadingNote(label: 'Searching Seerr')
                : requestable.isEmpty
                ? EmptyState(title: 'Nothing to request', body: 'Seerr found no other matches for “$q”.')
                : PosterGrid(
                    children: [for (final r in requestable) SeerrCard(key: ValueKey('${r.mediaType}:${r.id}'), item: r, onRequested: _runSeerr)],
                  ),
          )
        // Seerr turned on but not answering. Turned off, search is Plex alone and says nothing of it.
        : noPlexHits && app.settings.seerrEnabled
        ? ConsolePanel(
            title: 'Request It',
            child: EmptyState(
              title: "Seerr isn't connected",
              body: "Check the Seerr address and sign-in in Settings to request titles that aren't in Plex.",
              action: ConsoleButton(label: 'Open Settings', onPressed: () => ShellNav.of(context).go(const SettingsDest())),
            ),
          )
        : null;

    return PageBody(children: [if (noPlexHits) ?request, library, if (!noPlexHits) ?request]);
  }
}
