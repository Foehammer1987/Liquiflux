import 'dart:async';
import 'dart:io' show Platform;

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform.dart';

/// Match Frame Rate: puts the display on a refresh rate that shows the video's frames
/// evenly (23.976 Hz for film) while it plays, and back afterwards. Android TV asks for the
/// mode through the window (DisplayModes.kt); Windows switches the monitor the window is on
/// (windows/runner/display_mode.cpp). Which mode is Dart's call: [pickDisplayMode].
class DisplayMatch {
  static const _channel = MethodChannel('liquiflux/display');

  static bool get supported => Platform.isAndroid || Platform.isWindows;

  /// A TV changes resolution cleanly; a PC desktop would rearrange its windows, so Windows
  /// only ever changes the refresh rate.
  static bool get resolutionSupported => Platform.isAndroid;

  /// What the setting means here: [PlaybackPrefs.displayMatch] 'auto' is on for TVs, where
  /// films on a 60 Hz output judder, and off on a PC, whose monitor may run other things.
  static DisplayMatchMode effective(String pref) {
    if (!supported) return DisplayMatchMode.off;
    var m = DisplayMatchMode.parse(pref) ?? (isTv ? DisplayMatchMode.rate : DisplayMatchMode.off);
    if (m == DisplayMatchMode.rateAndResolution && !resolutionSupported) m = DisplayMatchMode.rate;
    return m;
  }

  /// How long a TV takes to show a picture again after the switch, while playback waits.
  static Duration get settle => Platform.isAndroid ? const Duration(seconds: 2) : const Duration(milliseconds: 800);

  /// The display was switched and hasn't been put back yet.
  static bool _switched = false;
  static Timer? _restore;

  /// Tests stand in for the platform here.
  @visibleForTesting
  static Future<Object?> Function(String method, [Object? args])? call;

  @visibleForTesting
  static Duration? settleForTest;

  @visibleForTesting
  static void reset() {
    _restore?.cancel();
    _restore = null;
    _switched = false;
    call = null;
    settleForTest = null;
  }

  static Future<Object?> _invoke(String method, [Object? args]) => call != null ? call!(method, args) : _channel.invokeMethod<Object?>(method, args);

  /// Switches the display for [fps] when [mode] asks for it and a mode fits, and returns
  /// true once the picture should be back ([settle] after the switch). False, at once, when
  /// it stays as it is. [before] runs just before a switch (the player pausing through it).
  static Future<bool> match({required DisplayMatchMode mode, required double fps, int? width, int? height, Future<void> Function()? before}) async {
    if (!supported && call == null) return false;
    if (mode == DisplayMatchMode.off) return false;
    // The next title is taking over: whatever it needs, no going back in between.
    _restore?.cancel();
    _restore = null;
    try {
      final r = await _invoke('modes');
      if (r is! Map) return false;
      final modes = [for (final m in (r['modes'] as List?) ?? const []) ?DisplayMode.fromMap(m)];
      final current = modes.where((m) => m.id == r['current']).firstOrNull;
      if (current == null) {
        debugPrint('display: current mode not listed, staying');
        return false;
      }
      final target = pickDisplayMode(
        modes: modes,
        current: current,
        fps: fps,
        resolution: mode == DisplayMatchMode.rateAndResolution && (resolutionSupported || call != null),
        videoWidth: width,
        videoHeight: height,
      );
      if (target == null) {
        debugPrint('display: $current fits ${fps.toStringAsFixed(3)} fps (or nothing fits better), staying');
        return false;
      }
      if (before != null) await before();
      final ok = await _invoke('set', {'id': target.id}) == true;
      debugPrint('display: $current -> $target for ${fps.toStringAsFixed(3)} fps: ${ok ? 'switched' : 'failed'}');
      if (!ok) return false;
      _switched = true;
      await Future<void>.delayed(settleForTest ?? settle);
      return true;
    } catch (e) {
      debugPrint('display match: $e');
      return false;
    }
  }

  /// The player is closing: the display goes back to its own mode shortly, unless the next
  /// episode asks for one first (then it keeps the same mode with no second blank).
  static void release({Duration after = const Duration(seconds: 3)}) {
    if (!_switched) return;
    _restore?.cancel();
    _restore = Timer(after, () => unawaited(restoreNow()));
  }

  /// Back to the display's own mode now (also before the window closes).
  static Future<void> restoreNow() async {
    _restore?.cancel();
    _restore = null;
    if (!_switched) return;
    _switched = false;
    try {
      await _invoke('restore');
      debugPrint('display: restored');
    } catch (e) {
      debugPrint('display restore: $e');
    }
  }
}
