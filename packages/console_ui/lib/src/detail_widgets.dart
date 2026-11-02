import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'art_image.dart';
import 'focusable.dart';
import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';
import 'widgets.dart';

/// "IMDb 7.9", "🍅 94%", "Audience 87%" as a compact chip.
class ScoreChip extends StatelessWidget {
  const ScoreChip(this.score, {super.key});
  final Score score;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    final Widget mark = switch (score.source) {
      ScoreSource.imdb => _wordMark('IMDb', const Color(0xFFF5C518), Colors.black),
      ScoreSource.tmdb => _wordMark('TMDB', const Color(0xFF01B4E4), const Color(0xFF0D253F)),
      ScoreSource.rtCritic => Icon(score.positive == false ? LucideIcons.droplet : LucideIcons.cherry, size: 14, color: score.positive == false ? const Color(0xFF6AC238) : const Color(0xFFFA320A)),
      ScoreSource.rtAudience => Icon(LucideIcons.popcorn, size: 14, color: score.positive == false ? const Color(0xFF6AC238) : const Color(0xFFFA320A)),
      ScoreSource.critic => Icon(LucideIcons.star, size: 14, color: c.warning),
      ScoreSource.audience => Icon(LucideIcons.users, size: 14, color: c.chartDownload),
    };
    final showLabel = score.source != ScoreSource.imdb && score.source != ScoreSource.tmdb;
    return Tooltip(
      message: switch (score.source) {
        ScoreSource.rtCritic => 'Rotten Tomatoes critics',
        ScoreSource.rtAudience => 'Rotten Tomatoes audience',
        ScoreSource.imdb => 'IMDb rating',
        ScoreSource.tmdb => 'TMDB user score',
        _ => '${score.label} rating',
      },
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: Space.space2),
        decoration: BoxDecoration(
          color: fx.controlFill,
          borderRadius: BorderRadius.circular(Radii.radiusFull),
          border: Border.all(color: fx.controlBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            mark,
            const SizedBox(width: 6),
            Text(
              score.value,
              style: ConsoleText.small.copyWith(fontWeight: FontWeight.w600, color: c.text100, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (showLabel) ...[const SizedBox(width: 4), Text(score.label, style: ConsoleText.caption.copyWith(color: c.text300))],
          ],
        ),
      ),
    );
  }

  Widget _wordMark(String word, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
    child: Text(
      word,
      style: ConsoleText.caption.copyWith(fontSize: 9, height: 1.2, fontWeight: FontWeight.w800, color: fg, letterSpacing: -0.2),
    ),
  );
}

/// Outlined content rating ("TV-PG", "PG-13").
class RatingTag extends StatelessWidget {
  const RatingTag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.radiusSm),
      border: Border.all(color: context.c.text300),
    ),
    child: Text(
      text,
      style: ConsoleText.caption.copyWith(fontWeight: FontWeight.w600, color: context.c.text100),
    ),
  );
}

/// Round headshot with name and role beneath; initials when there's no photo.
class CreditAvatar extends StatelessWidget {
  const CreditAvatar({super.key, required this.credit, this.onTap, this.size = 96});
  final Credit credit;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    return Focusable(
      onTap: onTap,
      semanticLabel: '${credit.name}${credit.role != null ? ', ${credit.role}' : ''}',
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, hover, focus) {
        final initials = Center(
          child: Text(
            credit.initials,
            style: ConsoleText.display.copyWith(color: c.text300, fontWeight: FontWeight.w500),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: size,
              height: size,
              transform: Matrix4.translationValues(0, fx.glass && (hover || focus) ? -3 : 0, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surface300,
                border: Border.all(color: focus ? c.primary : (hover ? c.border300 : fx.panelBorder), width: focus ? 2 : 1),
                boxShadow: fx.glass
                    ? [
                        BoxShadow(
                          color: fx.shadow.withValues(alpha: fx.shadow.a * 0.7),
                          blurRadius: hover ? 18 : 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: credit.photoUrl == null ? initials : ArtImage(credit.photoUrl!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => initials),
            ),
            const SizedBox(height: Space.space2),
            Text(
              credit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ConsoleText.small.copyWith(fontWeight: FontWeight.w500, color: hover ? c.link : c.text100),
            ),
            if (credit.role != null && credit.role!.isNotEmpty)
              Text(
                credit.role!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: ConsoleText.caption.copyWith(color: c.text300),
              ),
          ],
        );
      },
    );
  }
}

/// Two-column label / value rows (Directed by, Video, Audio…).
class FactTable extends StatelessWidget {
  const FactTable({super.key, required this.rows, this.labelWidth = 104});
  final List<(String, Widget)> rows;
  final double labelWidth;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.space1 + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(label, style: ConsoleText.small.copyWith(color: c.text300)),
                ),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: ConsoleText.small.copyWith(color: c.text100),
                    child: value,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Body text clamped to a few lines with a More / Less toggle.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.maxLines = 4, this.style});
  final String text;
  final int maxLines;
  final TextStyle? style;
  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? ConsoleText.body.copyWith(color: context.c.text100, height: 1.6);
    return LayoutBuilder(
      builder: (context, box) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = tp.didExceedMaxLines;
        tp.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.text, style: style, maxLines: _open ? null : widget.maxLines, overflow: _open ? null : TextOverflow.ellipsis),
            if (overflows || _open) ...[const SizedBox(height: Space.space1), ConsoleLink(label: _open ? 'Less' : 'More', onTap: () => setState(() => _open = !_open))],
          ],
        );
      },
    );
  }
}

/// Poster (2:3) or still (16:9) with a floating shadow and an optional watch bar.
class ArtFrame extends StatelessWidget {
  const ArtFrame({super.key, required this.url, required this.width, this.landscape = false, this.progress, this.caption, this.fallback = '', this.blur = false});
  final String? url;

  /// Blur the picture (an unwatched episode's still, with spoilers hidden).
  final bool blur;
  final double width;
  final bool landscape;
  final double? progress;
  final String? caption;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    final placeholder = Center(
      child: Text(fallback.isEmpty ? '' : fallback.characters.first.toUpperCase(), style: ConsoleText.display.copyWith(color: c.text300)),
    );
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.surface300,
              borderRadius: BorderRadius.circular(Radii.radiusMd),
              border: Border.all(color: fx.panelBorder),
              boxShadow: fx.glass ? [BoxShadow(color: fx.shadow, blurRadius: 32, offset: const Offset(0, 14), spreadRadius: -6)] : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: landscape ? 16 / 9 : 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null) blurred(blur, ArtImage(url!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder)) else placeholder,
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
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
                ],
              ),
            ),
          ),
          if (caption != null) ...[const SizedBox(height: Space.space2), Text(caption!, style: ConsoleText.caption.copyWith(color: c.text200))],
        ],
      ),
    );
  }
}
