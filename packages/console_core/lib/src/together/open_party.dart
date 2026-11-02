import 'package:openwatchparty/openwatchparty.dart' as owp;

import '../plex/plex_models.dart';

/// Our own `ext` member of a room's media (reverse DNS, as Open Watch Party asks): the Plex
/// server and item the host shared, so someone on the same server gets that exact file.
/// Other apps ignore it.
const liquifluxExt = 'com.foehammer.liquiflux';

/// Plezy's member, which names the same two things. Read, never written: it's Plezy's.
const plezyExt = 'app.plezy';

/// The Plex items a room's media can be: a movie or an episode, nothing else.
bool roomKind(PlexItem item) => item.type == 'movie' || item.type == 'episode';

/// How [item] is described to an Open Watch Party room. Everyone in the room finds their own
/// copy from this, by catalogue ids first and by title after. [show] is the episode's series,
/// for its ids. Null when there is no length to share or the room would refuse it.
owp.Media? describeForRoom(PlexItem item, {PlexItem? show, required String machineId, int? durationMs}) {
  if (!roomKind(item)) return null;
  final length = _length(item) ?? durationMs;
  if (length == null || length <= 0) return null;
  final episode = item.type == 'episode';
  final ext = <String, Object?>{
    if (machineId.isNotEmpty) liquifluxExt: {'server': machineId, 'item': item.ratingKey},
  };
  final file = _fileOf(item);
  owp.Media build(owp.MediaFile? f) => owp.Media(
    kind: episode ? owp.MediaKind.episode : owp.MediaKind.movie,
    title: roomText(item.title) ?? (episode ? 'Episode ${item.index ?? ''}'.trim() : 'Untitled'),
    year: episode ? null : item.year,
    ids: idsOf(item),
    series: episode ? owp.Series(title: roomText(item.grandparentTitle ?? show?.title) ?? 'Unknown', year: show?.year, ids: show == null ? const {} : idsOf(show)) : null,
    season: episode && (item.parentIndex ?? -1) >= 0 ? item.parentIndex : null,
    episode: episode && (item.index ?? -1) >= 0 ? item.index : null,
    durationMs: length,
    file: f,
    ext: ext.isEmpty ? null : ext,
  );
  var media = build(file);
  // A file name the room won't take is only a hint: send the rest.
  if (owp.checkMedia(media) != null && file != null) media = build(file.sizeBytes == null ? null : owp.MediaFile(sizeBytes: file.sizeBytes));
  return owp.checkMedia(media) == null ? media : null;
}

/// The length of the version that plays (the first), from its parts or the item.
int? _length(PlexItem item) {
  final parts = item.media.firstOrNull?.parts ?? const <PlexPart>[];
  if (parts.isNotEmpty && parts.every((p) => (p.duration ?? 0) > 0)) return parts.fold<int>(0, (a, p) => a + p.duration!);
  final d = item.duration;
  return d != null && d > 0 ? d : null;
}

owp.MediaFile? _fileOf(PlexItem item) {
  final parts = item.media.firstOrNull?.parts ?? const <PlexPart>[];
  if (parts.isEmpty) return null;
  final size = parts.every((p) => p.size != null) ? parts.fold<int>(0, (a, p) => a + p.size!) : null;
  final name = parts.length == 1 ? baseName(parts.single.file) : null;
  if (size == null && name == null) return null;
  return owp.MediaFile(sizeBytes: size, name: name);
}

/// The last part of a server path, whichever slash it uses.
String? baseName(String? path) {
  if (path == null) return null;
  final name = path.split(RegExp(r'[/\\]')).last.trim();
  return name.isEmpty || name == '.' || name == '..' ? null : name;
}

/// [text] as the room wants it: no control or direction characters, spaces folded.
String? roomText(String? text) {
  if (text == null) return null;
  final out = StringBuffer();
  var space = false;
  for (final r in text.runes) {
    if (r == 0x09 || r == 0x0A || r == 0x0B || r == 0x0C || r == 0x0D || r == 0x20) {
      space = out.isNotEmpty;
      continue;
    }
    if (r <= 0x1F || (r >= 0x7F && r <= 0x9F) || r == 0x061C || r == 0x200E || r == 0x200F || (r >= 0x202A && r <= 0x202E) || (r >= 0x2066 && r <= 0x2069) || (r >= 0xD800 && r <= 0xDFFF)) continue;
    if (space) out.write(' ');
    space = false;
    out.writeCharCode(r);
  }
  final s = out.toString();
  return s.isEmpty ? null : s;
}

final _imdb = RegExp(r'^tt\d{1,12}$');
final _number = RegExp(r'^\d{1,12}$');
final _plexGuid = RegExp(r'^plex://(movie|show|season|episode)/[A-Za-z0-9]{1,64}$');

/// A Plex item's catalogue ids, as a room names them.
Map<String, String> idsOf(PlexItem item) {
  final out = <String, String>{};
  for (final g in item.guids) {
    final i = g.indexOf('://');
    if (i <= 0) continue;
    final kind = g.substring(0, i), value = g.substring(i + 3);
    if (kind == 'imdb' && _imdb.hasMatch(value)) out['imdb'] ??= value;
    if ((kind == 'tmdb' || kind == 'tvdb') && _number.hasMatch(value)) out[kind] ??= value;
  }
  final plex = item.plexGuid;
  if (plex != null && _plexGuid.hasMatch(plex)) out['plex'] = plex;
  return out;
}

/// The ids of a room's media we can search by. They come from strangers, so only well-formed
/// ones count, and they are only ever compared, never sent anywhere.
Map<String, String> trustedIds(Map<String, String> ids) => {
  if (ids['imdb'] case final v? when _imdb.hasMatch(v)) 'imdb': v,
  if (ids['tmdb'] case final v? when _number.hasMatch(v)) 'tmdb': v,
  if (ids['tvdb'] case final v? when _number.hasMatch(v)) 'tvdb': v,
  if (ids['plex'] case final v? when _plexGuid.hasMatch(v)) 'plex': v,
};

/// The server and item a room's media names (ours, or Plezy's), when it's well formed.
({String server, String item})? sharedCopy(owp.Media media) {
  for (final name in const [liquifluxExt, plezyExt]) {
    final m = media.ext?[name];
    if (m is! Map) continue;
    final server = m['server'], item = m['item'];
    if (server is String && item is String && _safeId.hasMatch(server) && _ratingKey.hasMatch(item)) return (server: server, item: item);
  }
  return null;
}

final _safeId = RegExp(r'^[A-Za-z0-9._-]{1,128}$');
final _ratingKey = RegExp(r'^\d{1,12}$');

/// Does [item] carry any of [ids]?
bool sharesId(PlexItem item, Map<String, String> ids) {
  if (ids.isEmpty) return false;
  final own = idsOf(item);
  return ids.entries.any((e) => own[e.key] == e.value);
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The movies or series in [library] that are the room's title: any shared id wins, and only
/// when no id matched does the title (and year, within one) decide.
List<PlexItem> sameTitles(Iterable<PlexItem> library, {required String type, required String title, int? year, Map<String, String> ids = const {}}) {
  final pool = library.where((i) => i.type == type).toList();
  final trusted = trustedIds(ids);
  final byId = [for (final i in pool) if (sharesId(i, trusted)) i];
  if (byId.isNotEmpty) return byId;
  final name = _norm(title);
  if (name.isEmpty) return const [];
  return [
    for (final i in pool)
      if (_norm(i.title) == name && (year == null || i.year == null || (i.year! - year).abs() <= 1)) i,
  ];
}

/// The episode of a series that is the room's: by season and number, else by its ids.
PlexItem? sameEpisode(Iterable<PlexItem> episodes, owp.Media media) {
  final trusted = trustedIds(media.ids);
  for (final e in episodes) {
    if (e.type == 'episode' && sharesId(e, trusted)) return e;
  }
  final s = media.season, n = media.episode;
  if (s == null || n == null) return null;
  for (final e in episodes) {
    if (e.type == 'episode' && e.parentIndex == s && e.index == n) return e;
  }
  return null;
}

/// A file of ours the room could play, with its length so the room can tell a different cut.
owp.Candidate<String> candidateFor(PlexItem item) => owp.Candidate<String>(
  id: item.ratingKey,
  ref: item.ratingKey,
  durationMs: _length(item),
  sizeBytes: _fileOf(item)?.sizeBytes,
  name: _fileOf(item)?.name,
);

/// A room code as typed (dashes, spaces, lower case), or null when it isn't one.
String? roomCode(String input) {
  try {
    return owp.formatCode(input);
  } on owp.PartyException {
    return null;
  }
}
