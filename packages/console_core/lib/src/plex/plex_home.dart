import '../http_json.dart';

/// One person in a Plex Home: the admin, a managed user (a kid's profile, say) or another
/// plex.tv account that joined the Home.
class PlexHomeUser {
  const PlexHomeUser({required this.uuid, required this.title, this.id = 0, this.thumb = '', this.admin = false, this.guest = false, this.restricted = false, this.protected = false});

  final int id;

  /// What plex.tv switches by.
  final String uuid;
  final String title;

  /// The avatar on plex.tv, or empty.
  final String thumb;
  final bool admin;
  final bool guest;

  /// A managed user with content restrictions.
  final bool restricted;

  /// Switching to this user needs their 4-digit PIN.
  final bool protected;

  String get name => title.trim().isNotEmpty ? title.trim() : 'Plex user';

  /// Up to two letters for an avatar that has no picture.
  String get initials {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return (words.length == 1 ? words.first.substring(0, 1) : words.first.substring(0, 1) + words.last.substring(0, 1)).toUpperCase();
  }

  /// plex.tv's ids are hex or dashed uuids; anything else never goes into a request path.
  static bool validUuid(String s) => RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(s);

  /// A user from plex.tv's JSON, or null when it has no usable uuid.
  static PlexHomeUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final uuid = '${j['uuid'] ?? ''}';
    if (!validUuid(uuid)) return null;
    bool flag(String k) => j[k] == true || j[k] == 1 || j[k] == '1' || j[k] == 'true';
    final thumb = '${j['thumb'] ?? ''}';
    return PlexHomeUser(
      id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
      uuid: uuid,
      title: '${j['friendlyName'] is String && (j['friendlyName'] as String).trim().isNotEmpty ? j['friendlyName'] : (j['title'] ?? j['username'] ?? '')}',
      // Only a web picture; never a file: or anything else an image loader might open.
      thumb: thumb.startsWith('https://') ? thumb : '',
      admin: flag('admin') || flag('homeAdmin'),
      guest: flag('guest'),
      restricted: flag('restricted'),
      protected: flag('protected'),
    );
  }

  @override
  bool operator ==(Object other) => other is PlexHomeUser && other.uuid == uuid;
  @override
  int get hashCode => uuid.hashCode;
}

/// plex.tv said no to the PIN.
class PlexPinRejected implements Exception {
  const PlexPinRejected();
  @override
  String toString() => 'That PIN is not right';
}

/// Plex Home on plex.tv: who's in the Home, and switching to one of them, which gives back
/// that user's own plex.tv token.
class PlexHome {
  PlexHome({required this.clientId, this.product = 'Console', JsonHttp? http, this.base = 'https://clients.plex.tv/api/v2'}) : _http = http ?? JsonHttp();
  final String clientId;
  final String product;
  final String base;
  final JsonHttp _http;

  void close() => _http.close();

  Map<String, String> _headers(String token) => {'X-Plex-Client-Identifier': clientId, 'X-Plex-Product': product, 'X-Plex-Token': token};

  static const _odd = 'plex.tv answered with something unexpected. Check your internet connection and try again.';

  /// A Plex PIN is four digits.
  static bool validPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  /// Everyone in the Home of the account [token] belongs to. An account that isn't in a
  /// Home gets an empty list.
  Future<List<PlexHomeUser>> users(String token) async {
    dynamic body;
    try {
      body = await _http.send('GET', Uri.parse('$base/home/users'), headers: _headers(token));
    } on ApiException catch (e) {
      // No Home on this account.
      if (e.status == 404) return const [];
      rethrow;
    }
    final j = JsonHttp.object(body, _odd);
    final list = j['users'];
    if (list is! List) return const [];
    final seen = <String>{};
    return [
      for (final u in list.map(PlexHomeUser.fromJson))
        if (u != null && seen.add(u.uuid)) u,
    ];
  }

  /// The account [token] belongs to.
  Future<PlexHomeUser> me(String token) async {
    final u = PlexHomeUser.fromJson(JsonHttp.object(await _http.send('GET', Uri.parse('$base/user'), headers: _headers(token)), _odd));
    return u ?? (throw ApiException(0, _odd));
  }

  /// Switches to [user] from the Home of [token] and returns [user]'s plex.tv token.
  /// Throws [PlexPinRejected] when [pin] is wrong (or missing for a protected user).
  Future<String> switchTo(String token, PlexHomeUser user, {String? pin}) async {
    if (!PlexHomeUser.validUuid(user.uuid)) throw ApiException(0, _odd);
    if (pin != null && !validPin(pin)) throw const PlexPinRejected();
    final uri = Uri.parse('$base/home/users/${user.uuid}/switch').replace(queryParameters: {'pin': ?pin});
    dynamic body;
    try {
      body = await _http.send('POST', uri, headers: _headers(token));
    } on ApiException catch (e) {
      if (wrongPin(e)) throw const PlexPinRejected();
      rethrow;
    }
    final t = JsonHttp.object(body, _odd)['authToken'];
    if (t is! String || t.isEmpty) throw ApiException(0, _odd);
    return t;
  }

  /// plex.tv's answer to a bad PIN: error code 1041 (sent with a 403).
  static bool wrongPin(ApiException e) {
    if (e.status != 403 && e.status != 401) return false;
    final b = e.body;
    final errors = b is Map ? b['errors'] : null;
    final first = errors is List && errors.isNotEmpty ? errors.first : null;
    final code = first is Map ? first['code'] : null;
    return code == 1041;
  }
}
