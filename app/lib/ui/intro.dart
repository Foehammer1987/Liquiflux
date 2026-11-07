import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:console_ui/console_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_info.dart';
import 'player/remote.dart' show isExitKey;

/// The startup animation, "flow": the logo's two ribbons of liquid fly in twisting from
/// opposite edges of the screen (the L from the left, the outer layer from the right) and lay
/// themselves down into the LF. A shine runs across it, it glows, rises, and ripples roll out
/// across a waterline as the name's letters surface one by one; then it all fades and the app
/// shows through.
///
/// It starts from the Android launch screen's plain dark background (see
/// res/drawable/launch_background.xml), so the hand-over doesn't jump. Kept light for 2 GB TVs:
/// the flying part of each ribbon is a few hundred short lines along a precomputed route; the
/// part that has landed is the real logo (one small image per ribbon) shown through a thick
/// stroke along its centre line, in a layer only as big as the logo; no blur. The fade-out
/// animates the background's colour instead of putting an opacity layer over the whole
/// screen. Any key or a click skips to the fade-out; the key is swallowed so it doesn't also
/// act on Home.
class Intro extends StatefulWidget {
  const Intro({super.key, required this.onDone});
  final VoidCallback onDone;

  static const total = Duration(milliseconds: 3600);

  /// The logo's height as a share of the screen's (124 dp of a 1080p TV's 540).
  static const heightShare = 124 / 540;

  /// The two ribbons of the logo, drawn separately so each can land on its own. 800×600 each,
  /// the logo's whole box (see [_Ribbon]); decoded no bigger than the screen needs.
  static const ribbons = [
    ResizeImage(AssetImage('assets/logos/ribbon-1.png', package: 'console_ui'), height: 440, policy: ResizeImagePolicy.fit),
    ResizeImage(AssetImage('assets/logos/ribbon-2.png', package: 'console_ui'), height: 440, policy: ResizeImagePolicy.fit),
  ];

  static const background = Color(0xFF0C0C0C);

  static final _images = <ui.Image?>[null, null];

  /// Decodes both ribbons before the first frame, so they're ready when they land.
  static Future<void> preload() => Future.wait([for (var i = 0; i < ribbons.length; i++) _decode(i)]);

  static Future<void> _decode(int i) {
    final done = Completer<void>();
    final stream = ribbons[i].resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        _images[i] = info.image.clone();
        info.dispose();
        if (!done.isCompleted) done.complete();
        stream.removeListener(l);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(l);
      },
    );
    stream.addListener(l);
    return done.future.timeout(const Duration(seconds: 1), onTimeout: () {});
  }

  /// Once the intro is over (or isn't shown): the images' memory goes, and on Android the
  /// window behind the app goes back from the launch screen to black, which the video plane
  /// needs (see MainActivity.onCreate).
  static Future<void> over() async {
    for (var i = 0; i < _images.length; i++) {
      _images[i]?.dispose();
      _images[i] = null;
      ribbons[i].evict();
    }
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('liquiflux/window').invokeMethod<void>('plain');
    } on MissingPluginException {
      // Tests.
    } on PlatformException catch (e) {
      debugPrint('intro: window background: ${e.message}');
    }
  }

  @override
  State<Intro> createState() => _IntroState();
}

/// Times in ms on the [Intro.total] clock.
const _full = 1450.0; // both ribbons have landed
const _riseStart = 1350.0, _riseEnd = 2150.0; // the logo rises, the name surfaces beneath it
const _leaveStart = 2900.0; // 2900–3600: fade into the app

double _span(double ms, double a, double b, [Curve curve = Curves.linear]) => curve.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Intro.total)..addStatusListener(_status);
  late final _KeySwallow _keys;
  final _clock = Stopwatch()..start();
  bool _skipped = false;

  double get _ms => _c.value * Intro.total.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _keys = _KeySwallow(_skip);
    _c.forward();
  }

  void _status(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    debugPrint('intro: done after ${_clock.elapsedMilliseconds} ms${_skipped ? ' (skipped)' : ''}');
    _keys.finish();
    widget.onDone();
  }

  void _skip() {
    if (_skipped || _ms >= _leaveStart) return;
    _skipped = true;
    _c.value = _leaveStart / Intro.total.inMilliseconds;
    _c.forward();
  }

  @override
  void dispose() {
    _keys.finish();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Semantics(
      label: appName,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(animation: _c, builder: (context, _) => _frame(_Frame(size, _ms))),
      ),
    );
  }

  Widget _frame(_Frame f) {
    final name = _span(f.ms, _riseStart + 200, _riseEnd + 300);
    return CustomPaint(
      painter: _Pool(f),
      foregroundPainter: _Logo(f),
      child: name <= 0
          ? const SizedBox.expand()
          : Opacity(
              opacity: 1 - f.leave,
              child: Transform.scale(
                scale: f.zoom,
                child: Stack(
                  children: [Positioned(left: 0, right: 0, top: f.textY - f.fontSize / 2, child: Center(child: _risingLetters(f, name)))],
                ),
              ),
            ),
    );
  }

  /// Above MaterialApp's pages there's no Material to give text a style, so set it all here.
  static TextStyle _style(_Frame f, Color color) => ConsoleText.display.copyWith(
    fontSize: f.fontSize,
    height: 1,
    fontWeight: FontWeight.w500,
    letterSpacing: f.fontSize * _tracking,
    color: color,
    decoration: TextDecoration.none,
  );

  static const _tracking = 0.42;

  /// The name's letters rising one after another out of the pool, as [p] goes 0 → 1.
  Widget _risingLetters(_Frame f, double p) {
    final letters = appName.toUpperCase().split('');
    return Padding(
      // Letter spacing also follows the last letter; balance it so the name stays centred.
      padding: EdgeInsets.only(left: f.fontSize * _tracking),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, l) in letters.indexed)
            Builder(
              builder: (_) {
                final q = Curves.easeOutBack.transform(((p * (letters.length + 4) - i) / 5).clamp(0.0, 1.0));
                return Transform.translate(
                  offset: Offset(0, f.fontSize * 0.9 * (1 - q)),
                  child: Text(l, style: _style(f, Color.fromRGBO(255, 255, 255, q.clamp(0.0, 1.0)))),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Where things are on one frame.
class _Frame {
  _Frame(this.size, this.ms)
    : leave = _span(ms, _leaveStart, Intro.total.inMilliseconds.toDouble(), Curves.easeInCubic),
      rise = _span(ms, _riseStart, _riseEnd, Curves.easeInOutCubic);
  final Size size;
  final double ms, leave, rise;

  /// Grows a little and rises to make room for the name.
  double get logoHeight => size.height * Intro.heightShare * (1 + 0.12 * rise);
  double get logoWidth => logoHeight * _Ribbon.box.width / _Ribbon.box.height;
  Offset get logoCentre => Offset(size.width / 2, size.height / 2 - size.height * 0.11 * rise);
  Rect get logoRect => Rect.fromCenter(center: logoCentre, width: logoWidth, height: logoHeight);
  double get zoom => 1 + 0.08 * leave;
  double get fontSize => size.height * 0.074;
  double get textY => size.height * 0.665;
  double get lineY => textY + fontSize * 0.95;
  double get lineWidth => size.height * 0.62 * _span(ms, _riseStart + 450, _riseEnd + 500, Curves.easeOutCubic);
}

/// One of the logo's two ribbons: where it flies in from ([lead], from off screen to just
/// above the logo) and the centre line it then lays down along ([mark]), in the logo's own
/// units (its box is [box]; the screen is roughly −1400…2800 wide in them).
class _Ribbon {
  _Ribbon({required this.image, required Path lead, required Path mark, required this.width, required this.start, required this.end, required this.front, required this.back})
    : leadLength = _length(lead),
      _mark = mark.computeMetrics().first {
    markLength = _mark.length;
    final total = leadLength + markLength;
    final leadMetric = lead.computeMetrics().first;
    for (var i = 0; i <= _samples; i++) {
      final s = i / _samples * total;
      final t = s <= leadLength ? leadMetric.getTangentForOffset(s) : _mark.getTangentForOffset(s - leadLength);
      _points.add(t?.position ?? Offset.zero);
      _at.add(s);
    }
  }

  static const box = Rect.fromLTWH(467, 204, 480, 360);
  static const _samples = 420;

  final int image;
  final double width, start, end;
  final Color front, back;
  final double leadLength;
  late final double markLength;
  final ui.PathMetric _mark;
  final _points = <Offset>[];
  final _at = <double>[];

  static double _length(Path p) => p.computeMetrics().first.length;

  static final all = [
    // The L and the F's top arm, from the left.
    _Ribbon(
      image: 0,
      lead: Path()
        ..moveTo(-1050, 760)
        ..cubicTo(-650, 1050, -300, 520, -120, 160)
        ..cubicTo(40, -160, 380, -40, 509, 120),
      mark: Path()
        ..moveTo(509, 120)
        ..lineTo(509, 455)
        ..cubicTo(509, 490, 530, 502, 560, 502)
        ..lineTo(640, 502)
        ..cubicTo(700, 502, 740, 470, 740, 420)
        ..lineTo(740, 300)
        ..cubicTo(740, 268, 760, 247, 795, 247)
        ..lineTo(905, 247),
      width: 72,
      start: 120,
      end: 1300,
      front: const Color(0xFF1A7CFF),
      back: const Color(0xFF083482),
    ),
    // The outer layer and the F's middle arm, from the right.
    _Ribbon(
      image: 1,
      lead: Path()
        ..moveTo(2450, -150)
        ..cubicTo(2000, -40, 1900, 700, 1550, 690)
        ..cubicTo(1250, 680, 1150, 382, 980, 382),
      mark: Path()
        ..moveTo(980, 382)
        ..lineTo(860, 382)
        ..cubicTo(800, 382, 770, 410, 755, 455)
        ..cubicTo(742, 505, 715, 538, 660, 538)
        ..lineTo(535, 538)
        ..cubicTo(505, 538, 492, 520, 490, 490),
      width: 40,
      start: 300,
      end: _full,
      front: const Color(0xFF4FC0F5),
      back: const Color(0xFF0A3780),
    ),
  ];

  /// How far along the whole route the ribbon's head and tail are at [ms]: it's as long as
  /// [mark] plus a little while flying, and the tail reaches the logo as the head finishes.
  (double head, double tail) at(double ms) {
    final p = _span(ms, start, end, Curves.easeInOutCubic);
    final head = p * (leadLength + markLength);
    return (head, max(0.0, head - markLength - 600 * (1 - p)));
  }

  /// How much of [mark] has been laid down.
  double landed(double ms) => (at(ms).$1 - leadLength).clamp(0.0, markLength);

  /// The flying part: short lines whose width and shade follow a twist that travels along
  /// the ribbon and straightens out as it reaches the logo.
  void paintFlying(Canvas canvas, double ms, Paint paint) {
    final (head, tail) = at(ms);
    final end = min(head, leadLength);
    if (end <= tail) return;
    for (var i = 1; i < _points.length; i++) {
      final s = _at[i];
      if (s < tail || _at[i - 1] < tail) continue;
      if (s > end) break;
      final d = leadLength - s;
      final c = cos((d / 480 * pi + ms / 1000 * 3) * min(1.0, d / 320));
      final w = width * (1 + 0.35 * min(1.0, d / 600)) * (0.18 + 0.82 * c.abs()) * min(1.0, (s - tail) / 220);
      final shade = 0.75 + 0.25 * c.abs();
      final base = c >= 0 ? front : back;
      paint
        ..color = Color.from(alpha: 1, red: base.r * shade, green: base.g * shade, blue: base.b * shade)
        ..strokeWidth = w;
      canvas.drawLine(_points[i - 1], _points[i], paint);
      if (c.abs() > 0.92) {
        paint
          ..color = const Color(0x59A6DCFF)
          ..strokeWidth = w * 0.18;
        canvas.drawLine(_points[i - 1], _points[i], paint);
      }
    }
  }

  /// The landed part: the real ribbon, seen through a thick stroke along [mark] so far.
  void paintLanded(Canvas canvas, double ms, ui.Image img, double opacity) {
    final shown = landed(ms);
    if (shown <= 0) return;
    final dst = box;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final imagePaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    if (shown >= markLength - 1) {
      canvas.drawImageRect(img, src, dst, imagePaint);
      return;
    }
    canvas.saveLayer(dst, Paint());
    canvas.drawPath(
      _mark.extractPath(0, shown),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawImageRect(img, src, dst, imagePaint..blendMode = BlendMode.srcIn);
    canvas.restore();
  }
}

/// The logo: its ribbons flying in, landing, and the shine across it once they're down.
class _Logo extends CustomPainter {
  _Logo(this.f);
  final _Frame f;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = 1 - f.leave;
    if (fade <= 0) return;
    final ms = f.ms;
    final r = f.logoRect;
    final k = r.height / _Ribbon.box.height;
    canvas.save();
    // Zoom about the screen's centre as it leaves, then into the logo's own units.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(f.zoom);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.translate(r.left - _Ribbon.box.left * k, r.top - _Ribbon.box.top * k);
    canvas.scale(k);
    final line = Paint()..strokeCap = StrokeCap.round;
    for (final ribbon in _Ribbon.all) {
      ribbon.paintFlying(canvas, ms, line);
      final img = Intro._images[ribbon.image];
      if (img != null) ribbon.paintLanded(canvas, ms, img, fade);
    }
    // A band of light sweeping across once both have landed.
    final shine = _span(ms, _full - 50, _full + 450, Curves.easeOutCubic);
    final images = Intro._images;
    if (shine > 0 && shine < 1 && images.every((i) => i != null)) {
      final box = _Ribbon.box;
      canvas.saveLayer(box, Paint());
      for (final img in images) {
        canvas.drawImageRect(img!, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), box, Paint()..filterQuality = FilterQuality.medium);
      }
      final x = box.left - box.width * 0.3 + box.width * 1.6 * shine;
      canvas.drawRect(
        box,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = ui.Gradient.linear(
            Offset(x - box.width * 0.18, box.top),
            Offset(x + box.width * 0.18, box.top + box.height * 0.3),
            [const Color(0x00FFFFFF), Color.fromRGBO(220, 240, 255, 0.55 * fade), const Color(0x00FFFFFF)],
            [0, 0.5, 1],
          ),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Logo old) => old.f.ms != f.ms || old.f.size != f.size;
}

/// Everything behind the logo, painted straight onto the screen with no layers: the
/// background, the glow, the ripples and the waterline under the name.
class _Pool extends CustomPainter {
  _Pool(this.f);
  final _Frame f;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = f.ms;
    final fade = 1 - f.leave;
    canvas.drawRect(Offset.zero & size, Paint()..color = Intro.background.withValues(alpha: fade));
    if (fade <= 0) return;
    final centre = f.logoCentre;

    // Glow, rising as the ribbons arrive, flaring when they've landed.
    final full = _span(ms, _full - 100, _full + 250, Curves.easeOut) - 0.5 * _span(ms, _full + 250, _full + 1100);
    final bloom = (0.05 * _span(ms, 0, 400) + 0.1 * _span(ms, 300, _full) + 0.2 * full) * fade;
    final bloomR = f.logoHeight * 1.9;
    canvas.drawCircle(
      centre,
      bloomR,
      Paint()
        ..shader = RadialGradient(
          colors: [_blue.withValues(alpha: bloom), _blue.withValues(alpha: bloom * 0.3), _blue.withValues(alpha: 0)],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: centre, radius: bloomR)),
    );

    // Three ripples across the screen once it has landed.
    final base = Offset(centre.dx, f.lineY);
    for (var i = 0; i < 3; i++) {
      final p = _span(ms, _full + i * 200, _full + i * 200 + 1500, Curves.easeOutCubic);
      if (p <= 0 || p >= 1) continue;
      final r = size.width * 0.62 * p;
      canvas.drawOval(
        Rect.fromCenter(center: base, width: r * 2, height: r * 2 * 0.32),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - p) + 0.6
          ..color = const Color(0xFF66A8FF).withValues(alpha: (0.7 - i * 0.15) * (1 - p) * fade),
      );
    }

    // The waterline under the name.
    _line(canvas, base, f.lineWidth, fade);
  }

  @override
  bool shouldRepaint(_Pool old) => old.f.ms != f.ms || old.f.size != f.size;
}

const _blue = Color(0xFF006FFF);

/// A thin line of light opening out under the name.
void _line(Canvas canvas, Offset centre, double width, double fade) {
  if (width <= 1) return;
  final rect = Rect.fromCenter(center: centre, width: width, height: 1.5);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        colors: [const Color(0x0066A8FF), Color.fromRGBO(170, 205, 255, 0.95 * fade), const Color(0x0066A8FF)],
      ).createShader(rect),
  );
}

/// While the intro is up, any key skips it and is swallowed; so is its key-up, even when it
/// comes after the intro has gone, or an unhandled Back key-up would turn into a system Back.
/// The remote's Exit key is never taken: on a Samsung TV it closes the app from anywhere,
/// the launch animation too (flutter-tizen closes the app on an unhandled Exit key-up).
///
/// HardwareKeyboard handlers can't stop the focus system from also getting a key, so this
/// patches the key message handler once (it passes everything on when no intro is up).
class _KeySwallow {
  _KeySwallow(this.onKey) {
    _current = this;
    // The patch is the documented way to act before the focus system; its API is marked
    // deprecated only because it will go once RawKeyEvent does.
    // ignore: deprecated_member_use
    final manager = ServicesBinding.instance.keyEventManager;
    // ignore: deprecated_member_use
    if (manager.keyMessageHandler == _patch) return;
    // ignore: deprecated_member_use
    final next = manager.keyMessageHandler;
    // ignore: deprecated_member_use
    manager.keyMessageHandler = _patch = (message) {
      final s = _current;
      if (s != null && s._takes(message)) return true;
      return next?.call(message) ?? false;
    };
  }

  static _KeySwallow? _current;
  // ignore: deprecated_member_use
  static KeyMessageHandler? _patch;

  final VoidCallback onKey;
  final _down = <PhysicalKeyboardKey>{};
  bool _finished = false;

  // ignore: deprecated_member_use
  bool _takes(KeyMessage message) {
    var took = false;
    for (final e in message.events) {
      if (isExitKey(e)) continue;
      if (e is KeyUpEvent) {
        took |= _down.remove(e.physicalKey);
      } else if (!_finished) {
        _down.add(e.physicalKey);
        onKey();
        took = true;
      }
    }
    if (_finished && _down.isEmpty) _detach();
    return took;
  }

  void finish() {
    _finished = true;
    if (_down.isEmpty) _detach();
  }

  void _detach() {
    if (_current == this) _current = null;
  }
}

/// Puts the [Intro] over the app once per launch. The app builds underneath meanwhile, so
/// Home is loading while the logo plays.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  /// Played already this run (the gate can be rebuilt, e.g. when the theme changes).
  static bool played = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  late bool _showing;

  @override
  void initState() {
    super.initState();
    final first = !IntroGate.played;
    _showing = widget.enabled && first;
    IntroGate.played = true;
    if (first && !_showing) WidgetsBinding.instance.addPostFrameCallback((_) => Intro.over());
  }

  void _done() {
    if (!_showing) return;
    setState(() => _showing = false);
    Intro.over();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion && _showing) WidgetsBinding.instance.addPostFrameCallback((_) => _done());
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_showing && !reduceMotion)
          Positioned.fill(child: Intro(onDone: _done)),
      ],
    );
  }
}
