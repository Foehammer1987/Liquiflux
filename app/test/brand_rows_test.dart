import 'package:console_app/app_info.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/pages/trending_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

Future<void> settle(WidgetTester t, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openTrending(WidgetTester t) async {
  ShellNav.of(t.element(find.byType(HomePage))).go(const TrendingDest());
  await settle(t, 40);
  expect(find.byType(TrendingPage), findsOneWidget);
}

/// The App Store build (LIQUIFLUX_STORE=apple) has no rows named after streaming services on
/// Trending: no Netflix Top 10, no "Popular on ...", no "On Streaming" heading. Samsung keeps them.
void main() {
  test('only the Apple store build leaves the brand rows out', () {
    expect(brandRowsInBuild, storeBuild != 'apple');
  });

  testWidgets('with brand rows on, Trending has the streaming services', (t) async {
    await tvApp(t);
    await openTrending(t);
    expect(find.text('On Streaming'), findsOneWidget);
    expect(find.textContaining('Popular on '), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with brand rows off, Trending names no streaming service', (t) async {
    await tvApp(t, brandRows: false);
    await openTrending(t);
    expect(find.text('On Streaming'), findsNothing);
    expect(find.textContaining('Popular on '), findsNothing);
    expect(find.textContaining('Netflix'), findsNothing);
    // The genre charts are still there.
    expect(find.text('By Genre'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  for (final on in [true, false]) {
    testWidgets('Settings ${on ? 'has' : 'has no'} Streaming Region with brand rows ${on ? 'on' : 'off'}', (t) async {
      await tvApp(t, brandRows: on);
      ShellNav.of(t.element(find.byType(HomePage))).go(const SettingsDest());
      await settle(t, 30);
      expect(find.text('Discovery'), findsOneWidget);
      expect(find.text('Streaming Region'), on ? findsOneWidget : findsNothing);
      if (!on) expect(find.textContaining('Netflix'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  }
}
