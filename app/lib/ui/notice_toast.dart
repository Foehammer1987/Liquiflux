import 'dart:ui' show ImageFilter;

import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player/remote.dart' show backKeys;

/// A frosted card that slides in at the bottom right ("Ready to watch", a Watch Together
/// invitation), glowing in the title's colours, with its main action right on it.
///
/// With [takeFocus] (a TV, nothing covering the pages) it takes the remote's focus as it comes
/// in, on its main button, since the arrows can't reach a card in the corner from a page.
/// Back closes it, and when it goes, focus returns to where it was.
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
    this.takeFocus = false,
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
  final bool takeFocus;

  @override
  State<NoticeToast> createState() => _NoticeToastState();
}

class _NoticeToastState extends State<NoticeToast> with SingleTickerProviderStateMixin {
  late final _life = AnimationController(vsync: this, duration: widget.lifetime)..forward();
  bool _hover = false;

  final _card = FocusScopeNode(debugLabel: 'notice card');
  final _primary = FocusNode(debugLabel: 'notice main button');
  final _close = FocusNode(debugLabel: 'notice dismiss');

  /// Where the remote's focus was before the card took it.
  FocusNode? _before;

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDismiss();
    });
    if (widget.takeFocus) {
      _before = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (widget.onPrimary != null ? _primary : _close).requestFocus();
      });
    }
  }

  @override
  void dispose() {
    final hadFocus = _card.hasFocus;
    final before = _before;
    _life.dispose();
    _card.dispose();
    _primary.dispose();
    _close.dispose();
    if (hadFocus && before != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Not when what the card did covered the pages (the player, a popup).
        final ctx = before.context;
        if (ctx != null && ctx.mounted && before.canRequestFocus && (ModalRoute.of(ctx)?.isCurrent ?? true)) before.requestFocus();
      });
    }
    super.dispose();
  }

  /// Back closes the card (its key-up too, so it doesn't step a page back as well).
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!backKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) widget.onDismiss();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final poster = widget.poster;
    return FocusScope(
      node: _card,
      onKeyEvent: _onKey,
      child: _build(context, c, poster),
    );
  }

  Widget _build(BuildContext context, ConsoleColors c, String? poster) {
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
                                    focusNode: _close,
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
                                  ConsoleButton(label: widget.primary, icon: widget.primaryIcon, kind: ButtonKind.primary, focusNode: _primary, onPressed: widget.onPrimary),
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
