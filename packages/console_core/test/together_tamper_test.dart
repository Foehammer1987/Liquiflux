import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

import 'tamper_test.dart' show mutations;

/// The relay and everyone in the room are strangers: whatever they send, the session mustn't
/// throw, must keep answering in valid JSON, and must never ask the player to go somewhere
/// nonsensical.
void main() {
  late List<String> sent;
  late List<SyncEvent> events;
  late SyncplaySession s;
  final alex = jsonEncode({'deviceIdentifier': 'd2', 'deviceName': 'Living Room', 'userID': 9});

  setUp(() {
    sent = [];
    events = [];
    s = SyncplaySession(
      roomId: 'room1',
      deviceId: 'd1',
      deviceName: 'Liquiflux on DESKTOP',
      userId: 7,
      names: {9: 'Alex', 10: 'Evil\n\u202EName${'!' * 500}'},
      send: sent.add,
      clock: () => DateTime(2026, 10, 14, 20),
    );
    s.local = () => (position: const Duration(seconds: 100), paused: false);
    s.events.listen(events.add);
    s.handle(
      jsonEncode({
        'Hello': {'username': s.username},
      }),
    );
    sent.clear();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Everything we sent is JSON that decodes (no Infinity or NaN slipped in).
  void sentIsValid() {
    for (final f in sent) {
      expect(() => jsonDecode(f), returnsNormally, reason: f);
    }
  }

  void remotesAreSane() {
    for (final r in events.whereType<SyncRemote>()) {
      expect(r.position, greaterThanOrEqualTo(Duration.zero));
      expect(r.position, lessThanOrEqualTo(const Duration(hours: 48, seconds: 3)));
    }
  }

  test('frames that aren\'t what the protocol says are ignored', () async {
    for (final f in [
      '',
      'not json',
      '[1,2,3]',
      '"State"',
      '42',
      'null',
      '{"State": "x"}',
      '{"State": {"playstate": "x", "ping": [], "ignoringOnTheFly": 5}}',
      '{"State": {"playstate": {"position": {}, "paused": "yes", "setBy": 5}}}',
      '{"List": []}',
      '{"List": {"room1": "x"}}',
      '{"List": {"room1": {"a": "b", "c": null}}}',
      '{"Set": 5}',
      '{"Set": {"user": [], "ready": "x"}}',
      '{"Set": {"user": {"x": {"event": "joined"}}, "ready": {"username": 5}}}',
      '{"Error": "x"}',
      '{"Error": {"message": 5}}',
      '{"Hello": []}',
      '{"Chat": {"message": "hi"}, "TLS": {"startTLS": "true"}}',
      '{"State": {"ping": {"latencyCalculation": 1e400, "clientLatencyCalculation": -1e400, "serverRtt": 1e400}}}',
      '{"State": {"ignoringOnTheFly": {"server": 1e400}}}',
      '{"State": {"ignoringOnTheFly": {"server": "3", "client": "x"}}}',
      '{"State": {"ignoringOnTheFly": {"server": 99999999999999}}}',
      '{"State": {"playstate": {"position": 1e400, "paused": false, "doSeek": true, "setBy": "x"}}}',
      '{"State": {"playstate": {"position": -1e400, "paused": false, "doSeek": true, "setBy": "x"}}}',
    ]) {
      expect(() => s.handle(f), returnsNormally, reason: f);
    }
    await settle();
    sentIsValid();
    remotesAreSane();
    // A huge server ignore count is echoed back but held to something sensible.
    final ignores = [
      for (final f in sent)
        if ((jsonDecode(f) as Map)['State']?['ignoringOnTheFly']?['server'] case final int n) n,
    ];
    expect(ignores.every((n) => n <= 1000), isTrue);
  });

  test('every value of a state, a roster and a join swapped for something hostile', () async {
    final frames = <Map<String, dynamic>>[
      {
        'State': {
          'playstate': {'position': 42.5, 'paused': false, 'doSeek': true, 'setBy': alex},
          'ping': {'latencyCalculation': 1000.5, 'clientLatencyCalculation': 1792000000.0, 'serverRtt': 0.02},
          'ignoringOnTheFly': {'server': 1, 'client': 0},
        },
      },
      {
        'List': {
          'room1': {
            alex: {'isReady': true, 'position': 4},
            s.username: {'isReady': false},
          },
        },
      },
      {
        'Set': {
          'user': {
            alex: {
              'event': {'joined': true, 'left': false},
              'room': {'name': 'room1'},
            },
          },
          'ready': {'username': alex, 'isReady': true, 'manuallyInitiated': true},
        },
      },
    ];
    var n = 0;
    for (final frame in frames) {
      for (final (what, doc) in mutations(frame)) {
        final String text;
        try {
          text = jsonEncode(doc);
        } on JsonUnsupportedObjectError {
          continue; // NaN and Infinity can't be written as JSON; the raw-text test covers them.
        }
        try {
          s.handle(text);
        } catch (e) {
          fail('$what: $e');
        }
        n++;
      }
    }
    await settle();
    expect(n, greaterThan(500));
    sentIsValid();
    remotesAreSane();
    for (final p in events.whereType<SyncRoster>().expand((r) => r.peers)) {
      expect(p.name, isNot(contains('\n')));
      expect(p.name.runes.length, lessThanOrEqualTo(40));
    }
  });

  group('positions', () {
    Future<SyncRemote?> stateAt(String position, {bool paused = true}) async {
      events.clear();
      s.handle('{"State": {"playstate": {"position": $position, "paused": $paused, "doSeek": true, "setBy": ${jsonEncode(alex)}}}}');
      await settle();
      return events.whereType<SyncRemote>().firstOrNull;
    }

    test('before the start is the start', () async {
      expect((await stateAt('-30'))?.position, Duration.zero);
      expect((await stateAt('-1e300'))?.position, Duration.zero);
    });

    test('nonsense is ignored rather than followed', () async {
      expect(await stateAt('1e12'), isNull);
      expect(await stateAt('1e400'), isNull);
      expect(await stateAt('"42"'), isNull);
      expect(await stateAt('[42]'), isNull);
      expect(await stateAt('true'), isNull);
      expect(await stateAt('${48 * 3600 + 1}'), isNull);
    });

    test('a real position, even a long one, is followed', () async {
      expect((await stateAt('5400.25'))?.position, const Duration(milliseconds: 5400250));
      expect((await stateAt('${47 * 3600}'))?.position, const Duration(hours: 47));
      expect((await stateAt('null'))?.position, Duration.zero);
    });

    test('a state that claims to be ours is not followed', () async {
      for (final by in [s.username, '${s.username}_', '${s.username}___']) {
        events.clear();
        s.handle(
          jsonEncode({
            'State': {
              'playstate': {'position': 9999, 'paused': false, 'doSeek': true, 'setBy': by},
            },
          }),
        );
        await settle();
        expect(events.whereType<SyncRemote>(), isEmpty);
      }
    });
  });

  test('a huge roster stops growing at maxPeers', () async {
    s.handle(
      jsonEncode({
        'List': {
          'room1': {
            for (var k = 0; k < 10000; k++) 'user$k': {'isReady': true},
          },
        },
      }),
    );
    for (var k = 0; k < 2000; k++) {
      s.handle(
        jsonEncode({
          'Set': {
            'ready': {'username': 'spam$k', 'isReady': true},
          },
        }),
      );
    }
    await settle();
    final last = events.whereType<SyncRoster>().last;
    expect(last.peers.length, lessThanOrEqualTo(SyncplaySession.maxPeers));
  });

  test('a flood of joins makes only a few notices, with clean names', () async {
    s.handle(
      jsonEncode({
        'Set': {
          'user': {
            for (var k = 0; k < 1000; k++)
              jsonEncode({'deviceIdentifier': 'x$k', 'deviceName': 'Bad\nName\u0007$k${'z' * 300}', 'userID': 1000 + k}): {
                'event': {'joined': true},
              },
          },
        },
      }),
    );
    s.handle(
      jsonEncode({
        'Set': {
          'user': {
            jsonEncode({'deviceIdentifier': 'e', 'deviceName': 'x', 'userID': 10}): {
              'event': {'left': true},
            },
          },
        },
      }),
    );
    await settle();
    final notices = events.whereType<SyncNotice>().toList();
    expect(notices.length, lessThanOrEqualTo(9));
    for (final n in notices) {
      expect(n.text, isNot(contains('\n')));
      expect(n.text, isNot(contains('\u0007')));
      expect(n.text, isNot(contains('\u202E')));
      expect(n.text.runes.length, lessThan(60));
    }
    expect(notices.last.text, startsWith('Evil Name'));
  });

  test('frames past the size limit are dropped unread', () async {
    final big = jsonEncode({
      'List': {
        'room1': {'x' * (SyncplaySession.maxFrame): {}},
      },
    });
    s.handle(big);
    await settle();
    expect(events, isEmpty);
    expect(sent, isEmpty);
  });

  test('the room closing says why in one clean line', () async {
    s.handle(
      jsonEncode({
        'Error': {'message': 'Go to\nhttp://evil\u202E${'!' * 1000}'},
      }),
    );
    await settle();
    final e = events.whereType<SyncClosed>().single.error!;
    expect(e, startsWith('Go to http://evil'));
    expect(e.runes.length, lessThanOrEqualTo(200));
  });

  test('rapid-fire states are each answered once, and nothing piles up', () async {
    for (var k = 0; k < 5000; k++) {
      s.handle(
        jsonEncode({
          'State': {
            'playstate': {'position': k.toDouble(), 'paused': k.isEven, 'doSeek': true, 'setBy': alex},
            'ping': {'latencyCalculation': k * 1.0},
          },
        }),
      );
    }
    await settle();
    expect(sent.length, 5000);
    expect(events.whereType<SyncRemote>().length, 5000);
    sentIsValid();
  });

  test('a very long device name of our own still fits the 150-byte identity', () {
    final t = SyncplaySession(roomId: 'r', deviceId: 'd', deviceName: 'é' * 100000, userId: 1, send: (_) {});
    expect(utf8.encode(t.username).length, lessThan(150));
  });

  test('a relay address that isn\'t a plain host and port is refused before connecting', () async {
    for (final (host, port) in [('evil.example/ws?x=', 443), ('user@evil.example', 443), ('', 443), ('a b', 443), ('relay.example', 0), ('relay.example', 70000)]) {
      await expectLater(
        SyncplaySession.connect(host: host, port: port, roomId: 'r', deviceId: 'd', deviceName: 'n', userId: 1),
        throwsA(isA<ArgumentError>()),
        reason: '$host:$port',
      );
    }
  });
}
