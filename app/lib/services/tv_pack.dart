import 'dart:async';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'safe_file.dart';

/// Liquiflux's TV collection pack: the shows of each TV network and programming block
/// (Adult Swim, Toonami, Nick at Nite...). The same list for everyone; each install matches
/// it against its own library.
///
/// A copy ships inside the app. A newer one is fetched from the Liquiflux repository at
/// most once a day (rebuilt monthly by its Collection pack workflow) and kept on disk, so
/// new shows and blocks arrive without an app update. Nothing is sent but the request.
class TvPackStore {
  TvPackStore({http.Client? client, Future<Directory> Function()? folder, Future<String> Function()? bundled})
    : _client = client ?? http.Client(),
      _folder = folder ?? appDataDirectory,
      _bundled = bundled ?? (() => rootBundle.loadString(asset));

  static const asset = 'assets/collections/tv-pack.json';
  static final remote = Uri.parse('https://raw.githubusercontent.com/Foehammer1987/Liquiflux/main/app/$asset');
  static const maxBytes = 8 << 20;
  static const refreshEvery = Duration(days: 1);

  final http.Client _client;
  final Future<Directory> Function() _folder;
  final Future<String> Function() _bundled;

  CollectionPack? _pack;
  Future<CollectionPack>? _loading;
  DateTime? _checkedAt;

  /// The pack in hand, without waiting.
  CollectionPack? get now => _pack;

  Future<File> _file() async => File('${(await _folder()).path}${Platform.pathSeparator}tv-pack.json');

  /// The newest pack we have (downloaded or bundled); starts a background refresh when due.
  Future<CollectionPack> load() {
    final had = _pack;
    if (had != null) {
      _maybeRefresh();
      return Future.value(had);
    }
    return _loading ??= () async {
      CollectionPack? best;
      try {
        best = CollectionPack.parse(await _bundled());
      } catch (e) {
        debugPrint('tv pack (bundled): ${e.runtimeType}');
      }
      try {
        final f = await _file();
        if (await f.exists()) {
          final saved = CollectionPack.parse(await f.readAsString());
          if (best == null || saved.built.isAfter(best.built)) best = saved;
          _checkedAt = await f.lastModified();
        }
      } catch (e) {
        debugPrint('tv pack (saved): ${e.runtimeType}');
      }
      _pack = best ?? CollectionPack(built: DateTime.utc(2000), collections: const []);
      _loading = null;
      _maybeRefresh();
      return _pack!;
    }();
  }

  void _maybeRefresh() {
    final at = _checkedAt;
    if (at != null && DateTime.now().difference(at) < refreshEvery) return;
    _checkedAt = DateTime.now();
    unawaited(refresh());
  }

  /// Fetches the repository's pack; keeps it when it reads and is newer than ours.
  Future<bool> refresh() async {
    try {
      final r = await _client.get(remote).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200 || r.bodyBytes.length > maxBytes) return false;
      final text = r.body;
      final pack = CollectionPack.parse(text);
      final had = _pack;
      final f = await _file();
      if (had != null && !pack.built.isAfter(had.built)) {
        if (await f.exists()) await f.setLastModified(DateTime.now());
        return false;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(text, flush: true);
      _pack = pack;
      return true;
    } catch (e) {
      debugPrint('tv pack (refresh): ${e.runtimeType}');
      return false;
    }
  }
}
