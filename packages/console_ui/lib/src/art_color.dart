import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Colours taken from artwork, lifted so they read on a dark page.
/// Results are cached by URL; an empty palette means the art is grey or failed to load.
abstract final class ArtColor {
  static final _cache = <String, Future<List<Color>>>{};

  static void clear() => _cache.clear();

  /// The artwork's most vivid colour.
  static Future<Color?> of(String url, {Map<String, String>? headers}) => paletteOf(url, headers: headers).then((p) => p.firstOrNull);

  /// Up to five distinct colours from the artwork, strongest first.
  static Future<List<Color>> paletteOf(String url, {Map<String, String>? headers}) => _cache.putIfAbsent(
    url,
    () => _extract(ResizeImage(NetworkImage(url, headers: headers), width: 32, height: 48)).catchError((Object _) {
      // A passing failure (too many at once, a timeout) gets another try next time.
      _cache.remove(url);
      return const <Color>[];
    }),
  );

  static Future<List<Color>> _extract(ImageProvider provider) async {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete(info.image.clone());
        stream.removeListener(l);
      },
      onError: (e, _) {
        if (!done.isCompleted) done.completeError(e);
        stream.removeListener(l);
      },
    );
    stream.addListener(l);
    final ui.Image image;
    try {
      image = await done.future.timeout(const Duration(seconds: 15));
    } finally {
      stream.removeListener(l);
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) return const [];
    return palette(bytes.buffer.asUint8List());
  }

  /// The strongest colour of raw RGBA pixels, or null for grey art.
  @visibleForTesting
  static Color? pick(List<int> rgba) => palette(rgba).firstOrNull;

  /// Hues are binned, each pixel weighted by how saturated and bright it is; every bin
  /// holding a fair share of the colour gives its average, strongest first.
  static List<Color> palette(List<int> rgba, {int max = 5}) {
    const bins = 18;
    final weight = List<double>.filled(bins, 0);
    final sumR = List<double>.filled(bins, 0), sumG = List<double>.filled(bins, 0), sumB = List<double>.filled(bins, 0);
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      final hsv = HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
      if (hsv.saturation < 0.2 || hsv.value < 0.15) continue;
      final w = hsv.saturation * hsv.saturation * hsv.value;
      final b = (hsv.hue / 360 * bins).floor() % bins;
      weight[b] += w;
      sumR[b] += rgba[i] * w;
      sumG[b] += rgba[i + 1] * w;
      sumB[b] += rgba[i + 2] * w;
    }
    final order = List<int>.generate(bins, (b) => b)..sort((a, b) => weight[b].compareTo(weight[a]));
    final top = weight[order.first];
    if (top < 0.5) return const [];
    return [
      for (final b in order.take(max))
        if (weight[b] >= 0.5 && weight[b] >= top * 0.12) lift(Color.fromARGB(255, (sumR[b] / weight[b]).round(), (sumG[b] / weight[b]).round(), (sumB[b] / weight[b]).round())),
    ];
  }

  /// Saturated and mid-light, so it glows on a dark page.
  static Color lift(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withSaturation(math.max(hsl.saturation, 0.6)).withLightness(hsl.lightness.clamp(0.55, 0.68)).toColor();
  }

  /// Degrees between two colours' hues, 0..180.
  static double hueDistance(Color a, Color b) {
    final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  static Color rotate(Color c, double degrees) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withHue((hsl.hue + degrees) % 360).toColor();
  }

  /// One colour per artwork for a run of items (a Top 10 row), each clearly different from
  /// its neighbours: the artwork's own colours are tried first, then its main colour turned
  /// round the colour wheel until it stands apart. Grey art gets an evenly spaced hue.
  static List<Color> distinct(List<List<Color>> palettes, {double fromNeighbours = 60, double fromAll = 26}) {
    final out = <Color>[];
    for (final (i, pal) in palettes.indexed) {
      final base = pal.firstOrNull ?? HSLColor.fromAHSL(1, (i * 137.5 + 200) % 360, 0.7, 0.62).toColor();
      final candidates = [
        ...pal,
        for (final d in const [35.0, -35.0, 70.0, -70.0, 105.0, -105.0, 140.0, -140.0, 180.0]) rotate(base, d),
      ];
      double near(Color c) => [for (var j = math.max(0, i - 2); j < i; j++) hueDistance(c, out[j])].fold(180.0, math.min);
      double far(Color c) => [for (final o in out) hueDistance(c, o)].fold(180.0, math.min);
      final fits = candidates.where((c) => near(c) >= fromNeighbours && far(c) >= fromAll).firstOrNull;
      out.add(fits ?? candidates.reduce((a, b) => math.min(near(a), far(a) * 2) >= math.min(near(b), far(b) * 2) ? a : b));
    }
    return out;
  }

  /// A second colour for accents beside [main]: the artwork's next colour that differs
  /// enough, else [main] turned a little round the wheel.
  static Color accent(List<Color> palette, Color main, {double apart = 40}) => palette.where((c) => hueDistance(c, main) >= apart).firstOrNull ?? rotate(main, 48);
}

/// Builds with the artwork's colour, easing from [fallback] once it's known. Inside a
/// [DistinctTints] with an [index], the row's distinct colour for that index wins.
class ArtTint extends StatefulWidget {
  const ArtTint({super.key, required this.url, required this.fallback, required this.builder, this.headers, this.index});
  final String? url;
  final Map<String, String>? headers;
  final Color fallback;
  final int? index;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  State<ArtTint> createState() => _ArtTintState();
}

class _ArtTintState extends State<ArtTint> {
  Color? _color;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtTint old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    final url = widget.url;
    if (url == null) return;
    ArtColor.of(url, headers: widget.headers).then((c) {
      if (mounted && widget.url == url) setState(() => _color = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.index;
    final row = i == null ? null : DistinctTints.colorAt(context, i);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: row ?? _color ?? widget.fallback),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, c, _) => widget.builder(context, c ?? widget.fallback),
    );
  }
}

/// Works out one clearly different colour per artwork in [urls] (see [ArtColor.distinct])
/// and hands them to the [ArtTint]s below that carry an index.
class DistinctTints extends StatefulWidget {
  const DistinctTints({super.key, required this.urls, required this.child, this.headers});
  final List<String?> urls;
  final Map<String, String>? headers;
  final Widget child;

  static Color? colorAt(BuildContext context, int index) {
    final s = context.dependOnInheritedWidgetOfExactType<_DistinctScope>();
    final colors = s?.colors;
    return colors != null && index >= 0 && index < colors.length ? colors[index] : null;
  }

  @override
  State<DistinctTints> createState() => _DistinctTintsState();
}

class _DistinctTintsState extends State<DistinctTints> {
  List<Color>? _colors;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DistinctTints old) {
    super.didUpdateWidget(old);
    if (widget.urls.join('|') != _key) _load();
  }

  Future<void> _load() async {
    final key = _key = widget.urls.join('|');
    final palettes = await Future.wait([for (final u in widget.urls) u == null ? Future.value(const <Color>[]) : ArtColor.paletteOf(u, headers: widget.headers)]);
    if (mounted && key == _key) setState(() => _colors = ArtColor.distinct(palettes));
  }

  @override
  Widget build(BuildContext context) => _DistinctScope(colors: _colors, child: widget.child);
}

class _DistinctScope extends InheritedWidget {
  const _DistinctScope({required this.colors, required super.child});
  final List<Color>? colors;
  @override
  bool updateShouldNotify(_DistinctScope old) => old.colors != colors;
}
