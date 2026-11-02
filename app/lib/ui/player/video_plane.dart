import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The picture's Android SurfaceView behind the Flutter UI on 32-bit TVs (VideoPlane.kt),
/// for the 'plane' video output. The player page leaves its area transparent so it shows.
class VideoPlane {
  static const _channel = MethodChannel('liquiflux/video_plane');

  /// Called with the surface's JNI reference and size when it appears or changes, and with
  /// zeros when it goes. One player at a time owns the plane.
  static void Function(int wid, int width, int height)? _owner;

  /// Shows the plane, or hands it over from the player still closing (the next episode):
  /// a surface takes one decoder at a time, so the old one lets go first.
  static Future<void> show(void Function(int wid, int width, int height) onSurface) async {
    final old = _owner;
    if (old != null && old != onSurface) old(0, 0, 0);
    _owner = onSurface;
    _channel.setMethodCallHandler(_onCall);
    await _call('show');
  }

  /// The picture's width over its height; 0 fills the screen.
  static Future<void> aspect(double value) => _call('aspect', {'aspect': value});

  static Future<void> hide(void Function(int wid, int width, int height) onSurface) async {
    if (_owner != onSurface) return;
    await _call('hide');
    _owner = null;
  }

  static Future<void> _onCall(MethodCall call) async {
    if (call.method != 'surface') return;
    final a = (call.arguments as Map).cast<String, Object?>();
    _owner?.call(a['wid'] as int? ?? 0, a['width'] as int? ?? 0, a['height'] as int? ?? 0);
  }

  static Future<void> _call(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('video plane $method: $e');
    }
  }
}
