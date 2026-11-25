import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:console_app/ui/player/riptide.dart';

void main() {
  setUp(RiptideServer.reset);

  final later = DateTime.now().add(const Duration(hours: 12)).toUtc().toIso8601String();
  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  PlexItem film({List<Map<String, dynamic>> chapters = const []}) => PlexItem.fromJson({
    'ratingKey': '42',
    'type': 'movie',
    'title': 'Film',
    'Role': [
      {'id': 1, 'tag': 'Ann', 'role': 'Pilot'},
      {'id': 2, 'tag': 'Bob', 'role': 'Doctor'},
      {'id': 3, 'tag': 'Cy'},
    ],
    'Chapter': chapters,
  });

  final timeline = {
    'v': 1,
    'quality': 0.8,
    'people': [
      {'tag': 'Ann', 'id': 1},
      {'tag': 'Bob', 'id': 2},
    ],
    'spans': [
      [100, 110, 0, 0.9],
      [104, 120, 1, 0.8],
      [130, 140, 0, 0.9],
    ],
  };

  /// A Riptide server whose timeline answers come from [answers] in turn (the last repeats).
  ({Riptide riptide, List<http.Request> seen}) make(List<int> answers, {DateTime Function()? now}) {
    final seen = <http.Request>[];
    var n = 0;
    final client = MockClient((r) async {
      seen.add(r);
      if (r.url.path == '/api/v1/auth/plex') return json({'token': 'xr1.a.b', 'expiresAt': later});
      final status = answers[n < answers.length ? n : answers.length - 1];
      n++;
      return status == 200 ? json(timeline) : json({'error': 'no'}, status);
    });
    final plex = PlexClient(baseUrl: 'http://plex.test:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: MockClient((r) async => json({}, 404))));
    final riptide = Riptide(plex: plex, server: 'http://riptide.lan:8089', http: JsonHttp(client: client), retryDelays: const [Duration(milliseconds: 5), Duration(milliseconds: 5)], now: now);
    return (riptide: riptide, seen: seen);
  }

  int fetches(List<http.Request> seen) => seen.where((r) => r.url.path.startsWith('/api/v1/timeline/')).length;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('who is in the scene: on screen first, the rest of the scene after, cast names from Plex', () async {
    final t = make([200]);
    t.riptide.follow(film());
    await settle();
    expect(t.riptide.scanned, isTrue);
    // At 122 s Bob is on screen (his last frame was 2 s ago) and Ann is back in 8 s.
    expect(t.riptide.inScene(const Duration(seconds: 122)).map((r) => r.tag), ['Bob', 'Ann']);
    // At 125 s both are 5 s away: the surer one first.
    expect(t.riptide.inScene(const Duration(seconds: 125)).map((r) => r.tag), ['Ann', 'Bob']);
    expect(t.riptide.inScene(const Duration(seconds: 135)).map((r) => (r.tag, r.role)), [('Ann', 'Pilot'), ('Bob', 'Doctor')]);
    expect(t.riptide.inScene(const Duration(seconds: 300)), isEmpty); // the caller shows the cast
  });

  test("a chapter mark ends the scene", () async {
    final t = make([200]);
    t.riptide.follow(film(chapters: [
      {'tag': 'One', 'startTimeOffset': 0, 'endTimeOffset': 128000},
      {'tag': 'Two', 'startTimeOffset': 128000, 'endTimeOffset': 900000},
    ]));
    await settle();
    // Ann is back at 130 s, past the mark at 128 s; Bob left at 120 s, before it.
    expect(t.riptide.inScene(const Duration(seconds: 126)).map((r) => r.tag), ['Bob']);
    expect(t.riptide.inScene(const Duration(seconds: 129)).map((r) => r.tag), ['Ann']);
  });

  test('a fetch that fails for a moment is tried again', () async {
    final t = make([503, 502, 200]);
    t.riptide.follow(film());
    await settle();
    expect(fetches(t.seen), 3);
    expect(t.riptide.scanned, isTrue);
  });

  test('after the tries run out it is fetched again later, when someone looks', () async {
    var clock = DateTime(2026, 11, 23, 9);
    final t = make([503, 503, 503, 200], now: () => clock);
    t.riptide.follow(film());
    await settle();
    expect(fetches(t.seen), 3);
    expect(t.riptide.scanned, isFalse);
    clock = clock.add(const Duration(seconds: 30));
    expect(t.riptide.inScene(const Duration(seconds: 105)), isEmpty);
    await settle();
    expect(fetches(t.seen), 3); // too soon
    clock = clock.add(const Duration(seconds: 31));
    t.riptide.inScene(const Duration(seconds: 105));
    await settle();
    expect(fetches(t.seen), 4);
    expect(t.riptide.scanned, isTrue);
    expect(t.riptide.inScene(const Duration(seconds: 105)).map((r) => r.tag), ['Ann', 'Bob']);
  });

  test('refused or not scanned is not asked again', () async {
    var clock = DateTime(2026, 11, 23, 9);
    final refused = make([403], now: () => clock);
    refused.riptide.follow(film());
    await settle();
    clock = clock.add(const Duration(minutes: 5));
    refused.riptide.inScene(const Duration(seconds: 105));
    await settle();
    expect(fetches(refused.seen), 1);

    RiptideServer.reset();
    final missing = make([404], now: () => clock);
    missing.riptide.follow(film());
    await settle();
    clock = clock.add(const Duration(minutes: 5));
    missing.riptide.inScene(const Duration(seconds: 105));
    await settle();
    expect(fetches(missing.seen), 1);
    expect(missing.riptide.scanned, isFalse);
  });
}
