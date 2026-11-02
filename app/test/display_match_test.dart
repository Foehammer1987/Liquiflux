import 'package:console_app/services/display_match.dart';
import 'package:console_app/services/playback_prefs.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 4K TV at 60 Hz with film and PAL modes, standing in for the platform channel.
class FakeDisplay {
  int current = 2;
  final calls = <String>[];
  final modes = [
    {'id': 1, 'width': 3840, 'height': 2160, 'refreshRate': 59.94006},
    {'id': 2, 'width': 3840, 'height': 2160, 'refreshRate': 60.000004},
    {'id': 3, 'width': 3840, 'height': 2160, 'refreshRate': 23.976025},
    {'id': 4, 'width': 3840, 'height': 2160, 'refreshRate': 25.0},
    {'id': 5, 'width': 1920, 'height': 1080, 'refreshRate': 23.976025},
    {'id': 'junk'},
  ];

  Future<Object?> call(String method, [Object? args]) async {
    calls.add(method == 'set' ? 'set ${(args as Map)['id']}' : method);
    switch (method) {
      case 'modes':
        return {'current': current, 'modes': modes};
      case 'set':
        current = (args as Map)['id'] as int;
        return true;
      case 'restore':
        current = 2;
        return null;
    }
    return null;
  }
}

void main() {
  late FakeDisplay tv;
  setUp(() {
    DisplayMatch.reset();
    tv = FakeDisplay();
    DisplayMatch.call = tv.call;
    DisplayMatch.settleForTest = Duration.zero;
  });
  tearDown(DisplayMatch.reset);

  test('film switches to 23.976 and goes back after the player closes', () async {
    var paused = false;
    expect(
      await DisplayMatch.match(
        mode: DisplayMatchMode.rate,
        fps: 23.976,
        before: () async => paused = true,
      ),
      isTrue,
    );
    expect(tv.current, 3);
    expect(paused, isTrue);
    DisplayMatch.release(after: const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(tv.current, 2);
    expect(tv.calls.last, 'restore');
  });

  test('the next episode at the same rate keeps the mode with no restore in between', () async {
    await DisplayMatch.match(mode: DisplayMatchMode.rate, fps: 23.976);
    DisplayMatch.release(after: const Duration(milliseconds: 30));
    var paused = false;
    expect(await DisplayMatch.match(mode: DisplayMatchMode.rate, fps: 23.976, before: () async => paused = true), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(tv.current, 3, reason: 'the pending restore was cancelled');
    expect(paused, isFalse, reason: 'no switch, no pause');
    expect(tv.calls.where((c) => c == 'restore'), isEmpty);
    // It still goes back once that episode closes.
    DisplayMatch.release(after: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tv.current, 2);
  });

  test('a fitting display stays and nothing is restored', () async {
    tv.current = 1;
    expect(await DisplayMatch.match(mode: DisplayMatchMode.rate, fps: 29.97), isFalse);
    DisplayMatch.release(after: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tv.calls, ['modes']);
  });

  test('off asks nothing', () async {
    expect(await DisplayMatch.match(mode: DisplayMatchMode.off, fps: 23.976), isFalse);
    expect(tv.calls, isEmpty);
  });

  test('with resolution, a 1080p film goes to 1080p', () async {
    expect(await DisplayMatch.match(mode: DisplayMatchMode.rateAndResolution, fps: 23.976, width: 1920, height: 1040), isTrue);
    expect(tv.current, 5);
  });

  test('a failing platform is no switch', () async {
    DisplayMatch.call = (m, [a]) async => throw StateError('no display');
    expect(await DisplayMatch.match(mode: DisplayMatchMode.rate, fps: 23.976), isFalse);
    DisplayMatch.call = (m, [a]) async => m == 'modes' ? {'current': 9, 'modes': tv.modes} : null;
    expect(await DisplayMatch.match(mode: DisplayMatchMode.rate, fps: 23.976), isFalse);
  });

  test('the setting saves and refuses junk', () {
    expect(const PlaybackPrefs().displayMatch, 'auto');
    expect(PlaybackPrefs.fromJson(const PlaybackPrefs(displayMatch: 'rateAndResolution').toJson()).displayMatch, 'rateAndResolution');
    expect(PlaybackPrefs.fromJson({'displayMatch': 'off'}).displayMatch, 'off');
    expect(PlaybackPrefs.fromJson({'displayMatch': 'turbo'}).displayMatch, 'auto');
    expect(PlaybackPrefs.fromJson({'displayMatch': 3}).displayMatch, 'auto');
    // Linux tests: no display switching here, so everything is off.
    expect(DisplayMatch.effective('rate'), DisplayMatchMode.off);
  });
}
