import 'seerr/seerr_models.dart';

/// Thumbs up and down on recommendations, kept on this device. Keys are "movie:603".
class Taste {
  const Taste({this.likes = const {}, this.dislikes = const {}});
  factory Taste.fromJson(Map<String, dynamic>? j) => Taste(likes: _ratings(j?['likes']), dislikes: _ratings(j?['dislikes']));

  /// Only well-formed "movie:603" keys with a title are kept from what's on disk.
  static Map<String, String> _ratings(Object? v) => {
    if (v is Map)
      for (final e in v.entries)
        if (e.key is String && _key.hasMatch(e.key as String) && e.value is String) e.key as String: e.value as String,
  };
  static final _key = RegExp(r'^(movie|tv):\d{1,10}$');

  /// key → title, newest last.
  final Map<String, String> likes;
  final Map<String, String> dislikes;

  static String keyOf(String mediaType, int tmdbId) => '$mediaType:$tmdbId';

  bool liked(String key) => likes.containsKey(key);
  bool disliked(String key) => dislikes.containsKey(key);

  /// Thumbs up (or down when [up] is false); the same thumb again takes it back.
  Taste rate(String key, String title, {required bool up}) {
    final l = {...likes}..remove(key);
    final d = {...dislikes}..remove(key);
    final was = up ? likes.containsKey(key) : dislikes.containsKey(key);
    if (!was) (up ? l : d)[key] = title;
    return Taste(likes: l, dislikes: d);
  }

  Map<String, dynamic> toJson() => {'likes': likes, 'dislikes': dislikes};
}

/// A title recommendations start from: one you watched lately or gave a thumbs up.
typedef TasteSeed = ({String mediaType, int tmdbId, String title, bool liked});

/// One "Because you watched…" row.
class BecauseRow {
  BecauseRow({required this.seed, required this.items});
  final TasteSeed seed;
  final List<SeerrResult> items;
  String get heading => seed.liked ? 'Because You Liked ${seed.title}' : 'Because You Watched ${seed.title}';
}

/// The order seeds are tried in: thumbs-up titles (newest first), then what you watched
/// lately, without repeats or titles you gave a thumbs down.
List<TasteSeed> tasteSeeds(List<TasteSeed> watched, Taste taste, {int count = 4}) {
  final seen = <String>{};
  final out = <TasteSeed>[];
  final liked = taste.likes.entries.toList().reversed;
  for (final e in liked) {
    final parts = e.key.split(':');
    final id = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (id != null && seen.add(e.key)) out.add((mediaType: parts[0], tmdbId: id, title: e.value, liked: true));
  }
  for (final w in watched) {
    final k = Taste.keyOf(w.mediaType, w.tmdbId);
    if (!taste.disliked(k) && seen.add(k)) out.add(w);
  }
  return out.take(count).toList();
}

/// Builds the rows from each seed's recommendations ([recs], same order as [seeds]).
/// Thumbs-down titles, the seeds themselves and anything [skip] says (e.g. watched) drop
/// out; a title recommended by several seeds rises; each title shows in one row only.
List<BecauseRow> becauseYouWatched(List<TasteSeed> seeds, List<List<SeerrResult>> recs, Taste taste, {bool Function(SeerrResult)? skip, int rows = 3, int perRow = 20}) {
  final seedKeys = {for (final s in seeds) Taste.keyOf(s.mediaType, s.tmdbId)};
  final votes = <String, int>{};
  for (final list in recs) {
    for (final r in list) {
      votes.update(Taste.keyOf(r.mediaType, r.id), (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final shown = <String>{};
  final out = <BecauseRow>[];
  for (var i = 0; i < seeds.length && i < recs.length && out.length < rows; i++) {
    final keep = <(SeerrResult, double)>[];
    for (final (pos, r) in recs[i].indexed) {
      final k = Taste.keyOf(r.mediaType, r.id);
      if (taste.disliked(k) || seedKeys.contains(k) || shown.contains(k) || (skip?.call(r) ?? false)) continue;
      // TMDB's order, nudged up by other seeds agreeing and by a thumbs up.
      keep.add((r, pos - 5.0 * ((votes[k] ?? 1) - 1) - (taste.liked(k) ? 6 : 0)));
    }
    keep.sort((a, b) => a.$2.compareTo(b.$2));
    final items = [for (final (r, _) in keep.take(perRow)) r];
    if (items.length < 4) continue;
    shown.addAll(items.map((r) => Taste.keyOf(r.mediaType, r.id)));
    out.add(BecauseRow(seed: seeds[i], items: items));
  }
  return out;
}
