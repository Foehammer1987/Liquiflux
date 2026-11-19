import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/scope.dart';
import '../nav.dart';

/// Top 10 card: a big outlined rank beside the poster, coloured from the poster's art.
class RankedPoster extends StatefulWidget {
  const RankedPoster({
    super.key,
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
    this.onHighlight,
    this.dimmed = false,
    this.overlayIcon,
  });

  factory RankedPoster.plex(BuildContext context, {required int rank, required PlexItem item, ValueChanged<bool>? onHighlight}) {
    final plex = AppScope.of(context).plex;
    return RankedPoster(
      rank: rank,
      title: item.cardTitle,
      subtitle: item.audienceRating != null ? '★ ${item.audienceRating!.toStringAsFixed(1)}  ·  ${item.cardSubtitle}' : item.cardSubtitle,
      imageUrl: plex?.imageUrl(item.posterPath, width: 240, height: 360),
      onHighlight: onHighlight,
      onTap: () => ShellNav.of(context).push(ItemDest(item.ratingKey)),
    );
  }

  /// A title you don't have: opens its page, where it can be requested.
  /// [plexKey] marks one you already have, which opens in the library instead.
  factory RankedPoster.seerr(BuildContext context, {required int rank, required SeerrResult item, String? plexKey}) => RankedPoster(
    rank: rank,
    title: item.displayTitle,
    subtitle: [
      if (plexKey != null) 'In Your Library' else '★ ${(item.voteAverage ?? 0).toStringAsFixed(1)}',
      yearOf(item.date),
      item.isTv ? 'Series' : 'Movie',
    ].where((s) => s.isNotEmpty).join('  ·  '),
    imageUrl: item.posterUrl(),
    dimmed: plexKey == null,
    onTap: () => ShellNav.of(context).push(plexKey != null ? ItemDest(plexKey) : SeerrDest(item.mediaType, item.id)),
  );

  final int rank;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHighlight;
  final bool dimmed;
  final IconData? overlayIcon;

  @override
  State<RankedPoster> createState() => _RankedPosterState();
}

class _RankedPosterState extends State<RankedPoster> {
  static const _wideWidth = 168.0;
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Everything scales down together on a phone.
    final k = ConsoleDensity.compactOf(context) ? 0.62 : 1.0;
    final posterWidth = _wideWidth * k;
    final imageHeight = posterWidth * 1.5; // posters are 2:3
    final gap = Space.space2 * k;
    final text = '${widget.rank}';
    final numeral = ConsoleText.display.copyWith(fontSize: 210 * k, height: 1, fontWeight: FontWeight.w900, letterSpacing: widget.rank >= 10 ? -14 * k : 0);
    // Measure so the number sits fully beside the poster with its baseline on the poster's bottom edge.
    final tp = TextPainter(
      text: TextSpan(text: text, style: numeral),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = tp.width + 4; // room for the outline stroke
    final glyphTop = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.dispose();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: imageHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 2,
                top: 0,
                // Baseline puts the number's foot exactly on the poster's bottom edge.
                child: Baseline(
                  baseline: imageHeight,
                  baselineType: TextBaseline.alphabetic,
                  child: ArtTint(
                    url: widget.imageUrl,
                    index: widget.rank - 1,
                    fallback: c.text300,
                    builder: (context, tint) => AnimatedScale(
                      scale: _hot ? 1.04 : 1,
                      alignment: Alignment.bottomRight,
                      duration: const Duration(milliseconds: 200),
                      child: Stack(
                        children: [
                          // Fill: the art colour fading down into the page.
                          Text(
                            text,
                            style: numeral.copyWith(
                              foreground: Paint()
                                ..shader = LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    tint.withValues(alpha: _hot ? 0.55 : 0.32),
                                    c.surface000.withValues(alpha: 0.75),
                                  ],
                                ).createShader(Rect.fromLTWH(0, 0, width, glyphTop)),
                            ),
                          ),
                          Text(
                            text,
                            style: numeral.copyWith(
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 3 * k
                                ..color = tint.withValues(alpha: _hot ? 1 : 0.85),
                              shadows: [
                                Shadow(
                                  color: tint.withValues(alpha: _hot ? 0.6 : 0.25),
                                  blurRadius: _hot ? 28 : 16,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: gap),
        SizedBox(
          width: posterWidth,
          child: PosterCard(
            title: widget.title,
            subtitle: widget.subtitle,
            imageUrl: widget.imageUrl,
            dimmed: widget.dimmed,
            overlayIcon: widget.overlayIcon,
            onHighlight: (on) {
              setState(() => _hot = on);
              widget.onHighlight?.call(on);
            },
            onTap: widget.onTap,
          ),
        ),
      ],
    );
  }
}
