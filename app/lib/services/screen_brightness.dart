import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The screen's brightness, for the player's brightness gesture on a phone or tablet:
/// UIScreen.brightness on iOS (AppDelegate.swift), the window's brightness on Android
/// (MainActivity.kt). The first change remembers the brightness it started from, and
/// [reset] puts it back when the player closes. Elsewhere nothing happens.
class ScreenBrightness {
  ScreenBrightness();

  static final instance = ScreenBrightness();
  static const _channel = MethodChannel('liquiflux/brightness');

  bool get _supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  double? _changed;

  /// 0 to 1 (0.5 where it can't be read).
  Future<double> get() async {
    if (_changed != null) return _changed!;
    if (!_supported) return 0.5;
    try {
      return (await _channel.invokeMethod<double>('get')) ?? 0.5;
    } catch (e) {
      debugPrint('brightness: $e');
      return 0.5;
    }
  }

  Future<void> set(double value) async {
    _changed = value.clamp(0.0, 1.0);
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('set', _changed);
    } catch (e) {
      debugPrint('brightness: $e');
    }
  }

  /// Back to the brightness before the player changed it (on Android, the system's own).
  Future<void> reset() async {
    if (_changed == null) return;
    _changed = null;
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('reset');
    } catch (e) {
      debugPrint('brightness: $e');
    }
  }
}
