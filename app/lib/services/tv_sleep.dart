import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../app_info.dart';
import '../platform.dart';

/// Puts an Android TV to sleep when the sleep timer runs out (SleepService.kt). An app can
/// only do that through an accessibility service the person switches on once (Android TV has
/// no device admin); on a Shield, sleeping also turns the TV off over HDMI-CEC when that's on.
/// Elsewhere nothing happens.
abstract final class TvSleep {
  static const _channel = MethodChannel('liquiflux/sleep');

  static bool get supported => !kIsWeb && isAndroidTv && storeBuild.isEmpty;

  /// Known after the first [check]; null before, and off Android.
  static final allowed = ValueNotifier<bool?>(null);

  static Future<bool> check() => _call('allowed');

  /// Opens Android's Accessibility settings, where "Liquiflux sleep timer" is switched on;
  /// [allowed] is checked again when the app comes back.
  static Future<bool> ask() async {
    _back ??= AppLifecycleListener(onResume: () => unawaited(check()));
    return _call('ask');
  }

  static AppLifecycleListener? _back;

  /// True if the TV is going to sleep.
  static Future<bool> now() => _call('now');

  static Future<bool> _call(String method) async {
    if (!supported) return false;
    try {
      final r = await _channel.invokeMethod<bool>(method) ?? false;
      if (method == 'allowed') allowed.value = r;
      return r;
    } catch (e) {
      debugPrint('tv sleep $method: $e');
      return false;
    }
  }
}
