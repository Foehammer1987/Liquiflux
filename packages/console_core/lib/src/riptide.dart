import 'plex/plex_models.dart';
import 'security.dart';

/// Who's on screen when, for one title: what the Riptide scanner (tools/riptide) found by matching
/// faces in sampled frames against the cast's photos. Read from `<server>/<ratingKey>.json`.
class RiptideTimeline {
  RiptideTimeline({required this.people, required this.spans, this.chapters = const [], this.scenes = const [], this.quality});

  /// The file's people and the spans they're seen in. Bad entries are dropped, not fatal: a
  /// half-written or older file still gives what it can.
  factory RiptideTimeline.fromJson(Map<String, dynamic> j) {
    final people = <RiptidePerson>[
      for (final p in (j['people'] is List ? j['people'] as List : const []))
        if (p is Map<String, dynamic>)
          RiptidePerson(
            name: '${p['tag'] ?? ''}',
            plexTagId: p['id'] is int ? p['id'] as int : null,
            role: p['role'] is String ? p['role'] as String : null,
            alike: [for (final a in (p['alike'] is List ? p['alike'] as List : const [])) if (a is int) a],
          ),
    ];
    final spans = <RiptideSpan>[];
    for (final s in (j['spans'] is List ? j['spans'] as List : const [])) {
      if (s is! List || s.length < 4) continue;
      final [a, b, who, conf, ...] = s;
      if (a is! num || b is! num || who is! int || conf is! num) continue;
      if (who < 0 || who >= people.length || b < a) continue;
      spans.add(RiptideSpan(startMs: (a * 1000).round(), endMs: (b * 1000).round(), person: who, confidence: conf.toDouble().clamp(0, 1)));
    }
    spans.sort((x, y) => x.startMs.compareTo(y.startMs));
    final chapters = <RiptideChapter>[
      for (final c in (j['chapters'] is List ? j['chapters'] as List : const []))
        if (c is Map<String, dynamic> && c['start'] is num && c['end'] is num)
          RiptideChapter(startMs: ((c['start'] as num) * 1000).round(), endMs: ((c['end'] as num) * 1000).round(), confidence: c['confidence'] is num ? (c['confidence'] as num).toDouble() : null),
    ];
    // Scenes, for a scanner and server that send them ([start, end] in seconds); none do yet,
    // and without them a scene is found from the spans around the pause (see [scene]).
    final scenes = <(int, int)>[
      for (final s in (j['scenes'] is List ? j['scenes'] as List : const []))
        if (s is List && s.length >= 2 && s[0] is num && s[1] is num && (s[1] as num) > (s[0] as num)) (((s[0] as num) * 1000).round(), ((s[1] as num) * 1000).round()),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    return RiptideTimeline(people: people, spans: spans, chapters: chapters, scenes: scenes, quality: j['quality'] is num ? (j['quality'] as num).toDouble() : null);
  }

  /// Scene boundaries from the scanner, start and end in ms, in order (empty when it sent none).
  final List<(int, int)> scenes;

  final List<RiptidePerson> people;
  final List<RiptideSpan> spans;

  /// How sure the scanner was of each chapter overall, after its rescan.
  final List<RiptideChapter> chapters;

  /// How sure the scanner was of the title as a whole, 0-1 (null in files without it).
  final double? quality;

  /// Below this the whole file is ignored and the cast list shows.
  static const minQuality = 0.45;

  /// Whether to use this file for a title whose cast in Plex is [castIds]: the scan went well
  /// enough, and it was made against the same cast (a re-matched title's file is stale).
  bool usableFor(Iterable<int> castIds) {
    if (spans.isEmpty || (quality != null && quality! < minQuality)) return false;
    final ids = {for (final p in people) if (p.plexTagId != null) p.plexTagId!};
    final now = castIds.toSet();
    if (ids.isEmpty || now.isEmpty) return true;
    return ids.intersection(now).length * 2 >= ids.length;
  }

  /// A chapter averaging below this isn't trusted at all: its scenes fall back to the cast list.
  static const minChapterConfidence = 0.5;

  /// Below this the scanner wasn't sure enough to name someone.
  static const minConfidence = 0.45;

  /// The people on screen at [at], most certain first. [slack] widens each span a little,
  /// since frames are sampled every few seconds and a pause lands between them.
  ///
  /// Empty whenever the scanner can't be trusted there (an unsure chapter, or nobody named
  /// surely enough), so the caller falls back to top billing rather than naming the wrong
  /// people. Lookalikes (twins, say) come as a set: when one is seen, so is the other, since
  /// the scanner can't reliably tell them apart.
  List<RiptidePerson> at(Duration at, {Duration slack = const Duration(seconds: 3)}) {
    final t = at.inMilliseconds, pad = slack.inMilliseconds;
    final chapter = chapters.where((c) => c.startMs <= t && t < c.endMs).firstOrNull;
    if (chapter != null && (chapter.confidence ?? 0) < minChapterConfidence) return const [];
    final best = <int, double>{};
    for (final s in spans) {
      if (s.startMs - pad > t) break;
      if (s.endMs + pad < t || s.confidence < minConfidence) continue;
      if ((best[s.person] ?? -1) < s.confidence) best[s.person] = s.confidence;
    }
    final order = best.keys.toList()..sort((a, b) => best[b]!.compareTo(best[a]!));
    final seen = <int>{};
    return [
      for (final i in order)
        for (final k in [i, ...people[i].alike])
          if (k >= 0 && k < people.length && seen.add(k)) people[k],
    ];
  }

  /// How far either side of a pause the scene reaches when the scanner sent no scenes. So an
  /// actor's appearances up to twice this apart (the shot/reverse shot of a conversation) keep
  /// them in the scene between their shots. Measured on 1,007 rescanned films and 992 older
  /// scans at random pauses: someone is named at 90% of pauses (80% naming only who's on screen
  /// that moment), 70% on older scans (44%), and 99% of names are of people seen within 20 s.
  static const sceneReach = Duration(seconds: 15);

  /// Within this of one of their spans, someone counts as on screen now (frames are a few
  /// seconds apart, so a pause lands between them).
  static const onScreenSlack = Duration(seconds: 3);

  /// Who's in the scene at [at]: those on screen now first (most certain first), then the rest
  /// of the scene, nearest in time first. The scene is the scanner's when it sent [scenes];
  /// otherwise [sceneReach] either side of the pause, never past one of [breaks] (chapter
  /// marks: a new chapter is a new scene).
  ///
  /// Empty wherever the scanner can't be trusted (an unsure chapter, or nobody named surely
  /// enough), so the caller falls back to top billing. Lookalikes come as a set, as in [at].
  List<RiptideSeen> scene(Duration at, {Iterable<Duration> breaks = const []}) {
    final t = at.inMilliseconds;
    final chapter = chapters.where((c) => c.startMs <= t && t < c.endMs).firstOrNull;
    if (chapter != null && (chapter.confidence ?? 0) < minChapterConfidence) return const [];
    int lo, hi;
    final given = scenes.where((s) => s.$1 <= t && t < s.$2).firstOrNull;
    if (given != null) {
      (lo, hi) = given;
    } else {
      lo = t - sceneReach.inMilliseconds;
      hi = t + sceneReach.inMilliseconds;
      for (final b in breaks) {
        final ms = b.inMilliseconds;
        if (ms <= t && ms > lo) lo = ms;
        if (ms > t && ms < hi) hi = ms;
      }
    }
    final slack = onScreenSlack.inMilliseconds;
    final found = <int, RiptideSeen>{};
    for (final s in spans) {
      if (s.startMs > hi) break;
      if (s.endMs < lo || s.confidence < minConfidence) continue;
      final now = s.startMs - slack <= t && t <= s.endMs + slack;
      final away = now ? 0 : (t < s.startMs ? s.startMs - t : t - s.endMs);
      final seen = RiptideSeen(person: people[s.person], onScreen: now, confidence: s.confidence, away: Duration(milliseconds: away));
      final had = found[s.person];
      if (had == null || seen.comesBefore(had)) found[s.person] = seen;
    }
    final order = found.keys.toList()..sort((a, b) => found[a]!.comesBefore(found[b]!) ? -1 : (found[b]!.comesBefore(found[a]!) ? 1 : 0));
    final out = <int>{};
    return [
      for (final i in order)
        for (final k in [i, ...people[i].alike])
          if (k >= 0 && k < people.length && out.add(k)) k == i ? found[i]! : (found[k] ?? found[i]!.as(people[k])),
    ];
  }
}

/// Someone in the scene at a pause (see [RiptideTimeline.scene]).
class RiptideSeen {
  const RiptideSeen({required this.person, required this.onScreen, required this.confidence, this.away = Duration.zero});
  final RiptidePerson person;

  /// Seen at the pause itself, not just elsewhere in the scene.
  final bool onScreen;

  /// The scanner's surest look at them in this stretch, 0-1.
  final double confidence;

  /// How long before or after the pause they're seen (zero when [onScreen]).
  final Duration away;

  /// On screen first, then nearest in time, then most certain.
  bool comesBefore(RiptideSeen o) => onScreen != o.onScreen ? onScreen : (away != o.away ? away < o.away : confidence > o.confidence);

  RiptideSeen as(RiptidePerson p) => RiptideSeen(person: p, onScreen: onScreen, confidence: confidence, away: away);
}


class RiptidePerson {
  const RiptidePerson({required this.name, this.plexTagId, this.role, this.alike = const []});
  final String name;
  final int? plexTagId;

  /// The character, or several joined with " / " for an actor who plays more than one.
  final String? role;

  /// Other people (indexes into [RiptideTimeline.people]) the scanner finds too alike to tell
  /// apart from this one: twins, siblings, an actor and their double.
  final List<int> alike;
}

class RiptideChapter {
  const RiptideChapter({required this.startMs, required this.endMs, this.confidence});
  final int startMs;
  final int endMs;

  /// Null when the chapter had no faces clear enough to judge.
  final double? confidence;
}

class RiptideSpan {
  const RiptideSpan({required this.startMs, required this.endMs, required this.person, required this.confidence});
  final int startMs;
  final int endMs;

  /// Index into [RiptideTimeline.people].
  final int person;

  /// 0-1: how sure the scanner was, from face match, size, sharpness and how often it agreed.
  final double confidence;
}

/// Animated titles are never scanned (faces in animation don't match actors' photos), so
/// they only get the cast list.
bool isAnimated(PlexItem item) => item.genres.any((g) => const {'animation', 'anime'}.contains(g.toLowerCase()));

/// Where a title's timeline lives on the Riptide server, or null when there's no usable server.
Uri? riptideUri(String server, String ratingKey) {
  final base = server.trim();
  if (base.isEmpty || !isWebUrl(base) || !RegExp(r'^\d+$').hasMatch(ratingKey)) return null;
  return Uri.parse(base.endsWith('/') ? '$base$ratingKey.json' : '$base/$ratingKey.json');
}
