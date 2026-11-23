import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/scope.dart';
import 'nav.dart';
import 'play.dart';

/// What the long-press menu on a poster offers (phones and tablets), all of it things the
/// title page already does: play, mark watched or unwatched, open the show or season an
/// episode belongs to, and the title page itself.
enum PosterAction { play, markWatched, markUnwatched, goToShow, goToSeason, info }

/// The menu's choices for [item], in order.
List<PosterAction> posterActions(PlexItem item) {
  final watched = item.isPlayable ? item.isWatched : (item.leafCount != null && item.leafCount! > 0 && item.viewedLeafCount == item.leafCount);
  final playable = item.isPlayable || item.type == 'show' || item.type == 'season';
  return [
    if (playable) PosterAction.play,
    if (item.isPlayable || item.type == 'show' || item.type == 'season') watched ? PosterAction.markUnwatched : PosterAction.markWatched,
    if (item.type == 'episode' && item.grandparentRatingKey != null) PosterAction.goToShow,
    if (item.type == 'episode' && item.parentRatingKey != null) PosterAction.goToSeason,
    if (item.type == 'season' && item.parentRatingKey != null) PosterAction.goToShow,
    PosterAction.info,
  ];
}

String _label(PosterAction a, PlexItem item) => switch (a) {
  PosterAction.play => (item.viewOffset ?? 0) > 0 ? 'Resume' : 'Play',
  PosterAction.markWatched => 'Mark as Watched',
  PosterAction.markUnwatched => 'Mark as Unwatched',
  PosterAction.goToShow => 'Go to Show',
  PosterAction.goToSeason => 'Go to Season',
  PosterAction.info => 'More Info',
};

IconData _icon(PosterAction a) => switch (a) {
  PosterAction.play => LucideIcons.play,
  PosterAction.markWatched => LucideIcons.check,
  PosterAction.markUnwatched => LucideIcons.checkCheck,
  PosterAction.goToShow => LucideIcons.tv,
  PosterAction.goToSeason => LucideIcons.listVideo,
  PosterAction.info => LucideIcons.info,
};

/// The long-press menu for [item]: a sheet from the bottom with its choices.
Future<void> showPosterMenu(BuildContext context, PlexItem item) async {
  HapticFeedback.mediumImpact();
  final nav = ShellNav.of(context);
  final app = AppScope.read(context);
  final c = context.c;
  final picked = await showModalBottomSheet<PosterAction>(
    context: context,
    backgroundColor: c.surface100,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.space5, Space.space4, Space.space5, Space.space2),
              child: Text(item.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: ConsoleText.titleMd.copyWith(color: c.text100)),
            ),
            for (final a in posterActions(item))
              ListTile(
                leading: Icon(_icon(a), color: c.text100),
                title: Text(_label(a, item), style: ConsoleText.body.copyWith(color: c.text100)),
                onTap: () => Navigator.of(sheet).pop(a),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final plex = app.plex;
  switch (picked) {
    case PosterAction.play:
      await playTitle(context, item);
    case PosterAction.markWatched || PosterAction.markUnwatched:
      if (plex == null) return;
      try {
        if (picked == PosterAction.markWatched) {
          await plex.markWatched(item);
          // Marked watched by hand: Trakt's history and AniList hear about it too.
          unawaited(app.scrobbler.markedWatched(plex, item, server: app.server?.machineIdentifier ?? ''));
        } else {
          await plex.markUnwatched(item);
        }
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(picked == PosterAction.markWatched ? 'Marked as watched' : 'Marked as unwatched')));
        }
      } catch (e) {
        debugPrint('mark watched: $e');
      }
    case PosterAction.goToShow:
      nav.push(ItemDest(item.type == 'season' ? item.parentRatingKey! : item.grandparentRatingKey!));
    case PosterAction.goToSeason:
      nav.push(ItemDest(item.parentRatingKey!));
    case PosterAction.info:
      nav.push(ItemDest(item.ratingKey));
  }
}
