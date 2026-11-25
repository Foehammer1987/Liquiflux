import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../platform.dart';

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

/// The folder for the app's own files: Application Support, except on an Apple TV, whose
/// sandbox doesn't let an app create Application Support at all (only Library/Caches and tmp
/// are writable; found on a real Apple TV, the simulator allows it). There it is Caches,
/// which tvOS may purge, so only what can be fetched again lives there; settings and
/// channels go to user defaults (see doc_store.dart).
Future<Directory> appDataDirectory() => isTvOS ? getApplicationCacheDirectory() : getApplicationSupportDirectory();
