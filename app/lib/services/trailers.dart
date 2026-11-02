import 'dart:io';

import 'package:console_core/console_core.dart';

/// A clip to play behind the Home spotlight.
class TrailerClip {
  const TrailerClip({required this.url, this.headers = const {}, this.start = Duration.zero, this.viaYtdl = false});
  final String url;
  final Map<String, String> headers;

  /// Skip the studio logos at the top of most trailers.
  final Duration start;

  /// A YouTube link mpv opens through yt-dlp (only ever a youtube.com or youtu.be address).
  final bool viaYtdl;
}

/// Finds a trailer for a title: the Plex trailer extra first, then (when yt-dlp is
/// installed) the TMDB trailer on YouTube that Seerr lists.
class Trailers {
  Trailers({required this.plex, this.seerr});
  final PlexClient plex;
  final SeerrClient? seerr;
  final _cache = <String, Future<TrailerClip?>>{};

  static Future<bool>? _ytdl;

  /// yt-dlp on PATH lets mpv play YouTube trailers.
  static Future<bool> get ytdlAvailable => _ytdl ??= () async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', ['yt-dlp']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }();

  Future<TrailerClip?> forItem(PlexItem item) {
    // Episodes and seasons use their show's trailer.
    final key =
        switch (item.type) {
          'episode' => item.grandparentRatingKey,
          'season' => item.parentRatingKey,
          _ => item.ratingKey,
        } ??
        item.ratingKey;
    final hit = _cache[key];
    if (hit != null) return hit;
    // A definite answer (a clip, or none to be had) is kept; a failed lookup is tried again next time.
    late final Future<TrailerClip?> f;
    f = _find(key).catchError((Object e) {
      final definite = e is ApiException && e.status == 404;
      if (!definite && identical(_cache[key], f)) _cache.remove(key);
      return null;
    });
    return _cache[key] = f;
  }

  Future<TrailerClip?> _find(String ratingKey) async {
    final extras = await plex.extras(ratingKey);
    var trailer = extras.where((e) => e.subtype == 'trailer').firstOrNull ?? extras.firstOrNull;
    if (trailer != null && trailer.media.isEmpty) trailer = await plex.metadata(trailer.ratingKey);
    final url = trailer == null ? null : plex.directPlayUrl(trailer);
    if (url != null) {
      final d = trailer!.duration ?? 0;
      return TrailerClip(
        url: url,
        // An online trailer lives off-server and must not see the token.
        headers: plex.headersFor(url),
        start: Duration(milliseconds: d > 60000 ? (d * 0.12).round() : 0),
      );
    }

    final s = seerr;
    if (s == null || !await ytdlAvailable) return null;
    final item = await plex.metadata(ratingKey);
    final tmdb = item?.tmdbId;
    if (item == null || tmdb == null) return null;
    final d = await s.details(item.type == 'movie' ? 'movie' : 'tv', tmdb);
    final yt = d.videos.where((v) => v.site == 'YouTube' && v.type == 'Trailer').firstOrNull ?? d.videos.where((v) => v.site == 'YouTube').firstOrNull;
    // yt-dlp only ever gets a YouTube link rebuilt from the video's id, whatever the
    // server's url field says, so it can't be pointed at another address or a local file.
    final link = yt == null ? null : youtubeUrl(key: yt.key, url: yt.url);
    if (link == null) return null;
    return TrailerClip(url: link, start: const Duration(seconds: 8), viaYtdl: true);
  }
}
