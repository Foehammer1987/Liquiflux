import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

void main() {
  RiptideTimeline timeline() => RiptideTimeline.fromJson({
    'v': 1,
    'people': [
      {'tag': 'Zoe Saldaña', 'id': 11, 'role': 'Neytiri'},
      {'tag': 'Sam Worthington', 'id': 12, 'role': 'Jake Sully'},
      {'tag': 'Stephen Lang', 'id': 13},
    ],
    'spans': [
      [10, 40, 1, 0.9],
      [20, 30, 0, 0.6],
      [25, 26, 2, 0.3], // too unsure to name
      [100, 120, 0, 0.95],
    ],
  });

  test('names who is on screen, most certain first', () {
    final t = timeline();
    expect(t.at(const Duration(seconds: 25)).map((p) => p.name), ['Sam Worthington', 'Zoe Saldaña']);
    expect(t.at(const Duration(seconds: 110)).single.plexTagId, 11);
    expect(t.at(const Duration(seconds: 70)), isEmpty);
  });

  test('a pause just past a span still counts it, a later one does not', () {
    final t = timeline();
    expect(t.at(const Duration(seconds: 42)).map((p) => p.name), ['Sam Worthington']);
    expect(t.at(const Duration(seconds: 50)), isEmpty);
  });

  test('bad entries are dropped, not fatal', () {
    final t = RiptideTimeline.fromJson({
      'people': [
        {'tag': 'A'},
        'junk',
      ],
      'spans': [
        [0, 10, 0, 2.0],
        [0, 10, 5, 0.9],
        [10, 0, 0, 0.9],
        ['x', 10, 0, 0.9],
        [1, 2],
      ],
    });
    expect(t.people, hasLength(1));
    expect(t.spans.single.confidence, 1.0);
    expect(RiptideTimeline.fromJson({}).spans, isEmpty);
  });

  test('timeline address', () {
    expect(riptideUri('http://homeserver:8089', '1234').toString(), 'http://homeserver:8089/1234.json');
    expect(riptideUri('http://homeserver:8089/riptide/', '1234').toString(), 'http://homeserver:8089/riptide/1234.json');
    expect(riptideUri('', '1234'), isNull);
    expect(riptideUri('file:///tmp', '1234'), isNull);
    expect(riptideUri('http://homeserver:8089', '../secret'), isNull);
  });

  test('animated titles are left to the cast list', () {
    expect(isAnimated(PlexItem.fromJson({'ratingKey': '1', 'type': 'movie', 'title': 'Up', 'Genre': [{'tag': 'Animation'}]})), isTrue);
    expect(isAnimated(PlexItem.fromJson({'ratingKey': '2', 'type': 'movie', 'title': 'Heat', 'Genre': [{'tag': 'Crime'}]})), isFalse);
  });

  test('an unsure chapter names nobody, so the cast list shows instead', () {
    final t = RiptideTimeline.fromJson({
      'people': [
        {'tag': 'A'},
      ],
      'spans': [
        [0, 100, 0, 0.9],
        [600, 700, 0, 0.9],
      ],
      'chapters': [
        {'start': 0, 'end': 600, 'confidence': 0.42},
        {'start': 600, 'end': 1200, 'confidence': 0.8},
      ],
    });
    expect(t.at(const Duration(seconds: 50)), isEmpty);
    expect(t.at(const Duration(seconds: 650)).single.name, 'A');
  });

  test('lookalikes come together', () {
    final t = RiptideTimeline.fromJson({
      'people': [
        {'tag': 'James Phelps', 'role': 'Fred Weasley', 'alike': [1]},
        {'tag': 'Oliver Phelps', 'role': 'George Weasley', 'alike': [0]},
        {'tag': 'Someone', 'alike': [9]},
      ],
      'spans': [
        [0, 10, 1, 0.8],
        [0, 10, 2, 0.7],
      ],
    });
    expect(t.at(const Duration(seconds: 5)).map((p) => p.name), ['Oliver Phelps', 'James Phelps', 'Someone']);
  });

  test('a poor or stale scan is not used', () {
    Map<String, dynamic> file(double q, List<int> ids) => {
      'quality': q,
      'people': [for (final id in ids) {'tag': 'P$id', 'id': id}],
      'spans': [
        [0, 10, 0, 0.9],
      ],
    };
    expect(RiptideTimeline.fromJson(file(0.7, [1, 2])).usableFor([1, 2, 3]), isTrue);
    expect(RiptideTimeline.fromJson(file(0.3, [1, 2])).usableFor([1, 2, 3]), isFalse);
    expect(RiptideTimeline.fromJson(file(0.7, [7, 8, 9])).usableFor([1, 2, 3]), isFalse);
    expect(RiptideTimeline.fromJson({'people': [], 'spans': []}).usableFor([1]), isFalse);
  });

  group('who is in the scene', () {
    List<String> names(RiptideTimeline t, int s, {List<int> breaks = const []}) => [
      for (final p in t.scene(Duration(seconds: s), breaks: [for (final b in breaks) Duration(seconds: b)])) p.person.name,
    ];

    // A conversation: A and B cut back and forth, C walks in at the end, D is in the next scene.
    RiptideTimeline talk() => RiptideTimeline.fromJson({
      'people': [
        {'tag': 'A'},
        {'tag': 'B'},
        {'tag': 'C'},
        {'tag': 'D'},
      ],
      'spans': [
        [100, 110, 0, 0.9],
        [110, 118, 1, 0.8],
        [118, 126, 0, 0.7],
        [126, 140, 1, 0.95],
        [138, 142, 2, 0.6],
        [180, 200, 3, 0.9],
        [130, 131, 3, 0.3], // too unsure to name
      ],
    });

    test('on screen now first, then the rest of the scene nearest first', () {
      final t = talk();
      final at114 = t.scene(const Duration(seconds: 114));
      expect([for (final s in at114) (s.person.name, s.onScreen, s.away.inSeconds)], [('B', true, 0), ('A', false, 4)]);
      expect(names(t, 133), ['B', 'C', 'A']);
      final c = t.scene(const Duration(seconds: 133))[1];
      expect(c.onScreen, isFalse);
      expect(c.away, const Duration(seconds: 5));
      // A span a moment ago still counts as on screen (frames are seconds apart).
      expect(t.scene(const Duration(seconds: 112)).first.onScreen, isTrue);
    });

    test('between their shots someone stays in the scene', () {
      final t = RiptideTimeline.fromJson({
        'people': [
          {'tag': 'A'},
          {'tag': 'B'},
        ],
        'spans': [
          [0, 10, 0, 0.9],
          [0, 10, 1, 0.8],
          [38, 48, 0, 0.9], // A again 28 s later: there all along
          [60, 70, 1, 0.8], // B again 50 s later: left and came back
        ],
      });
      expect(names(t, 24), ['A', 'B']);
      expect(names(t, 35), ['A']);
      expect(names(t, 44), ['A']);
    });

    test('names linger 15 s after someone was last seen, not longer', () {
      final t = talk();
      expect(names(t, 155), ['C', 'B']);
      expect(names(t, 158), isEmpty);
      expect(names(t, 166), ['D']);
    });

    test('a chapter mark ends the scene', () {
      final t = talk();
      expect(names(t, 150), ['C', 'B']);
      expect(names(t, 150, breaks: [145]), isEmpty);
      expect(names(t, 170, breaks: [145, 172]), isEmpty); // D is past the next mark
      expect(names(t, 175, breaks: [172]), ['D']);
    });

    test("the scanner's own scenes are used when it sends them", () {
      final t = RiptideTimeline.fromJson({
        'people': [
          {'tag': 'A'},
          {'tag': 'B'},
        ],
        'spans': [
          [0, 5, 0, 0.9],
          [80, 90, 1, 0.9],
        ],
        'scenes': [
          [100, 200],
          [0, 100],
          ['x', 3],
          [50, 40],
        ],
      });
      expect(t.scenes, [(0, 100000), (100000, 200000)]);
      expect(names(t, 45), ['B', 'A']); // 35 and 40 s away, but the same scene
      expect(names(t, 150), isEmpty);
    });

    test('an old file (no chapters, no scenes) still works, and an empty one names nobody', () {
      final t = RiptideTimeline.fromJson({
        'v': 1,
        'people': [
          {'tag': 'A', 'id': 1},
        ],
        'spans': [
          [10, 12.5, 0, 0.6],
        ],
      });
      expect(names(t, 20), ['A']);
      expect(names(t, 40), isEmpty);
      expect(RiptideTimeline.fromJson({}).scene(Duration.zero), isEmpty);
      expect(RiptideTimeline.fromJson({'people': [], 'spans': []}).scene(const Duration(seconds: 5)), isEmpty);
    });

    test('an unsure chapter names nobody, and lookalikes still come together', () {
      final t = RiptideTimeline.fromJson({
        'people': [
          {'tag': 'Fred', 'alike': [1]},
          {'tag': 'George', 'alike': [0]},
        ],
        'spans': [
          [0, 10, 0, 0.9],
          [600, 610, 1, 0.9],
        ],
        'chapters': [
          {'start': 0, 'end': 300, 'confidence': 0.4},
          {'start': 300, 'end': 900, 'confidence': 0.8},
        ],
      });
      expect(names(t, 5), isEmpty);
      expect(names(t, 605), ['George', 'Fred']);
      expect(t.scene(const Duration(seconds: 605)).every((s) => s.onScreen), isTrue);
    });
  });
}
