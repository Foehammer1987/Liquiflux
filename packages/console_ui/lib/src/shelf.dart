import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'density.dart';
import 'focusable.dart';
import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

/// A titled, horizontally scrolling row of cards (the Home page rows), with paging arrows on hover.
class Shelf extends StatefulWidget {
  const Shelf({super.key, required this.title, required this.children, this.itemWidth = 176, this.spacing = Space.space5, this.trailing, this.inset = 48});
  final String title;
  final List<Widget> children;

  /// Each card's width; null lets cards size themselves (the Top rows).
  final double? itemWidth;
  final double spacing;
  final Widget? trailing;

  /// Left and right page margin; the first card lines up with the spotlight text.
  final double inset;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final _scroll = ScrollController();

  /// Pointer over the row: only the arrows rebuild, not every card.
  final _hover = ValueNotifier(false);
  bool _canBack = false;
  bool _canForward = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final back = p.pixels > 4, fwd = p.pixels < p.maxScrollExtent - 4;
    if (back != _canBack || fwd != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
    }
  }

  void _page(int dir) {
    final p = _scroll.position;
    _scroll.animateTo((p.pixels + dir * p.viewportDimension * 0.8).clamp(0, p.maxScrollExtent), duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A phone: narrower margins and cards, a smaller heading (see [ConsoleDensity]).
    final compact = ConsoleDensity.compactOf(context);
    final inset = compact ? 16.0 : widget.inset;
    final itemWidth = widget.itemWidth == null ? null : (compact ? (widget.itemWidth! * ConsoleDensity.compactScale).roundToDouble() : widget.itemWidth);
    final spacing = compact ? widget.spacing * 0.5 : widget.spacing;
    return MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: ConsoleText.titleLg.copyWith(
                      fontSize: compact ? 17 : 21,
                      fontWeight: FontWeight.w700,
                      color: c.text100,
                      shadows: Theme.of(context).brightness == Brightness.dark ? const [Shadow(color: Color(0x99000000), blurRadius: 12)] : null,
                    ),
                  ),
                ),
                ?widget.trailing,
              ],
            ),
          ),
          Stack(
            children: [
              // A resize or new cards change what's left to scroll: keep the arrows honest.
              NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _sync();
                  });
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.hardEdge,
                  padding: EdgeInsets.fromLTRB(inset, compact ? Space.space2 : Space.space3, inset, compact ? Space.space3 : Space.space4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < widget.children.length; i++) ...[
                        if (i > 0) SizedBox(width: spacing),
                        itemWidth == null ? widget.children[i] : SizedBox(width: itemWidth, child: widget.children[i]),
                      ],
                    ],
                  ),
                ),
              ),
              if (_canBack)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: _Arrow(visible: _hover, icon: LucideIcons.chevronLeft, onTap: () => _page(-1)),
                ),
              if (_canForward)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: _Arrow(visible: _hover, icon: LucideIcons.chevronRight, onTap: () => _page(1)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.visible, required this.icon, required this.onTap});
  final ValueListenable<bool> visible;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
    child: ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, visible, child) => AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: visible ? 1 : 0,
        // Hidden arrows take neither clicks nor keyboard focus.
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeFocus(excluding: !visible, child: child!),
        ),
      ),
      child: Focusable(
        onTap: onTap,
        semanticLabel: icon == LucideIcons.chevronLeft ? 'Scroll back' : 'Scroll forward',
        builder: (context, hover, _) => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hover ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.55),
            border: Border.all(color: context.fx.controlBorder),
          ),
          child: Icon(icon, size: 22, color: hover ? Colors.black : Colors.white),
        ),
      ),
    ),
  );
}
