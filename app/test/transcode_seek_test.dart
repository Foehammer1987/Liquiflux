import 'package:console_app/ui/player/player_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeks during a Plex transcode (1.1.3). A Fire TV user's forward skips went back to the
/// start of the film: the title had been resumed partway in, and a skip past what Plex had
/// made so far restarted its transcoder counting from the title's start.
void main() {
  const offset = Duration(minutes: 9, seconds: 40);
  const buffered = Duration(seconds: 25);
  bool stays(Duration to, {Duration from = offset, Duration held = buffered}) => PlayerSession.seekStaysInStream(to: to, offset: from, buffered: held);

  test('a skip inside what the player holds stays in the stream', () {
    expect(stays(offset), isTrue);
    expect(stays(offset + const Duration(seconds: 10)), isTrue);
    expect(stays(offset + buffered), isTrue);
  });

  test('a skip past what the player holds starts a new transcode', () {
    // The one that showed 1:26 of the film at "11:06".
    expect(stays(const Duration(minutes: 11, seconds: 6)), isFalse);
    expect(stays(offset + buffered + const Duration(seconds: 1)), isFalse);
    expect(stays(const Duration(hours: 1)), isFalse);
  });

  test('so does one from the very start, where nothing is held yet', () {
    expect(stays(const Duration(seconds: 30), from: Duration.zero, held: Duration.zero), isFalse);
    expect(stays(Duration.zero, from: Duration.zero, held: Duration.zero), isTrue);
  });

  test('a skip back before the transcode starts a new one', () {
    expect(stays(offset - const Duration(seconds: 1)), isFalse);
    expect(stays(Duration.zero), isFalse);
  });
}
