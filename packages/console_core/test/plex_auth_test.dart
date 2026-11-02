import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('plex pin', () {
    late List<http.Request> sent;
    PlexAuth auth(Map<String, dynamic> answer) {
      sent = [];
      return PlexAuth(
        clientId: 'client-1',
        product: 'Liquiflux',
        http: JsonHttp(
          client: MockClient((req) async {
            sent.add(req);
            return http.Response(jsonEncode(answer), 201, headers: {'content-type': 'application/json'});
          }),
        ),
      );
    }

    test('a link code asks for a short, non-strong pin', () async {
      final pin = await auth({'id': 42, 'code': 'AB12', 'expiresIn': 900}).createPin(strong: false);
      expect(sent.single.method, 'POST');
      expect(sent.single.url.toString(), 'https://plex.tv/api/v2/pins?strong=false');
      expect(sent.single.headers['X-Plex-Client-Identifier'], 'client-1');
      expect(sent.single.headers['X-Plex-Product'], 'Liquiflux');
      expect(pin.id, 42);
      expect(pin.code, 'AB12');
      expect(pin.expiresAt!.difference(DateTime.now()).inSeconds, inInclusiveRange(890, 900));
    });

    test('the browser flow still asks for a strong pin', () async {
      final pin = await auth({'id': 7, 'code': 'long-code'}).createPin();
      expect(sent.single.url.queryParameters['strong'], 'true');
      expect(pin.expiresAt, isNull);
    });

    test('an answer without an id or code is refused', () async {
      await expectLater(auth({'code': 'AB12'}).createPin(strong: false), throwsA(isA<ApiException>()));
      await expectLater(auth({'id': 1, 'code': ''}).createPin(strong: false), throwsA(isA<ApiException>()));
      await expectLater(auth({'id': 1}).createPin(strong: false), throwsA(isA<ApiException>()));
    });
  });
}
