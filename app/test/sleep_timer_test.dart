import 'package:console_app/ui/player/sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a clock counts down, warns in the last minute and never goes below zero', () {
    var now = DateTime(2026, 10, 30, 23);
    final t = SleepTimer(now: () => now)..setMinutes(30);
    expect(t.active, isTrue);
    expect(t.left, const Duration(minutes: 30));
    expect(t.warning, isFalse);
    now = now.add(const Duration(minutes: 29, seconds: 1));
    expect(t.warning, isTrue);
    now = now.add(const Duration(minutes: 5));
    expect(t.left, Duration.zero);
    t.cancel();
    expect(t.active, isFalse);
    expect(t.left, isNull);
  });

  test('counting titles: stops after the last one, going on to the next counts', () {
    final t = SleepTimer()..setTitles(3);
    expect(t.stopsAtEnd, isFalse);
    expect(t.finishedTitle(), isFalse);
    expect(t.titles, 2);
    expect(t.finishedTitle(), isFalse);
    expect(t.stopsAtEnd, isTrue);
    expect(t.finishedTitle(), isTrue);
    expect(t.active, isFalse);
    // With nothing running, finishing a title never stops playback.
    expect(t.finishedTitle(), isFalse);
  });

  test('picking one kind drops the other', () {
    final t = SleepTimer()..setTitles(2);
    t.setMinutes(15);
    expect(t.titles, isNull);
    expect(t.minutes, 15);
    t.setTitles(1);
    expect(t.deadline, isNull);
    expect(t.minutes, isNull);
    expect(t.stopsAtEnd, isTrue);
  });
}
