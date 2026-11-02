import 'package:flutter/foundation.dart';

/// The player's sleep timer. It lives outside any one player, so it keeps running when
/// Up Next swaps in the next episode (each episode gets its own player page).
///
/// Two kinds: a clock ([deadline], 15 minutes to 90) or a number of titles ([titles]:
/// stop when this one ends, or after one or two more).
class SleepTimer extends ChangeNotifier {
  SleepTimer({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final instance = SleepTimer();

  /// How long before the deadline the warning shows and the volume starts to fade.
  static const warnFor = Duration(seconds: 60);

  final DateTime Function() _now;

  DateTime? deadline;

  /// The length picked, in minutes, for the panel's chips; null when the clock isn't running.
  int? minutes;

  /// Titles left to finish, counting the one playing; null when not counting titles.
  int? titles;

  bool get active => deadline != null || titles != null;

  /// The credits play out with no Up Next countdown: this is the last title.
  bool get stopsAtEnd => titles == 1;

  /// Time to the deadline, never below zero; null without one.
  Duration? get left {
    final d = deadline;
    if (d == null) return null;
    final l = d.difference(_now());
    return l.isNegative ? Duration.zero : l;
  }

  /// Inside the last minute: the warning shows and the volume fades.
  bool get warning => left != null && left! <= warnFor;

  void setMinutes(int m) => setFor(Duration(minutes: m), minutes: m);

  /// A clock of any length ([Probe]'s `sleep=S` uses seconds).
  void setFor(Duration d, {int? minutes}) {
    titles = null;
    this.minutes = minutes;
    deadline = _now().add(d);
    notifyListeners();
  }

  /// 1 stops at the end of the title playing, 2 after the next one, and so on.
  void setTitles(int n) {
    deadline = null;
    minutes = null;
    titles = n < 1 ? 1 : n;
    notifyListeners();
  }

  void cancel() {
    if (!active) return;
    deadline = null;
    minutes = null;
    titles = null;
    notifyListeners();
  }

  /// A title has finished (played out, or Next / Up Next went on from it). True when
  /// that was the last one the timer allowed: playback should stop rather than go on.
  bool finishedTitle() {
    final n = titles;
    if (n == null) return false;
    if (n <= 1) {
      cancel();
      return true;
    }
    titles = n - 1;
    notifyListeners();
    return false;
  }
}
