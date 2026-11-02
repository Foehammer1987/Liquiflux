import 'package:flutter/material.dart';

import 'art_image.dart';
import 'focusable.dart';
import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

/// Poster or landscape card: art with hairline, title and caption beneath, optional watch bar.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.headers,
    this.progress,
    this.onTap,
    this.wide = false,
    this.dimmed = false,
    this.autofocus = false,
    this.overlayIcon,
    this.onHighlight,
    this.blur = false,
  });
  final String title;

  /// Centered mark over the art, e.g. a play icon on extras.
  final IconData? overlayIcon;

  /// Blur the picture (an unwatched episode's still, with spoilers hidden).
  final bool blur;
  final ValueChanged<bool>? onHighlight;
  final String? subtitle;
  final String? imageUrl;
  final Map<String, String>? headers;
  final double? progress;
  final VoidCallback? onTap;
  final bool wide;
  final bool dimmed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Focusable(
      onTap: onTap,
      autofocus: autofocus,
      semanticLabel: title,
      onHighlight: onHighlight,
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, hover, focus) {
        final fx = context.fx;
        final lifted = fx.glass && onTap != null && (hover || focus);
        final borderColor = focus ? c.primary : (hover ? c.border300 : (fx.glass ? fx.panelBorder : c.border200));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: wide ? 16 / 9 : 2 / 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
                decoration: BoxDecoration(
                  color: c.surface300,
                  borderRadius: BorderRadius.circular(Radii.radiusMd),
                  border: Border.all(color: borderColor, width: focus ? 2 : 1),
                  boxShadow: [
                    if (focus) BoxShadow(color: c.primaryTint, spreadRadius: 4),
                    if (fx.glass)
                      BoxShadow(
                        color: fx.shadow.withValues(alpha: fx.shadow.a * (lifted ? 1 : 0.6)),
                        blurRadius: lifted ? 22 : 12,
                        offset: Offset(0, lifted ? 10 : 4),
                      ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      Opacity(
                        opacity: dimmed ? 0.85 : 1,
                        child: blurred(blur, ArtImage(imageUrl!, headers: headers, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _Placeholder(title))),
                      )
                    else
                      _Placeholder(title),
                    if (overlayIcon != null)
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hover || focus ? c.primaryFill : Colors.black.withValues(alpha: 0.5),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Icon(overlayIcon, size: 18, color: Colors.white),
                        ),
                      ),
                    if (progress != null && progress! > 0)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.radiusFull),
                          child: SizedBox(
                            height: 4,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const ColoredBox(color: Color(0x99000000)),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress!.clamp(0, 1),
                                  child: ColoredBox(color: c.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.space1 + 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ConsoleText.small.copyWith(fontWeight: FontWeight.w500, color: c.text100),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.caption.copyWith(color: c.text300),
              ),
          ],
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(title.isEmpty ? '' : title.characters.first.toUpperCase(), style: ConsoleText.display.copyWith(color: context.c.text300)),
  );
}

/// Responsive grid of posters.
class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.children, this.minWidth = 132});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = (box.maxWidth / (minWidth + Space.space3)).floor().clamp(2, 12);
      final w = (box.maxWidth - Space.space3 * (cols - 1)) / cols;
      return SizedBox(
        width: box.maxWidth,
        child: Wrap(
          spacing: Space.space3,
          runSpacing: Space.space4,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        ),
      );
    },
  );
}

/// One horizontally scrolling row of cards.
class PosterRow extends StatelessWidget {
  const PosterRow({super.key, required this.children, this.itemWidth = 150});
  final List<Widget> children;
  final double itemWidth;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // Clip at the panel edge, with room for the focus ring.
    clipBehavior: Clip.hardEdge,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, Space.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: Space.space4), SizedBox(width: itemWidth, child: children[i])],
        ],
      ),
    ),
  );
}
