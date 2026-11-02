import '../http_json.dart';
import '../security.dart';

class PlexPin {
  PlexPin({required this.id, required this.code, this.expiresAt});
  final int id;
  final String code;

  /// When plex.tv stops accepting this code, if it said.
  final DateTime? expiresAt;
}

class PlexConnection {
  PlexConnection({required this.uri, required this.local, required this.relay});
  final String uri;
  final bool local;
  final bool relay;
}

class PlexServerResource {
  PlexServerResource({required this.name, required this.machineIdentifier, required this.accessToken, required this.owned, required this.connections});
  final String name;
  final String machineIdentifier;
  final String accessToken;
  final bool owned;
  final List<PlexConnection> connections;

  /// Local direct first, then remote direct, relay last; within each, https (the
  /// plex.direct address, with the server's own certificate) before plain http.
  List<PlexConnection> get orderedConnections => [...connections]
    ..sort((a, b) {
      int score(PlexConnection c) => (c.relay ? 4 : 0) + (c.local ? 0 : 2) + (c.uri.startsWith('https://') ? 0 : 1);
      return score(a).compareTo(score(b));
    });
}

/// Sign in with a plex.tv account using the PIN flow: the user approves in their browser,
/// or, on a TV, types a short code at [linkUrl] on their phone or computer.
class PlexAuth {
  PlexAuth({required this.clientId, this.product = 'Console', JsonHttp? http}) : _http = http ?? JsonHttp();
  final String clientId;
  final String product;
  final JsonHttp _http;

  /// Frees the HTTP connection; call when sign-in is over.
  void close() => _http.close();

  Map<String, String> get _headers => {'X-Plex-Client-Identifier': clientId, 'X-Plex-Product': product};

  static const _odd = 'plex.tv answered with something unexpected. Check your internet connection and try again.';

  /// Where a TV's link code is typed in.
  static const linkUrl = 'https://plex.tv/link';

  /// A new PIN. [strong] gives the long code that goes in [authUrl]; otherwise it's the
  /// 4-character code a person types at [linkUrl].
  Future<PlexPin> createPin({bool strong = true}) async {
    final j = JsonHttp.object(await _http.send('POST', Uri.parse('https://plex.tv/api/v2/pins?strong=$strong'), headers: _headers), _odd);
    final id = j['id'];
    final code = j['code'];
    if (id is! num || code is! String || code.isEmpty) throw ApiException(0, _odd);
    final left = j['expiresIn'];
    return PlexPin(
      id: id.toInt(),
      code: code,
      expiresAt: left is num && left > 0 ? DateTime.now().add(Duration(seconds: left.toInt())) : null,
    );
  }

  /// The page the user opens to approve this app.
  String authUrl(PlexPin pin) => 'https://app.plex.tv/auth#?${Uri(queryParameters: {'clientID': clientId, 'code': pin.code, 'context[device][product]': product}).query}';

  /// Returns the account token once the user has approved, otherwise null.
  Future<String?> checkPin(PlexPin pin) async {
    final j = JsonHttp.object(await _http.send('GET', Uri.parse('https://plex.tv/api/v2/pins/${pin.id}'), headers: _headers), _odd);
    final t = j['authToken'];
    return t is String && t.isNotEmpty ? t : null;
  }

  /// Polls until approved or [timeout] passes. A dropped connection along the way just
  /// means asking again.
  Future<String?> waitForToken(PlexPin pin, {Duration timeout = const Duration(minutes: 5), bool Function()? cancelled}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (cancelled?.call() ?? false) return null;
      try {
        final t = await checkPin(pin);
        if (t != null) return t;
      } on ApiException catch (e) {
        if (e.status != 0) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<List<PlexServerResource>> servers(String accountToken) async {
    final body = await _http.send('GET', Uri.parse('https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1'), headers: {..._headers, 'X-Plex-Token': accountToken});
    final list = JsonHttp.array(body, _odd);
    return list.whereType<Map<String, dynamic>>().where((r) => '${r['provides']}'.contains('server')).map((r) {
      final conns = (r['connections'] as List? ?? const []).whereType<Map<String, dynamic>>().map((c) => PlexConnection(uri: '${c['uri']}', local: c['local'] == true, relay: c['relay'] == true));
      return PlexServerResource(
        name: '${r['name']}',
        machineIdentifier: '${r['clientIdentifier'] ?? ''}',
        accessToken: '${r['accessToken'] ?? accountToken}',
        owned: r['owned'] == true,
        connections: conns.toList(),
      );
    }).toList();
  }

  /// The best connection of [server] that answers, or null. Every address is tried at
  /// once; the first that works in [PlexServerResource.orderedConnections] order wins.
  ///
  /// The probe carries no token: /identity answers without one, and its machine id shows
  /// it's really this server and not whatever else has that LAN address on another network.
  /// A plain-http address on the internet only wins when nothing else answers. [probe]
  /// stands in for the network in tests.
  Future<String?> firstReachable(PlexServerResource server, {JsonHttp? probe}) async {
    final quick = probe ?? JsonHttp(timeout: const Duration(seconds: 4));
    try {
      Future<bool> answers(PlexConnection c) async {
        try {
          final body = await quick.send('GET', Uri.parse('${c.uri}/identity'));
          final id = body is Map ? (body['MediaContainer'] is Map ? body['MediaContainer']['machineIdentifier'] : null) : null;
          return server.machineIdentifier.isEmpty || id == server.machineIdentifier;
        } on ApiException catch (e) {
          // A server set to want a token everywhere: an https address's certificate still
          // vouches for which server this is.
          return (e.status == 401 || e.status == 403) && c.uri.startsWith('https://');
        } catch (_) {
          return false;
        }
      }

      final conns = [...server.orderedConnections.where((c) => !sendsCredentialsInClear(c.uri)), ...server.orderedConnections.where((c) => sendsCredentialsInClear(c.uri))];
      final probes = conns.map(answers).toList();
      for (var i = 0; i < conns.length; i++) {
        if (await probes[i]) return conns[i].uri;
      }
      return null;
    } finally {
      if (probe == null) quick.close();
    }
  }
}
