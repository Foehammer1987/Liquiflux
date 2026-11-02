import 'dart:async';

import 'package:flutter/foundation.dart';

/// Every mpv player (media_kit [Player]) the app has open, so all of them can be let go before Android closes
/// the app.
///
/// media_kit hands each mpv handle a wakeup callback that lives in the Dart isolate. When
/// the activity finishes (Back from Home), the isolate goes and the callback's code with it,
/// but a player nobody disposed keeps its mpv threads, and the next wakeup jumps into freed
/// memory: the native SIGSEGV in libmpv on 2 of 4 Back exits on the Shield (0.9.35).
/// Disposing a player clears that callback first, so [releaseAll] runs before leaving.
class LivePlayers {
  LivePlayers._();

  static final _live = <Object, Future<void> Function()>{};
  static final _going = <Future<void>>{};

  /// Players open now (tests).
  @visibleForTesting
  static int get count => _live.length + _going.length;

  /// [player] is open; [release] lets it go (its owner's own way, surface first and so on)
  /// and reports through [going].
  static void add(Object player, Future<void> Function() release) => _live[player] = release;

  /// [player] is being let go; [done] completes once it has. Returns [done], errors dropped.
  static Future<void> going(Object player, Future<void> done) {
    _live.remove(player);
    final f = done.catchError((Object e) => debugPrint('player release: $e'));
    _going.add(f);
    unawaited(f.whenComplete(() => _going.remove(f)));
    return f;
  }

  /// Lets go of every open player and waits (at most [limit]) for all of them, including
  /// ones already on their way out.
  static Future<void> releaseAll({Duration limit = const Duration(seconds: 3)}) async {
    for (final release in _live.values.toList()) {
      try {
        unawaited(release());
      } catch (e) {
        debugPrint('player release: $e');
      }
    }
    if (_going.isEmpty) return;
    final watch = Stopwatch()..start();
    try {
      await Future.wait(_going.toList()).timeout(limit);
      debugPrint('players released in ${watch.elapsedMilliseconds} ms');
    } on TimeoutException {
      debugPrint('players: ${_going.length} still closing after ${limit.inMilliseconds} ms');
    }
  }
}
