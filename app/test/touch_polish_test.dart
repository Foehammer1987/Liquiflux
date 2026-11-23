// 1.1.8's phone polish: the title page on a phone on its side, Home's spotlight and Continue
// Watching on a phone, the player's settings as a bottom sheet on a narrow screen, the
// long-press menu on posters, the scrubber's chapter ticks, bounce scrolling on Apple, and
// the player gestures' setting.
//
// The layout tests need CONSOLE_TOUCH=1; the rest run anywhere.
import 'package:console_app/platform.dart';
import 'package:console_app/services/playback_prefs.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/pages/player_page.dart';
import 'package:console_app/ui/player/seek_bar.dart';
import 'package:console_app/ui/poster_menu.dart';
import 'package:console_app/ui/touch.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

PlexItem _item(String type, {int? viewCount, int? leafCount, int? viewedLeafCount, String? show, String? season}) => PlexItem(
  ratingKey: '1',
  key: '/library/metadata/1',
  type: type,
  title: 'T',
  viewCount: viewCount,
  leafCount: leafCount,
  viewedLeafCount: viewedLeafCount,
  grandparentRatingKey: show,
  parentRatingKey: season,
);

void main() {
  group('long-press menu', () {
    test('a film: play, mark watched, more info', () {
      expect(posterActions(_item('movie')), [PosterAction.play, PosterAction.markWatched, PosterAction.info]);
      expect(posterActions(_item('movie', viewCount: 1)), contains(PosterAction.markUnwatched));
    });

    test('an episode: also its show and season', () {
      expect(posterActions(_item('episode', show: '10', season: '11')), [PosterAction.play, PosterAction.markWatched, PosterAction.goToShow, PosterAction.goToSeason, PosterAction.info]);
    });

    test('a show watched to the end can be marked unwatched; a season goes to its show', () {
      expect(posterActions(_item('show', leafCount: 8, viewedLeafCount: 8)), contains(PosterAction.markUnwatched));
      expect(posterActions(_item('season', season: '10')), contains(PosterAction.goToShow));
    });

    test('anything else: just the title page', () {
      expect(posterActions(_item('collection')), [PosterAction.info]);
    });
  });

  test('the player\'s settings come up from the bottom only on a narrow touch screen held upright', () {
    expect(playerSheetFromBottom(const Size(402, 874), touch: true), isTrue);
    expect(playerSheetFromBottom(const Size(320, 1024), touch: true), isTrue, reason: 'iPad Slide Over');
    expect(playerSheetFromBottom(const Size(874, 402), touch: true), isFalse, reason: 'a phone on its side');
    expect(playerSheetFromBottom(const Size(1180, 820), touch: true), isFalse, reason: 'a tablet');
    expect(playerSheetFromBottom(const Size(402, 874), touch: false), isFalse, reason: 'a computer window');
  });

  test('Home\'s phone spotlight leaves room for the whole Continue Watching row', () {
    for (final page in const [Size(402, 782), Size(375, 575), Size(440, 830)]) {
      final h = phoneSpotlightHeight(page, TextScaler.noScaling);
      final row = page.height - h;
      expect(row, greaterThanOrEqualTo(phoneContinueWidth * ConsoleDensity.compactScale * 9 / 16 + 60), reason: '$page');
      expect(h, greaterThanOrEqualTo(page.width * 0.9), reason: 'never shorter than a square: $page');
    }
    // Larger text takes more room under the cards.
    expect(phoneSpotlightHeight(const Size(402, 660), const TextScaler.linear(1.3)), lessThan(phoneSpotlightHeight(const Size(402, 660), TextScaler.noScaling)));
  });

  test('the scrubber knows which chapter a moment falls in', () {
    final chapters = [PlexChapter(title: 'A', startMs: 0, endMs: 1000), PlexChapter(title: 'B', startMs: 1000, endMs: 2000)];
    expect(chapterIndexAt(chapters, const Duration(milliseconds: 500)), 0);
    expect(chapterIndexAt(chapters, const Duration(milliseconds: 1500)), 1);
    expect(chapterIndexAt(const [], const Duration(seconds: 1)), -1);
  });

  test('player gestures are on unless turned off, and the choice is kept', () {
    expect(const PlaybackPrefs().gestures, isTrue);
    expect(PlaybackPrefs.fromJson(const PlaybackPrefs(gestures: false).toJson()).gestures, isFalse);
    expect(PlaybackPrefs.fromJson(const {}).gestures, isTrue);
  });

  testWidgets('Apple platforms bounce at the ends of a list; Android keeps its own', (t) async {
    final physics = <TargetPlatform, ScrollPhysics>{};
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.android]) {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          // The theme's platform is the device's (the app never overrides the scroll behaviour).
          theme: ConsoleTheme.dark().copyWith(platform: platform),
          home: Builder(
            builder: (context) {
              physics[platform] = ScrollConfiguration.of(context).getScrollPhysics(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(physics[TargetPlatform.iOS], isA<BouncingScrollPhysics>());
    expect(physics[TargetPlatform.macOS], isA<BouncingScrollPhysics>());
    expect(physics[TargetPlatform.android], isNot(isA<BouncingScrollPhysics>()));
  });

  group('phone layout', () {
    testWidgets('a title on a phone on its side: the poster beside the details', (t) async {
      await touchApp(t, size: const Size(874, 402), padding: const EdgeInsets.only(left: 62, right: 62, bottom: 21));
      ShellNav.of(t.element(find.descendant(of: find.byType(ShellNav), matching: find.byType(Navigator)).first)).push(const ItemDest('1'));
      for (var i = 0; i < 15; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      final poster = t.getRect(find.byType(ArtFrame).first);
      final title = t.getRect(find.text('Film 1').first);
      expect(title.left, greaterThan(poster.right), reason: 'beside it, not under it');
      expect(title.top, lessThan(poster.bottom));
      expect(poster.height, lessThan(260), reason: 'small enough to leave the buttons in view');
      expect(t.takeException(), isNull);
    });

    testWidgets('Home on a phone: the whole Continue Watching row shows without scrolling', (t) async {
      await touchApp(t);
      final heading = find.text('Continue Watching');
      expect(heading, findsOneWidget);
      final bar = t.getRect(find.byType(TouchBar));
      // The first card's caption is above the bottom bar.
      final firstCard = find.descendant(of: find.ancestor(of: heading, matching: find.byType(Shelf)), matching: find.byType(PosterCard)).first;
      expect(t.getRect(firstCard).bottom, lessThanOrEqualTo(bar.top));
      // More than two cards across.
      expect(t.getRect(firstCard).width, lessThan(402 / 2.2));
      expect(t.takeException(), isNull);
    });

    testWidgets('a long press on a poster opens its menu', (t) async {
      await touchApp(t);
      final poster = find.byType(PosterCard).first;
      await t.ensureVisible(poster);
      await t.longPress(poster);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(ListTile, 'More Info'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Mark as Watched').evaluate().length + find.widgetWithText(ListTile, 'Mark as Unwatched').evaluate().length, 1);
      expect(t.takeException(), isNull);
    });
  }, skip: !isTouch);
}
