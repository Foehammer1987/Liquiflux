import 'package:flutter/services.dart';

/// The Apple TV player's native side (AetherEngine), one per app. See README.md.
///
/// Times are seconds, as AetherEngine counts them. [events] carries maps holding only what
/// changed: `state` (idle, loading, playing, paused, seeking, ended, error), `position`,
/// `duration`, `buffering`, `audioTracks` / `subtitleTracks` (lists of maps with `id`, `name`,
/// `codec`, `channels`, `language`), `activeAudio` / `activeSubtitle` (-1 for none), `cue`
/// (the subtitle text showing now) and `error`.
class Aether {
  Aether._();

  static const _channel = MethodChannel('liquiflux/aether');
  static final Stream<Map<Object?, Object?>> events =
      const EventChannel('liquiflux/aether/events').receiveBroadcastStream().cast<Map<Object?, Object?>>();

  /// Starts [url] (playing unless [play] is false) from [start] seconds.
  static Future<void> open(String url, {Map<String, String> headers = const {}, double? start, bool play = true}) =>
      _channel.invokeMethod('open', {'url': url, 'headers': headers, 'start': start, 'play': play});

  static Future<void> play() => _channel.invokeMethod('play');
  static Future<void> pause() => _channel.invokeMethod('pause');
  static Future<void> seek(double seconds) => _channel.invokeMethod('seek', {'position': seconds});
  static Future<void> setRate(double rate) => _channel.invokeMethod('setRate', {'rate': rate});

  /// 0 to 1.
  static Future<void> setVolume(double volume) => _channel.invokeMethod('setVolume', {'volume': volume});
  static Future<void> selectAudio(int id) => _channel.invokeMethod('audio', {'id': id});

  /// A subtitle track by id, or none for -1.
  static Future<void> selectSubtitle(int id) => _channel.invokeMethod('subtitle', {'id': id});

  /// Adds a sidecar subtitle file and shows it; returns its track id.
  static Future<int?> addSubtitle(String url, {String? title, String? language}) =>
      _channel.invokeMethod<int>('externalSubtitle', {'url': url, 'title': title, 'language': language});

  /// The picture's fit: 'fit' (letterbox), 'fill' (crop to fill the screen) or 'stretch'.
  static Future<void> setFit(String aspect) => _channel.invokeMethod('fit', {'aspect': aspect});

  /// What the system's Now Playing card shows for the next title (the engine fills in time
  /// and rate, and answers the remote's commands). [artwork] is an image address.
  static Future<void> nowPlaying({required String title, String? subtitle, String? artwork}) =>
      _channel.invokeMethod('nowPlaying', {'title': title, 'subtitle': subtitle, 'artwork': artwork});

  /// Ends the session and hides the picture.
  static Future<void> stop() => _channel.invokeMethod('stop');
}
