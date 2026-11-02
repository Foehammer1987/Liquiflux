import 'dart:async';

import '../http_json.dart';
import '../plex/plex_models.dart';

/// An anime on AniList, with what Liquiflux needs to place an episode in it.
class AniListMedia {
  const AniListMedia({
    required this.id,
    required this.format,
    this.episodes,
    this.start,
    this.end,
    this.titles = const [],
    this.sequels = const [],
    this.prequels = const [],
    this.progress,
    this.status,
  });

  final int id;

  /// TV, TV_SHORT, ONA, MOVIE, OVA, SPECIAL…
  final String format;
  final int? episodes;

  /// First and last air dates, when AniList has the whole date.
  final DateTime? start;
  final DateTime? end;

  /// English, romaji and native titles, then synonyms.
  final List<String> titles;

  /// Ids of the anime AniList lists as this one's sequels and prequels.
  final List<int> sequels;
  final List<int> prequels;

  /// The signed-in user's list entry: episodes watched and CURRENT, COMPLETED…
  final int? progress;
  final String? status;

  bool get isSeries => const {'TV', 'TV_SHORT', 'ONA'}.contains(format);
  int? get year => start?.year;

  static const fields = 'id format episodes startDate{year month day} endDate{year month day} title{english romaji native} synonyms '
      'relations{edges{relationType node{id type format}}} mediaListEntry{progress status}';

  static AniListMedia? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! int) return null;
    DateTime? date(Object? d) {
      if (d is! Map) return null;
      final y = d['year'], m = d['month'], day = d['day'];
      return y is int && m is int && day is int ? DateTime.utc(y, m, day) : null;
    }

    final t = j['title'] is Map ? j['title'] as Map : const {};
    // Series first, so a chain steps season to season rather than into a side story.
    final related = <(String, int, bool)>[];
    final edges = j['relations'] is Map ? (j['relations'] as Map)['edges'] : null;
    for (final e in edges is List ? edges : const []) {
      if (e is! Map || e['node'] is! Map) continue;
      final node = e['node'] as Map;
      if (node['type'] == 'ANIME' && node['id'] is int) related.add(('${e['relationType']}', node['id'] as int, const {'TV', 'TV_SHORT', 'ONA'}.contains(node['format'])));
    }
    related.sort((a, b) => (b.$3 ? 1 : 0) - (a.$3 ? 1 : 0));
    final entry = j['mediaListEntry'] is Map ? j['mediaListEntry'] as Map : null;
    return AniListMedia(
      id: id,
      format: '${j['format'] ?? ''}',
      episodes: j['episodes'] is int ? j['episodes'] as int : null,
      start: date(j['startDate']),
      end: date(j['endDate']),
      titles: [
        for (final k in const ['english', 'romaji', 'native'])
          if (t[k] case final String s when s.isNotEmpty) s,
        for (final s in j['synonyms'] is List ? j['synonyms'] as List : const [])
          if (s is String && s.isNotEmpty) s,
      ],
      sequels: [for (final (r, i, _) in related) if (r == 'SEQUEL') i],
      prequels: [for (final (r, i, _) in related) if (r == 'PREQUEL') i],
      progress: entry?['progress'] is int ? entry!['progress'] as int : null,
      status: entry?['status'] is String ? entry!['status'] as String : null,
    );
  }
}

/// Signed in to AniList with a token from its pin page (AniList has no code sign-in for
/// TVs, so the token is pasted on a phone; see the app's phone link).
class AniListAccount {
  AniListAccount({required this.token, String endpoint = 'https://graphql.anilist.co', JsonHttp? http}) : _endpoint = Uri.parse(endpoint), _http = http ?? JsonHttp();
  final String token;
  final Uri _endpoint;
  final JsonHttp _http;

  void close() => _http.close();

  /// Where a token is handed out: AniList's implicit grant, shown on its pin page when the
  /// app's redirect address is https://anilist.co/api/v2/oauth/pin.
  static String authorizeUrl(String clientId) => 'https://anilist.co/api/v2/oauth/authorize?client_id=${Uri.encodeQueryComponent(clientId)}&response_type=token';

  /// A token as pasted: the bare token, or the whole address it came back in.
  static String? cleanToken(String pasted) {
    var t = pasted.trim();
    final m = RegExp(r'access_token=([^&\s]+)').firstMatch(t);
    if (m != null) t = Uri.decodeQueryComponent(m[1]!);
    // A JWT: three base64url parts.
    return RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(t) && t.length < 4096 ? t : null;
  }

  static const _odd = 'AniList answered with something unexpected. Try again in a moment.';

  Future<Map<String, dynamic>> _query(String query, [Map<String, Object?> variables = const {}]) async {
    final body = await _http.send('POST', _endpoint, headers: {'authorization': 'Bearer $token'}, body: {'query': query, 'variables': variables});
    final j = JsonHttp.object(body, _odd);
    final errors = j['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final status = first is Map && first['status'] is int ? first['status'] as int : 0;
      throw ApiException(status, first is Map ? '${first['message'] ?? _odd}' : _odd);
    }
    return JsonHttp.object(j['data'], _odd);
  }

  /// The signed-in user's name.
  Future<String> viewer() async {
    final d = await _query('query{Viewer{id name}}');
    final v = d['Viewer'];
    return v is Map && v['name'] is String ? v['name'] as String : '';
  }

  /// Anime whose titles match [title]; [movie] narrows it to films, else to series.
  Future<List<AniListMedia>> search(String title, {bool movie = false}) async {
    final d = await _query(
      'query(\$q:String,\$f:[MediaFormat]){Page(perPage:10){media(search:\$q,type:ANIME,format_in:\$f,sort:SEARCH_MATCH){${AniListMedia.fields}}}}',
      {
        'q': title,
        'f': movie ? ['MOVIE'] : ['TV', 'TV_SHORT', 'ONA'],
      },
    );
    final page = d['Page'];
    final list = page is Map ? page['media'] : null;
    return [for (final m in list is List ? list : const []) ?AniListMedia.fromJson(m)];
  }

  Future<AniListMedia?> media(int id) async => AniListMedia.fromJson((await _query('query(\$id:Int){Media(id:\$id,type:ANIME){${AniListMedia.fields}}}', {'id': id}))['Media']);

  /// Sets the list entry's progress (and status).
  Future<void> save(int mediaId, {required int progress, required String status}) async {
    await _query('mutation(\$id:Int,\$p:Int,\$s:MediaListStatus){SaveMediaListEntry(mediaId:\$id,progress:\$p,status:\$s){id progress status}}', {'id': mediaId, 'p': progress, 's': status});
  }

  /// Records that episode [number] of [media] was watched: only ever moves progress
  /// forward, and leaves a finished show alone (a rewatch). Returns what changed, or null.
  Future<String?> watched(AniListMedia media, int number) async {
    final change = progressChange(media, number);
    if (change == null) return null;
    await save(media.id, progress: change.progress, status: change.status);
    return '${change.status} ${change.progress}${media.episodes != null ? '/${media.episodes}' : ''}';
  }
}

/// What watching episode [number] does to [media]'s list entry, or null for nothing.
({int progress, String status})? progressChange(AniListMedia media, int number) {
  if (number < 1) return null;
  if (media.status == 'COMPLETED') return null;
  if ((media.progress ?? 0) >= number) return null;
  final done = media.episodes != null && number >= media.episodes!;
  final status = done ? 'COMPLETED' : (media.status == 'REPEATING' ? 'REPEATING' : 'CURRENT');
  return (progress: media.episodes != null && number > media.episodes! ? media.episodes! : number, status: status);
}

/// Lower case letters and digits only, for comparing titles.
String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// "Hunter x Hunter (2011)" → ("Hunter x Hunter", 2011).
(String, int?) splitTitleYear(String title) {
  final m = RegExp(r'^(.*?)\s*\((\d{4})\)\s*$').firstMatch(title);
  return m == null ? (title.trim(), null) : (m[1]!, int.parse(m[2]!));
}

/// The search result that is [title] from [year]: a title that matches outright (or one
/// containing the other, from the right year). Null rather than a guess, since a wrong
/// match would move someone else's show forward on the user's list.
AniListMedia? pickMatch(List<AniListMedia> results, String title, int? year) {
  final (bare, inTitle) = splitTitleYear(title);
  final want = _norm(bare);
  final y = year ?? inTitle;
  if (want.isEmpty) return null;
  AniListMedia? best;
  var bestScore = 0;
  for (final m in results) {
    final names = m.titles.map(_norm).where((n) => n.isNotEmpty);
    var score = names.contains(want) ? 3 : (names.any((n) => n.contains(want) || want.contains(n)) ? 1 : 0);
    if (score == 0) continue;
    if (y != null && m.year != null) {
      final off = (m.year! - y).abs();
      score += off == 0 ? 2 : (off == 1 ? 1 : -2);
    }
    if (score > bestScore) {
      best = m;
      bestScore = score;
    }
  }
  return bestScore >= 3 ? best : null;
}

/// Where an episode lands on AniList: which entry, and its episode number there.
class AniListPlace {
  const AniListPlace(this.media, this.number);
  final AniListMedia media;
  final int number;
  @override
  String toString() => 'AniList ${media.id} episode $number';
}

/// Places [episode] in [chain] (a show's AniList series in airing order). AniList gives each
/// season, and each half of a split season, its own entry, while Plex's seasons follow TVDB
/// or TMDB; so the air date picks the entry, and the episode's number there is counted
/// from the first of [episodes] (the show's episodes in Plex) to air in it. Without dates,
/// season N is the Nth entry. Null when it can't tell.
AniListPlace? placeEpisode(List<AniListMedia> chain, PlexItem episode, List<PlexItem> episodes) {
  final season = episode.parentIndex, index = episode.index;
  if (season == null || season < 1 || index == null || chain.isEmpty) return null;
  DateTime? aired(PlexItem e) => DateTime.tryParse(e.originallyAvailableAt ?? '');
  final when = aired(episode);
  final dated = chain.where((m) => m.start != null).toList()..sort((a, b) => a.start!.compareTo(b.start!));
  const slack = Duration(days: 2);
  if (when != null && dated.isNotEmpty) {
    final at = dated.lastIndexWhere((m) => !m.start!.subtract(slack).isAfter(when));
    if (at < 0) return null;
    final media = dated[at];
    final until = at + 1 < dated.length ? dated[at + 1].start!.subtract(slack) : null;
    // Aired long after the last entry ended: AniList doesn't have this season yet.
    if (until == null && media.end != null && when.isAfter(media.end!.add(const Duration(days: 45)))) return null;
    bool inside(PlexItem e) {
      final d = aired(e);
      return d != null && (e.parentIndex ?? 0) >= 1 && e.index != null && !d.isBefore(media.start!.subtract(slack)) && (until == null || d.isBefore(until));
    }

    // Per Plex season inside this entry: where it starts and how many numbers it covers.
    final first = <int, int>{}, last = <int, int>{};
    for (final e in [...episodes.where(inside), episode]) {
      final s = e.parentIndex!, i = e.index!;
      first[s] = first[s] == null || i < first[s]! ? i : first[s]!;
      last[s] = last[s] == null || i > last[s]! ? i : last[s]!;
    }
    var number = 0;
    for (final s in first.keys.toList()..sort()) {
      if (s < season) number += last[s]! - first[s]! + 1;
    }
    number += index - first[season]! + 1;
    if (media.episodes != null && number > media.episodes!) return null;
    return AniListPlace(media, number);
  }
  if (season > chain.length) return null;
  final media = chain[season - 1];
  if (media.episodes != null && index > media.episodes!) return null;
  return AniListPlace(media, index);
}

/// Builds a show's chain of AniList series: from the entry its title finds, back through
/// prequels to the first season and on through sequels (films and OVAs in between are
/// passed through, not counted). [fetch] reads one entry.
Future<List<AniListMedia>> seriesChain(AniListMedia found, Future<AniListMedia?> Function(int id) fetch, {int limit = 25}) async {
  final seen = <int, AniListMedia>{found.id: found};
  var hops = 0;
  Future<AniListMedia?> get(int id) async {
    if (seen.containsKey(id)) return seen[id];
    if (hops++ >= limit) return null;
    final m = await fetch(id);
    if (m != null) seen[id] = m;
    return m;
  }

  final before = <AniListMedia>[];
  var at = found;
  while (at.prequels.isNotEmpty) {
    final p = await get(at.prequels.first);
    if (p == null || before.any((b) => b.id == p.id)) break;
    before.insert(0, p);
    at = p;
  }
  final after = <AniListMedia>[];
  at = found;
  while (at.sequels.isNotEmpty) {
    final n = await get(at.sequels.first);
    if (n == null || n.id == found.id || after.any((a) => a.id == n.id) || before.any((b) => b.id == n.id)) break;
    after.add(n);
    at = n;
  }
  return [...before, found, ...after].where((m) => m.isSeries).toList();
}
