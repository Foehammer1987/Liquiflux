import 'dart:async';

import 'package:console_ui/console_ui.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/screen_brightness.dart';

/// What a drag or pinch on the picture is doing, once it has moved far enough to tell.
enum PlayerGesture { none, seek, volume, brightness, pinch }

/// Phones and tablets: gestures on the picture, around the player's own taps.
///
/// * Up or down on the right half: the player's volume. On the left half: the screen's
///   brightness (put back when the player closes, see [ScreenBrightness.reset]).
/// * Sideways: seek, shown as the time it would go to; it happens on release, and dragging
///   back to where it started (within [seekDeadband]) cancels it.
/// * Two fingers apart or together: the picture fills the screen or fits inside it.
///
/// A touch that starts in [edges] (the screen's own swipes: back at the left, the home
/// indicator at the bottom, Control Center and notifications at the top) is left to the
/// system, as is anything while [enabled] is false (a panel open, the controls locked, or
/// Settings' Player Gestures off). Taps and double taps on the [child] are unaffected: a
/// gesture only begins once a finger has moved [slop].
class PlayerGestures extends StatefulWidget {
  const PlayerGestures({
    super.key,
    required this.enabled,
    required this.child,
    required this.position,
    required this.duration,
    required this.volume,
    required this.onVolume,
    required this.onSeek,
    required this.fill,
    required this.onFill,
    this.edges = const EdgeInsets.fromLTRB(28, 44, 28, 36),
    this.brightness,
  });

  final bool enabled;
  final Widget child;
  final Duration Function() position;
  final Duration Function() duration;

  /// The player's volume, 0 to 100.
  final double Function() volume;
  final ValueChanged<double> onVolume;
  final ValueChanged<Duration> onSeek;

  /// Whether the picture fills the screen now.
  final bool fill;
  final ValueChanged<bool> onFill;
  final EdgeInsets edges;

  /// The screen's brightness (tests hand in their own).
  final ScreenBrightness? brightness;

  /// How far a finger moves before a drag counts (Flutter's own touch slop).
  static const slop = kTouchSlop;

  /// A sideways drag across the whole width moves this far.
  static const seekSpan = Duration(seconds: 120);

  /// A seek this close to where it started is no seek at all.
  static const seekDeadband = Duration(seconds: 2);

  @override
  State<PlayerGestures> createState() => PlayerGesturesState();
}

@visibleForTesting
class PlayerGesturesState extends State<PlayerGestures> {
  PlayerGesture mode = PlayerGesture.none;
  Offset _start = Offset.zero;
  bool _ignored = false;
  double _startLevel = 0;

  /// 0 to 1 for volume and brightness, while they change.
  double level = 0;

  /// Where a seek would go, while dragging.
  Duration? seekTarget;
  Duration _seekFrom = Duration.zero;
  double _scale = 1;
  Timer? _hide;

  /// The indicator on screen (it stays a moment after a volume or brightness drag ends).
  PlayerGesture showing = PlayerGesture.none;

  ScreenBrightness get _brightness => widget.brightness ?? ScreenBrightness.instance;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  bool _inEdge(Offset p, Size size) => p.dx < widget.edges.left || p.dx > size.width - widget.edges.right || p.dy < widget.edges.top || p.dy > size.height - widget.edges.bottom;

  /// Where the first finger touched: the scale gesture itself only starts once it has moved.
  Offset? _down;
  double _brightnessNow = 0.5;

  void _onDown(PointerDownEvent e) {
    if (_down != null) return;
    _down = e.localPosition;
    // Read now, so a brightness drag starts from it without waiting.
    unawaited(_brightness.get().then((b) => _brightnessNow = b));
  }

  void _onUp(PointerEvent _) => _down = null;

  void _onStart(ScaleStartDetails d, Size size) {
    _hide?.cancel();
    mode = PlayerGesture.none;
    _start = _down ?? d.localFocalPoint;
    _ignored = !widget.enabled || _inEdge(_start, size);
    _scale = 1;
  }

  void _onUpdate(ScaleUpdateDetails d, Size size) {
    if (_ignored) return;
    if (mode == PlayerGesture.none) {
      if (d.pointerCount >= 2) {
        mode = PlayerGesture.pinch;
      } else {
        final delta = d.localFocalPoint - _start;
        if (delta.distance < PlayerGestures.slop) return;
        if (delta.dx.abs() > delta.dy.abs()) {
          mode = PlayerGesture.seek;
          _seekFrom = widget.position();
        } else if (_start.dx < size.width / 2) {
          mode = PlayerGesture.brightness;
          _startLevel = _brightnessNow;
        } else {
          mode = PlayerGesture.volume;
          _startLevel = widget.volume() / 100;
        }
        HapticFeedback.selectionClick();
      }
      if (mode != PlayerGesture.pinch) setState(() => showing = mode);
    }
    final delta = d.localFocalPoint - _start;
    switch (mode) {
      case PlayerGesture.seek:
        final ms = (delta.dx / size.width * PlayerGestures.seekSpan.inMilliseconds).round();
        final total = widget.duration();
        var to = _seekFrom + Duration(milliseconds: ms);
        if (to < Duration.zero) to = Duration.zero;
        if (total > Duration.zero && to > total) to = total;
        setState(() => seekTarget = to);
      case PlayerGesture.volume || PlayerGesture.brightness:
        // Three quarters of the height covers the whole range.
        final next = (_startLevel - delta.dy / (size.height * 0.75)).clamp(0.0, 1.0);
        setState(() => level = next);
        if (mode == PlayerGesture.volume) {
          widget.onVolume(next * 100);
        } else {
          unawaited(_brightness.set(next));
        }
      case PlayerGesture.pinch:
        _scale = d.scale;
      case PlayerGesture.none:
        return;
    }
  }

  void _onEnd(ScaleEndDetails _) {
    if (_ignored) return;
    switch (mode) {
      case PlayerGesture.seek:
        final to = seekTarget;
        if (to != null && (to - _seekFrom).abs() >= PlayerGestures.seekDeadband) {
          widget.onSeek(to);
          HapticFeedback.lightImpact();
        }
      case PlayerGesture.pinch:
        if (_scale > 1.12 && !widget.fill) {
          widget.onFill(true);
          HapticFeedback.lightImpact();
        } else if (_scale < 0.9 && widget.fill) {
          widget.onFill(false);
          HapticFeedback.lightImpact();
        }
      case PlayerGesture.volume || PlayerGesture.brightness || PlayerGesture.none:
        break;
    }
    final was = mode;
    setState(() {
      mode = PlayerGesture.none;
      seekTarget = null;
      if (was == PlayerGesture.seek) showing = PlayerGesture.none;
    });
    // A level stays up a moment after the finger lifts.
    _hide = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => showing = PlayerGesture.none);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      return Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            onPointerDown: _onDown,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: GestureDetector(behavior: HitTestBehavior.translucent, onScaleStart: (d) => _onStart(d, size), onScaleUpdate: (d) => _onUpdate(d, size), onScaleEnd: _onEnd, child: widget.child),
          ),
          if (showing != PlayerGesture.none) IgnorePointer(child: Center(child: _indicator(context))),
        ],
      );
    },
  );

  Widget _indicator(BuildContext context) {
    final style = ConsoleText.titleMd.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]);
    final Widget content;
    if (showing == PlayerGesture.seek) {
      final to = seekTarget ?? _seekFrom;
      final by = to - _seekFrom;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_clock(to), style: style.copyWith(fontSize: 26)),
          const SizedBox(height: 2),
          Text('${by.isNegative ? '−' : '+'}${_clock(by.abs())}', style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.75))),
        ],
      );
    } else if (showing == PlayerGesture.volume || showing == PlayerGesture.brightness) {
      final volume = showing == PlayerGesture.volume;
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(volume ? (level == 0 ? LucideIcons.volumeX : LucideIcons.volume2) : LucideIcons.sun, color: Colors.white, size: 22),
          const SizedBox(width: Space.space3),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: level, minHeight: 6, backgroundColor: Colors.white.withValues(alpha: 0.25), color: Colors.white),
            ),
          ),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.space5, vertical: Space.space3),
        child: content,
      ),
    );
  }
}

String _clock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
