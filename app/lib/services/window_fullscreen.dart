import 'dart:io' show Platform;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Full screen on and off for the desktop window. On a Mac, leaving full screen could put
/// the window somewhere else than before (window_manager hands it back to macOS, which
/// picks a spot), so the window's bounds are noted on the way in and put back on the way
/// out. Elsewhere it's just window_manager's setFullScreen.
class WindowFullscreen {
  WindowFullscreen({bool? mac, Future<Rect> Function()? getBounds, Future<void> Function(Rect)? setBounds, Future<void> Function(bool)? setFull})
    : _mac = mac ?? Platform.isMacOS,
      _getBounds = getBounds ?? windowManager.getBounds,
      _setBounds = setBounds ?? ((r) => windowManager.setBounds(r)),
      _setFull = setFull ?? windowManager.setFullScreen;

  static final instance = WindowFullscreen();

  final bool _mac;
  final Future<Rect> Function() _getBounds;
  final Future<void> Function(Rect) _setBounds;
  final Future<void> Function(bool) _setFull;

  /// Where the window was before it went full screen, on a Mac.
  Rect? _before;

  Future<void> set(bool on) async {
    if (_mac && on) {
      try {
        _before = await _getBounds();
      } catch (e) {
        debugPrint('window bounds: $e');
      }
    }
    await _setFull(on);
    final before = _before;
    if (_mac && !on && before != null) {
      _before = null;
      // macOS animates out of full screen; the window takes its bounds once it's back.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        await _setBounds(before);
      } catch (e) {
        debugPrint('window bounds: $e');
      }
    }
  }
}
