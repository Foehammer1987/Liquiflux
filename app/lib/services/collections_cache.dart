import 'dart:convert';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'safe_file.dart';

/// A Plex collection as Collections needs it: its own details and which items it holds.
typedef PlexSeries = ({PlexItem collection, List<String> items, int? tmdbId});

/// Everything Collections is built from, kept on disk so the page opens straight away and
/// is brought up to date in the background: TMDB's series (refetched weekly) and the Plex
/// collections (listed on every refresh; a collection's films are fetched again only when
/// its updatedAt or childCount changed).
class CollectionsCache {
  /// The Plex server it belongs to; another server starts afresh.
  String server = '';
  final tmdb = <int, ({DateTime at, SeerrCollection series})>{};
  List<PlexSeries> plex = const [];
  bool loaded = false;
  final _saves = SaveQueue();

  static const tmdbMaxAge = Duration(days: 7);

  /// The most that's read from disk: a bigger file isn't one we wrote, so it's left alone
  /// (and replaced on the next save).
  static const maxBytes = 64 * 1024 * 1024;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}collections_cache.json');
  }

  bool get isEmpty => tmdb.isEmpty && plex.isEmpty;

  /// True when collection [now] still holds what [before] (from last time) did. An entry
  /// saved before these were kept has no updatedAt, so it counts as changed.
  static bool same(PlexItem before, PlexItem now) => before.updatedAt != null && before.updatedAt == now.updatedAt && before.childCount == now.childCount;

  /// TMDB's series, if it was fetched recently enough to trust.
  SeerrCollection? fresh(int id) {
    final e = tmdb[id];
    if (e == null) return null;
    // A date in the future (a clock that was wrong, or a hand-edited file) isn't fresh.
    final age = DateTime.now().difference(e.at);
    return !age.isNegative && age < tmdbMaxAge ? e.series : null;
  }

  Future<void> load(String forServer) async {
    if (loaded && server == forServer) return;
    loaded = true;
    server = forServer;
    tmdb.clear();
    plex = const [];
    try {
      final f = await _file();
      if (!await f.exists() || await f.length() > maxBytes) return;
      read(await f.readAsString(), forServer);
    } catch (e) {
      debugPrint('collections cache: $e');
    }
  }

  /// Fills the cache from [text] (the file's contents) when it was saved for [forServer].
  /// The file is ours but anyone can edit it, so an entry that doesn't read is skipped and a
  /// file that doesn't read at all leaves the cache empty; nothing here throws.
  @visibleForTesting
  void read(String text, String forServer) {
    tmdb.clear();
    plex = const [];
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (j is! Map || j['server'] != forServer) return;
    final t = j['tmdb'];
    if (t is Map) {
      for (final e in t.entries) {
        final id = int.tryParse('${e.key}');
        final v = e.value;
        if (id == null || id <= 0 || v is! Map) continue;
        final at = v['at'], json = v['json'];
        if (at is! int || at < -8640000000000000 || at > 8640000000000000 || json is! Map<String, dynamic>) continue;
        final series = SeerrCollection.fromJson(json);
        // A series filed under another series' id would show the wrong films.
        if (series.id != id) continue;
        tmdb[id] = (at: DateTime.fromMillisecondsSinceEpoch(at), series: series);
      }
    }
    final p = j['plex'];
    plex = [for (final e in (p is List ? p : const []).whereType<Map<dynamic, dynamic>>()) ?_series(e)];
  }

  /// One saved Plex collection, or null when it doesn't read.
  static PlexSeries? _series(Map<dynamic, dynamic> p) {
    final c = p['collection'], items = p['items'], tmdbId = p['tmdbId'];
    if (c is! Map<String, dynamic> || items is! List) return null;
    final collection = PlexItem.fromJson(c);
    if (collection.ratingKey.isEmpty) return null;
    return (
      collection: collection,
      // ratingKeys are plain ids; they're only ever looked up in the library, never fetched.
      items: [
        for (final k in items)
          if ((k is String || k is int) && RegExp(r'^\w{1,64}$').hasMatch('$k')) '$k',
      ],
      tmdbId: tmdbId is int && tmdbId > 0 ? tmdbId : null,
    );
  }

  /// Saves run one at a time, each writing what's in hand when its turn comes.
  Future<void> save() => _saves.run(() async {
    try {
      await writeAtomically(
        await _file(),
        jsonEncode({
          'server': server,
          'tmdb': {
            for (final e in tmdb.entries) '${e.key}': {'at': e.value.at.millisecondsSinceEpoch, 'json': e.value.series.json},
          },
          'plex': [
            for (final p in plex)
              {
                'collection': {
                  'ratingKey': p.collection.ratingKey,
                  'type': 'collection',
                  'title': p.collection.title,
                  'summary': p.collection.summary,
                  'thumb': p.collection.thumb,
                  'art': p.collection.art,
                  'updatedAt': p.collection.updatedAt,
                  'childCount': p.collection.childCount,
                },
                'items': p.items,
                'tmdbId': p.tmdbId,
              },
          ],
        }),
      );
    } catch (e) {
      debugPrint('collections cache save: $e');
    }
  });
}
