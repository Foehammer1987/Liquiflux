// Keeping credentials where they belong: scrubbing them out of text that gets logged or
// shown, checking links and media addresses that come from servers, and the mpv options
// a user (or a tampered settings file) may set.

import 'playback.dart' show isLocalAddress;

const _hidden = '<redacted>';

/// Secrets the app holds right now (the Plex token, the Seerr key…), scrubbed from any text
/// passed through [redactSecrets] wherever they turn up, not only after a known name.
final _known = <String>{};

/// Adds [secret] to the values [redactSecrets] always hides. Short values are skipped, since
/// hiding "1" or "on" everywhere would mangle ordinary text.
void rememberSecret(String? secret) {
  final s = secret?.trim() ?? '';
  if (s.length >= 6) _known.add(s);
}

/// Forgets every value added with [rememberSecret] (for tests).
void forgetSecrets() => _known.clear();

/// Names whose value is a credential: query parameters, headers, JSON fields and cookies.
final _named = RegExp(
  r'(?<![\w-])(x-plex-token|x-api-key|trakt-api-key|api[-_]?key|auth[-_]?token|access[-_]?token|token|authorization|proxy-authorization|set-cookie|cookie|connect\.sid)(?![\w-])'
  r'''(\s*["']?\s*[:=]\s*["']?\s*)((?:bearer|basic)\s+)?([^\s&"',;}\]#]+)''',
  caseSensitive: false,
);

/// user:password@ in an address.
final _userInfo = RegExp(r'(\w+://)[^/\s@]+@');

/// [text] with tokens, API keys, cookies and passwords in addresses replaced by
/// `<redacted>`. Use it on anything logged, shown or put in an error message.
String redactSecrets(String text) {
  var out = text.replaceAllMapped(_named, (m) => '${m[1]}${m[2]}${m[3] ?? ''}$_hidden');
  out = out.replaceAllMapped(_userInfo, (m) => '${m[1]}$_hidden@');
  for (final s in _known) {
    out = out.replaceAll(s, _hidden);
    final encoded = Uri.encodeQueryComponent(s);
    if (encoded != s) out = out.replaceAll(encoded, _hidden);
  }
  return out;
}

/// An error in words for the viewer or the log, with any credentials scrubbed out.
String errorText(Object? e) => redactSecrets('$e');

/// True for an absolute http or https address with a host.
bool isWebUrl(String? url) {
  final u = url == null ? null : Uri.tryParse(url.trim());
  return u != null && (u.isScheme('http') || u.isScheme('https')) && u.host.isNotEmpty;
}

/// [url] as a link that's safe to hand to the system browser: http or https only (never
/// file:, javascript: or an app's own scheme), with a host and no user:password. Null otherwise.
Uri? safeExternalUri(String? url) {
  if (!isWebUrl(url)) return null;
  final u = Uri.parse(url!.trim());
  return u.userInfo.isEmpty ? u : null;
}

/// True when [a] and [b] are the same scheme, host and port, i.e. the same server.
bool sameOrigin(Uri a, Uri b) => a.scheme.toLowerCase() == b.scheme.toLowerCase() && a.host.toLowerCase() == b.host.toLowerCase() && a.port == b.port;

const _youtubeHosts = {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'};
final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{6,20}$');

/// A YouTube watch link for a video [key] (TMDB lists trailers by key), or [url] when it's
/// already an https YouTube link. Null for anything else, so a server can't point yt-dlp at
/// an address of its choosing.
String? youtubeUrl({String? key, String? url}) {
  if (key != null && _youtubeId.hasMatch(key)) return 'https://www.youtube.com/watch?v=$key';
  final u = url == null ? null : Uri.tryParse(url.trim());
  if (u == null || !u.isScheme('https') || u.userInfo.isNotEmpty || u.port != 443) return null;
  return _youtubeHosts.contains(u.host.toLowerCase()) ? u.toString() : null;
}

/// True for an address that only this network (or a private VPN) can reach: what
/// [isLocalAddress] counts, plus Tailscale-style 100.64.0.0/10, IPv6 loopback, link-local
/// and private ranges, bare machine names ("nas") and home-network suffixes.
bool isPrivateAddress(String url) {
  if (isLocalAddress(url)) return true;
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (!host.contains('.') && !host.contains(':')) return true; // "nas", "plexserver"
  for (final suffix in const ['.lan', '.home', '.home.arpa', '.internal', '.localdomain', '.intranet']) {
    if (host.endsWith(suffix)) return true;
  }
  if (host.contains(':')) {
    final h = host.replaceAll(RegExp(r'^\[|\]$'), '');
    return h == '::1' || h.startsWith('fe80:') || h.startsWith('fc') || h.startsWith('fd');
  }
  final parts = host.split('.').map(int.tryParse).toList();
  return parts.length == 4 && parts[0] == 100 && parts[1] != null && parts[1]! >= 64 && parts[1]! <= 127;
}

/// True when signing in to [url] would send a token or key in plain text across the
/// internet: plain http to an address that isn't on this network.
bool sendsCredentialsInClear(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null && u.isScheme('http') && u.host.isNotEmpty && !isPrivateAddress(url);
}

/// The mpv options custom Settings lines may set: picture, scaling, HDR, cache, audio and
/// subtitle look. Anything not named here is refused, so options that run programs or
/// scripts, open sockets, read or write local files (`external-files`, `ao-pcm-file`,
/// `vo-image-outdir`, filter graphs with `movie=`…), change how the player talks to the
/// network (`http-proxy`, `tls-verify`, extra headers) or switch yt-dlp on can't be set,
/// including ones a future mpv adds. Path-taking options stay off the list; the one
/// exception is `glsl-shaders`, since a shader file only runs on the GPU.
const mpvAllowedOptions = {
  // Decoding and frame timing.
  'hwdec', 'hwdec-codecs', 'vd-lavc-threads', 'vd-lavc-film-grain', 'video-sync', 'interpolation', 'tscale',
  'framedrop', 'deinterlace', 'video-latency-hacks',
  // Rendering and scaling.
  'scale', 'cscale', 'dscale', 'scale-antiring', 'cscale-antiring', 'dscale-antiring', 'scale-blur', 'scale-param1',
  'scale-param2', 'correct-downscaling', 'linear-downscaling', 'linear-upscaling', 'sigmoid-upscaling',
  'sigmoid-center', 'sigmoid-slope', 'deband', 'deband-iterations', 'deband-threshold', 'deband-range',
  'deband-grain', 'dither', 'dither-depth', 'temporal-dither', 'glsl-shaders', 'gpu-api', 'gpu-context',
  'fbo-format', 'video-output-levels', 'brightness', 'contrast', 'saturation', 'gamma', 'hue', 'sharpen',
  'video-aspect-override', 'video-zoom', 'video-pan-x', 'video-pan-y', 'video-unscaled', 'panscan', 'keepaspect',
  'video-rotate',
  // Colour and HDR.
  'tone-mapping', 'tone-mapping-param', 'tone-mapping-mode', 'tone-mapping-max-boost', 'tone-mapping-visualize',
  'gamut-mapping-mode', 'hdr-compute-peak', 'hdr-peak-percentile', 'hdr-peak-decay-rate',
  'hdr-scene-threshold-low', 'hdr-scene-threshold-high', 'hdr-contrast-recovery', 'hdr-contrast-smoothness',
  'inverse-tone-mapping', 'target-colorspace-hint', 'target-prim', 'target-trc', 'target-peak',
  'target-contrast', 'target-gamut', 'icc-intent',
  // Cache and buffering (in memory only).
  'cache', 'cache-secs', 'cache-pause', 'cache-pause-initial', 'cache-pause-wait', 'demuxer-max-bytes',
  'demuxer-max-back-bytes', 'demuxer-readahead-secs', 'demuxer-seekable-cache', 'demuxer-donate-buffer',
  'network-timeout', 'stream-buffer-size',
  // Audio.
  'audio-pitch-correction', 'audio-normalize-downmix', 'audio-delay', 'audio-buffer', 'audio-stream-silence',
  'audio-samplerate', 'audio-format', 'audio-channels', 'audio-exclusive', 'audio-spdif', 'volume-max',
  'replaygain', 'replaygain-preamp', 'replaygain-clip', 'gapless-audio',
  // Subtitles and on-screen text.
  'sub-delay', 'sub-scale', 'sub-scale-by-window', 'sub-scale-with-window', 'sub-pos', 'sub-margin-x',
  'sub-margin-y', 'sub-align-x', 'sub-align-y', 'sub-justify', 'sub-font', 'sub-font-size', 'sub-bold',
  'sub-italic', 'sub-color', 'sub-back-color', 'sub-border-color', 'sub-border-size', 'sub-outline-color',
  'sub-outline-size', 'sub-shadow-color', 'sub-shadow-offset', 'sub-spacing', 'sub-blur', 'sub-use-margins',
  'sub-ass-override', 'sub-ass-force-margins', 'sub-ass-vsfilter-aspect-compat', 'sub-ass-hinting',
  'sub-ass-shaper', 'sub-ass-force-style', 'sub-fix-timing', 'sub-gauss', 'sub-gray', 'sub-filter-sdh',
  'sub-filter-sdh-harder', 'blend-subtitles', 'stretch-image-subs-to-screen', 'image-subs-video-resolution',
  'osd-font', 'osd-font-size', 'osd-color', 'osd-border-color', 'osd-border-size', 'osd-level',
  // Language and track choice.
  'alang', 'slang', 'vlang', 'subs-with-matching-audio', 'subs-fallback', 'subs-fallback-forced',
};

/// Whether a custom mpv option [name] is allowed (see [mpvOptions]): only names on
/// [mpvAllowedOptions], in any case, with or without a leading `--`.
bool mpvOptionAllowed(String name) {
  final n = name.trim().toLowerCase().replaceFirst(RegExp(r'^--'), '');
  return RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(n) && mpvAllowedOptions.contains(n);
}

/// The custom mpv options typed in Settings: one name=value per line, # for comments.
/// [allowed] are safe to apply; [blocked] names the ones that are refused (not on
/// [mpvAllowedOptions]).
({List<(String, String)> allowed, List<String> blocked}) mpvOptions(String text) {
  final allowed = <(String, String)>[];
  final blocked = <String>[];
  for (final line in text.split('\n')) {
    final t = line.trim();
    final eq = t.indexOf('=');
    if (t.isEmpty || t.startsWith('#') || eq <= 0) continue;
    final name = t.substring(0, eq).trim();
    final value = t.substring(eq + 1).trim();
    if (mpvOptionAllowed(name) && !value.contains('\u0000')) {
      allowed.add((name.trim().toLowerCase().replaceFirst(RegExp(r'^--'), ''), value));
    } else {
      blocked.add(name);
    }
  }
  return (allowed: allowed, blocked: blocked);
}

/// What ffmpeg may open from inside a stream (HLS playlists, segments and keys). Leaves out
/// file:, udp: and rtp:, so a playlist from a server can't make the player read files on
/// this computer or reach out over other protocols.
const streamProtocols = ['http', 'https', 'tcp', 'tls', 'crypto', 'httpproxy', 'data'];
