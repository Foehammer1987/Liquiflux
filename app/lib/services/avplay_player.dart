import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:video_player_avplay/video_player.dart' as av;
import 'package:video_player_avplay/video_player_platform_interface.dart' show DisplayMode, VideoFormat;

import '../app_info.dart';

/// Samsung's hardware player (AVPlay, through `video_player_avplay`) behind media_kit's
/// [mk.Player] API, so the player page and [PlayerSession] work unchanged on a Samsung TV,
/// where there is no mpv. Made by [newPlayer] on Tizen.
///
/// The picture is on the TV's video plane behind the app; [AvPlayView] cuts the hole it
/// shows through. Subtitles reach the page as text on [mk.PlayerStream.subtitle], the same way
/// mpv's do with direct output, so the app draws them ([AppSubtitles]).
///
/// What AVPlay can't do, compared with mpv: request headers other than Cookie and
/// User-Agent (Plex's token is already in every address the app plays), exact seeks (it
/// lands on the nearest keyframe), libass styling, audio delay, volume over 100%, and any
/// mpv property. Those settings are hidden on Tizen.
class AvPlayPlayer extends mk.PlatformPlayer {
  AvPlayPlayer({super.configuration = const mk.PlayerConfiguration()});

  /// The controller now playing, for [AvPlayView]; null between files.
  final ValueNotifier<av.VideoPlayerController?> controller = ValueNotifier(null);

  av.VideoPlayerController? get _c => controller.value;

  /// AVPlay's own tracks in file order, matched to the ids '1', '2', … that [PlayerSession]
  /// uses (mpv numbers a file's audio and subtitle tracks from 1 in the same order).
  List<av.AudioTrack> _audio = const [];
  List<av.TextTrack> _text = const [];

  /// Subtitles off ('no'), so captions AVPlay still reports aren't shown.
  bool _subtitlesOff = false;

  /// A sidecar subtitle file (SRT or WebVTT from Plex) read by the app, shown by position.
  List<av.TextCaption>? _sidecar;
  String? _sidecarTitle;
  final _sidecarTracks = <mk.SubtitleTrack>[];

  bool _disposed = false;

  /// Each open gets a number, so a slow open that's been replaced lets go quietly.
  int _generation = 0;

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    final media = switch (playable) {
      final mk.Media m => m,
      final mk.Playlist p when p.medias.isNotEmpty => p.medias[p.index.clamp(0, p.medias.length - 1)],
      _ => null,
    };
    if (media == null || _disposed) return;
    final gen = ++_generation;
    await _close();
    _sidecar = null;
    _sidecarTitle = null;
    _sidecarTracks.clear();
    _subtitlesOff = false;
    _lastError = null;
    final url = avPlayUrl(media.uri, media.httpHeaders ?? const {});
    final c = av.VideoPlayerController.network(
      url,
      formatHint: url.contains('.m3u8') ? VideoFormat.hls : null,
      httpHeaders: {'User-Agent': '$appName/$appVersion (Tizen)'},
    );
    _set(playlist: mk.Playlist([media]), completed: false, buffering: true, position: Duration.zero, duration: Duration.zero);
    try {
      await c.initialize();
    } catch (e) {
      await c.dispose();
      if (gen != _generation || _disposed) return;
      _set(buffering: false);
      if (!errorController.isClosed) errorController.add('AVPlay could not open the stream: ${_short(e)}');
      return;
    }
    if (gen != _generation || _disposed) {
      await c.dispose();
      return;
    }
    controller.value = c;
    c.addListener(_changed);
    await c.setDisplayMode(_fit).catchError((Object _) => false);
    final start = media.start;
    if (start != null && start > Duration.zero) await c.seekTo(start);
    await _readTracks(c);
    _set(duration: c.value.duration.end, videoParams: mk.VideoParams(w: c.value.size.width.round(), h: c.value.size.height.round()));
    if (play) await c.play();
    _changed();
  }

  /// Reads AVPlay's track lists into media_kit's [mk.Tracks] ('auto' and 'no' first, as mpv
  /// reports them).
  Future<void> _readTracks(av.VideoPlayerController c) async {
    try {
      _audio = [...?await c.audioTracks]..sort((a, b) => a.trackId.compareTo(b.trackId));
      _text = [...?await c.textTracks]..sort((a, b) => a.trackId.compareTo(b.trackId));
    } catch (e) {
      debugPrint('avplay tracks: ${_short(e)}');
    }
    _emitTracks();
  }

  void _emitTracks() {
    final video = _c?.value.size;
    _set(
      tracks: mk.Tracks(
        video: [
          mk.VideoTrack.auto(),
          mk.VideoTrack.no(),
          if (video != null && video.width > 0) mk.VideoTrack('1', null, null, w: video.width.round(), h: video.height.round()),
        ],
        audio: [
          mk.AudioTrack.auto(),
          mk.AudioTrack.no(),
          for (final (i, a) in _audio.indexed) mk.AudioTrack('${i + 1}', null, a.language.isEmpty ? null : a.language, channelscount: a.channel),
        ],
        subtitle: [
          mk.SubtitleTrack.auto(),
          mk.SubtitleTrack.no(),
          for (final (i, t) in _text.indexed) mk.SubtitleTrack('${i + 1}', null, t.language.isEmpty ? null : t.language),
          ..._sidecarTracks,
        ],
      ),
    );
  }

  bool _wasCompleted = false;
  String? _lastError;

  /// AVPlay's state, passed on as media_kit's.
  void _changed() {
    final c = _c;
    if (c == null || _disposed) return;
    final v = c.value;
    // Reported once each, not on every change after it.
    if (v.errorDescription != _lastError) {
      _lastError = v.errorDescription;
      if (_lastError != null && !errorController.isClosed) errorController.add('AVPlay: ${_short(_lastError!)}');
    }
    _set(
      playing: v.isPlaying,
      buffering: v.isBuffering,
      position: v.position,
      duration: v.duration.end > Duration.zero ? v.duration.end : null,
      volume: v.volume * 100,
      rate: v.playbackSpeed,
      subtitle: [_captionAt(v)],
    );
    if (v.isCompleted && !_wasCompleted) {
      _wasCompleted = true;
      _set(completed: true, playing: false);
    } else if (!v.isCompleted) {
      _wasCompleted = false;
    }
  }

  String _captionAt(av.VideoPlayerValue v) {
    if (_subtitlesOff) return '';
    final side = _sidecar;
    if (side != null) return side.where((c) => v.position >= c.start && v.position < c.end).map((c) => c.text).join('\n');
    return [for (final c in v.captions.textCaptions ?? const <av.TextCaption>[]) c.text].where((t) => t.isNotEmpty).join('\n');
  }

  /// Updates [state] and sends what changed down its stream.
  void _set({
    mk.Playlist? playlist,
    bool? playing,
    bool? completed,
    Duration? position,
    Duration? duration,
    double? volume,
    double? rate,
    bool? buffering,
    mk.VideoParams? videoParams,
    mk.Tracks? tracks,
    mk.Track? track,
    List<String>? subtitle,
  }) {
    if (_disposed) return;
    state = state.copyWith(
      playlist: playlist,
      playing: playing,
      completed: completed,
      position: position,
      duration: duration,
      volume: volume,
      rate: rate,
      buffering: buffering,
      videoParams: videoParams,
      tracks: tracks,
      track: track,
      subtitle: subtitle,
      width: videoParams?.w,
      height: videoParams?.h,
    );
    void send<T>(StreamController<T> s, T? v) {
      if (v != null && !s.isClosed) s.add(v);
    }

    send(playlistController, playlist);
    send(playingController, playing);
    send(completedController, completed);
    send(positionController, position);
    send(durationController, duration);
    send(volumeController, volume);
    send(rateController, rate);
    send(bufferingController, buffering);
    send(videoParamsController, videoParams);
    send(tracksController, tracks);
    send(trackController, track);
    send(subtitleController, subtitle);
  }

  @override
  Future<void> play() async => _c?.play();

  @override
  Future<void> pause() async => _c?.pause();

  @override
  Future<void> playOrPause() async => state.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _generation++;
    await _close();
    _set(playing: false, position: Duration.zero, duration: Duration.zero);
  }

  @override
  Future<void> seek(Duration duration) async {
    final c = _c;
    if (c == null) return;
    // AVPlay only seeks at normal speed.
    final speed = c.value.playbackSpeed;
    if (speed != 1) await c.setPlaybackSpeed(1);
    await c.seekTo(duration < Duration.zero ? Duration.zero : duration);
    if (speed != 1) await c.setPlaybackSpeed(speed).catchError((Object _) {});
    _set(position: duration);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _c?.setVolume((volume / 100).clamp(0, 1).toDouble());
    _set(volume: volume.clamp(0, 100).toDouble());
  }

  @override
  Future<void> setRate(double rate) async {
    try {
      await _c?.setPlaybackSpeed(rate);
      _set(rate: rate);
    } catch (e) {
      // It fails in a title's last three seconds.
      debugPrint('avplay speed: ${_short(e)}');
    }
  }

  /// The picture's fit: Liquiflux's Aspect setting ('fit', 'fill', 'stretch').
  Future<void> setFit(String aspect) async {
    _fit = switch (aspect) {
      'fill' => DisplayMode.croppedFull,
      'stretch' => DisplayMode.fullScreen,
      _ => DisplayMode.letterBox,
    };
    await _c?.setDisplayMode(_fit).catchError((Object _) => false);
  }

  DisplayMode _fit = DisplayMode.letterBox;

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> setAudioDevice(mk.AudioDevice audioDevice) async {}

  @override
  Future<void> setVideoTrack(mk.VideoTrack track) async {}

  @override
  Future<void> setAudioTrack(mk.AudioTrack track) async {
    final c = _c;
    final i = int.tryParse(track.id);
    if (c == null || i == null || i < 1 || i > _audio.length) return;
    final ok = await c.setTrackSelection(_audio[i - 1]).catchError((Object _) => false);
    if (ok) _set(track: state.track.copyWith(audio: track));
  }

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    final c = _c;
    if (c == null) return;
    if (track.id == 'no') {
      _subtitlesOff = true;
      _sidecar = null;
      _set(track: state.track.copyWith(subtitle: track), subtitle: const ['']);
      return;
    }
    _subtitlesOff = false;
    if (track.uri) {
      await _loadSidecar(track);
      return;
    }
    final known = _sidecarTracks.where((t) => t.id == track.id || (track.title != null && t.title == track.title)).firstOrNull;
    if (known != null) {
      await _loadSidecar(known);
      return;
    }
    _sidecar = null;
    final i = int.tryParse(track.id);
    if (i == null || i < 1 || i > _text.length) return;
    final ok = await c.setTrackSelection(_text[i - 1]).catchError((Object _) => false);
    if (ok) _set(track: state.track.copyWith(subtitle: track));
  }

  /// Reads a sidecar SRT or WebVTT file from Plex; the app shows its lines by position.
  Future<void> _loadSidecar(mk.SubtitleTrack track) async {
    final url = track.id;
    if (_sidecarTitle == track.title && _sidecar != null) return;
    try {
      final body = await _fetchText(url);
      final file = body.trimLeft().startsWith('WEBVTT') ? av.WebVTTCaptionFile(body) : av.SubRipCaptionFile(body);
      _sidecar = file.textCaptions;
      _sidecarTitle = track.title;
      if (!_sidecarTracks.any((t) => t.id == url)) {
        _sidecarTracks.add(mk.SubtitleTrack(url, track.title, track.language, uri: true));
        _emitTracks();
      }
      _set(track: state.track.copyWith(subtitle: track));
      _changed();
    } catch (e) {
      debugPrint('avplay subtitles: ${_short(e)}');
    }
  }

  static Future<String> _fetchText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(const Utf8Decoder(allowMalformed: true)).join();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _close() async {
    final c = controller.value;
    controller.value = null;
    if (c == null) return;
    c.removeListener(_changed);
    await c.dispose().catchError((Object _) {});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _generation++;
    await _close();
    _disposed = true;
    controller.dispose();
    await super.dispose();
  }

  /// Errors can carry the stream's address, which holds the Plex token.
  static String _short(Object e) => e.toString().replaceAll(RegExp(r'https?://\S+'), '<address>');
}

/// The address AVPlay is given. AVPlay sends no request headers but Cookie and User-Agent, so
/// the Plex ones the app would have sent ([headers]: the token, client id, product) go in the
/// address instead, which Plex reads the same way. Only `X-Plex-*` headers are moved, and one
/// already in the address is left as it is.
@visibleForTesting
String avPlayUrl(String url, Map<String, String> headers) {
  final u = Uri.tryParse(url);
  if (u == null || headers.isEmpty) return url;
  final extra = {
    for (final e in headers.entries)
      if (e.key.startsWith('X-Plex-') && !u.queryParameters.containsKey(e.key)) e.key: e.value,
  };
  if (extra.isEmpty) return url;
  return u.replace(queryParameters: {...u.queryParameters, ...extra}).toString();
}

/// Where an [AvPlayPlayer]'s picture shows: a hole in the app over the TV's video plane.
class AvPlayView extends StatelessWidget {
  const AvPlayView({super.key, required this.player});
  final AvPlayPlayer player;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<av.VideoPlayerController?>(
    valueListenable: player.controller,
    builder: (context, c, _) => c == null ? const SizedBox.expand() : SizedBox.expand(child: av.VideoPlayer(c)),
  );
}
