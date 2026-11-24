import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:liquiflux_aether/liquiflux_aether.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// The Apple TV's player (AetherEngine, through the liquiflux_aether plugin) behind media_kit's
/// [mk.Player] API, so the player page and [PlayerSession] work unchanged on tvOS, where there
/// is no mpv. Made by [PlayerSession] on tvOS, the way [AvPlayPlayer] is on a Samsung TV.
///
/// The picture is a native view behind the app, which is see-through there ([AetherView] is an
/// empty box). Text subtitles reach the page on [mk.PlayerStream.subtitle] and the app draws
/// them ([AppSubtitles]).
///
/// One engine serves the whole app: AetherEngine is made to be kept for the app's lifetime.
class AetherPlayer extends mk.PlatformPlayer {
  AetherPlayer({super.configuration = const mk.PlayerConfiguration()}) {
    _events = Aether.events.listen(_event, onError: (Object e) => _error('$e'));
  }

  late final StreamSubscription<Map<Object?, Object?>> _events;
  bool _disposed = false;

  /// Engine track ids, in file order, matched to the ids '1', '2', … that [PlayerSession] uses.
  List<int> _audioIds = const [];
  List<int> _subtitleIds = const [];
  List<Map<Object?, Object?>> _audio = const [];
  List<Map<Object?, Object?>> _subtitles = const [];
  final _sidecarTracks = <mk.SubtitleTrack>[];
  final _sidecarIds = <String, int>{};

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    final media = switch (playable) {
      final mk.Media m => m,
      final mk.Playlist p when p.medias.isNotEmpty => p.medias[p.index.clamp(0, p.medias.length - 1)],
      _ => null,
    };
    if (media == null || _disposed) return;
    _sidecarTracks.clear();
    _sidecarIds.clear();
    _set(playlist: mk.Playlist([media]), completed: false, buffering: true, position: Duration.zero, duration: Duration.zero);
    final start = media.start;
    try {
      await Aether.open(
        media.uri,
        headers: media.httpHeaders ?? const {},
        start: start == null ? null : start.inMilliseconds / 1000,
        play: play,
      );
    } catch (e) {
      _set(buffering: false);
      _error('AetherEngine could not open the stream: ${_short(e)}');
    }
  }

  void _event(Map<Object?, Object?> e) {
    if (_disposed) return;
    Duration secs(Object? v) => Duration(microseconds: ((v as num? ?? 0) * 1e6).round());
    if (e['state'] case final String s) {
      switch (s) {
        case 'playing':
          _set(playing: true, buffering: false, completed: false);
        case 'paused':
          _set(playing: false, buffering: false);
        case 'loading':
          _set(buffering: true);
        case 'ended':
          _set(playing: false, completed: true);
        case 'idle':
          _set(playing: false);
        case 'error':
          _set(playing: false, buffering: false);
      }
    }
    if (e.containsKey('position')) _set(position: secs(e['position']));
    if (e.containsKey('duration')) _set(duration: secs(e['duration']));
    if (e['buffering'] case final bool b) _set(buffering: b);
    if (e['error'] case final String m) _error('AetherEngine: ${_short(m)}');
    if (e['cue'] case final String text) _set(subtitle: [text]);
    var tracksChanged = false;
    if (e['audioTracks'] case final List l) {
      _audio = [...l.cast<Map<Object?, Object?>>()]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      _audioIds = [for (final t in _audio) t['id'] as int];
      tracksChanged = true;
    }
    if (e['subtitleTracks'] case final List l) {
      // Sidecars the app added are listed by the app, not again by the engine.
      _subtitles = [...l.cast<Map<Object?, Object?>>().where((t) => !_sidecarIds.containsValue(t['id']))]
        ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      _subtitleIds = [for (final t in _subtitles) t['id'] as int];
      tracksChanged = true;
    }
    if (tracksChanged) _emitTracks();
  }

  void _emitTracks() {
    String? lang(Map<Object?, Object?> t) => t['language'] as String?;
    String? name(Map<Object?, Object?> t) => (t['name'] as String?)?.isEmpty ?? true ? null : t['name'] as String;
    _set(
      tracks: mk.Tracks(
        video: [mk.VideoTrack.auto(), mk.VideoTrack.no()],
        audio: [
          mk.AudioTrack.auto(),
          mk.AudioTrack.no(),
          for (final (i, a) in _audio.indexed) mk.AudioTrack('${i + 1}', name(a), lang(a), channelscount: a['channels'] as int?, codec: a['codec'] as String?),
        ],
        subtitle: [
          mk.SubtitleTrack.auto(),
          mk.SubtitleTrack.no(),
          for (final (i, s) in _subtitles.indexed) mk.SubtitleTrack('${i + 1}', name(s), lang(s), codec: s['codec'] as String?),
          ..._sidecarTracks,
        ],
      ),
    );
  }

  void _error(String message) {
    if (!errorController.isClosed) errorController.add(message);
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
      tracks: tracks,
      track: track,
      subtitle: subtitle,
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
    send(tracksController, tracks);
    send(trackController, track);
    send(subtitleController, subtitle);
  }

  @override
  Future<void> play() => Aether.play();

  @override
  Future<void> pause() => Aether.pause();

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> stop() async {
    await Aether.stop();
    _set(playing: false, position: Duration.zero, duration: Duration.zero);
  }

  @override
  Future<void> seek(Duration duration) async {
    final to = duration < Duration.zero ? Duration.zero : duration;
    _set(position: to);
    await Aether.seek(to.inMicroseconds / 1e6);
  }

  @override
  Future<void> setVolume(double volume) async {
    await Aether.setVolume((volume / 100).clamp(0, 1).toDouble());
    _set(volume: volume.clamp(0, 100).toDouble());
  }

  @override
  Future<void> setRate(double rate) async {
    await Aether.setRate(rate);
    _set(rate: rate);
  }

  /// The picture's fit: Liquiflux's Aspect setting ('fit', 'fill', 'stretch').
  Future<void> setFit(String aspect) => Aether.setFit(aspect);

  /// The system's Now Playing card for the next title: [title], [subtitle] (a show and
  /// episode), and [artwork], an image address.
  Future<void> nowPlaying({required String title, String? subtitle, String? artwork}) =>
      Aether.nowPlaying(title: title, subtitle: subtitle, artwork: artwork).catchError((Object e) => debugPrint('now playing: ${_short(e)}'));

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> setAudioDevice(mk.AudioDevice audioDevice) async {}

  @override
  Future<void> setVideoTrack(mk.VideoTrack track) async {}

  @override
  Future<void> setAudioTrack(mk.AudioTrack track) async {
    final i = int.tryParse(track.id);
    if (i == null || i < 1 || i > _audioIds.length) return;
    await Aether.selectAudio(_audioIds[i - 1]);
    _set(track: state.track.copyWith(audio: track));
  }

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    if (track.id == 'no') {
      await Aether.selectSubtitle(-1);
      _set(track: state.track.copyWith(subtitle: track), subtitle: const ['']);
      return;
    }
    if (track.uri || _sidecarIds.containsKey(track.id)) {
      final known = _sidecarIds[track.id];
      if (known != null) {
        await Aether.selectSubtitle(known);
      } else {
        final id = await Aether.addSubtitle(track.id, title: track.title, language: track.language);
        if (id == null) return;
        _sidecarIds[track.id] = id;
        _sidecarTracks.add(mk.SubtitleTrack(track.id, track.title, track.language, uri: true));
        _emitTracks();
      }
      _set(track: state.track.copyWith(subtitle: track));
      return;
    }
    final i = int.tryParse(track.id);
    if (i == null || i < 1 || i > _subtitleIds.length) return;
    await Aether.selectSubtitle(_subtitleIds[i - 1]);
    _set(track: state.track.copyWith(subtitle: track));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.cancel();
    await Aether.stop().catchError((Object _) {});
    await super.dispose();
  }

  /// Errors can carry the stream's address, which holds the Plex token.
  static String _short(Object e) => e.toString().replaceAll(RegExp(r'https?://\S+'), '<address>');
}

/// Where an [AetherPlayer]'s picture shows: nothing drawn, so the video behind the app shows.
class AetherView extends StatelessWidget {
  const AetherView({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
