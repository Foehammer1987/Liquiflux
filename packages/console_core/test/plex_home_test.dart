import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late List<http.Request> sent;
  PlexHome home(http.Response Function(http.Request) answer) {
    sent = [];
    return PlexHome(
      clientId: 'client-1',
      product: 'Liquiflux',
      http: JsonHttp(
        client: MockClient((req) async {
          sent.add(req);
          return answer(req);
        }),
      ),
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  group('Plex Home users', () {
    test('lists the Home with the token in a header, never the address', () async {
      final users = await home(
        (_) => json({
          'id': 1,
          'users': [
            {'id': 1, 'uuid': 'aaaa1111', 'title': 'Sam', 'thumb': 'https://plex.tv/users/aaaa1111/avatar', 'admin': true, 'protected': true},
            {'id': 2, 'uuid': 'bbbb2222', 'title': 'Kid', 'friendlyName': 'Little One', 'thumb': 'file:///etc/passwd', 'restricted': true, 'protected': false},
            {'id': 3, 'uuid': '../../evil', 'title': 'Bad'},
            {'id': 4, 'uuid': 'aaaa1111', 'title': 'Twice'},
          ],
        }),
      ).users('acct-token');
      expect(sent.single.url.toString(), 'https://clients.plex.tv/api/v2/home/users');
      expect(sent.single.headers['X-Plex-Token'], 'acct-token');
      expect(sent.single.headers['X-Plex-Client-Identifier'], 'client-1');
      expect(sent.single.url.query, isEmpty);
      expect(users.map((u) => u.uuid), ['aaaa1111', 'bbbb2222']);
      expect(users.first.admin, isTrue);
      expect(users.first.protected, isTrue);
      expect(users.first.thumb, startsWith('https://'));
      expect(users.last.name, 'Little One');
      expect(users.last.thumb, isEmpty, reason: 'only https pictures are kept');
      expect(users.last.restricted, isTrue);
      expect(users.last.initials, 'LO');
    });

    test('an account without a Home has nobody to switch to', () async {
      expect(await home((_) => json({'errors': []}, 404)).users('t'), isEmpty);
      expect(await home((_) => json({'id': 1})).users('t'), isEmpty);
    });

    test('me is the account the token belongs to', () async {
      final me = await home((_) => json({'id': 9, 'uuid': 'cccc3333', 'title': 'Owner', 'username': 'owner'})).me('t');
      expect(sent.single.url.path, '/api/v2/user');
      expect(me.uuid, 'cccc3333');
    });
  });

  group('switching', () {
    const kid = PlexHomeUser(uuid: 'bbbb2222', title: 'Kid', protected: true);

    test('gives back the user token; the PIN goes along', () async {
      final token = await home((_) => json({'authToken': 'kid-token', 'uuid': 'bbbb2222'}, 201)).switchTo('acct-token', kid, pin: '1234');
      expect(token, 'kid-token');
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/api/v2/home/users/bbbb2222/switch');
      expect(sent.single.url.queryParameters, {'pin': '1234'});
      expect(sent.single.headers['X-Plex-Token'], 'acct-token');
    });

    test('no PIN for a user without one', () async {
      await home((_) => json({'authToken': 'x'}, 201)).switchTo('t', const PlexHomeUser(uuid: 'dddd4444', title: 'Open'));
      expect(sent.single.url.query, isEmpty);
    });

    test('a wrong PIN (code 1041) is PlexPinRejected', () async {
      final h = home(
        (_) => json({
          'errors': [
            {'code': 1041, 'message': 'Invalid PIN', 'status': 403},
          ],
        }, 403),
      );
      await expectLater(h.switchTo('t', kid, pin: '0000'), throwsA(isA<PlexPinRejected>()));
    });

    test('other refusals stay ApiExceptions', () async {
      await expectLater(home((_) => json({'error': 'nope'}, 401)).switchTo('t', kid, pin: '1234'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      await expectLater(home((_) => json({}, 201)).switchTo('t', kid, pin: '1234'), throwsA(isA<ApiException>()));
    });

    test('a malformed PIN or uuid never reaches plex.tv', () async {
      final h = home((_) => json({'authToken': 'x'}, 201));
      await expectLater(h.switchTo('t', kid, pin: '12a4'), throwsA(isA<PlexPinRejected>()));
      await expectLater(h.switchTo('t', const PlexHomeUser(uuid: 'a/b', title: 'x')), throwsA(isA<ApiException>()));
      expect(sent, isEmpty);
    });
  });
}
