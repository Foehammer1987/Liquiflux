import 'package:console_app/ui/player/player_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeks during a Plex transcode (1.1.3). A Fire TV user's skips went back to the start of
/// the film: the title had been resumed partway in, and a skip to a part the player didn't
/// hold made Plex restart its transcoder counting from the title's start.
void main() {
  const offset = Duration(minutes: 9, seconds: 40);
  const playing = Duration(seconds: 32);
  const buffered = Duration(seconds: 57);
  bool stays(Duration to, {Duration from = offset, Duration at = playing, Duration held = buffered}) =>
      PlayerSession.seekStaysInStream(to: to, offset: from, playing: at, buffered: held);

  group('a transcode that started partway in', () {
    test('a skip ahead into what is already read stays in the stream', () {
      expect(stays(offset + playing), isTrue);
      expect(stays(offset + playing + const Duration(seconds: 10)), isTrue);
      expect(stays(offset + buffered), isTrue);
    });

    test('a skip past what is read starts a new transcode', () {
      // The one that showed 1:26 of the film at "11:06".
      expect(stays(const Duration(minutes: 11, seconds: 6)), isFalse);
      expect(stays(offset + buffered + const Duration(seconds: 1)), isFalse);
      expect(stays(const Duration(hours: 1)), isFalse);
    });

    test('so does any skip back, even inside the stream', () {
      // 10 s back, 4 s into the stream: the player had let go of it, and Plex miscounted.
      expect(stays(offset + const Duration(seconds: 4), at: const Duration(seconds: 14)), isFalse);
      expect(stays(offset + playing - const Duration(seconds: 1)), isFalse);
      expect(stays(offset), isFalse);
      expect(stays(offset - const Duration(seconds: 1)), isFalse);
      expect(stays(Duration.zero), isFalse);
    });
  });

  test('a transcode from the start keeps every seek in the stream', () {
    bool fromStart(Duration to) => stays(to, from: Duration.zero);
    expect(fromStart(Duration.zero), isTrue);
    expect(fromStart(const Duration(seconds: 5)), isTrue);
    expect(fromStart(const Duration(minutes: 30)), isTrue);
    expect(fromStart(const Duration(hours: 1, minutes: 6, seconds: 40)), isTrue);
  });
}
