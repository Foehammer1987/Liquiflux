import 'dart:io';
import 'dart:ui' as ui;

import 'package:console_ui/console_ui.dart' show ArtMemory;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import 'probe.dart';

/// What one player took from the rest of the app, given back by [GpuMemory.afterPlayback].
class PlaybackHold {
  PlaybackHold._(this.art);

  /// The pages behind the player let go of their artwork (a 4K file).
  final bool art;
  bool _ended = false;
}

/// Graphics memory on 32-bit TVs. Flutter's Skia renderer keeps a GPU cache of textures
/// sized from the screen (on Android, 12 full screens: hundreds of MB at the Shield's
/// resolution). On the 2019 Shield that memory comes out of the same RAM the video decoder
/// needs: with Liquiflux open the system's graphics memory sat at 400–650 MB and fell by
/// 300–400 MB each time Android killed the app, and a 4K HEVC decoder needs about 500 MB
/// more. So the cache is capped all the time and nearly emptied while a video plays.
///
/// Plezy, which plays the same 4K files on that Shield, started them with about 250 MB
/// less graphics memory in use than Liquiflux 0.9.9. Decoded artwork is the rest of it:
/// it is decoded no wider than [maxArtWidth] there, and for 4K the pages behind the player
/// let go of theirs ([ArtMemory]).
///
/// Letting go wasn't enough on its own: 0.9.11 measured about 235 MB still held with the
/// player covering Home, against 60 MB with no artwork at all, and 0.9.12 the same with only
/// 6 images left in use. Flutter doesn't draw a page another page hides, so a hidden page
/// keeps the last drawing it made, and that drawing holds on to every picture in it. So for
/// a moment the hidden pages are drawn again without their artwork ([_redrawHidden]), under
/// the player drawn black.
///
/// Flutter uploads artwork on its image-loading thread and draws it on the raster thread;
/// when a picture is dropped, Skia hands its texture back to the loading thread's context,
/// which (going by the engine's and Skia's source) frees it only the next time it loads or
/// drops an image. While a video plays nothing loads. [_freeUploads] makes that thread tidy up.
class GpuMemory {
  /// The cap while browsing: posters and backdrops still stay cached.
  static const browsingBytes = 64 << 20;

  /// The cap while the player is open; only the controls are drawn.
  static const playbackBytes = 8 << 20;

  /// The widest artwork is decoded on a 32-bit TV: a 1280x720 backdrop takes 3.5 MB, a
  /// 1920x1080 one 8 MB.
  static const maxArtWidth = 1280;

  /// A transparent 1x1 PNG.
  @visibleForTesting
  static final pixel = Uint8List.fromList(const [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, //
    84, 120, 156, 99, 96, 0, 2, 0, 0, 5, 0, 1, 122, 94, 171, 63, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
  ]);

  /// Set by the app: while on, the pages other pages hide are drawn too.
  static void Function(bool on)? showHidden;

  static int _browsing = browsingBytes;
  static int _players = 0;
  static int _artHolds = 0;

  static Future<void> _cap(int bytes) async {
    try {
      // Lowering the cap makes Skia free unused textures down to it straight away.
      await SystemChannels.skia.invokeMethod<void>('Skia.setResourceCacheMaxBytes', bytes);
    } catch (e) {
      debugPrint('skia cache: $e');
    }
  }

  /// At launch.
  static Future<void> init() async {
    if (!isLowMemoryTv) return;
    ArtMemory.maxDecodeWidth = maxArtWidth;
    final probe = int.tryParse(Probe.value('cache') ?? '');
    if (probe != null) _browsing = probe << 20;
    await _cap(_browsing);
  }

  /// A player's claim on graphics memory, given back by [afterPlayback]. With
  /// [releaseArt] (a 4K file) the pages behind the player drop their artwork until then.
  static PlaybackHold? startPlayback({bool releaseArt = false}) {
    if (!isLowMemoryTv) return null;
    _players++;
    if (releaseArt) {
      _artHolds++;
      ArtMemory.releaseCovered.value = true;
    }
    return PlaybackHold._(releaseArt);
  }

  /// Before the video opens: drops decoded artwork nothing shows and empties the GPU cache
  /// down to [playbackBytes]. For a 4K file it first waits until [covered] says the player
  /// hides the pages behind it, so they have let go of their artwork, then lets the engine
  /// free those textures before the decoder takes its memory.
  static Future<void> forPlayback(PlaybackHold? hold, {Future<void>? covered}) async {
    if (hold == null) return;
    debugPrint('graphics memory before playback: ${status()}');
    if (hold.art) {
      if (covered != null) await covered.timeout(const Duration(seconds: 3), onTimeout: () {});
      // One frame rebuilds the covered pages without their pictures, the next frees them.
      await _frames(2);
      debugPrint('graphics memory with the artwork behind put away: ${status()}');
      // The probe's `noredraw` measures without it, as in 0.9.12.
      if (!Probe.has('noredraw')) {
        await _redrawHidden();
        debugPrint('graphics memory with the pages behind drawn again: ${status()}');
      }
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await _cap(playbackBytes);
    if (hold.art) {
      await _frames(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // The probe's `nofree` measures without it, as in 0.9.11.
    if (!Probe.has('nofree')) await _freeUploads();
    debugPrint('graphics memory for playback: ${status()}');
  }

  /// Draws the hidden pages once without their artwork (see the class notes). The player
  /// draws itself black while [ArtMemory.releaseAll] is on, so nothing shows.
  static Future<void> _redrawHidden() async {
    final show = showHidden;
    if (show == null) return;
    ArtMemory.releaseAll.value = true;
    try {
      show(true);
      // One frame draws them again, the next lets go of what they drew before.
      await _frames(2);
    } finally {
      show(false);
      // Hidden again before their artwork may come back, so it doesn't load meanwhile.
      await _frames(1);
      ArtMemory.releaseAll.value = false;
    }
    await _frames(1);
  }

  /// Makes Flutter's image-loading thread free the textures handed back to it (see the class
  /// notes) by loading and dropping a 1-pixel image. Twice, since the raster thread hands
  /// textures back over a frame or two.
  static Future<void> _freeUploads() async {
    for (var i = 0; i < 2; i++) {
      await _frames(1);
      try {
        final codec = await ui.instantiateImageCodec(pixel);
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        codec.dispose();
      } catch (e) {
        debugPrint('graphics memory: $e');
        return;
      }
      // Dropped images are freed in batches a few milliseconds apart.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// When the player closes. Covered pages show their artwork again as soon as they are
  /// uncovered.
  static Future<void> afterPlayback(PlaybackHold? hold) async {
    if (hold == null || hold._ended) return;
    hold._ended = true;
    _players--;
    if (hold.art && --_artHolds == 0) ArtMemory.releaseCovered.value = false;
    if (_players == 0) await _cap(_browsing);
  }

  /// The TV's available memory and Tegra graphics memory in use (from /proc/meminfo), and
  /// Flutter's decoded images, for the log.
  static String status() {
    final cache = PaintingBinding.instance.imageCache;
    final images = 'images ${cache.currentSizeBytes >> 20} MB cached in ${cache.currentSize}, ${cache.liveImageCount} in use';
    try {
      return '${meminfo(File('/proc/meminfo').readAsStringSync())}, $images';
    } catch (_) {
      return images;
    }
  }

  @visibleForTesting
  static String meminfo(String text) {
    String mb(String key) {
      final m = RegExp('^$key:\\s+(\\d+) kB', multiLine: true).firstMatch(text);
      return m == null ? '?' : '${int.parse(m.group(1)!) >> 10} MB';
    }

    return 'available ${mb('MemAvailable')}, graphics ${mb('NvMapMemUsed')}';
  }

  /// Waits for [n] frames, or gives up if the app isn't drawing (sent to the background).
  static Future<void> _frames(int n) async {
    for (var i = 0; i < n; i++) {
      await SchedulerBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 500), onTimeout: () {});
    }
  }
}
