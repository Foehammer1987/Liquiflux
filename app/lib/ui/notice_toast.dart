import 'dart:ui' show ImageFilter;

import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

/// A frosted card that slides in at the bottom right ("Ready to watch", a Watch Together
/// invitation), glowing in the title's colours, with its main action right on it.
class NoticeToast extends StatefulWidget {
  const NoticeToast({
    super.key,
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.body,
    required this.primary,
    required this.onPrimary,
    required this.onDismiss,
    this.poster,
    this.art,
    this.primaryIcon = LucideIcons.play,
    this.secondary,
    this.onSecondary,
    this.lifetime = const Duration(seconds: 12),
  });
  final String eyebrow;
  final IconData icon;
  final String title;
  final String body;
  final String? poster;

  /// Where its colour comes from (the backdrop, else the poster).
  final String? art;
  final String primary;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final VoidCallback onDismiss;
  final Duration lifetime;

  @override
  State<NoticeToast> createState() => _NoticeToastState();
}

class _NoticeToastState extends State<NoticeToast> with SingleTickerProviderStateMixin {
  late final _life = AnimationController(vsync: this, duration: widget.lifetime)..forward();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final poster = widget.poster;
    return MouseRegion(
      // Pointing at it holds it open.
      onEnter: (_) {
        setState(() => _hover = true);
        _life.stop();
      },
      onExit: (_) {
        setState(() => _hover = false);
        _life.forward();
      },
      child: ArtTint(
        url: widget.art ?? poster,
        fallback: c.primary,
        builder: (context, tint) => ClipRRect(
          borderRadius: BorderRadius.circular(Radii.radiusLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 380,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color.lerp(Colors.black, tint, 0.32)!.withValues(alpha: 0.86), Colors.black.withValues(alpha: 0.78)]),
                borderRadius: BorderRadius.circular(Radii.radiusLg),
                border: Border.all(color: tint.withValues(alpha: 0.55)),
                boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 30)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Space.space3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: widget.onSecondary ?? widget.onPrimary,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.radiusMd),
                            child: SizedBox(
                              width: 64,
                              height: 96,
                              child: poster == null ? ColoredBox(color: tint.withValues(alpha: 0.3)) : ArtImage(poster, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(widget.icon, size: 14, color: tint),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      widget.eyebrow,
                                      style: ConsoleText.caption.copyWith(color: tint, letterSpacing: 1.6, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Focusable(
                                    onTap: widget.onDismiss,
                                    semanticLabel: 'Dismiss',
                                    builder: (_, hover, _) => Icon(LucideIcons.x, size: 16, color: Colors.white.withValues(alpha: hover ? 1 : 0.6)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: ConsoleText.titleMd.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                              ),
                              const SizedBox(height: Space.space3),
                              Row(
                                children: [
                                  ConsoleButton(label: widget.primary, icon: widget.primaryIcon, kind: ButtonKind.primary, onPressed: widget.onPrimary),
                                  if (widget.secondary != null) ...[const SizedBox(width: Space.space2), ConsoleButton(label: widget.secondary!, onPressed: widget.onSecondary)],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // How long it stays: a thin bar in the title's colour that runs down.
                  AnimatedBuilder(
                    animation: _life,
                    builder: (_, _) => LinearProgressIndicator(value: _hover ? 1 : 1 - _life.value, minHeight: 2, backgroundColor: Colors.transparent, color: tint.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
