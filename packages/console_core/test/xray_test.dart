import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

void main() {
  XRayTimeline timeline() => XRayTimeline.fromJson({
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
    final t = XRayTimeline.fromJson({
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
    expect(XRayTimeline.fromJson({}).spans, isEmpty);
  });

  test('timeline address', () {
    expect(xrayUri('http://homeserver:8089', '1234').toString(), 'http://homeserver:8089/1234.json');
    expect(xrayUri('http://homeserver:8089/xray/', '1234').toString(), 'http://homeserver:8089/xray/1234.json');
    expect(xrayUri('', '1234'), isNull);
    expect(xrayUri('file:///tmp', '1234'), isNull);
    expect(xrayUri('http://homeserver:8089', '../secret'), isNull);
  });

  test('animated titles are left to the cast list', () {
    expect(isAnimated(PlexItem.fromJson({'ratingKey': '1', 'type': 'movie', 'title': 'Up', 'Genre': [{'tag': 'Animation'}]})), isTrue);
    expect(isAnimated(PlexItem.fromJson({'ratingKey': '2', 'type': 'movie', 'title': 'Heat', 'Genre': [{'tag': 'Crime'}]})), isFalse);
  });

  test('an unsure chapter names nobody, so the cast list shows instead', () {
    final t = XRayTimeline.fromJson({
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
    final t = XRayTimeline.fromJson({
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
    expect(XRayTimeline.fromJson(file(0.7, [1, 2])).usableFor([1, 2, 3]), isTrue);
    expect(XRayTimeline.fromJson(file(0.3, [1, 2])).usableFor([1, 2, 3]), isFalse);
    expect(XRayTimeline.fromJson(file(0.7, [7, 8, 9])).usableFor([1, 2, 3]), isFalse);
    expect(XRayTimeline.fromJson({'people': [], 'spans': []}).usableFor([1]), isFalse);
  });
}
