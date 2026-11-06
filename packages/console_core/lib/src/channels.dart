import 'dart:math';

import 'plex/plex_client.dart';
import 'plex/plex_models.dart';

/// Where a channel's episodes, or its bumpers, come from in Plex.
class ChannelSource {
  const ChannelSource({required this.kind, required this.key, required this.title, this.section});

  /// collection, label, show or section (a whole library).
  final String kind;

  /// The collection's or show's ratingKey, the label's id, or the section's key.
  final String key;
  final String title;

  /// The library a label belongs to (labels are listed per library).
  final String? section;

  static const kinds = ['collection', 'label', 'show', 'section'];

  Map<String, dynamic> toJson() => {'kind': kind, 'key': key, 'title': title, if (section != null) 'section': section};

  /// Null for anything that isn't one of ours.
  static ChannelSource? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = j['kind'], key = j['key'], title = j['title'], section = j['section'];
    if (kind is! String || !kinds.contains(kind) || key is! String || key.isEmpty || key.length > 200) return null;
    return ChannelSource(kind: kind, key: key, title: title is String ? _clip(title, 200) : '', section: section is String && section.length <= 200 ? section : null);
  }

  @override
  bool operator ==(Object other) => other is ChannelSource && other.kind == kind && other.key == key && other.section == section;

  @override
  int get hashCode => Object.hash(kind, key, section);
}

String _clip(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// A saved shuffle rule: a "channel" that plays random episodes from [source], with
/// optional bumpers from [bumpers] between them.
class ChannelRule {
  const ChannelRule({
    required this.id,
    required this.name,
    required this.source,
    this.bumpers,
    this.bumperEvery = 1,
    this.bumperFirst = true,
    this.evenShows = true,
    this.weights = const {},
  });

  final String id;
  final String name;
  final ChannelSource source;

  /// Short clips played between episodes (null = none).
  final ChannelSource? bumpers;

  /// A bumper after every this many episodes.
  final int bumperEvery;

  /// A bumper before the first episode too.
  final bool bumperFirst;

  /// Every show gets an equal turn (pick a show, then an episode). Off is a classic shuffle,
  /// where a show with 800 episodes comes up 16 times as often as one with 50.
  final bool evenShows;

  /// Per show (ratingKey): how much more or less often than the others it comes up. 1 is
  /// normal, 0 leaves it out. Missing shows count as 1.
  final Map<String, double> weights;

  static const maxWeight = 12.0;

  /// The steps the weight control moves through.
  static const weightSteps = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0];

  double weightOf(String show) => weights[show] ?? 1;

  ChannelRule copyWith({String? name, ChannelSource? source, ChannelSource? Function()? bumpers, int? bumperEvery, bool? bumperFirst, bool? evenShows, Map<String, double>? weights}) => ChannelRule(
    id: id,
    name: name ?? this.name,
    source: source ?? this.source,
    bumpers: bumpers != null ? bumpers() : this.bumpers,
    bumperEvery: bumperEvery ?? this.bumperEvery,
    bumperFirst: bumperFirst ?? this.bumperFirst,
    evenShows: evenShows ?? this.evenShows,
    weights: weights ?? this.weights,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source.toJson(),
    if (bumpers != null) 'bumpers': bumpers!.toJson(),
    'bumperEvery': bumperEvery,
    'bumperFirst': bumperFirst,
    'evenShows': evenShows,
    'weights': {for (final e in weights.entries) if (e.value != 1) e.key: e.value},
  };

  /// Null for a rule that doesn't read; values out of range are brought back into it.
  static ChannelRule? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'];
    final source = ChannelSource.fromJson(j['source']);
    if (id is! String || id.isEmpty || id.length > 64 || source == null) return null;
    final every = j['bumperEvery'];
    final w = j['weights'];
    return ChannelRule(
      id: id,
      name: name is String && name.trim().isNotEmpty ? _clip(name.trim(), 80) : source.title,
      source: source,
      bumpers: ChannelSource.fromJson(j['bumpers']),
      bumperEvery: every is int ? every.clamp(1, 10) : 1,
      bumperFirst: j['bumperFirst'] != false,
      evenShows: j['evenShows'] != false,
      weights: {
        if (w is Map)
          for (final e in w.entries.take(5000))
            if (e.key is String && e.value is num && (e.value as num).isFinite) e.key as String: (e.value as num).toDouble().clamp(0, maxWeight),
      },
    );
  }
}

/// What a channel has played so far, so it doesn't repeat itself and can pick up again.
class ChannelProgress {
  ChannelProgress({Map<String, Set<String>>? played, Set<String>? bumpersPlayed, this.current, this.lastShow})
    : played = played ?? {},
      bumpersPlayed = bumpersPlayed ?? {};

  /// Per show: the episodes played since that show last ran out.
  final Map<String, Set<String>> played;

  /// Bumpers played since the bumpers last ran out.
  final Set<String> bumpersPlayed;

  /// The episode playing when the channel was left, to carry on with.
  String? current;

  /// The show that played last, so the next pick can be a different one.
  String? lastShow;

  ChannelProgress copy() => ChannelProgress(
    played: {for (final e in played.entries) e.key: {...e.value}},
    bumpersPlayed: {...bumpersPlayed},
    current: current,
    lastShow: lastShow,
  );

  Map<String, dynamic> toJson() => {
    'played': {for (final e in played.entries) if (e.value.isNotEmpty) e.key: e.value.toList()},
    'bumpers': bumpersPlayed.toList(),
    if (current != null) 'current': current,
    if (lastShow != null) 'lastShow': lastShow,
  };

  static ChannelProgress fromJson(Object? j) {
    if (j is! Map) return ChannelProgress();
    List<String> keys(Object? v) => v is List ? [for (final k in v.take(50000)) if (k is String && k.length <= 64) k] : const [];
    final p = j['played'];
    final cur = j['current'], last = j['lastShow'];
    return ChannelProgress(
      played: {
        if (p is Map)
          for (final e in p.entries.take(5000))
            if (e.key is String) e.key as String: keys(e.value).toSet(),
      },
      bumpersPlayed: keys(j['bumpers']).toSet(),
      current: cur is String && cur.length <= 64 ? cur : null,
      lastShow: last is String && last.length <= 64 ? last : null,
    );
  }
}

/// Everything a channel can play: its shows' episodes, and its bumpers.
class ChannelPool {
  ChannelPool({required this.shows, required this.titles, this.bumpers = const []});

  /// Show ratingKey (or a movie's own) to its episodes, in order.
  final Map<String, List<PlexItem>> shows;

  /// Show ratingKey to the show's name.
  final Map<String, String> titles;
  final List<PlexItem> bumpers;

  int get episodeCount => shows.values.fold(0, (a, l) => a + l.length);

  /// The show an episode belongs to.
  String? showOf(String episode) {
    for (final e in shows.entries) {
      if (e.value.any((i) => i.ratingKey == episode)) return e.key;
    }
    return null;
  }
}

/// How often each show comes up under [rule], as a share of all picks (0 to 1).
Map<String, double> channelShares(ChannelRule rule, ChannelPool pool) {
  final raw = {
    for (final e in pool.shows.entries)
      if (e.value.isNotEmpty) e.key: (rule.evenShows ? 1.0 : e.value.length.toDouble()) * rule.weightOf(e.key),
  };
  final total = raw.values.fold(0.0, (a, b) => a + b);
  return {for (final e in raw.entries) e.key: total > 0 ? e.value / total : 0};
}

/// One item in a channel's line-up.
class ChannelSlot {
  const ChannelSlot(this.item, {this.bumper = false});
  final PlexItem item;
  final bool bumper;
}

/// Picks a channel's line-up: a show by its share, then an episode of it that hasn't played
/// since the show last ran out, with bumpers between them. Works on its own copy of the
/// progress, so a line-up made but never watched doesn't count as played.
class ChannelPicker {
  ChannelPicker(this.rule, this.pool, ChannelProgress progress, {Random? random}) : _p = progress.copy(), _rng = random ?? Random();
  final ChannelRule rule;
  final ChannelPool pool;
  final ChannelProgress _p;
  final Random _rng;
  int _sinceBumper = 0;
  bool _started = false;
  String? _lastBumper;

  bool get hasBumpers => rule.bumpers != null && pool.bumpers.isNotEmpty;

  /// The next episode, or null when nothing can play (no shows, or every weight is 0).
  PlexItem? nextEpisode() {
    final shares = channelShares(rule, pool)..removeWhere((_, s) => s <= 0);
    if (shares.isEmpty) return null;
    // A different show from the last one, while there's another to pick.
    if (shares.length > 1) shares.remove(_p.lastShow);
    var r = _rng.nextDouble() * shares.values.fold(0.0, (a, b) => a + b);
    var show = shares.keys.last;
    for (final e in shares.entries) {
      r -= e.value;
      if (r <= 0) {
        show = e.key;
        break;
      }
    }
    final eps = pool.shows[show]!;
    var played = _p.played.putIfAbsent(show, () => {});
    var left = eps.where((e) => !played.contains(e.ratingKey)).toList();
    if (left.isEmpty) {
      // The show has run out: start it over.
      played.clear();
      left = eps;
    }
    final pick = left[_rng.nextInt(left.length)];
    played.add(pick.ratingKey);
    _p.lastShow = show;
    return pick;
  }

  /// A random bumper that hasn't played since the bumpers last ran out.
  PlexItem? nextBumper() {
    if (!hasBumpers) return null;
    var left = pool.bumpers.where((b) => !_p.bumpersPlayed.contains(b.ratingKey)).toList();
    if (left.isEmpty) {
      _p.bumpersPlayed.clear();
      // Not the same clip twice running when the bumpers start over.
      left = pool.bumpers.length > 1 ? pool.bumpers.where((b) => b.ratingKey != _lastBumper).toList() : pool.bumpers;
    }
    final pick = left[_rng.nextInt(left.length)];
    _p.bumpersPlayed.add(pick.ratingKey);
    _lastBumper = pick.ratingKey;
    return pick;
  }

  /// The next [episodes] episodes, with bumpers where the rule puts them. The first call
  /// starts with [first] (an episode to carry on with), if given.
  List<ChannelSlot> next(int episodes, {PlexItem? first}) {
    final out = <ChannelSlot>[];
    if (!_started) {
      _started = true;
      if (rule.bumperFirst && first == null) {
        final b = nextBumper();
        if (b != null) out.add(ChannelSlot(b, bumper: true));
      }
      if (first != null) {
        final show = pool.showOf(first.ratingKey);
        if (show != null) {
          _p.played.putIfAbsent(show, () => {}).add(first.ratingKey);
          _p.lastShow = show;
        }
        out.add(ChannelSlot(first));
        _sinceBumper = 1;
        episodes--;
      }
    }
    for (var n = 0; n < episodes; n++) {
      if (_sinceBumper >= rule.bumperEvery) {
        final b = nextBumper();
        if (b != null) out.add(ChannelSlot(b, bumper: true));
        _sinceBumper = 0;
      }
      final e = nextEpisode();
      if (e == null) break;
      out.add(ChannelSlot(e));
      _sinceBumper++;
    }
    return out;
  }
}

/// Records that [slot] started playing in [progress].
void channelStarted(ChannelProgress progress, ChannelPool pool, ChannelSlot slot) {
  final key = slot.item.ratingKey;
  if (slot.bumper) {
    if (pool.bumpers.isNotEmpty && pool.bumpers.every((b) => progress.bumpersPlayed.contains(b.ratingKey) || b.ratingKey == key)) {
      progress.bumpersPlayed.clear();
    }
    progress.bumpersPlayed.add(key);
    return;
  }
  final show = pool.showOf(key);
  if (show == null) return;
  final played = progress.played.putIfAbsent(show, () => {});
  final eps = pool.shows[show]!;
  if (eps.every((e) => played.contains(e.ratingKey) || e.ratingKey == key)) played.clear();
  played.add(key);
  progress.lastShow = show;
  progress.current = key;
}

/// Reads what [source] holds from Plex, as shows and their episodes. A movie or a lone clip
/// counts as a show of its own.
/// Specials (season 0) are left out unless [specials].
Future<Map<String, List<PlexItem>>> loadChannelSource(PlexClient plex, ChannelSource source, {Map<String, String>? titles, bool specials = false}) async {
  final top = switch (source.kind) {
    'collection' => await plex.collectionItems(source.key),
    'label' => await plex.labelled(source.section ?? '', source.key),
    'section' => (await plex.sectionItems(source.key, size: 20000, timeout: const Duration(minutes: 2))).items,
    _ => [?await plex.metadata(source.key)],
  };
  final out = <String, List<PlexItem>>{};
  void add(String show, String title, List<PlexItem> eps) {
    final list = out.putIfAbsent(show, () => []);
    final have = {for (final e in list) e.ratingKey};
    list.addAll(eps.where((e) => have.add(e.ratingKey)));
    titles?[show] ??= title;
  }

  final shows = <PlexItem>[];
  for (final i in top) {
    switch (i.type) {
      case 'show' || 'season':
        shows.add(i);
      case 'episode':
        add(i.grandparentRatingKey ?? i.ratingKey, i.grandparentTitle ?? i.title, [i]);
      case 'movie' || 'clip' || 'video':
        add(i.ratingKey, i.title, [i]);
    }
  }
  // A few shows at a time, so a big collection doesn't swamp the server.
  for (var k = 0; k < shows.length; k += 6) {
    final batch = shows.skip(k).take(6).toList();
    final eps = await Future.wait([for (final s in batch) s.type == 'season' ? plex.children(s.ratingKey) : plex.episodes(s.ratingKey)]);
    for (final (n, s) in batch.indexed) {
      final key = s.type == 'season' ? (s.parentRatingKey ?? s.ratingKey) : s.ratingKey;
      final title = s.type == 'season' ? (s.parentTitle ?? s.title) : s.title;
      // Specials stay out of a channel, like they do on TV.
      add(key, title, [for (final e in eps[n]) if (e.type == 'episode' || e.type == 'movie' || e.type == 'clip') if (specials || (e.parentIndex ?? 1) > 0) e]);
    }
  }
  out.removeWhere((_, v) => v.isEmpty);
  return out;
}

/// Everything [rule] can play.
Future<ChannelPool> loadChannelPool(PlexClient plex, ChannelRule rule) async {
  final titles = <String, String>{};
  final shows = loadChannelSource(plex, rule.source, titles: titles);
  // Bumpers keep their specials: a "show" of clips often files them as season 0.
  final bumpers = rule.bumpers == null ? Future.value(<String, List<PlexItem>>{}) : loadChannelSource(plex, rule.bumpers!, specials: true);
  final b = await bumpers;
  final s = await shows;
  return ChannelPool(shows: s, titles: titles, bumpers: [for (final l in b.values) ...l]);
}
