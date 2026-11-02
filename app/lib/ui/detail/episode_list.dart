import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../spoiler.dart';

/// Episodes with stills, length, air date, synopsis and watch state.
class EpisodeList extends StatelessWidget {
  const EpisodeList({super.key, required this.episodes, required this.imageUrl, required this.onOpen, required this.onPlay, this.current, this.spoilers = const SpoilerPrefs()});
  final List<PlexItem> episodes;
  final String? Function(PlexItem) imageUrl;
  final ValueChanged<PlexItem> onOpen;
  final ValueChanged<PlexItem> onPlay;

  /// Highlights the episode being viewed.
  final String? current;

  /// What to keep back about episodes not watched yet.
  final SpoilerPrefs spoilers;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, e) in episodes.indexed) ...[
        if (i > 0) Divider(height: 1, thickness: 1, color: context.fx.glass ? context.fx.panelBorder : context.c.border100),
        _EpisodeRow(episode: e, spoilers: spoilers, imageUrl: imageUrl(e), selected: e.ratingKey == current, onOpen: () => onOpen(e), onPlay: () => onPlay(e)),
      ],
    ],
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.spoilers, required this.imageUrl, required this.selected, required this.onOpen, required this.onPlay});
  final PlexItem episode;
  final SpoilerPrefs spoilers;
  final String? imageUrl;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    final e = episode;
    final aired = DateTime.tryParse(e.originallyAvailableAt ?? '');
    final meta = [formatDuration(e.duration), if (aired != null) formatDate(aired)].where((s) => s.isNotEmpty).join('  ·  ');
    return Focusable(
      onTap: onOpen,
      semanticLabel: 'Episode ${e.index}, ${spoilers.titleOf(e)}',
      builder: (context, hover, focus) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: Space.space3),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint.withValues(alpha: 0.6) : (hover || focus ? fx.controlFill : Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.radiusMd),
          border: focus ? Border.all(color: c.primary, width: 2) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 192,
              child: Focusable(
                onTap: onPlay,
                semanticLabel: 'Play ${spoilers.titleOf(e)}',
                builder: (context, playHover, playFocus) => Container(
                  decoration: BoxDecoration(
                    color: c.surface300,
                    borderRadius: BorderRadius.circular(Radii.radiusSm),
                    border: Border.all(color: playFocus ? c.primary : fx.panelBorder, width: playFocus ? 2 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null) SpoilerBlur(hide: spoilers.hideImage(e), child: ArtImage(imageUrl!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox())),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: hover || playHover || playFocus ? 1 : 0,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: playHover ? c.primaryFill : Colors.black.withValues(alpha: 0.55),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: const Icon(LucideIcons.play, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        if (e.watchProgress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: SizedBox(
                              height: 3,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Color(0x99000000)),
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: e.watchProgress!.clamp(0, 1),
                                    child: ColoredBox(color: c.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spoilers.hideTitle(e) ? spoilers.titleOf(e) : '${e.index ?? ''}. ${e.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ConsoleText.titleSm.copyWith(color: hover ? c.link : c.text100),
                        ),
                      ),
                      if (e.isWatched) ...[const SizedBox(width: Space.space2), Icon(LucideIcons.circleCheckBig, size: 14, color: c.successText)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: ConsoleText.caption.copyWith(color: c.text300)),
                  if ((e.summary ?? '').isNotEmpty) ...[
                    const SizedBox(height: Space.space1),
                    SpoilerText(
                      key: ValueKey(e.ratingKey),
                      hide: spoilers.hideSummary(e),
                      builder: (_) => Text(
                        e.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ConsoleText.small.copyWith(color: c.text200, height: 1.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
