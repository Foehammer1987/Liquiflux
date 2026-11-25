import 'package:console_app/app_info.dart';
import 'package:console_app/ui/channels/source_picker.dart';
import 'package:console_app/ui/collections/tv_collections_page.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Opens Channels > New Channel > Add, and returns the picker's tab names.
Future<List<String>> pickerTabs(WidgetTester t) async {
  ShellNav.of(t.element(find.byType(HomePage))).go(const ChannelsDest());
  await settle(t, 30);
  await t.tap(find.text('New Channel'));
  await settle(t);
  await t.tap(find.text('Add Shows and Collections'));
  await settle(t);
  expect(find.byType(SourcePicker), findsOneWidget);
  final picker = find.byType(SourcePicker);
  return [
    for (final n in ['Shows', 'Collections', 'Networks & Blocks', 'Labels', 'Libraries'])
      if (find.descendant(of: picker, matching: find.textContaining(n)).evaluate().isNotEmpty) n,
  ];
}

/// The Samsung and Apple store builds (LIQUIFLUX_STORE=samsung or apple) have no TV Networks: no rail item, no
/// page, no pack read or fetched, and no Networks & Blocks source for a channel.
void main() {
  test('only the Samsung and Apple store builds leave TV Networks out', () {
    expect(tvNetworksInBuild, storeBuild != 'samsung' && storeBuild != 'apple');
  });

  testWidgets('with TV Networks on, the rail, the page and the picker tab are there', (t) async {
    final app = await tvApp(t);
    expect(find.byKey(const ValueKey('rail-tip:TV Networks')), findsOneWidget);
    ShellNav.of(t.element(find.byType(HomePage))).go(const TvCollectionsDest());
    await settle(t, 30);
    expect(find.byType(TvCollectionsPage), findsOneWidget);
    expect(app.tvPack.now, isNotNull);
    ShellNav.of(t.element(find.byType(TvCollectionsPage))).go(const HomeDest());
    await settle(t);
    expect(await pickerTabs(t), contains('Networks & Blocks'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with TV Networks off, nothing of the pack shows or loads', (t) async {
    final app = await tvApp(t, tvNetworks: false);
    expect(find.byKey(const ValueKey('rail-tip:TV Networks')), findsNothing);
    // A stray way to the page (an old link) lands on Home instead.
    ShellNav.of(t.element(find.byType(HomePage))).go(const TvCollectionsDest());
    await settle(t, 30);
    expect(find.byType(TvCollectionsPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    ShellNav.of(t.element(find.byType(HomePage))).go(const TvCollectionDest('saturday'));
    await settle(t, 30);
    expect(find.byType(TvCollectionPage), findsNothing);

    final tabs = await pickerTabs(t);
    expect(tabs, isNot(contains('Networks & Blocks')));
    expect(tabs, contains('Shows'));

    // A channel's saved "pack" source plays nothing, and the pack was never read.
    expect(await app.packShows('saturday'), isEmpty);
    expect((await app.tvCollections()).pack.collections, isEmpty);
    expect(app.tvPack.now, isNull);
    await t.pumpWidget(const SizedBox());
  });
}
