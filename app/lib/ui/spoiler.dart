import 'dart:ui' show ImageFilter;

import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

/// Blurs an unwatched episode's still when spoilers are hidden (Settings > Appearance).
class SpoilerBlur extends StatelessWidget {
  const SpoilerBlur({super.key, required this.hide, required this.child, this.icon = true});
  final bool hide;
  final Widget child;

  /// A small closed-eye mark, so it reads as hidden rather than a bad picture.
  final bool icon;

  @override
  Widget build(BuildContext context) {
    if (!hide) return child;
    return ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.decal), child: child),
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.18))),
          if (icon)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: const Icon(LucideIcons.eyeOff, size: 12, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}

/// An unwatched episode's synopsis, kept back until asked for.
class SpoilerText extends StatefulWidget {
  const SpoilerText({super.key, required this.hide, required this.builder, this.style});
  final bool hide;
  final WidgetBuilder builder;
  final TextStyle? style;
  @override
  State<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<SpoilerText> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.hide || _shown) return widget.builder(context);
    final c = context.c;
    return Focusable(
      onTap: () => setState(() => _shown = true),
      semanticLabel: 'Show the story',
      builder: (context, hover, focus) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.space1, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.radiusSm),
          border: focus ? Border.all(color: c.primary, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.eyeOff, size: 14, color: hover || focus ? c.link : c.text300),
            const SizedBox(width: Space.space1),
            Flexible(
              child: Text(
                'Story hidden until you’ve watched it. Show it',
                style: (widget.style ?? ConsoleText.small).copyWith(color: hover || focus ? c.link : c.text300, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
