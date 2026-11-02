import 'dart:async';

import 'package:console_app/services/live_players.dart';
import 'package:console_app/ui/player/remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LivePlayers', () {
    test('releaseAll lets go of open players and waits for ones already closing', () async {
      final a = Object(), b = Object();
      final closingB = Completer<void>();
      var releasedA = false;
      LivePlayers.add(a, () => LivePlayers.going(a, Future(() => releasedA = true)));
      LivePlayers.add(b, () async {});
      LivePlayers.going(b, closingB.future);
      var done = false;
      final all = LivePlayers.releaseAll().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(releasedA, isTrue);
      expect(done, isFalse, reason: 'b is still closing');
      closingB.complete();
      await all;
      expect(LivePlayers.count, 0);
    });

    test('a release that fails or hangs does not stop the app leaving', () async {
      final a = Object(), b = Object();
      LivePlayers.add(a, () => LivePlayers.going(a, Future.error(StateError('gone'))));
      LivePlayers.add(b, () => LivePlayers.going(b, Completer<void>().future));
      await LivePlayers.releaseAll(limit: const Duration(milliseconds: 50));
      expect(LivePlayers.count, 1, reason: 'only the hung one is left');
    });
  });

  group('playerBack', () {
    PlayerBack back({bool offer = false, bool panel = false, bool info = false, bool upNext = false, bool playing = true, bool controls = false}) =>
        playerBack(resumeOffer: offer, panel: panel, info: info, upNext: upNext, playing: playing, controls: controls);

    test('paused, Back leaves from the pause screen and from the controls', () {
      expect(back(playing: false), PlayerBack.leave);
      expect(back(playing: false, controls: true), PlayerBack.leave);
    });

    test('paused, a panel or the info still closes first', () {
      expect(back(playing: false, panel: true), PlayerBack.closePanel);
      expect(back(playing: false, info: true), PlayerBack.closeInfo);
    });

    test('playing, Back hides the controls, then leaves', () {
      expect(back(controls: true), PlayerBack.hideControls);
      expect(back(), PlayerBack.leave);
      expect(back(upNext: true, controls: true), PlayerBack.dismissUpNext);
      expect(back(offer: true, panel: true), PlayerBack.leave);
    });
  });
}
