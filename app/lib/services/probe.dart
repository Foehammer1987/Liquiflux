import 'dart:async';
import 'dart:io';

import 'package:console_core/console_core.dart' show PlexItem, redactSecrets;
import 'package:console_ui/console_ui.dart' show DrawProbe;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';
import '../state/scope.dart';
import '../ui/play.dart';
import 'gpu_memory.dart';

/// Measuring switches for one launch on an Android TV, given from adb:
///
///     adb shell am start -n com.foehammer.liquiflux/com.foehammer.console_app.Probe --es probe noglass,cover=25
///
/// On Windows they come from the environment, and the log goes to a file
/// (LIQUIFLUX_PROBE_LOG, or liquiflux-probe.log in the temp folder):
///
///     $env:LIQUIFLUX_PROBE = 'play=1234,full'; .\Liquiflux.exe
///
/// With any switch (`on` alone just logs) the app logs its memory every second, as lines
/// starting "probe". A normal launch has none and behaves as usual. While a title plays, the
/// player also logs mpv's frame counts every second ("probe video").
///
/// * `surface`: Flutter draws on its own surface, as before 0.9.9, not in a TextureView
///   (MainActivity reads this one; the video plane is hidden behind it then).
/// * `blank`: a black screen and nothing else, for what the engine itself costs.
/// * `noart`: no artwork.
/// * `noglass`: panels drawn flat, as with Surfaces: Flat in Settings.
/// * `noblur`: no blurred art behind the pages, no faded edge on the Home spotlight.
/// * `cache=N`: Skia's GPU cache capped at N MB while browsing instead of 64.
/// * `nofree`: the player doesn't make Flutter free the artwork it put away (as in 0.9.11).
/// * `noredraw`: the player doesn't draw the hidden pages again without their artwork (as in
///   0.9.12).
/// * `cover=T`: T seconds after launch an empty page covers the app for 15 s, the way the
///   player does for a 4K file, without a video.
/// * `trailers`: Home trailers in Spotlight Only mode, whatever Settings says.
/// * `play=KEY`: 30 s after launch (or after `cover`), opens Plex item KEY's title page as a
///   person would, and 12 s later plays it from the start, muted. `play=4k` takes the first
///   4K movie in the library; any other word the first 4K movie with it in its title
///   (`play=way_of_water`, underscores for spaces).
/// * `nointro`: no logo animation at launch.
/// * `playat=T`: `play` starts T seconds after launch instead of 30.
/// * `full`: on Windows, `play` puts the window full screen first.
/// * `at=T`: the title `play` starts plays from T seconds in.
/// * `quit=T`: on Windows, the app closes T seconds after launch.
/// * `room=KEY`: at `playat` (30 s), opens a Watch Together room by code for Plex item KEY
///   (or the first movie with that word in its title, underscores for spaces) and logs its code ("probe room code K7M-Q2X"); the player opens through the room.
/// * `join=CODE`: at `playat`, joins that room.
/// * `drive`: as a room's host, once its player has played 20 s with someone else in the room: pause, play 10 s later, then
///   jump 5 minutes on, then back 2 minutes, 15 s apart.
/// With `room` or `join`, a "probe room" line every second says where the room and the player
/// are.
/// * `lowmem`: the low-memory behaviour of a small TV (see isLowMemoryTv) on any Android
///   device, such as a 64-bit Fire TV with more RAM.
/// * `sleep=S`: the first title played starts a sleep timer of S seconds (its last minute
///   warns and fades). Logs "probe sleep" lines every second.
abstract final class Probe {
  static const _channel = MethodChannel('liquiflux/probe');
  static Set<String> _flags = const {};
  static final _clock = Stopwatch();
  static String _phase = 'starting';
  static bool _started = false;
  static String _mapped = '';

  static bool get on => _flags.isNotEmpty;

  /// The probe started the player (`play`); it plays muted.
  static bool get playing => _playing;
  static bool _playing = false;
  static bool has(String flag) => _flags.contains(flag);

  /// The N of a `key=N` switch.
  static String? value(String key) {
    for (final f in _flags) {
      if (f.startsWith('$key=')) return f.substring(key.length + 1);
    }
    return null;
  }

  @visibleForTesting
  static void set(String? flags) => _flags = {...?flags?.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty)};

  /// At launch, before anything else is set up.
  static Future<void> init() async {
    if (Platform.isWindows) {
      set(Platform.environment['LIQUIFLUX_PROBE']);
      if (!on) return;
      _logToFile(Platform.environment['LIQUIFLUX_PROBE_LOG'] ?? '${Directory.systemTemp.path}\\liquiflux-probe.log');
      final quit = int.tryParse(value('quit') ?? '');
      if (quit != null) Timer(Duration(seconds: quit), () => exit(0));
    } else if (Platform.isAndroid) {
      try {
        set(await _channel.invokeMethod<String>('flags'));
      } catch (_) {
        return;
      }
    } else {
      return;
    }
    if (!on) return;
    _clock.start();
    DrawProbe.noArt = has('noart');
    DrawProbe.noBlur = has('noblur');
    debugPrint('probe: ${_flags.join(',')}');
    Timer.periodic(const Duration(seconds: 1), (t) {
      // The process's own mappings take longer to read, so every few seconds.
      if (Platform.isAndroid && t.tick % 5 == 1) _mapped = _readMapped();
      log();
    });
  }

  /// Every log line also goes to [path], with the time since launch (Windows has no logcat).
  static void _logToFile(String path) {
    final file = File(path);
    try {
      file.writeAsStringSync('');
    } catch (e) {
      debugPrint('probe: no log file at $path: $e');
      return;
    }
    final plain = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      plain(message, wrapWidth: wrapWidth);
      if (message == null) return;
      final ms = _clock.elapsedMilliseconds;
      try {
        file.writeAsStringSync('${(ms / 1000).toStringAsFixed(3)} ${redactSecrets(message)}\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    };
  }

  static void log() => debugPrint('probe ${_clock.elapsed.inSeconds}s $_phase: ${GpuMemory.status()}$_mapped');

  /// Once the app's shell is up: runs `cover` and `play`. [openTitle] opens a title page.
  static Future<void> atHome(BuildContext context, {required void Function(String ratingKey) openTitle}) async {
    if (!on || _started) return;
    _started = true;
    _phase = 'home';
    final coverAt = int.tryParse(value('cover') ?? '');
    if (coverAt != null) {
      await _until(coverAt);
      if (!context.mounted) return;
      await _cover(context);
    }
    final roomKey = value('room'), joinCode = value('join');
    if (roomKey != null || joinCode != null) {
      await _until(int.tryParse(value('playat') ?? '') ?? 30);
      if (!context.mounted) return;
      await _room(context, roomKey, joinCode);
    }
    final key = value('play');
    if (key != null) {
      await _until(int.tryParse(value('playat') ?? '') ?? 30);
      if (!context.mounted) return;
      await _play(context, key, openTitle);
    }
  }

  /// Opens or joins a room by code, logs it every second, and as host plays the room about.
  static Future<void> _room(BuildContext context, String? key, String? code) async {
    final app = AppScope.read(context);
    for (var i = 0; i < 120 && (app.plex == null || app.plexConn != Conn.ok); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final party = app.openParty;
    var ok = false;
    _playing = true;
    if (key != null) {
      var ratingKey = key;
      if (int.tryParse(key) == null) {
        // A word: the first movie with it in its title, not a 4K one if there's a choice.
        final words = key.replaceAll('_', ' ').toLowerCase();
        final found = [
          for (final section in (await app.library()).bySection)
            for (final item in section)
              if (item.type == 'movie' && item.title.toLowerCase().contains(words)) item,
        ]..sort((a, b) => (a.media.any((m) => m.videoResolution?.toLowerCase() == '4k') ? 1 : 0).compareTo(b.media.any((m) => m.videoResolution?.toLowerCase() == '4k') ? 1 : 0));
        debugPrint('probe room: movies for "$words": ${found.take(5).map((i) => '${i.title} (${i.ratingKey})').join(', ')}');
        if (found.isEmpty) return;
        ratingKey = found.first.ratingKey;
      }
      final item = await app.plex?.metadata(ratingKey).catchError((Object _) => null);
      ok = item != null && await party.start(item);
      debugPrint('probe room code ${party.code} (${ok ? 'open' : 'failed: ${party.error}'})');
    } else {
      ok = await party.join(code!);
      debugPrint('probe room joined ${party.code} (${ok ? 'ok' : 'failed: ${party.error}'})');
    }
    if (!ok) return;
    _phase = 'room';
    var played = 0, step = 0;
    Timer.periodic(const Duration(seconds: 1), (t) {
      final s = party.session;
      if (!party.inRoom && t.tick > 5) {
        debugPrint('probe room: left (${party.error ?? 'no error'})');
        t.cancel();
        return;
      }
      final room = party.state.room;
      debugPrint(
        'probe room: ${party.state.connection.name} ${room?.phase.name ?? '-'} room@${room == null ? '-' : (party.state.room!.positionMs / 1000).toStringAsFixed(1)}'
        ' me@${s == null ? '-' : (s.position.inMilliseconds / 1000).toStringAsFixed(1)} ${s?.player.state.playing == true ? 'playing' : 'paused'}'
        ' match=${party.state.match?.state.name ?? '-'} people=${room?.participants.map((p) => '${p.player.name}${p.host ? '*' : ''}').join(',') ?? '-'}',
      );
      if (!has('drive') || !party.isHost || s == null) return;
      if (s.player.state.playing && (room?.participants.length ?? 0) >= 2) played++;
      if (played < 20) return;
      step++;
      switch (step) {
        case 1:
          debugPrint('probe room drive: pause');
          party.pause();
        case 11:
          debugPrint('probe room drive: play');
          party.play();
        case 26:
          debugPrint('probe room drive: jump +300 s');
          unawaited(party.seek(s.position + const Duration(minutes: 5)));
        case 41:
          debugPrint('probe room drive: jump -120 s');
          unawaited(party.seek(s.position - const Duration(minutes: 2)));
      }
    });
  }

  static Future<void> _until(int seconds) async {
    final left = Duration(seconds: seconds) - _clock.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  /// What the player does to the pages behind it for a 4K file, with an empty page.
  static Future<void> _cover(BuildContext context) async {
    final nav = Navigator.of(context, rootNavigator: true);
    _phase = 'covering';
    log();
    final hold = GpuMemory.startPlayback(releaseArt: true);
    // The player's own kind of route, so the pages behind it are treated the same.
    final route = playerRoute((_) => const ColoredBox(color: Color(0xFF000000)));
    unawaited(nav.push(route));
    await GpuMemory.forPlayback(hold, covered: _settled(route));
    _phase = 'covered';
    log();
    await Future<void>.delayed(const Duration(seconds: 15));
    if (route.isActive) nav.removeRoute(route);
    await GpuMemory.afterPlayback(hold);
    _phase = 'uncovered';
    log();
  }

  static Future<void> _settled(ModalRoute<void> route) async {
    final animation = route.animation;
    if (animation == null || !animation.isAnimating) return;
    final done = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status.isAnimating) return;
      animation.removeStatusListener(onStatus);
      if (!done.isCompleted) done.complete();
    }

    animation.addStatusListener(onStatus);
    await done.future;
  }

  static Future<void> _play(BuildContext context, String key, void Function(String ratingKey) openTitle) async {
    final app = AppScope.read(context);
    for (var i = 0; i < 120 && (app.plex == null || app.plexConn != Conn.ok); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final plex = app.plex;
    if (plex == null || app.plexConn != Conn.ok) {
      debugPrint('probe: Plex is not connected');
      return;
    }
    var ratingKey = key;
    if (int.tryParse(key) == null) {
      final words = key.replaceAll('_', ' ').toLowerCase();
      final library = await app.library();
      final found = [
        for (final section in library.bySection)
          for (final item in section)
            if (item.type == 'movie' &&
                item.media.any((m) => m.videoResolution?.toLowerCase() == '4k') &&
                (words == '4k' || item.title.toLowerCase().contains(words)))
              item,
      ];
      String versions(PlexItem i) => i.media.map((m) => m.videoResolution).join('/');
      debugPrint('probe: 4K movies for "$words": ${found.take(10).map((i) => '${i.title} (${i.ratingKey}, versions ${versions(i)})').join(', ')}');
      if (found.isEmpty && words != '4k') {
        // Not a 4K title: any movie with the words in its title.
        found.addAll([
          for (final section in library.bySection)
            for (final item in section)
              if (item.type == 'movie' && item.title.toLowerCase().contains(words)) item,
        ]);
        debugPrint('probe: movies for "$words": ${found.take(10).map((i) => '${i.title} (${i.ratingKey}, versions ${versions(i)})').join(', ')}');
      }
      if (found.isEmpty) return;
      ratingKey = found.first.ratingKey;
    }
    final item = await plex.metadata(ratingKey);
    if (item == null || !context.mounted) return;
    _phase = 'title page ${item.title} ($ratingKey)';
    log();
    openTitle(ratingKey);
    await Future<void>.delayed(const Duration(seconds: 12));
    if (!context.mounted) return;
    _phase = 'playing ${item.title} ($ratingKey)';
    log();
    _playing = true;
    if (Platform.isWindows && has('full')) await windowManager.setFullScreen(true);
    if (!context.mounted) return;
    await playTitle(context, item, resume: false);
    _playing = false;
    _phase = 'home';
  }

  static String _readMapped() {
    try {
      return mapped(File('/proc/self/smaps').readAsStringSync());
    } catch (e) {
      return ', mapped: $e';
    }
  }

  /// The process's mappings of devices and buffers shared with the GPU (/dev/nvmap and the
  /// like), the largest first: graphics memory this app holds, which /proc/meminfo only
  /// gives for the whole TV.
  @visibleForTesting
  static String mapped(String smaps) {
    final size = <String, int>{};
    final rss = <String, int>{};
    final header = RegExp(r'^[0-9a-f]+-[0-9a-f]+ \S+ \S+ \S+ \S+\s*(.*)$');
    final field = RegExp(r'^(Size|Rss):\s+(\d+) kB');
    String? name;
    for (final line in smaps.split('\n')) {
      final h = header.firstMatch(line);
      if (h != null) {
        final path = h.group(1)!.trim();
        name = path.startsWith('/dev/') || path.startsWith('anon_inode:') || path.contains('dmabuf') || path.contains('dma_buf') ? path : null;
        continue;
      }
      final f = name == null ? null : field.firstMatch(line);
      if (f == null) continue;
      final kb = int.parse(f.group(2)!);
      (f.group(1) == 'Size' ? size : rss).update(name!, (v) => v + kb, ifAbsent: () => kb);
    }
    if (size.isEmpty) return ', mapped: none';
    final top = size.keys.toList()..sort((a, b) => size[b]!.compareTo(size[a]!));
    return ', mapped: ${top.take(4).map((k) => '$k ${size[k]! >> 10} MB (${(rss[k] ?? 0) >> 10} resident)').join(', ')}';
  }
}
