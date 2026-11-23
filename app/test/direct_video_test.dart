import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:console_app/services/playback_prefs.dart';
import 'package:console_app/ui/player/app_subtitles.dart';
import 'package:console_app/ui/player/decoders.dart';
import 'package:console_app/ui/player/player_session.dart';

void main() {
  group('video output', () {
    test('auto is direct only on a low-memory Android TV', () {
      const p = PlaybackPrefs();
      expect(p.videoOutput, 'auto');
      expect(p.directVideo(android: true, lowMemory: true), isTrue);
      expect(p.directVideo(android: true, lowMemory: false), isFalse);
      expect(p.directVideo(android: false, lowMemory: true), isFalse);
    });

    test('a choice in Settings wins on Android, and nothing changes elsewhere', () {
      expect(const PlaybackPrefs(videoOutput: 'mpv').directVideo(android: true, lowMemory: true), isFalse);
      expect(const PlaybackPrefs(videoOutput: 'direct').directVideo(android: true, lowMemory: false), isTrue);
      expect(const PlaybackPrefs(videoOutput: 'direct').directVideo(android: false, lowMemory: false), isFalse);
    });

    test('is saved, and an unknown value reads as auto', () {
      final p = PlaybackPrefs.fromJson(const PlaybackPrefs(videoOutput: 'direct').toJson());
      expect(p.videoOutput, 'direct');
      expect(PlaybackPrefs.fromJson(const PlaybackPrefs(videoOutput: 'plane').toJson()).videoOutput, 'plane');
      expect(PlaybackPrefs.fromJson({'videoOutput': 'vulkan'}).videoOutput, 'auto');
      expect(PlaybackPrefs.fromJson({'videoOutput': 3}).videoOutput, 'auto');
      // 0.9.6's test of the same idea.
      expect(PlaybackPrefs.fromJson({'videoOutput': 'overlay'}).videoOutput, 'plane');
    });
  });

  group('video plane', () {
    test('auto uses it on a low-memory Android TV only', () {
      const p = PlaybackPrefs();
      expect(p.planeVideo(android: true, lowMemory: true), isTrue);
      expect(p.planeVideo(android: true, lowMemory: false), isFalse);
      expect(p.planeVideo(android: false, lowMemory: true), isFalse);
    });

    test('is also direct output: the app draws subtitles', () {
      const p = PlaybackPrefs(videoOutput: 'plane');
      expect(p.planeVideo(android: true, lowMemory: true), isTrue);
      expect(p.directVideo(android: true, lowMemory: true), isTrue);
    });

    test('runs as direct where the window is opaque, and not when another output is chosen', () {
      const p = PlaybackPrefs(videoOutput: 'plane');
      expect(p.planeVideo(android: true, lowMemory: false), isFalse);
      expect(p.directVideo(android: true, lowMemory: false), isTrue);
      expect(const PlaybackPrefs(videoOutput: 'direct').planeVideo(android: true, lowMemory: true), isFalse);
      expect(const PlaybackPrefs(videoOutput: 'mpv').planeVideo(android: true, lowMemory: true), isFalse);
    });
  });

  group('4K in another app (removed in 0.9.49)', () {
    test('an old saved switch is ignored and not saved again', () {
      final p = PlaybackPrefs.fromJson({'external4kApp': true, 'external4k': true});
      expect(p.toJson().keys.where((k) => k.startsWith('external')), isEmpty);
    });
  });

  group('direct output sends to Plex', () {
    final hevc = PlexStream(streamType: 1, codec: 'hevc');
    final av1 = PlexStream(streamType: 1, codec: 'av1');
    final pgs = PlexStream(streamType: 3, codec: 'pgs');
    final srt = PlexStream(streamType: 3, codec: 'srt');

    test('picture-based subtitles and codecs the decoder lacks', () {
      expect(PlayerSession.directNeedsServer(direct: true, video: hevc, subtitle: pgs), isTrue);
      expect(PlayerSession.directNeedsServer(direct: true, video: av1), isTrue);
    });

    test('not text subtitles, hardware codecs, or the mpv path', () {
      expect(PlayerSession.directNeedsServer(direct: true, video: hevc, subtitle: srt), isFalse);
      expect(PlayerSession.directNeedsServer(direct: true, video: hevc), isFalse);
      expect(PlayerSession.directNeedsServer(direct: true), isFalse);
      expect(PlayerSession.directNeedsServer(direct: false, video: av1, subtitle: pgs), isFalse);
    });
  });

  group('codecs the platform\'s player can\'t decode go through Plex', () {
    PlexStream a(String codec) => PlexStream(streamType: 2, codec: codec);
    PlexStream v(String codec) => PlexStream(streamType: 1, codec: codec);
    const apple = PlayerDecoders.apple;

    test('Apple: TrueHD and MLP sound, and VC-1 pictures, which its FFmpeg lacks', () {
      for (final c in ['truehd', 'TrueHD', 'mlp', 'cook']) {
        expect(PlayerSession.decodersNeedServer(apple, audio: a(c), video: v('hevc')), isTrue, reason: c);
      }
      expect(PlayerSession.decodersNeedServer(apple, audio: a('eac3'), video: v('vc1')), isTrue);
    });

    test('Apple: what its FFmpeg decodes plays directly', () {
      for (final c in ['aac', 'ac3', 'eac3', 'dca', 'dca-ma', 'flac', 'alac', 'opus', 'vorbis', 'mp3', 'mp2', 'pcm', 'pcm_s24le', 'wmav2', 'wmapro']) {
        expect(apple.playsAudio(c), isTrue, reason: c);
      }
      for (final c in ['h264', 'hevc', 'av1', 'mpeg2video', 'mpeg4', 'vp9', 'vp8', 'wmv3', 'msmpeg4v3']) {
        expect(apple.playsVideo(c), isTrue, reason: c);
      }
      expect(PlayerSession.decodersNeedServer(apple, audio: a('eac3'), video: v('hevc')), isFalse);
      expect(PlayerSession.decodersNeedServer(apple), isFalse, reason: 'no tracks named');
    });

    test('Windows, Linux and Android decode everything, as before', () {
      expect(PlayerDecoders.forPlatform(apple: false), same(PlayerDecoders.all));
      for (final c in ['truehd', 'mlp', 'cook', 'dca-ma']) {
        expect(PlayerSession.decodersNeedServer(PlayerDecoders.all, audio: a(c), video: v('vc1')), isFalse, reason: c);
      }
    });
  });

  group('app-drawn subtitles', () {
    test('main line only, trimmed, no blank lines', () {
      expect(subtitleText([' Hello \n\n there ', 'secondary']), 'Hello\nthere');
      expect(subtitleText(['', '']), '');
      expect(subtitleText(const []), '');
    });

    test('size and height follow the subtitle settings', () {
      final a = subtitleLook(height: 1000, size: 100, raise: 0, controlsShown: false);
      expect(a.fontSize, closeTo(58, 0.001));
      expect(a.bottom, closeTo(30, 0.001));
      final b = subtitleLook(height: 1000, size: 150, raise: 10, controlsShown: true);
      expect(b.fontSize, closeTo(87, 0.001));
      expect(b.bottom, closeTo(250, 0.001));
    });
  });
}
