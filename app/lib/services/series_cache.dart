import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'safe_file.dart';

/// Which film series (TMDB collection) each movie belongs to, 0 for none, kept on disk so
/// a big library is only looked up once and new films are checked as they arrive.
class SeriesCache {
  final Map<int, int> _map = {};
  bool _loaded = false;
  bool _dirty = false;
  final _saves = SaveQueue();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}series_cache.json');
  }

  /// The most that's read from disk: a bigger file isn't one we wrote.
  static const maxBytes = 16 * 1024 * 1024;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists() && await f.length() <= maxBytes) read(await f.readAsString());
    } catch (e) {
      debugPrint('series cache: $e');
    }
  }

  /// Adds what [text] (the file's contents) holds: "movie id": series id, 0 for none. Anything
  /// else in it is skipped, and text that isn't JSON adds nothing; nothing here throws.
  @visibleForTesting
  void read(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (j is! Map) return;
    for (final e in j.entries) {
      final k = int.tryParse('${e.key}');
      final v = e.value;
      if (k != null && k > 0 && v is int && v >= 0) _map[k] = v;
    }
  }

  bool has(int movie) => _map.containsKey(movie);
  int? operator [](int movie) => _map[movie];

  void operator []=(int movie, int collection) {
    _map[movie] = collection;
    _dirty = true;
  }

  /// Writes the cache if anything changed; saves run one at a time, each writing what's
  /// in hand when its turn comes.
  Future<void> save() => _saves.run(() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await writeAtomically(await _file(), jsonEncode({for (final e in _map.entries) '${e.key}': e.value}));
    } catch (e) {
      _dirty = true;
      debugPrint('series cache save: $e');
    }
  });
}
