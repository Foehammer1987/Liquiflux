import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'remote.dart';

/// The scrubber: played, buffered, chapter breaks and intro/credits spans, with a time and
/// chapter tip that follows the pointer. Seeks when you let go. With [focusable] (a TV), the
/// D-pad scrubs it too: Left / Right move a preview, Select jumps there, Back or leaving drops it.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.color,
    this.accent,
    required this.onSeek,
    this.markers = const [],
    this.chapters = const [],
    this.onScrub,
    this.focusable = false,
    this.focusNode,
    this.step = const Duration(seconds: 10),
  });
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Color color;

  /// Second colour: the start of the played gradient and the intro / credits spans.
  final Color? accent;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onScrub;
  final List<PlexMarker> markers;
  final List<PlexChapter> chapters;

  /// Takes focus from the D-pad and scrubs with Left / Right.
  final bool focusable;
  final FocusNode? focusNode;

  /// How far one press of Left / Right moves the preview (more while held).
  final Duration step;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _hover; // 0..1 under the pointer
  double? _drag; // 0..1 while dragging
  bool _focused = false;
  DateTime? _heldSince;

  // The tip lives in the page's overlay, pinned to the bar, so the frosted control bar's
  // clip can't cut it off and it sits above everything else.
  final _link = LayerLink();
  final _tip = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _tip.show();
  }

  double _frac(double dx, double w) => (dx / w).clamp(0.0, 1.0);
  Duration _at(double f) => Duration(milliseconds: (widget.duration.inMilliseconds * f).round());

  void _end() {
    final d = _drag;
    if (d != null) widget.onSeek(_at(d));
    setState(() => _drag = null);
    widget.onScrub?.call(false);
  }

  void _cancel() {
    if (_drag == null) return;
    setState(() => _drag = null);
    widget.onScrub?.call(false);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    final total = widget.duration.inMilliseconds;
    if (e is KeyUpEvent || total <= 0) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      final now = DateTime.now();
      if (e is KeyDownEvent) _heldSince = now;
      final secs = heldSkip(widget.step.inSeconds, now.difference(_heldSince ?? now));
      final by = secs * 1000 / total * (k == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      if (_drag == null) widget.onScrub?.call(true);
      setState(() => _drag = ((_drag ?? widget.position.inMilliseconds / total) + by).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    if (_drag != null && e is KeyDownEvent) {
      if (selectKeys.contains(k)) {
        _end();
        return KeyEventResult.handled;
      }
      if (k != LogicalKeyboardKey.goBack && backKeys.contains(k)) {
        _cancel();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final played = total <= 0 ? 0.0 : (_drag ?? widget.position.inMilliseconds / total).clamp(0.0, 1.0);
        final tip = _drag ?? _hover ?? (_focused ? played : null);
        final active = tip != null;
        final bar = MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => setState(() => _hover = _frac(e.localPosition.dx, w)),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) => widget.onSeek(_at(_frac(e.localPosition.dx, w))),
            onHorizontalDragStart: (e) {
              setState(() => _drag = _frac(e.localPosition.dx, w));
              widget.onScrub?.call(true);
            },
            onHorizontalDragUpdate: (e) => setState(() => _drag = _frac(e.localPosition.dx, w)),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            child: SizedBox(
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: active ? 1 : 0),
                      duration: const Duration(milliseconds: 140),
                      builder: (context, t, _) => CustomPaint(
                        painter: _BarPainter(
                          played: played,
                          buffered: total <= 0 ? 0 : (widget.buffered.inMilliseconds / total).clamp(0.0, 1.0),
                          markers: [
                            for (final m in widget.markers)
                              if (total > 0) (m.startMs / total, m.endMs / total),
                          ],
                          breaks: [
                            for (final c in widget.chapters)
                              if (total > 0 && c.startMs > 0) c.startMs / total,
                          ],
                          color: widget.color,
                          accent: widget.accent ?? Color.lerp(widget.color, Colors.white, 0.25)!,
                          grow: t,
                          hover: _hover,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CompositedTransformTarget(
                      link: _link,
                      child: OverlayPortal(
                        controller: _tip,
                        overlayChildBuilder: (context) => tip == null || total <= 0
                            ? const SizedBox.shrink()
                            : Align(
                                alignment: Alignment.topLeft,
                                child: CompositedTransformFollower(
                                  link: _link,
                                  showWhenUnlinked: false,
                                  followerAnchor: Alignment.bottomLeft,
                                  offset: Offset((tip * w - 80).clamp(-8.0, w - 152), -2),
                                  child: IgnorePointer(
                                    child: SizedBox(
                                      width: 160,
                                      child: Center(
                                        heightFactor: 1,
                                        child: _Tip(time: _at(tip), chapter: _chapterAt(_at(tip))?.title, color: widget.color),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (!widget.focusable) return bar;
        return Focus(
          focusNode: widget.focusNode,
          onKeyEvent: _onKey,
          onFocusChange: (f) {
            setState(() => _focused = f);
            if (!f) _cancel();
          },
          child: DecoratedBox(position: DecorationPosition.foreground, decoration: tvRing(_focused, radius: 14) ?? const BoxDecoration(), child: bar),
        );
      },
    );
  }

  PlexChapter? _chapterAt(Duration t) {
    final ms = t.inMilliseconds;
    return widget.chapters.where((c) => ms >= c.startMs && ms < c.endMs).firstOrNull;
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.time, required this.chapter, required this.color});
  final Duration time;
  final String? chapter;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.space3, vertical: Space.space1 + 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(Radii.radiusMd),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          clock(time),
          style: ConsoleText.bodyStrong.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (chapter != null && chapter!.isNotEmpty)
          Text(
            chapter!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
      ],
    ),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.played, required this.buffered, required this.markers, required this.breaks, required this.color, required this.accent, required this.grow, required this.hover});
  final double played;
  final double buffered;
  final List<(double, double)> markers;
  final List<double> breaks;
  final Color color;
  final Color accent;
  final double grow;
  final double? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final h = 4 + 3 * grow;
    final y = size.height / 2;
    final w = size.width;
    final r = Radius.circular(h / 2);
    RRect bar(double a, double b) => RRect.fromLTRBR(a * w, y - h / 2, b * w, y + h / 2, r);

    // Chapter breaks cut small gaps out of the whole bar.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRRect(bar(0, 1), Paint()..color = Colors.white.withValues(alpha: 0.22));
    canvas.drawRRect(bar(0, buffered), Paint()..color = Colors.white.withValues(alpha: 0.28));
    for (final (a, b) in markers) {
      canvas.drawRect(Rect.fromLTRB(a * w, y - h / 2, b * w, y + h / 2), Paint()..color = accent.withValues(alpha: 0.6));
    }
    if (hover != null && hover! > played) canvas.drawRRect(bar(played, hover!), Paint()..color = Colors.white.withValues(alpha: 0.25));
    final fill = Paint()..shader = LinearGradient(colors: [accent, color]).createShader(Rect.fromLTWH(0, 0, (played * w).clamp(1, w), size.height));
    canvas.drawRRect(bar(0, played), fill);
    for (final b in breaks) {
      canvas.drawRect(Rect.fromLTWH(b * w - 1.5, y - h, 3, h * 2), Paint()..blendMode = BlendMode.clear);
    }
    canvas.restore();

    // Thumb, with a soft glow in the title's colour.
    final thumb = 6 + 2 * grow;
    final at = Offset(played * w, y);
    canvas.drawCircle(
      at,
      thumb + 6,
      Paint()
        ..color = color.withValues(alpha: 0.25 * grow + 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(at, thumb * (0.6 + 0.4 * grow), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.played != played ||
      o.buffered != buffered ||
      o.grow != grow ||
      o.hover != hover ||
      o.color != color ||
      o.accent != accent ||
      o.markers.length != markers.length ||
      o.breaks.length != breaks.length;
}
