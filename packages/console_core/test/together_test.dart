import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('TogetherRoom', () {
    test('reads the server and title from the source', () {
      final r = TogetherRoom.fromJson({
        'id': 'abc',
        'title': 'Dune',
        'sourceUri': TogetherRoom.sourceFor('m123', '4567'),
        'syncplayHost': 'pop.example',
        'syncplayPort': 7776,
        'users': [
          {'id': 9, 'title': 'Alex'},
        ],
      });
      expect(r.machineId, 'm123');
      expect(r.ratingKey, '4567');
      expect(r.port, 7776);
      expect(r.users.single.title, 'Alex');
    });
  });

  group('SyncplaySession', () {
    late List<Map<String, dynamic>> sent;
    late SyncplaySession s;
    var now = DateTime(2026, 10, 14, 20);
    final alex = jsonEncode({'deviceIdentifier': 'd2', 'deviceName': 'Living Room', 'userID': 9});

    setUp(() {
      sent = [];
      now = DateTime(2026, 10, 14, 20);
      s = SyncplaySession(
        roomId: 'room1',
        deviceId: 'd1',
        deviceName: 'Liquiflux on DESKTOP',
        userId: 7,
        names: {9: 'Alex'},
        send: (f) => sent.add(jsonDecode(f) as Map<String, dynamic>),
        clock: () => now,
      );
      s.local = () => (position: const Duration(seconds: 100), paused: false);
    });

    void hello() => s.handle(
      jsonEncode({
        'Hello': {
          'username': s.username,
          'room': {'name': 'room1'},
        },
      }),
    );

    test('says hello as a Plex identity under 150 bytes, then readies up and asks who is here', () {
      s.start();
      final h = sent.single['Hello'] as Map;
      expect((h['room'] as Map)['name'], 'room1');
      expect(utf8.encode(h['username'] as String).length, lessThan(150));
      expect((jsonDecode(h['username'] as String) as Map)['userID'], 7);
      hello();
      expect(sent[1].keys.single, 'Set');
      expect(sent[2].keys.single, 'List');
    });

    test('follows what others do and answers every state with its own', () async {
      hello();
      sent.clear();
      final events = <SyncEvent>[];
      s.events.listen(events.add);
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': 42.0, 'paused': true, 'doSeek': true, 'setBy': alex},
            'ping': {'latencyCalculation': 1000.5, 'serverRtt': 0},
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      final r = events.whereType<SyncRemote>().single;
      expect(r.position, const Duration(seconds: 42));
      expect(r.paused, isTrue);
      expect(r.seek, isTrue);
      expect(r.by?.name, 'Alex');
      final reply = sent.single['State'] as Map;
      expect((reply['ping'] as Map)['latencyCalculation'], 1000.5);
      expect((reply['playstate'] as Map)['position'], 100.0);
    });

    test('ignores its own state coming back, even with underscores added', () async {
      hello();
      final events = <SyncEvent>[];
      s.events.listen(events.add);
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': 5, 'paused': false, 'setBy': '${s.username}__'},
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<SyncRemote>(), isEmpty);
    });

    test('holds off following the room until the relay has taken our change', () async {
      hello();
      final events = <SyncEvent>[];
      s.events.listen(events.add);
      sent.clear();
      s.changed(position: const Duration(seconds: 30), paused: true);
      final mine = sent.single['State'] as Map;
      expect((mine['playstate'] as Map)['paused'], isTrue);
      expect((mine['ignoringOnTheFly'] as Map)['client'], 1);
      // The relay hasn't seen it yet: its stale state must not undo the pause.
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': 29, 'paused': false, 'setBy': alex},
          },
        }),
      );
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': 30, 'paused': true, 'setBy': alex},
            'ignoringOnTheFly': {'client': 1},
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      final remote = events.whereType<SyncRemote>().toList();
      expect(remote, hasLength(1));
      expect(remote.single.paused, isTrue);
    });

    test('acknowledges a change the relay pushes', () {
      hello();
      sent.clear();
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': 1, 'paused': true, 'setBy': alex},
            'ignoringOnTheFly': {'server': 3},
          },
        }),
      );
      expect(((sent.single['State'] as Map)['ignoringOnTheFly'] as Map)['server'], 3);
    });

    test('lists the room by name', () async {
      hello();
      final events = <SyncEvent>[];
      s.events.listen(events.add);
      s.handle(
        jsonEncode({
          'List': {
            'room1': {
              s.username: {'isReady': true},
              alex: {'isReady': false},
            },
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      final peers = events.whereType<SyncRoster>().single.peers;
      expect(peers.map((p) => p.name), containsAll(['Alex', 'Liquiflux on DESKTOP']));
      expect(peers.firstWhere((p) => p.me).userId, 7);
    });

    test('reports no position while no player is attached', () {
      hello();
      s.local = () => null;
      sent.clear();
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': 1, 'paused': false, 'setBy': alex},
          },
        }),
      );
      expect((sent.single['State'] as Map).containsKey('playstate'), isFalse);
    });

    test('speaks up when the relay goes quiet', () {
      hello();
      sent.clear();
      now = now.add(const Duration(seconds: 5));
      s.heartbeat();
      expect(sent.single.keys.single, 'State');
    });
  });

  group('TogetherClient.friends', () {
    const usersXml = '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<MediaContainer friendlyName="myPlex" identifier="com.plexapp.plugins.myplex" size="3">\n'
        '<User id="101" title="Zoë &amp; Co" username="zoe" email="z@example.com" thumb="https://plex.tv/users/a/avatar" home="0">\n'
        '  <Server id="1" serverId="2" machineIdentifier="abc" name="Neotower" />\n'
        '</User>\n'
        '<User id="55" title="" username="bob" thumb="" home="1"/>\n'
        '<User title="no id" username="x"/>\n'
        '</MediaContainer>';

    TogetherClient client(Future<http.Response> Function(http.Request) handler) =>
        TogetherClient(token: 'tok', clientId: 'cid', http: JsonHttp(client: MockClient(handler)));

    test('reads friends from /api/users, since /api/v2/friends is gone', () async {
      final asked = <String>[];
      final c = client((req) async {
        asked.add(req.url.path);
        expect(req.headers['X-Plex-Token'], 'tok');
        if (req.url.path == '/api/users') return http.Response(usersXml, 200, headers: {'content-type': 'application/xml; charset=utf-8'});
        return http.Response('{"error":"gone"}', 410);
      });
      final list = await c.friends();
      expect(asked, ['/api/users']);
      expect([for (final f in list) f.id], [55, 101]);
      expect(list[0].title, 'bob');
      expect(list[1].title, 'Zoë & Co');
      expect(list[1].username, 'zoe');
      expect(list[1].thumb, 'https://plex.tv/users/a/avatar');
      expect(list[0].thumb, isNull);
    });

    test('falls back to /api/v2/friends when /api/users fails', () async {
      final c = client((req) async {
        if (req.url.path == '/api/users') return http.Response('', 500);
        return http.Response(jsonEncode([{'id': 7, 'title': 'Ann', 'username': 'ann'}]), 200);
      });
      expect([for (final f in await c.friends()) f.title], ['Ann']);
    });

    test('reports the /api/users error when both fail', () async {
      final c = client((req) async => http.Response('', req.url.path == '/api/users' ? 401 : 410));
      expect(c.friends(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    });

    test('reads only User attributes and ignores odd entities', () {
      final list = TogetherClient.parseUsersXml('<User id="9" title="A&#x42;&#67;&bogus;&#xD800;"/><User id="9" title="dupe"/><Users id="3"/>');
      expect(list.single.title, 'ABC&bogus;');
    });
  });
}
