import 'dart:async';
import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('JsonHttp', () {
    test('times out a body that never finishes', () async {
      final body = StreamController<List<int>>();
      final client = MockClient.streaming((req, _) async {
        body.add(utf8.encode('{"a":'));
        return http.StreamedResponse(body.stream, 200);
      });
      final h = JsonHttp(client: client, timeout: const Duration(milliseconds: 100));
      await expectLater(h.send('GET', Uri.parse('http://x.test/slow')), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
      await body.close();
    });

    test('turns a connection lost mid-body into an ApiException', () async {
      final client = MockClient.streaming((req, _) async {
        Stream<List<int>> cut() async* {
          yield utf8.encode('{"a":');
          throw http.ClientException('reset');
        }

        return http.StreamedResponse(cut(), 200);
      });
      final h = JsonHttp(client: client);
      await expectLater(h.send('GET', Uri.parse('http://x.test/cut')), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
    });

    test('a per-request timeout overrides the default', () async {
      final client = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return http.Response('{"ok":true}', 200);
      });
      final h = JsonHttp(client: client, timeout: const Duration(milliseconds: 50));
      expect(await h.send('GET', Uri.parse('http://x.test/big'), timeout: const Duration(seconds: 2)), {'ok': true});
    });
  });

  group('SeerrClient', () {
    test('requests that find the session expired together sign in again once', () async {
      var signIns = 0;
      var accepted = 'connect.sid=s1';
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/auth/plex')) {
          signIns++;
          return http.Response('{}', 200, headers: {'set-cookie': 'connect.sid=s$signIns; Path=/; HttpOnly'});
        }
        if (req.headers['cookie'] != accepted) return http.Response('{"message":"expired"}', 401);
        return http.Response(jsonEncode({'id': 1, 'displayName': 'Sam'}), 200);
      });
      final seerr = SeerrClient(
        baseUrl: 'http://seerr.test',
        plexToken: 'tok',
        http: JsonHttp(client: client),
      );
      final first = await Future.wait([seerr.me(), seerr.me(), seerr.me()]);
      expect(first.map((m) => m.name), ['Sam', 'Sam', 'Sam']);
      expect(signIns, 1);

      accepted = 'connect.sid=s2';
      final again = await Future.wait([seerr.me(), seerr.me(), seerr.me()]);
      expect(again.map((m) => m.name), ['Sam', 'Sam', 'Sam']);
      expect(signIns, 2);
    });

    test('a page that is not Seerr gets a plain explanation', () async {
      final client = MockClient((req) async => http.Response('<html>router login</html>', 200));
      final seerr = SeerrClient(
        baseUrl: 'http://seerr.test',
        apiKey: 'k',
        http: JsonHttp(client: client),
      );
      await expectLater(seerr.me(), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains("isn't Seerr"))));
    });
  });

  test('Netflix Top 10 is read once for both kinds', () {
    const tsv =
        'week\tcategory\tweekly_rank\tshow_title\n2026-10-05\tTV (English)\t1\tOld Show\n2026-10-12\tTV (English)\t1\tA Show\n2026-10-12\tFilms (English)\t2\tB Film\n2026-10-12\tFilms (English)\t1\tA Film\n';
    expect(NetflixTop10.parse(tsv, 'movie').map((t) => t.title), ['A Film', 'B Film']);
    expect(NetflixTop10.parse(tsv, 'tv').map((t) => t.title), ['A Show']);
    expect(identical(NetflixTop10.parse(tsv, 'tv'), NetflixTop10.parse(tsv, 'tv')), isTrue);
  });
}
