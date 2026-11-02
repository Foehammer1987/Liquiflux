/// Refresh-rate (and resolution) matching: which of the display's modes shows a video's
/// frames evenly, so 23.976 fps film doesn't judder through a 60 Hz screen's 3:2 cadence.
library;

/// What Settings > Video > Match Frame Rate does.
enum DisplayMatchMode {
  off('Off'),
  rate('Frame Rate'),
  rateAndResolution('Rate and Resolution');

  const DisplayMatchMode(this.label);
  final String label;

  static DisplayMatchMode? parse(Object? s) {
    for (final m in values) {
      if (m.name == s) return m;
    }
    return null;
  }
}

/// One mode the display offers: its physical size in pixels and refresh rate in Hz.
class DisplayMode {
  const DisplayMode({required this.id, required this.width, required this.height, required this.refreshRate});

  /// Android's Display.Mode id; on Windows, the index EnumDisplaySettings listed it at.
  final int id;
  final int width;
  final int height;
  final double refreshRate;

  bool sameSize(DisplayMode o) => width == o.width && height == o.height;

  /// From the platform channel's map; null for anything malformed.
  static DisplayMode? fromMap(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], w = m['width'], h = m['height'], r = m['refreshRate'];
    if (id is! int || w is! int || h is! int || r is! num || w <= 0 || h <= 0 || !r.isFinite || r <= 0) return null;
    return DisplayMode(id: id, width: w, height: h, refreshRate: r.toDouble());
  }

  @override
  bool operator ==(Object other) => other is DisplayMode && other.id == id && other.width == width && other.height == height && other.refreshRate == refreshRate;

  @override
  int get hashCode => Object.hash(id, width, height, refreshRate);

  @override
  String toString() => '${width}x$height@${refreshRate.toStringAsFixed(3)}';
}

/// The broadcast and film rates, which files and displays only ever approximate.
const standardFrameRates = [23.976, 24.0, 25.0, 29.97, 30.0, 47.952, 48.0, 50.0, 59.94, 60.0, 100.0, 119.88, 120.0];

/// Two rates count as the same within this share of each other (0.05%): 23.976 and 24 are
/// 0.1% apart, and a display's 23.976 is reported as 23.976025 or the like.
const _same = 0.0005;

bool sameRate(double a, double b) => (a - b).abs() <= _same * b;

/// [fps] moved onto the standard rate it approximates (mpv's 23.976023 is 23.976), or
/// left as it is when it is near none of them.
double snapFrameRate(double fps) {
  for (final r in standardFrameRates) {
    if (sameRate(fps, r)) return r;
  }
  // Exact NTSC rates written out: 24000/1001 and friends.
  for (final r in standardFrameRates) {
    if ((fps - r).abs() < 0.002) return r;
  }
  return fps;
}

/// The video's frame rate, from the best source there is: Plex's exact `frameRate` for the
/// video track, then mpv's container-fps, then Plex's rough label (24p is nearly always
/// 23.976 film). Null when nothing says.
double? contentFrameRate({double? stream, double? mpv, String? label}) {
  for (final f in [stream, mpv]) {
    if (f != null && f.isFinite && f >= 10 && f <= 300) return snapFrameRate(f);
  }
  switch (label?.toLowerCase()) {
    case '24p':
      return 23.976;
    case 'pal':
    case '25p':
      return 25;
    case 'ntsc':
    case '30p':
      return 29.97;
    case '50p':
      return 50;
    case '60p':
      return 59.94;
  }
  return null;
}

/// How well a display rate [hz] shows [fps]: 0 exact, 1-4 an even multiple (48 Hz for 24,
/// 50 for 25, 120 for 24 or 30), 10 a near miss that drops or repeats one frame every half
/// a minute or more (24 Hz for 23.976), null no good (60 Hz for 24, the judder this fixes).
int? rateFit(double hz, double fps) {
  if (sameRate(hz, fps)) return 0;
  final n = (hz / fps).round();
  if (n >= 2 && n <= 5 && sameRate(hz, fps * n)) return n - 1;
  if (n == 1 && (hz - fps).abs() <= 0.0015 * fps) return 10;
  return null;
}

/// The mode to switch to for [fps] (and, with [resolution], a [videoWidth] x [videoHeight]
/// picture), or null to stay on [current]: when it already fits, or no mode does.
DisplayMode? pickDisplayMode({
  required List<DisplayMode> modes,
  required DisplayMode current,
  required double fps,
  bool resolution = false,
  int? videoWidth,
  int? videoHeight,
}) {
  if (modes.isEmpty || !fps.isFinite || fps <= 0) return null;
  if (resolution && videoWidth != null && videoHeight != null && videoWidth > 0 && videoHeight > 0) {
    final size = _sizeFor(modes, videoWidth, videoHeight);
    final picked = _best(modes, size, current, fps);
    if (picked != null) return picked;
    // Nothing at that size shows this rate evenly; the rate alone may still be matched.
  }
  return _best(modes, current, current, fps);
}

/// The best mode the size of [size] for [fps]; null to keep [current] (or when none fit).
DisplayMode? _best(List<DisplayMode> modes, DisplayMode size, DisplayMode current, double fps) {
  if (current.sameSize(size)) {
    final now = rateFit(current.refreshRate, fps);
    // Already even (exact or a multiple): switching would only blank the screen.
    if (now != null && now < 10) return null;
  }
  DisplayMode? best;
  int? bestFit;
  for (final m in modes) {
    if (!m.sameSize(size)) continue;
    final f = rateFit(m.refreshRate, fps);
    if (f == null) continue;
    if (bestFit == null || f < bestFit || (f == bestFit && m.refreshRate < best!.refreshRate)) {
      best = m;
      bestFit = f;
    }
  }
  if (best == null) return null;
  if (best.sameSize(current) && sameRate(best.refreshRate, current.refreshRate)) return null;
  return best;
}

/// The smallest size the display has that holds the picture, but never below 1080p while
/// the display has 1080p or more (the TV upscales SD and 720p better than a mode change
/// to 480p or 720p would look), and the largest when the picture is bigger than all.
DisplayMode _sizeFor(List<DisplayMode> modes, int w, int h) {
  final sizes = <DisplayMode>[];
  for (final m in modes) {
    if (!sizes.any((s) => s.sameSize(m))) sizes.add(m);
  }
  sizes.sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
  final floor = sizes.any((s) => s.height >= 1080) ? 1080 : 0;
  for (final s in sizes) {
    // A little under counts as holding it: 1916 wide or 1072 high encodes are 1080p.
    if (s.height >= floor && s.width >= w * 0.95 && s.height >= h * 0.95) return s;
  }
  return sizes.last;
}
