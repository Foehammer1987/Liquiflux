import 'dart:math';

import 'package:console_core/console_core.dart';
import 'package:test/test.dart';

PlexItem ep(String show, int n) => PlexItem(ratingKey: '$show-$n', key: '/library/metadata/$show-$n', type: 'episode', title: '$show $n', grandparentRatingKey: show, parentIndex: 1, index: n);
PlexItem clip(int n) => PlexItem(ratingKey: 'bump-$n', key: '/library/metadata/bump-$n', type: 'episode', title: 'Bump $n', parentIndex: 0);

ChannelPool pool({int big = 800, int small = 50, int bumpers = 5}) => ChannelPool(
  shows: {
    'simpsons': [for (var i = 0; i < big; i++) ep('simpsons', i)],
    'squidbillies': [for (var i = 0; i < small; i++) ep('squidbillies', i)],
    'venture': [for (var i = 0; i < small; i++) ep('venture', i)],
  },
  titles: const {'simpsons': 'The Simpsons', 'squidbillies': 'Squidbillies', 'venture': 'The Venture Bros.'},
  bumpers: [for (var i = 0; i < bumpers; i++) clip(i)],
);

const src = ChannelSource(kind: 'collection', key: '42', title: 'Adult Swim');
const bumps = ChannelSource(kind: 'show', key: '99', title: 'Adult Swim Bumpers');

Map<String, int> countShows(Iterable<ChannelSlot> slots) {
  final out = <String, int>{};
  for (final s in slots.where((s) => !s.bumper)) {
    out.update(s.item.grandparentRatingKey!, (v) => v + 1, ifAbsent: () => 1);
  }
  return out;
}

void main() {
  test('every show gets an equal turn by default, however many episodes it has', () {
    const rule = ChannelRule(id: 'a', name: 'Adult Swim', source: src);
    final slots = ChannelPicker(rule, pool(), ChannelProgress(), random: Random(1)).next(3000);
    final c = countShows(slots);
    for (final n in c.values) {
      expect(n, inInclusiveRange(850, 1150));
    }
  });

  test('a classic shuffle follows episode counts; weights change a show\'s share', () {
    final p = pool();
    expect(channelShares(const ChannelRule(id: 'a', name: '', source: src, evenShows: false), p)['simpsons'], closeTo(800 / 900, 1e-9));
    const weighted = ChannelRule(id: 'a', name: '', source: src, weights: {'simpsons': 3});
    expect(channelShares(weighted, p)['simpsons'], closeTo(0.6, 1e-9));
    final c = countShows(ChannelPicker(weighted, p, ChannelProgress(), random: Random(2)).next(3000));
    // The same show never plays twice running, which pulls a big share down a little.
    expect(c['simpsons']! / 3000, inInclusiveRange(0.42, 0.62));
    const off = ChannelRule(id: 'a', name: '', source: src, weights: {'venture': 0});
    expect(countShows(ChannelPicker(off, p, ChannelProgress(), random: Random(3)).next(200)).containsKey('venture'), isFalse);
  });

  test('no repeats until a show runs out, and never the same show twice running', () {
    const rule = ChannelRule(id: 'a', name: '', source: src);
    final slots = ChannelPicker(rule, pool(big: 100, small: 100), ChannelProgress(), random: Random(4)).next(30);
    expect(slots.map((s) => s.item.ratingKey).toSet().length, 30);
    for (var i = 1; i < slots.length; i++) {
      expect(slots[i].item.grandparentRatingKey, isNot(slots[i - 1].item.grandparentRatingKey));
    }
    // After that, each show starts over.
    final more = ChannelPicker(rule, pool(big: 2, small: 2), ChannelProgress(), random: Random(5)).next(12);
    expect(more.length, 12);
  });

  test('bumpers go first and between every N episodes, without repeats', () {
    const rule = ChannelRule(id: 'a', name: '', source: src, bumpers: bumps, bumperEvery: 2);
    final picker = ChannelPicker(rule, pool(bumpers: 3), ChannelProgress(), random: Random(6));
    final slots = picker.next(6);
    expect(slots.map((s) => s.bumper), [true, false, false, true, false, false, true, false, false]);
    expect(slots.where((s) => s.bumper).map((s) => s.item.ratingKey).toSet().length, 3);
    // The next block carries on the count.
    expect(picker.next(2).map((s) => s.bumper), [true, false, false]);
    const none = ChannelRule(id: 'b', name: '', source: src, bumpers: bumps, bumperFirst: false);
    expect(ChannelPicker(none, pool(), ChannelProgress(), random: Random(7)).next(2).map((s) => s.bumper), [false, true, false]);
    // No bumpers found: just episodes.
    expect(ChannelPicker(rule, pool(bumpers: 0), ChannelProgress()).next(3).every((s) => !s.bumper), isTrue);
  });

  test('carries on from the episode it was left on, and remembers what played', () {
    const rule = ChannelRule(id: 'a', name: '', source: src, bumpers: bumps);
    final p = pool(big: 3, small: 3);
    final progress = ChannelProgress();
    final first = ChannelPicker(rule, p, progress, random: Random(8)).next(4);
    for (final s in first.take(4)) {
      channelStarted(progress, p, s);
    }
    final playing = first.take(4).lastWhere((s) => !s.bumper).item;
    expect(progress.current, playing.ratingKey);
    final again = ChannelPicker(rule, p, progress, random: Random(9)).next(5, first: playing);
    expect(again.first.item.ratingKey, playing.ratingKey);
    final played = {for (final s in first.take(4)) s.item.ratingKey};
    // Nothing else that already played comes back while its show has episodes left.
    expect(again.skip(1).where((s) => !s.bumper).take(3).any((s) => played.contains(s.item.ratingKey)), isFalse);
  });

  test('rules and progress survive a round trip; bad files are ignored', () {
    const rule = ChannelRule(id: 'r1', name: 'Adult Swim', source: src, bumpers: bumps, bumperEvery: 3, bumperFirst: false, evenShows: false, weights: {'simpsons': 0.5});
    final back = ChannelRule.fromJson(rule.toJson())!;
    expect((back.name, back.source, back.bumpers, back.bumperEvery, back.bumperFirst, back.evenShows), (rule.name, src, bumps, 3, false, false));
    expect(back.weights, {'simpsons': 0.5});
    expect(ChannelRule.fromJson({'id': 'x', 'source': {'kind': 'nope', 'key': '1'}}), isNull);
    expect(ChannelRule.fromJson({'id': 'x', 'source': src.toJson(), 'bumperEvery': 999, 'weights': {'a': 1e9, 'b': 'x'}})!.bumperEvery, 10);
    final pr = ChannelProgress(played: {'s': {'1', '2'}}, bumpersPlayed: {'b'}, current: '2', lastShow: 's');
    final pb = ChannelProgress.fromJson(pr.toJson());
    expect(pb.played['s'], {'1', '2'});
    expect(pb.bumpersPlayed, {'b'});
    expect((pb.current, pb.lastShow), ('2', 's'));
    expect(ChannelProgress.fromJson('junk').played, isEmpty);
  });
}
