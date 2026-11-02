import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  setUp(XRayServer.reset);

  final timeline = {'v': 1, 'ratingKey': '1234', 'people': [], 'spans': []};

  ({XRayServer server, List<http.Request> seen}) make(String base, Future<http.Response> Function(http.Request r) answer) {
    final seen = <http.Request>[];
    final client = MockClient((r) {
      seen.add(r);
      return answer(r);
    });
    return (server: XRayServer.shared(base, 'plextoken123', http: JsonHttp(client: client))!, seen: seen);
  }

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
  final later = DateTime.now().add(const Duration(hours: 12)).toUtc().toIso8601String();

  test('signs in once with the Plex token, then sends only the session', () async {
    final t = make('http://192.168.1.30:8089/', (r) async {
      if (r.url.path == '/api/v1/auth/plex') return json({'token': 'xr1.abc.def', 'expiresAt': later});
      if (r.url.path == '/api/v1/timeline/1234') {
        return r.headers['authorization'] == 'Bearer xr1.abc.def' ? json(timeline) : json({'error': 'no'}, 401);
      }
      return json({'error': 'not found'}, 404);
    });
    expect(await t.server.timeline('1234'), timeline);
    expect(await t.server.timeline('1234'), timeline);
    expect(await t.server.timeline('9999'), isNull);
    expect(t.seen.where((r) => r.url.path == '/api/v1/auth/plex'), hasLength(1));
    final signIn = t.seen.first;
    expect(jsonDecode(signIn.body), {'plexToken': 'plextoken123'});
    for (final r in t.seen) {
      expect(r.url.toString(), isNot(contains('plextoken123')));
      if (r.url.path != '/api/v1/auth/plex') expect(r.body, isNot(contains('plextoken123')));
    }
  });

  test('signs in again when the server forgot the session (restart)', () async {
    var n = 0;
    final t = make('https://xray.example.com', (r) async {
      if (r.url.path == '/api/v1/auth/plex') return json({'token': 'xr1.s${++n}.x', 'expiresAt': later});
      return r.headers['authorization'] == 'Bearer xr1.s2.x' ? json(timeline) : json({'error': 'not signed in'}, 401);
    });
    expect(await t.server.timeline('1234'), timeline);
    expect(n, 2);
  });

  test('a plain file server is read directly', () async {
    final t = make('http://homeserver:8089', (r) async {
      if (r.method == 'POST') return http.Response('Unsupported method', 501);
      if (r.url.path == '/1234.json') return json(timeline);
      return http.Response('nope', 404);
    });
    expect(await t.server.timeline('1234'), timeline);
    expect(await t.server.timeline('1'), isNull);
    expect(await t.server.check(), isFalse);
  });

  test('never sends the Plex token over plain http across the internet', () async {
    final t = make('http://xray.example.com', (r) async => r.url.path == '/1234.json' ? json(timeline) : http.Response('', 404));
    expect(await t.server.timeline('1234'), timeline);
    expect(t.seen.any((r) => r.method == 'POST'), isFalse);
  });

  test('a refused account is not asked again for every title', () async {
    final t = make('https://xray.example.com', (r) async => json({'error': 'this Plex account has no access to this server'}, 403));
    await expectLater(t.server.timeline('1234'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    await expectLater(t.server.timeline('8443'), throwsA(isA<ApiException>()));
    expect(t.seen, hasLength(1));
    expect(t.server.refusal, contains('no access'));
  });

  test('odd addresses and keys are refused', () async {
    expect(XRayServer.shared('', 't'), isNull);
    expect(XRayServer.shared('file:///etc', 't'), isNull);
    expect(XRayServer.shared('http://user:pw@host', 't'), isNull);
    final t = make('http://homeserver:8089', (r) async => json(timeline));
    expect(await t.server.timeline('../secret'), isNull);
    expect(t.seen, isEmpty);
  });
}
