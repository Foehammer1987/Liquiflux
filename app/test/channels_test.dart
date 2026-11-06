import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:console_app/services/channels.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter_test/flutter_test.dart';

PlexItem ep(String show, int n) => PlexItem(ratingKey: '$show-$n', key: '/library/metadata/$show-$n', type: 'episode', title: '$show $n', grandparentRatingKey: show, parentIndex: 1, index: n);
PlexItem clip(int n) => PlexItem(ratingKey: 'bump-$n', key: '/library/metadata/bump-$n', type: 'episode', title: 'Bump $n');

const src = ChannelSource(kind: 'collection', key: '42', title: 'Adult Swim');
const bumps = ChannelSource(kind: 'show', key: '99', title: 'Bumpers');

ChannelPool pool() => ChannelPool(
  shows: {
    'a': [for (var i = 0; i < 20; i++) ep('a', i)],
    'b': [for (var i = 0; i < 20; i++) ep('b', i)],
  },
  titles: const {'a': 'A', 'b': 'B'},
  bumpers: [for (var i = 0; i < 4; i++) clip(i)],
);

void main() {
  test('a channel\'s line-up marks its bumpers and grows as it plays', () {
    const rule = ChannelRule(id: 'r', name: 'Adult Swim', sources: [src], bumpers: bumps);
    var saves = 0;
    final run = ChannelRun(rule, pool(), ChannelProgress(), random: Random(1), onChange: () => saves++);
    // Bumper, then episode and bumper in turn.
    expect(run.isBumperAt(0), isTrue);
    expect(run.isBumperAt(1), isFalse);
    expect(run.isBumperAt(2), isTrue);
    expect(run.isBumperAt(null), isFalse);
    expect(run.isBumperAt(999), isFalse);
    final start = run.queue.length;
    final queue = run.queue;
    for (var i = 0; i < start; i++) {
      run.started(i);
    }
    // The same list, longer: the open player keeps reading next from it.
    expect(identical(queue, run.queue), isTrue);
    expect(run.queue.length, greaterThan(start));
    expect(saves, start);
    expect(run.progress.current, isNotNull);
    expect(run.isBumperAt(run.queue.indexWhere((i) => i.ratingKey == run.progress.current)), isFalse);
  });

  test('channels are kept per server and survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('channels');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/channels.json');
    final store = ChannelStore(file: () async => file);
    await store.load('server-1');
    expect(store.rules, isEmpty);
    store.put(const ChannelRule(id: 'r', name: 'Adult Swim', sources: [src], bumpers: bumps, weights: {'a': 2}));
    store.progressOf('r')
      ..current = 'a-3'
      ..played['a'] = {'a-3'};
    await store.save();

    final again = ChannelStore(file: () async => file);
    await again.load('server-1');
    expect(again.rules.single.name, 'Adult Swim');
    expect(again.rules.single.weights, {'a': 2.0});
    expect(again.canResume('r'), isTrue);
    expect(again.progressOf('r').played['a'], {'a-3'});

    // Another server has its own channels, and the first server's stay in the file.
    await again.load('server-2');
    expect(again.rules, isEmpty);
    again.put(const ChannelRule(id: 's', name: 'Toonami', sources: [src]));
    await again.save();
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect((j['servers'] as Map).keys, containsAll(['server-1', 'server-2']));

    // A new source starts the channel afresh; deleting forgets it.
    await again.load('server-1');
    again.put(const ChannelRule(id: 'r', name: 'Adult Swim', sources: [ChannelSource(kind: 'label', key: '7', title: 'AS', section: '2')]));
    expect(again.canResume('r'), isFalse);
    again.remove('r');
    expect(again.rules, isEmpty);
  });

  test('a damaged file leaves the channels empty', () async {
    final dir = await Directory.systemTemp.createTemp('channels');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/channels.json')..writeAsStringSync('{not json');
    final store = ChannelStore(file: () async => file);
    await store.load('x');
    expect(store.rules, isEmpty);
    store.read({'rules': [{'id': 'a'}, 'junk', const ChannelRule(id: 'ok', name: 'n', sources: [src]).toJson()]});
    expect(store.rules.map((r) => r.id), ['ok']);
  });
}
