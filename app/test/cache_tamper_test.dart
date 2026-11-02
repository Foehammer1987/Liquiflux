import 'dart:convert';
import 'dart:io';

import 'package:console_app/services/collections_cache.dart';
import 'package:console_app/services/series_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Values a hand-edited or corrupted file might hold where something else belongs.
const hostile = <Object?>[null, 'oops', '', -1, 0, 9223372036854775807, -9223372036854775808, 1e308, 2.5, true, <Object?>[], <String, Object?>{}, '../../../etc/passwd'];

List<List<Object>> _paths(Object? node, [List<Object> at = const []]) => [
  if (at.isNotEmpty) at,
  if (node is Map)
    for (final e in node.entries) ..._paths(e.value, [...at, e.key as Object]),
  if (node is List)
    for (var i = 0; i < node.length; i++) ..._paths(node[i], [...at, i]),
];

/// [doc] as JSON text with one value at a time swapped for each hostile value, or removed.
Iterable<(String, String)> mutations(Map<String, Object?> doc) sync* {
  for (final path in _paths(doc)) {
    for (final v in [...hostile, #remove]) {
      final copy = jsonDecode(jsonEncode(doc));
      dynamic parent = copy;
      for (final key in path.take(path.length - 1)) {
        parent = parent[key];
      }
      if (v == #remove) {
        parent is Map ? parent.remove(path.last) : (parent as List).removeAt(path.last as int);
      } else {
        parent[path.last] = v;
      }
      yield ('${path.join('.')} = $v', jsonEncode(copy));
    }
  }
}

final now = DateTime.now().millisecondsSinceEpoch;

Map<String, Object?> collectionsFile({String server = 'machine1', int? at}) => {
  'server': server,
  'tmdb': {
    '10': {
      'at': at ?? now,
      'json': {
        'id': 10,
        'name': 'Star Wars Collection',
        'posterPath': '/p.jpg',
        'parts': [
          {'id': 11, 'title': 'Star Wars', 'releaseDate': '1977-05-25'},
          {'id': 1891, 'title': 'The Empire Strikes Back', 'releaseDate': '1980-05-20'},
        ],
      },
    },
  },
  'plex': [
    {
      'collection': {'ratingKey': '300', 'type': 'collection', 'title': 'Star Wars', 'updatedAt': 1700000000, 'childCount': 2},
      'items': ['101', '102'],
      'tmdbId': 10,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollectionsCache.read', () {
    test('reads back what save writes', () {
      final c = CollectionsCache()..read(jsonEncode(collectionsFile()), 'machine1');
      expect(c.tmdb[10]?.series.parts, hasLength(2));
      expect(c.fresh(10)?.name, 'Star Wars Collection');
      expect(c.plex.single.items, ['101', '102']);
      expect(c.plex.single.tmdbId, 10);
    });

    test('a cache for another server is ignored', () {
      final c = CollectionsCache()..read(jsonEncode(collectionsFile(server: 'someone-else')), 'machine1');
      expect(c.isEmpty, isTrue);
    });

    test('truncated or garbage text leaves it empty', () {
      final text = jsonEncode(collectionsFile());
      for (final t in [text.substring(0, text.length ~/ 2), '', 'null', '[]', '"x"', '42', '{', '\u0000\u0001', 'x' * 100000]) {
        final c = CollectionsCache();
        expect(() => c.read(t, 'machine1'), returnsNormally, reason: t);
        expect(c.isEmpty, isTrue);
      }
    });

    test('a value of the wrong type drops that entry, never the app', () {
      var n = 0;
      for (final (what, text) in mutations(collectionsFile())) {
        final c = CollectionsCache();
        try {
          c.read(text, 'machine1');
          c.fresh(10);
          for (final p in c.plex) {
            expect(p.items.every((k) => RegExp(r'^\w+$').hasMatch(k)), isTrue, reason: what);
            CollectionsCache.same(p.collection, p.collection);
          }
        } catch (e) {
          fail('$what: $e');
        }
        n++;
      }
      expect(n, greaterThan(300));
    });

    test('a series filed under another id is skipped', () {
      final f = collectionsFile();
      ((f['tmdb'] as Map)['10'] as Map)['json'] = {'id': 99, 'name': 'Wrong'};
      final c = CollectionsCache()..read(jsonEncode(f), 'machine1');
      expect(c.tmdb, isEmpty);
    });

    test('a fetch date in the future is not fresh, so it is fetched again', () {
      final c = CollectionsCache()..read(jsonEncode(collectionsFile(at: DateTime(2999).millisecondsSinceEpoch)), 'machine1');
      expect(c.tmdb[10], isNotNull);
      expect(c.fresh(10), isNull);
    });

    test('ratingKeys that are paths or worse are dropped', () {
      final f = collectionsFile();
      ((f['plex'] as List).first as Map)['items'] = ['101', '../../x', 'a/b', 5, null, {}, '102?x=1'];
      final c = CollectionsCache()..read(jsonEncode(f), 'machine1');
      expect(c.plex.single.items, ['101', '5']);
    });
  });

  group('SeriesCache.read', () {
    test('keeps only movie id → series id pairs', () {
      final c = SeriesCache()..read(jsonEncode({'603': 2344, '604': 0, 'x': 1, '-5': 3, '605': -1, '606': '7', '607': 1.5, '608': null, '609': 9223372036854775807}));
      expect(c[603], 2344);
      expect(c[604], 0);
      expect(c.has(605), isFalse);
      expect(c.has(606), isFalse);
      expect(c.has(607), isFalse);
      expect(c[609], 9223372036854775807);
    });

    test('garbage leaves it empty', () {
      for (final t in ['', '{', '[1,2]', 'null', '"x"', 'x' * 100000]) {
        final c = SeriesCache();
        expect(() => c.read(t), returnsNormally);
        expect(c.has(603), isFalse);
      }
    });
  });

  group('loading from disk', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('liquiflux-tamper');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
      dir.deleteSync(recursive: true);
    });

    File file(String name) => File('${dir.path}${Platform.pathSeparator}$name');

    test('a corrupt collections file is ignored and replaced on the next save', () async {
      file('collections_cache.json').writeAsStringSync('{"server": "machine1", "tmdb": {"10": {"at": "yesterday"');
      final c = CollectionsCache();
      await c.load('machine1');
      expect(c.isEmpty, isTrue);
      await c.save();
      expect(jsonDecode(file('collections_cache.json').readAsStringSync())['server'], 'machine1');
    });

    test('an enormous file is not read at all', () async {
      final f = file('collections_cache.json');
      final sink = f.openWrite()..write('{"server": "machine1", "plex": [');
      final chunk = '{"collection": {"ratingKey": "1"}, "items": []},' * 10000;
      for (var written = 0; written <= CollectionsCache.maxBytes; written += chunk.length) {
        sink.write(chunk);
        await sink.flush();
      }
      sink.write('{}]}');
      await sink.close();
      expect(f.lengthSync(), greaterThan(CollectionsCache.maxBytes));
      final c = CollectionsCache();
      await c.load('machine1');
      expect(c.isEmpty, isTrue);
    });

    test('a series file of the wrong shape is ignored', () async {
      file('series_cache.json').writeAsStringSync('[1, 2, 3]');
      final c = SeriesCache();
      await c.load();
      expect(c.has(1), isFalse);
      c[603] = 2344;
      await c.save();
      expect(jsonDecode(file('series_cache.json').readAsStringSync()), {'603': 2344});
    });
  });
}
