import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'doc_store.dart';
import 'safe_file.dart';

/// The shuffle channels saved on this device, per Plex server, and what each has played.
class ChannelStore extends ChangeNotifier {
  ChannelStore({Future<File> Function()? file, this.disk = true, DocStore? docs}) : _fileFor = file, _docs = docs;
  final Future<File> Function()? _fileFor;

  /// Where channels.json lives when it isn't a file of its own: user defaults on an Apple TV
  /// ([DefaultsDocStore]). Null keeps it in the support folder.
  final DocStore? _docs;
  static const _name = 'channels.json';

  /// Off keeps the channels in memory only (tests).
  final bool disk;

  /// Every server's channels, as read from disk: {machineId: {rules, progress}}.
  Map<String, dynamic> _all = {};
  String _server = '';
  List<ChannelRule> rules = const [];
  final _progress = <String, ChannelProgress>{};
  bool _loaded = false;
  final _saves = SaveQueue();

  /// The most that's read from disk: a bigger file isn't one we wrote.
  static const maxBytes = 8 * 1024 * 1024;
  static const maxRules = 100;

  Future<File> _file() async {
    final f = _fileFor;
    if (f != null) return f();
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_name');
  }

  Future<void> _write(String text) async {
    if (_docs case final docs?) return docs.write(_name, text);
    await writeAtomically(await _file(), text);
  }

  /// Reads the channels saved for [server] (its machine id).
  Future<void> load(String server) async {
    if (_loaded && server == _server) return;
    await (_reading ??= _readFile());
    if (_loaded && server == _server) return;
    _loaded = true;
    _server = server;
    read(_all[server]);
    notifyListeners();
  }

  Future<void>? _reading;

  Future<void> _readFile() async {
    if (!disk) return;
    try {
      final String? text;
      if (_docs case final docs?) {
        text = await docs.read(_name);
      } else {
        final f = await _file();
        text = await f.exists() && await f.length() <= maxBytes ? await f.readAsString() : null;
      }
      if (text != null && text.length <= maxBytes) {
        final j = jsonDecode(text);
        if (j is Map<String, dynamic> && j['servers'] is Map<String, dynamic>) _all = j['servers'] as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('channels: $e');
    }
  }

  /// Fills the store from one server's entry; anything that doesn't read is skipped.
  @visibleForTesting
  void read(Object? j) {
    rules = const [];
    _progress.clear();
    if (j is! Map) return;
    final r = j['rules'];
    final p = j['progress'];
    final seen = <String>{};
    rules = [
      if (r is List)
        for (final x in r.take(maxRules))
          if (ChannelRule.fromJson(x) case final rule? when seen.add(rule.id)) rule,
    ];
    if (p is Map) {
      for (final rule in rules) {
        if (p[rule.id] != null) _progress[rule.id] = ChannelProgress.fromJson(p[rule.id]);
      }
    }
  }

  ChannelProgress progressOf(String id) => _progress.putIfAbsent(id, ChannelProgress.new);

  /// A channel can carry on where it was left.
  bool canResume(String id) => _progress[id]?.current != null;

  void put(ChannelRule rule) {
    final at = rules.indexWhere((r) => r.id == rule.id);
    rules = [...rules];
    if (at >= 0) {
      // A new source starts the channel afresh.
      if (!listEquals(rules[at].sources, rule.sources)) _progress.remove(rule.id);
      if (rules[at].bumpers != rule.bumpers) _progress[rule.id]?.bumpersPlayed.clear();
      rules[at] = rule;
    } else if (rules.length < maxRules) {
      rules.add(rule);
    }
    notifyListeners();
    unawaited(save());
  }

  void remove(String id) {
    rules = [for (final r in rules) if (r.id != id) r];
    _progress.remove(id);
    notifyListeners();
    unawaited(save());
  }

  /// Starts a channel over: everything may play again.
  void reset(String id) {
    _progress.remove(id);
    notifyListeners();
    unawaited(save());
  }

  static String newId() {
    final r = Random.secure();
    return [for (var i = 0; i < 8; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  Future<void> save() => _saves.run(() async {
    _all[_server] = {
      'rules': [for (final r in rules) r.toJson()],
      'progress': {for (final r in rules) if (_progress[r.id] case final p?) r.id: p.toJson()},
    };
    if (!disk) return;
    try {
      await _write(jsonEncode({'servers': _all}));
    } catch (e) {
      debugPrint('channels save: $e');
    }
  });
}

/// One sitting of a channel: its line-up so far, which grows as it plays.
class ChannelRun {
  ChannelRun(this.rule, this.pool, this.progress, {Random? random, this.onChange, PlexItem? first}) : _picker = ChannelPicker(rule, pool, progress, random: random) {
    _add(_picker.next(ahead, first: first));
  }

  final ChannelRule rule;
  final ChannelPool pool;

  /// The channel's saved progress, updated as titles start.
  final ChannelProgress progress;
  final ChannelPicker _picker;

  /// Told when something started, so the progress can be saved.
  final VoidCallback? onChange;

  /// How many episodes the line-up stays ahead of what's playing.
  static const ahead = 8;

  /// The line-up: episodes and bumpers in play order. The player reads next and previous
  /// from it, so it only ever grows.
  final List<PlexItem> queue = [];
  final List<bool> _bumper = [];

  bool get isEmpty => queue.isEmpty;

  bool isBumperAt(int? at) => at != null && at >= 0 && at < _bumper.length && _bumper[at];

  void _add(List<ChannelSlot> slots) {
    for (final s in slots) {
      queue.add(s.item);
      _bumper.add(s.bumper);
    }
  }

  /// The title at [at] started playing.
  void started(int at) {
    if (at < 0 || at >= queue.length) return;
    channelStarted(progress, pool, ChannelSlot(queue[at], bumper: _bumper[at]));
    final episodesLeft = [for (var i = at + 1; i < queue.length; i++) if (!_bumper[i]) i].length;
    if (episodesLeft < ahead ~/ 2) _add(_picker.next(ahead));
    onChange?.call();
  }

  /// Reads [rule]'s shows and bumpers from Plex and lines up the first titles; on [resume]
  /// the episode it was left on comes first. Null when the source has nothing to play.
  static Future<ChannelRun?> start(PlexClient plex, ChannelStore store, ChannelRule rule, {bool resume = true, PackShows? packShows}) async {
    final pool = await loadChannelPool(plex, rule, packShows: packShows);
    if (pool.shows.isEmpty) return null;
    final progress = store.progressOf(rule.id);
    final key = resume ? progress.current : null;
    PlexItem? first;
    if (key != null) {
      for (final eps in pool.shows.values) {
        first ??= eps.where((e) => e.ratingKey == key).firstOrNull;
      }
    }
    final run = ChannelRun(rule, pool, progress, first: first, onChange: () => unawaited(store.save()));
    return run.isEmpty ? null : run;
  }
}
