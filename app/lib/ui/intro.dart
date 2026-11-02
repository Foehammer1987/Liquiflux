import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:console_ui/console_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_info.dart';

/// The startup animation, "liquid": a drop of blue falls onto a faint outline of the logo,
/// which fills from the bottom with rippling liquid. When it's full the logo glows, rises, and
/// ripples roll out across a waterline as the name's letters surface one by one; then it all
/// fades and the app shows through.
///
/// It starts where Android's launch screen leaves off (the same faint logo, at the same size,
/// on the same background; see res/drawable/launch_background.xml), so the hand-over doesn't
/// jump. Kept light for 2 GB TVs: one small image drawn three times (outline, back wave, front
/// wave) under simple clips, gradients and ovals painted straight onto the screen, no blur, and
/// the fade-out animates the background's colour instead of putting an opacity layer over the
/// whole screen. Any key or a click skips to the fade-out; the key is swallowed so it doesn't
/// also act on Home.
class Intro extends StatefulWidget {
  const Intro({super.key, required this.onDone});
  final VoidCallback onDone;

  static const total = Duration(milliseconds: 3400);

  /// The logo's height as a share of the screen's. Matches the launch screen: 146 dp of a
  /// 1080p TV's 540.
  static const heightShare = 146 / 540;

  /// Decoded small: the source is 799×1024, the screen needs at most ~440 px of it.
  static const logo = ResizeImage(AssetImage('assets/logos/mark-blue.png', package: 'console_ui'), height: 440, policy: ResizeImagePolicy.fit);

  /// The faint outline the liquid fills.
  static const outline = ResizeImage(AssetImage('assets/logos/mark-white.png', package: 'console_ui'), height: 440, policy: ResizeImagePolicy.fit);

  /// How strongly the outline shows. The launch screen's logo (launch_logo.png) is the white
  /// mark at this strength over [background].
  static const outlineOpacity = 0.16;

  static const background = Color(0xFF0C0C0C);

  /// Decodes both images before the first frame, so the intro's first frame already has the
  /// outline and the launch screen's doesn't blink out and back.
  static Future<void> preload() => Future.wait([_decode(outline), _decode(logo)]);

  static Future<void> _decode(ImageProvider image) {
    final done = Completer<void>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (_, _) {
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
    logo.evict();
    outline.evict();
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
const _dropLands = 380.0, _fillEnd = 1500.0; // the drop falls; the logo fills
const _riseStart = 1150.0, _riseEnd = 1950.0; // the logo rises, the name surfaces beneath it
const _leaveStart = 2750.0; // 2750–3400: fade into the app

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
    final ms = f.ms;
    final fill = _span(ms, _dropLands, _fillEnd, Curves.easeInOutSine);
    final wave = ms / 1000 * 2 * pi * 1.1;
    // Waves calm as the logo fills.
    final amp = 0.045 * (1 - pow(fill, 3).toDouble());
    final name = _span(ms, _riseStart + 200, _riseEnd + 300);
    final lh = f.logoHeight;
    return CustomPaint(
      painter: _Pool(ms: ms, leave: f.leave, logoCentre: f.logoCentre, logoHeight: lh, lineY: f.lineY, lineWidth: f.lineWidth),
      child: Opacity(
        opacity: 1 - f.leave,
        child: Transform.scale(
          scale: 1 + 0.08 * f.leave,
          child: Stack(
            children: [
              Positioned(
                left: f.logoCentre.dx - lh * 799 / 1024 / 2,
                width: lh * 799 / 1024,
                top: f.logoCentre.dy - lh / 2,
                height: lh,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Image(image: Intro.outline, fit: BoxFit.contain, opacity: AlwaysStoppedAnimation(Intro.outlineOpacity), filterQuality: FilterQuality.medium, gaplessPlayback: true),
                    ClipPath(
                      clipper: _Surface(level: fill, amp: amp, phase: wave + 1.7, lead: 0.035),
                      child: const Image(image: Intro.logo, fit: BoxFit.contain, opacity: AlwaysStoppedAnimation(0.45), filterQuality: FilterQuality.medium, gaplessPlayback: true),
                    ),
                    ClipPath(
                      clipper: _Surface(level: fill, amp: amp, phase: wave, lead: 0),
                      child: const Image(image: Intro.logo, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                    ),
                  ],
                ),
              ),
              if (name > 0) Positioned(left: 0, right: 0, top: f.textY - f.fontSize / 2, child: Center(child: _risingLetters(f, name))),
            ],
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

  /// Starts at the launch screen's size and place, grows a little and rises to make room
  /// for the name.
  double get logoHeight => size.height * Intro.heightShare * (1 + 0.12 * rise);
  Offset get logoCentre => Offset(size.width / 2, size.height / 2 - size.height * 0.11 * rise);
  double get fontSize => size.height * 0.074;
  double get textY => size.height * 0.665;
  double get lineY => textY + fontSize * 0.95;
  double get lineWidth => size.height * 0.62 * _span(ms, _riseStart + 450, _riseEnd + 500, Curves.easeOutCubic);
}

/// The surface of the liquid inside the logo: below it is filled. [level] 0 → 1 from empty
/// to full; [lead] raises this layer a little above the main one.
class _Surface extends CustomClipper<Path> {
  _Surface({required this.level, required this.amp, required this.phase, required this.lead});
  final double level, amp, phase, lead;

  @override
  Path getClip(Size size) {
    // From just under the bottom (empty) to well over the top, so the waves clear it.
    final y0 = size.height * (1.08 - 1.25 * level - lead);
    final a = size.height * amp;
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += size.width / 24) {
      path.lineTo(x, y0 + a * sin(phase + x / size.width * 2 * pi * 1.2) + a * 0.5 * sin(phase * 1.7 + x / size.width * 2 * pi * 2.3));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_Surface old) => old.level != level || old.phase != phase || old.amp != amp;
}

/// Everything behind the logo, painted straight onto the screen with no layers: the
/// background, the falling drop, the glow, the ripples and the waterline under the name.
class _Pool extends CustomPainter {
  _Pool({required this.ms, required this.leave, required this.logoCentre, required this.logoHeight, required this.lineY, required this.lineWidth});
  final double ms, leave, logoHeight, lineY, lineWidth;
  final Offset logoCentre;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = 1 - leave;
    canvas.drawRect(Offset.zero & size, Paint()..color = Intro.background.withValues(alpha: fade));
    if (fade <= 0) return;
    final top = logoCentre.dy - logoHeight / 2;

    // The drop, falling onto the logo's tip.
    if (ms < _dropLands) {
      final p = _span(ms, 60, _dropLands, Curves.easeInQuad);
      final y = -size.height * 0.05 + (top + size.height * 0.05) * p;
      final r = size.height * 0.012;
      final drop = Path()
        ..moveTo(logoCentre.dx, y - r * 3.2)
        ..quadraticBezierTo(logoCentre.dx + r * 1.1, y - r * 0.4, logoCentre.dx, y + r)
        ..quadraticBezierTo(logoCentre.dx - r * 1.1, y - r * 0.4, logoCentre.dx, y - r * 3.2);
      canvas.drawPath(drop, Paint()..color = const Color(0xFF3D8BFF));
    }

    // Glow, rising as the logo fills, flaring when it's full.
    final full = _span(ms, _fillEnd - 100, _fillEnd + 250, Curves.easeOut) - 0.5 * _span(ms, _fillEnd + 250, _fillEnd + 1100);
    final bloom = (0.06 * _span(ms, 0, 400) + 0.12 * _span(ms, _dropLands, _fillEnd) + 0.18 * full) * fade;
    final bloomR = logoHeight * 1.8;
    canvas.drawCircle(
      logoCentre,
      bloomR,
      Paint()
        ..shader = RadialGradient(
          colors: [_blue.withValues(alpha: bloom), _blue.withValues(alpha: bloom * 0.3), _blue.withValues(alpha: 0)],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: logoCentre, radius: bloomR)),
    );

    // Ripples: a small one where the drop lands, then three across the screen when it's full.
    void ripple(Offset c, double start, double length, double reach, double strength) {
      final p = _span(ms, start, start + length, Curves.easeOutCubic);
      if (p <= 0 || p >= 1) return;
      final r = reach * p;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 2, height: r * 2 * 0.32),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - p) + 0.6
          ..color = const Color(0xFF66A8FF).withValues(alpha: strength * (1 - p) * fade),
      );
    }

    ripple(Offset(logoCentre.dx, top), _dropLands, 700, logoHeight * 0.7, 0.8);
    final base = Offset(logoCentre.dx, lineY);
    for (var i = 0; i < 3; i++) {
      ripple(base, _fillEnd + i * 200, 1500, size.width * 0.62, 0.7 - i * 0.15);
    }

    // The waterline under the name.
    _line(canvas, Offset(logoCentre.dx, lineY), lineWidth, fade);
  }

  @override
  bool shouldRepaint(_Pool old) => old.ms != ms || old.logoCentre != logoCentre || old.logoHeight != logoHeight;
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
