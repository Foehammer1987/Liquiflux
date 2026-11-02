import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

/// Critic reviews as a horizontal row of cards.
class ReviewRow extends StatelessWidget {
  const ReviewRow({super.key, required this.reviews});
  final List<PlexReview> reviews;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, r) in reviews.take(12).indexed) ...[
            if (i > 0) const SizedBox(width: Space.space3),
            Container(
              width: 320,
              height: 168,
              padding: const EdgeInsets.all(Space.space4),
              decoration: BoxDecoration(
                color: fx.controlFill,
                borderRadius: BorderRadius.circular(Radii.radiusMd),
                border: Border.all(color: fx.controlBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (r.image != null && r.image!.startsWith('rottentomatoes://'))
                        Padding(
                          padding: const EdgeInsets.only(right: Space.space2),
                          child: Icon(
                            r.image!.endsWith('rotten') ? LucideIcons.droplet : LucideIcons.cherry,
                            size: 14,
                            color: r.image!.endsWith('rotten') ? const Color(0xFF6AC238) : const Color(0xFFFA320A),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          r.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ConsoleText.titleSm.copyWith(color: c.text100),
                        ),
                      ),
                    ],
                  ),
                  if (r.source != null)
                    Text(
                      r.source!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ConsoleText.caption.copyWith(color: c.text300),
                    ),
                  const SizedBox(height: Space.space2),
                  Expanded(
                    child: Text(
                      r.text,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: ConsoleText.small.copyWith(color: c.text200, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
