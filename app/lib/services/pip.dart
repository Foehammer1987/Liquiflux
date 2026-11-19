import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform.dart';

/// Picture-in-picture on Android phones and tablets (PictureInPicture.kt): the player
/// shrinks into a floating window when you go Home mid-video, or from its button.
abstract final class Pip {
  static const _channel = MethodChannel('liquiflux/pip');

  /// Only the phone/tablet build allows it (its manifest); a TV has no use for it.
  static bool get supported => !kIsWeb && isTouch && Platform.isAndroid;

  /// True while the app is in the floating window: the player hides its controls then.
  static final active = ValueNotifier(false);

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
    });
  }

  /// A video is playing (going Home then floats it) or isn't any more.
  static Future<void> playing(bool on, {double? aspect}) => _call('playing', {'on': on, 'aspect': ?aspect});

  /// Into the floating window now.
  static Future<void> enter({double? aspect}) => _call('enter', {'aspect': ?aspect});

  static Future<void> _call(String method, Map<String, Object> args) async {
    if (!supported) return;
    _listen();
    try {
      await _channel.invokeMethod<bool>(method, args);
    } on MissingPluginException {
      // Tests.
    } on PlatformException catch (e) {
      debugPrint('pip $method: ${e.message}');
    }
  }
}
