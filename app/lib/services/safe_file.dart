import 'dart:async';
import 'dart:io';

/// Replaces [f]'s contents in one step: the text goes to a file alongside that is then
/// renamed over it, so a crash mid-save never leaves half a file behind.
Future<void> writeAtomically(File f, String text) async {
  await f.parent.create(recursive: true);
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(text, flush: true);
  await tmp.rename(f.path);
}

/// Runs saves one after another, so a slow save can't land after (and undo) a newer one.
class SaveQueue {
  Future<void> _tail = Future.value();

  Future<void> run(Future<void> Function() job) {
    final next = _tail.catchError((Object _) {}).then((_) => job());
    _tail = next;
    return next;
  }
}
