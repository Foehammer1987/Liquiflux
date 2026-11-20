import 'plex/plex_models.dart';
import 'security.dart';

/// Who's on screen when, for one title: what the Riptide scanner (tools/riptide) found by matching
/// faces in sampled frames against the cast's photos. Read from `<server>/<ratingKey>.json`.
class RiptideTimeline {
  RiptideTimeline({required this.people, required this.spans, this.chapters = const [], this.quality});

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
    return RiptideTimeline(people: people, spans: spans, chapters: chapters, quality: j['quality'] is num ? (j['quality'] as num).toDouble() : null);
  }

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
