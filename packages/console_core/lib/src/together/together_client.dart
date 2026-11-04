import '../format.dart';
import '../http_json.dart';

/// A plex.tv friend (or Home user) who can be asked into a room.
class PlexFriend {
  PlexFriend({required this.id, required this.title, this.username, this.thumb});
  factory PlexFriend.fromJson(Map<String, dynamic> j) => PlexFriend(
    id: _int(j['id']) ?? 0,
    title: cleanLabel(_str(j['title']) ?? _str(j['friendlyName']) ?? _str(j['username']), max: 60, fallback: 'Friend'),
    username: j['username']?.toString(),
    thumb: j['thumb']?.toString(),
  );
  final int id;
  final String title;
  final String? username;
  final String? thumb;
}

/// A Plex Watch Together room: one title on one server, the people asked in, and the
/// sync relay everyone's player talks to.
class TogetherRoom {
  TogetherRoom({required this.id, required this.title, required this.sourceUri, required this.host, required this.port, this.createdBy, this.endsAt, this.users = const []});

  /// A room made by someone else is shown and joined from what plex.tv says about it, so the
  /// title and names are cleaned for display and the list of people is kept to a sane size.
  factory TogetherRoom.fromJson(Map<String, dynamic> j) {
    final port = _int(j['syncplayPort']);
    return TogetherRoom(
      id: '${j['id'] ?? ''}',
      title: cleanLabel(_str(j['title']), max: 120),
      sourceUri: _str(j['sourceUri']) ?? '',
      host: _str(j['syncplayHost']) ?? '',
      port: port != null && port > 0 && port < 65536 ? port : 443,
      createdBy: j['createdBy'] is Map ? PlexFriend.fromJson((j['createdBy'] as Map).cast<String, dynamic>()) : null,
      endsAt: _time(j['endsAt']),
      users: [for (final u in (j['users'] is List ? j['users'] as List : const []).whereType<Map<dynamic, dynamic>>().take(100)) PlexFriend.fromJson(u.cast<String, dynamic>())],
    );
  }

  final String id;
  final String title;

  /// `server://<machineId>/com.plexapp.plugins.library/library/metadata/<ratingKey>`
  final String sourceUri;
  final String host;
  final int port;
  final PlexFriend? createdBy;
  final DateTime? endsAt;
  final List<PlexFriend> users;

  static final _source = RegExp(r'^server://([\w.-]+)/[^/]+/library/metadata/(\w+)');

  /// The server the title lives on.
  String? get machineId => _source.firstMatch(sourceUri)?.group(1);

  /// The title, on that server.
  String? get ratingKey => _source.firstMatch(sourceUri)?.group(2);

  bool get expired => endsAt != null && endsAt!.isBefore(DateTime.now());

  static String sourceFor(String machineId, String ratingKey) => 'server://$machineId/com.plexapp.plugins.library/library/metadata/$ratingKey';
}

/// The signed-in plex.tv account.
class PlexAccount {
  PlexAccount({required this.id, required this.title, this.thumb});
  final int id;
  final String title;
  final String? thumb;
}

/// Plex's Watch Together service (the rooms behind Plex Web's "Watch Together"). It isn't a
/// published API: this follows what Plex Web sends, so it can change under us.
class TogetherClient {
  TogetherClient({required this.token, required this.clientId, String? baseUrl, String? plexTvUrl, JsonHttp? http, this.product = 'Console'})
    : baseUrl = (baseUrl ?? 'https://together.plex.tv').replaceAll(RegExp(r'/+$'), ''),
      plexTvUrl = (plexTvUrl ?? 'https://plex.tv').replaceAll(RegExp(r'/+$'), ''),
      _http = http ?? JsonHttp();

  final String token;
  final String clientId;
  final String product;
  final String baseUrl;
  final String plexTvUrl;
  final JsonHttp _http;

  Map<String, String> get _headers => {'X-Plex-Token': token, 'X-Plex-Client-Identifier': clientId, 'X-Plex-Product': product};

  Future<dynamic> _send(String method, String url, [Object? body]) => _http.send(method, Uri.parse(url), headers: _headers, body: body);

  Future<PlexAccount> me() async {
    final j = await _send('GET', '$plexTvUrl/api/v2/user');
    if (j is! Map) throw ApiException(0, 'plex.tv sent an account we couldn’t read');
    return PlexAccount(
      id: _int(j['id']) ?? 0,
      title: cleanLabel(_str(j['friendlyName']) ?? _str(j['title']) ?? _str(j['username']), max: 60, fallback: 'Me'),
      thumb: j['thumb']?.toString(),
    );
  }

  /// People you can ask in. Watch Together only invites friends and Home users.
  ///
  /// plex.tv retired `/api/v2/friends` (it answers 410 Gone), so the list comes from the
  /// older `/api/users`, which is XML. The v2 call is only tried when that one fails, for a
  /// plex.tv (or test double) that still has it.
  Future<List<PlexFriend>> friends() async {
    List<PlexFriend> list;
    try {
      list = parseUsersXml(await _http.getText(Uri.parse('$plexTvUrl/api/users'), headers: _headers));
    } on ApiException catch (first) {
      try {
        list = await _friendsV2();
      } on ApiException {
        throw first;
      }
    }
    return list..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<List<PlexFriend>> _friendsV2() async {
    final j = await _send('GET', '$plexTvUrl/api/v2/friends');
    final container = j is Map ? j['MediaContainer'] : null;
    final list = _listOf(j is List ? j : (j is Map ? (j['friends'] ?? (container is Map ? container['User'] : null)) : null));
    return [for (final f in list.whereType<Map<dynamic, dynamic>>()) PlexFriend.fromJson(f.cast<String, dynamic>())];
  }

  /// The `<User …>` entries of plex.tv's `/api/users` answer. Only the attributes are read
  /// (no entities beyond XML's own, no DTDs), at most 500 people, and anyone without an id is
  /// left out since they can't be invited.
  static List<PlexFriend> parseUsersXml(String xml) {
    final out = <PlexFriend>[];
    final seen = <int>{};
    for (final m in _userTag.allMatches(xml)) {
      if (out.length >= 500) break;
      final a = <String, String>{for (final x in _attr.allMatches(m.group(1)!)) x.group(1)!: _unescape(x.group(2)!)};
      final f = PlexFriend.fromJson({
        'id': a['id'],
        'title': (a['title'] ?? '').isNotEmpty ? a['title'] : null,
        'username': (a['username'] ?? '').isNotEmpty ? a['username'] : null,
        'thumb': (a['thumb'] ?? '').isNotEmpty ? a['thumb'] : null,
      });
      if (f.id > 0 && seen.add(f.id)) out.add(f);
    }
    return out;
  }

  static final _userTag = RegExp(r'<User\b([^>]*)>');
  static final _attr = RegExp(r'([A-Za-z_][\w.-]*)\s*=\s*"([^"]*)"');

  static String _unescape(String v) => v.replaceAllMapped(RegExp(r'&(#x[0-9A-Fa-f]{1,6}|#[0-9]{1,7}|amp|lt|gt|quot|apos);'), (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    return code != null && code > 0 && code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF) ? String.fromCharCode(code) : '';
  });

  /// Rooms you made or were asked into that haven't run out.
  Future<List<TogetherRoom>> rooms() async {
    final j = await _send('GET', '$baseUrl/rooms');
    final list = _listOf(j is List ? j : (j is Map ? j['rooms'] : null));
    return [for (final r in list.whereType<Map<dynamic, dynamic>>()) TogetherRoom.fromJson(r.cast<String, dynamic>())].where((r) => !r.expired).toList();
  }

  Future<TogetherRoom> create({required String machineId, required String ratingKey, required String title, List<int> users = const []}) async {
    final j = await _send('POST', '$baseUrl/rooms', {'sourceUri': TogetherRoom.sourceFor(machineId, ratingKey), 'title': title, 'users': users});
    return TogetherRoom.fromJson((j as Map).cast<String, dynamic>());
  }

  Future<void> invite(String roomId, List<int> users) => _send('POST', '$baseUrl/rooms/${Uri.encodeComponent(roomId)}/invite', {'users': users});

  /// Leaves the room (it closes once everyone has gone or after three hours).
  Future<void> leave(String roomId) => _send('DELETE', '$baseUrl/rooms/${Uri.encodeComponent(roomId)}');

  void close() => _http.close();
}

int? _int(Object? v) => v is int ? v : (v is String ? int.tryParse(v) : null);
String? _str(Object? v) => v is String ? v : null;
List<dynamic> _listOf(Object? v) => v is List ? v : const [];

/// Seconds or milliseconds since 1970, or an ISO date; null when it's out of DateTime's range.
DateTime? _time(Object? v) {
  if (v is int) {
    const limit = 8640000000000000;
    if (v < -limit || v > limit) return null;
    final ms = v > 100000000000 || v < -100000000000 ? v : v * 1000;
    return ms < -limit || ms > limit ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
  return v is String ? DateTime.tryParse(v) : null;
}
