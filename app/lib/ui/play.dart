import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';

import '../platform.dart';
import '../state/scope.dart';
import 'pages/player_page.dart';

/// How the player opens over the app. On a low-memory TV it fades in and leaves the app behind it
/// as it was, instead of fading that out: the app stays drawable there, so for a 4K file the
/// pages behind can be drawn again without their artwork (see GpuMemory).
PageRoute<void> playerRoute(WidgetBuilder builder) => isLowMemoryTv
    ? PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
      )
    : MaterialPageRoute<void>(builder: builder);

/// Plays a movie or episode; a show plays its next unwatched episode. [queue] keeps going
/// after it in order (a collection marathon), with Up Next between titles.
/// Returns once the player closes.
Future<void> playTitle(BuildContext context, PlexItem item, {bool resume = true, List<PlexItem> queue = const []}) async {
  final plex = AppScope.read(context).plex;
  if (plex == null) return;
  PlexItem? target = item;
  if (item.type == 'show') {
    try {
      target = await nextEpisode(plex, item);
    } catch (e) {
      debugPrint('next episode: $e');
      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Couldn’t load the episodes. Try again in a moment.')));
      return;
    }
  }
  if (target == null || !context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(playerRoute((_) => PlayerPage(item: target!, resume: resume, queue: queue)));
}

/// The episode to carry on with: the first unwatched one of the first unfinished season.
Future<PlexItem?> nextEpisode(PlexClient plex, PlexItem show) async {
  final seasons = (await plex.children(show.ratingKey)).where((s) => (s.index ?? 0) > 0).toList();
  final season = seasons.where((s) => (s.viewedLeafCount ?? 0) < (s.leafCount ?? 0)).firstOrNull ?? seasons.firstOrNull;
  final eps = season == null ? const <PlexItem>[] : await plex.children(season.ratingKey);
  return eps.where((e) => !e.isWatched).firstOrNull ?? eps.firstOrNull;
}
