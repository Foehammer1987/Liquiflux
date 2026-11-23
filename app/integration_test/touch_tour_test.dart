// The phone and tablet app on a simulator or device, page by page, for screenshots and a
// look at every screen: run it with tools/ios-tour.sh, which launches it on a simulator and
// takes a screenshot at each "SHOT name" line this prints.
//
// Signed in (the fake servers of tools/mock-servers.mjs, given through the environment as for
// any dev build): Home, a library, a title page, search, the More sheet, Settings and About,
// the player, then Home on its side. Signed out (TOUR=welcome): the welcome page, the link
// code page and the browser sign-in.
import 'dart:async';

import 'package:console_app/main.dart' as app;
import 'package:console_app/state/scope.dart';
import 'package:console_app/ui/settings/plex_link_code.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/play.dart';
import 'package:console_app/ui/player/seek_bar.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tour = String.fromEnvironment('TOUR', defaultValue: 'app');

/// The fake servers (tools/mock-servers.mjs). A simulator reaches the Mac at localhost.
const _plex = String.fromEnvironment('MOCK_PLEX', defaultValue: 'http://localhost:9001');
const _seerr = String.fromEnvironment('MOCK_SEERR', defaultValue: 'http://localhost:9002');

/// TOUR=signin: the server to pick when the account has more than one.
const _server = String.fromEnvironment('SERVER');

/// TOUR=real: parts to leave out on a second run (comma-separated: pages, hd-panels).
final _skip = const String.fromEnvironment('SKIP').split(',');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Real time passes (the app's own timers, the network) while frames are drawn.
  Future<void> wait(WidgetTester t, double seconds) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Asks tools/ios-tour.sh for a screenshot, and gives it time to take one.
  Future<void> shot(WidgetTester t, String name) async {
    await wait(t, 1.5);
    debugPrint('SHOT $name');
    await wait(t, 2.5);
  }

  Future<bool> tapText(WidgetTester t, String text) async {
    // Scrolled into view first when it's further down a list.
    final anywhere = find.text(text, skipOffstage: false);
    if (anywhere.evaluate().isNotEmpty) {
      await t.ensureVisible(anywhere.first);
      await wait(t, 0.6);
    }
    final f = find.text(text, skipOffstage: true);
    if (f.evaluate().isEmpty) {
      debugPrint('TOUR: no "$text" on screen');
      return false;
    }
    await t.tap(f.first, warnIfMissed: false);
    return true;
  }

  Size screen(WidgetTester t) => t.view.physicalSize / t.view.devicePixelRatio;

  /// A finger drag up the middle of the screen (the page scrolls).
  Future<void> scrollUp(WidgetTester t, double by) async {
    final s = screen(t);
    await t.dragFrom(Offset(s.width / 2, s.height * 0.7), Offset(0, -by));
  }

  ShellNav nav(WidgetTester t) => ShellNav.of(t.element(find.descendant(of: find.byType(ShellNav), matching: find.byType(Navigator)).first));

  testWidgets('signed out: welcome, link code, browser sign-in', (t) async {
    unawaited(app.main());
    await wait(t, 9);
    await shot(t, 'welcome');
    if (await tapText(t, 'Use a Link Code')) {
      await wait(t, 4);
      await shot(t, 'link-code');
      await tapText(t, 'Cancel');
      await wait(t, 2);
    }
    if (await tapText(t, 'Enter Address Manually')) {
      await wait(t, 2);
      await shot(t, 'welcome-manual');
      final field = find.byType(EditableText);
      if (field.evaluate().isNotEmpty) {
        await t.tap(field.first, warnIfMissed: false);
        await wait(t, 2);
        await shot(t, 'welcome-keyboard');
        FocusManager.instance.primaryFocus?.unfocus();
        await wait(t, 1);
      }
    }
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
    await wait(t, 2);
    await shot(t, 'welcome-landscape');
    await SystemChrome.setPreferredOrientations(const []);
  }, skip: _tour != 'welcome', timeout: const Timeout(Duration(minutes: 5)));

  // TOUR=signin: a real sign-in with a link code (printed as "CODE ABCD"), waited for up to
  // 15 minutes. The sign-in stays in the simulator for TOUR=real runs afterwards.
  testWidgets('link code sign-in', (t) async {
    unawaited(app.main());
    await wait(t, 9);
    final state = AppScope.read(t.element(find.byType(Navigator).first));
    if (!state.settings.plexReady) {
      expect(await tapText(t, 'Use a Link Code'), isTrue);
      String? code;
      for (var i = 0; i < 60 && code == null; i++) {
        await wait(t, 0.5);
        final f = find.byType(PlexLinkCode);
        if (f.evaluate().isNotEmpty) code = t.widget<PlexLinkCode>(f).code;
      }
      debugPrint('CODE $code');
      await shot(t, 'link-code-real');
      // Up to an hour, with a new code each time one runs out.
      final end = DateTime.now().add(const Duration(minutes: 60));
      while (!state.settings.plexReady && DateTime.now().isBefore(end)) {
        await wait(t, 2);
        if (_server.isNotEmpty && find.text('Choose a server').evaluate().isNotEmpty) {
          await tapText(t, _server);
          await wait(t, 6);
          continue;
        }
        final f = find.byType(PlexLinkCode);
        if (f.evaluate().isNotEmpty && t.widget<PlexLinkCode>(f).expired) {
          await tapText(t, 'Get a New Code');
          await wait(t, 4);
          if (f.evaluate().isNotEmpty) debugPrint('CODE ${t.widget<PlexLinkCode>(f).code}');
        }
      }
    }
    debugPrint(state.settings.plexReady ? 'SIGNED IN' : 'NOT SIGNED IN');
    await wait(t, 12);
    await shot(t, 'real-home');
  }, skip: _tour != 'signin', timeout: const Timeout(Duration(minutes: 70)));

  // TOUR=real, after TOUR=signin on the same simulator (run with --no-uninstall): the
  // viewer's own server. Pages, then playback: a 1080p and a 4K HDR film played directly, a
  // 720p conversion, an anime episode with ASS subtitles, the pickers, scrubbing, turning the
  // phone round and leaving the app mid-film ("HOST bg" / "HOST fg" ask tools/ios-tour.sh).
  testWidgets('real server', (t) async {
    unawaited(app.main());
    await wait(t, 15);
    final state = AppScope.read(t.element(find.byType(Navigator).first));
    debugPrint('TOUR: signed in ${state.settings.plexReady}, ${state.sections.length} libraries');
    final plex = state.plex!;
    final movies = state.sections.firstWhere((s) => s.type == 'movie');
    if (!_skip.contains('pages')) {
      await shot(t, 'real-home');
      await scrollUp(t, 700);
      await shot(t, 'real-home-rows');
      nav(t).go(LibraryDest(movies.key));
      await wait(t, 5);
      await shot(t, 'real-library');
      nav(t).go(const SearchDest('the'));
      await wait(t, 6);
      await shot(t, 'real-search');
    }

    // Titles to play, from the films library.
    final all = (await plex.sectionItems(movies.key, size: 600)).items;
    PlexItem? hd, uhdHdr;
    for (final it in all) {
      final r = it.media.isEmpty ? null : it.media.first.videoResolution;
      if (hd == null && r == '1080') hd = it;
      if (uhdHdr == null && r == '4k') {
        final full = await plex.metadata(it.ratingKey, full: true);
        final video = full?.media.first.streams.where((s) => s.streamType == 1).firstOrNull;
        final name = '${video?.displayTitle} ${video?.title}';
        if (name.contains('HDR') || name.contains('DoVi') || name.contains('Dolby Vision')) uhdHdr = full;
      }
      if (hd != null && uhdHdr != null) break;
    }
    debugPrint('TOUR: 1080p ${hd?.title}, 4K HDR ${uhdHdr?.title}');

    Future<void> playFor(String name, PlexItem item, {Future<void> Function()? during}) async {
      nav(t).push(ItemDest(item.ratingKey));
      await wait(t, 4);
      if (name == 'hd') await shot(t, 'real-detail');
      unawaited(playTitle(t.element(find.byType(Navigator).first), item, resume: false));
      await wait(t, 25);
      await t.tapAt(screen(t).center(Offset.zero));
      await wait(t, 1);
      await shot(t, 'real-play-$name');
      await during?.call();
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await wait(t, 5);
    }

    Future<void> openPanel(String tooltip, String shotName) async {
      await t.tapAt(screen(t).center(Offset.zero));
      await wait(t, 1);
      final f = find.byTooltip(tooltip);
      if (f.evaluate().isEmpty) return debugPrint('TOUR: no $tooltip');
      await t.tap(f.first, warnIfMissed: false);
      await wait(t, 2);
      await shot(t, shotName);
    }

    Future<void> hdPanels() async {
      // Scrub a third of the way along.
      final bar = find.byType(SeekBar);
      if (bar.evaluate().isNotEmpty) {
        final r = t.getRect(bar.first);
        await t.dragFrom(Offset(r.left + 2, r.center.dy), Offset(r.width / 3, 0));
        await wait(t, 10);
        await t.tapAt(screen(t).center(Offset.zero));
        await wait(t, 1);
        await shot(t, 'real-play-hd-scrubbed');
      }
      await openPanel('Audio (A)', 'real-audio');
      await openPanel('Subtitles (C)', 'real-subtitles');
      // The other way round, then back.
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeRight]);
      await wait(t, 4);
      await shot(t, 'real-play-hd-rotated');
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }

    if (hd != null) {
      await playFor('hd', hd, during: () async {
        if (!_skip.contains('hd-panels')) await hdPanels();
        // Leave the app mid-film and come back.
        debugPrint('HOST bg');
        await wait(t, 20);
        await t.tapAt(screen(t).center(Offset.zero));
        await wait(t, 1);
        await shot(t, 'real-play-hd-back');
        // A 720p conversion.
        await openPanel('Playback Settings', 'real-quality');
        if (await tapText(t, '720p · 2 Mbps')) {
          await wait(t, 25);
          await t.tapAt(screen(t).center(Offset.zero));
          await wait(t, 1);
          await shot(t, 'real-play-720p');
          await openPanel('Playback Settings', 'real-quality-720p');
          await tapText(t, 'Original');
          await wait(t, 3);
        }
      });
    }
    if (uhdHdr != null && !_skip.contains('4k')) await playFor('4k-hdr', uhdHdr);

    // An anime episode with ASS subtitles.
    PlexItem? anime;
    for (final sec in state.sections.where((s) => s.type == 'show')) {
      final shows = (await plex.sectionItems(sec.key, size: 600)).items.where((i) => i.genres.any((g) => g.toLowerCase().contains('anim'))).take(25);
      for (final show in shows) {
        final eps = await plex.episodes(show.ratingKey);
        if (eps.isEmpty) continue;
        final full = await plex.metadata(eps.first.ratingKey, full: true);
        if (full != null && full.media.isNotEmpty && full.media.first.streams.any((s) => s.streamType == 3 && (s.codec == 'ass' || s.codec == 'ssa'))) {
          anime = full;
          break;
        }
      }
      if (anime != null) break;
    }
    debugPrint('TOUR: anime with ASS ${anime?.grandparentTitle} ${anime?.title}');
    if (anime != null) {
      await playFor('anime-ass', anime, during: () async {
        await openPanel('Subtitles (C)', 'real-anime-subtitles');
        await tapText(t, 'English / ASS [choom]');
        await wait(t, 4);
        // A tap on the picture beside the panel closes it.
        await t.tapAt(Offset(screen(t).width * 0.2, screen(t).height * 0.5));
        // Into the episode, where people talk.
        await wait(t, 3);
        final bar = find.byType(SeekBar);
        if (bar.evaluate().isNotEmpty) {
          final r = t.getRect(bar.first);
          await t.dragFrom(Offset(r.left + 2, r.center.dy), Offset(r.width * 0.12, 0));
        }
        await wait(t, 15);
        await shot(t, 'real-anime-ass');
      });
    }
    await SystemChrome.setPreferredOrientations(const []);
    debugPrint('TOUR: done');
  }, skip: _tour != 'real', timeout: const Timeout(Duration(minutes: 25)));

  // TOUR=polish, against the fake servers: the screens the phone layout work changes (Home's
  // top, a film and a show on their side, the player's panels upright and on its side).
  testWidgets('phone polish', (t) async {
    unawaited(app.main());
    await wait(t, 9);
    final state = AppScope.read(t.element(find.byType(Navigator).first));
    await state.update(state.settings.copyWith(plexUrl: _plex, plexToken: 'x', seerrUrl: _seerr, seerrApiKey: 'x', seerrEnabled: true));
    await wait(t, 10);
    await shot(t, 'home');
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
    await wait(t, 2);
    nav(t).push(const ItemDest('100'));
    await wait(t, 5);
    await shot(t, 'film-sideways');
    await scrollUp(t, 250);
    await wait(t, 1.5);
    await shot(t, 'film-sideways-scrolled');
    nav(t).push(const ItemDest('200'));
    await wait(t, 5);
    await shot(t, 'show-sideways');
    // The player, its quality panel on its side, then upright.
    nav(t).push(const ItemDest('100'));
    await wait(t, 4);
    unawaited(playTitle(t.element(find.byType(Navigator).first), (await state.plex!.metadata('100'))!, resume: false));
    await wait(t, 10);
    await t.tapAt(screen(t).center(Offset.zero));
    await wait(t, 1);
    final settings = find.byTooltip('Playback Settings');
    if (settings.evaluate().isNotEmpty) await t.tap(settings.first, warnIfMissed: false);
    await wait(t, 2);
    await shot(t, 'player-panel-sideways');
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    await wait(t, 4);
    await shot(t, 'player-panel-upright');
    await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await wait(t, 3);
    await SystemChrome.setPreferredOrientations(const []);
    await wait(t, 2);
  }, skip: _tour != 'polish', timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('signed in: every page', (t) async {
    unawaited(app.main());
    await wait(t, 9);
    // Signed in as with Enter Address Manually.
    final state = AppScope.read(t.element(find.byType(Navigator).first));
    await state.update(state.settings.copyWith(plexUrl: _plex, plexToken: 'x', seerrUrl: _seerr, seerrApiKey: 'x', seerrEnabled: true));
    await wait(t, 8);
    await shot(t, 'home');
    await scrollUp(t, 600);
    await wait(t, 2);
    await shot(t, 'home-rows');

    nav(t).go(const LibraryDest('1'));
    await wait(t, 4);
    await shot(t, 'library');

    nav(t).push(const ItemDest('100'));
    await wait(t, 5);
    await shot(t, 'detail');
    await scrollUp(t, 500);
    await wait(t, 2);
    await shot(t, 'detail-more');

    nav(t).go(const SearchDest('the'));
    await wait(t, 4);
    await shot(t, 'search');
    // The search field and the keyboard.
    if (await tapText(t, 'Search')) {
      await wait(t, 2);
      await shot(t, 'search-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(t, 1);
    }

    nav(t).go(const HomeDest());
    await wait(t, 2);
    if (await tapText(t, 'More')) {
      await wait(t, 2);
      await shot(t, 'more-sheet');
      await t.tapAt(const Offset(20, 120));
      await wait(t, 1);
    }

    nav(t).go(const SettingsDest());
    await wait(t, 3);
    await shot(t, 'settings');
    if (await tapText(t, 'Advanced')) {
      await wait(t, 2);
      for (var i = 0; i < 6; i++) {
        await scrollUp(t, 500);
        await wait(t, 0.3);
      }
      await wait(t, 2);
      await shot(t, 'settings-about');
    }

    nav(t).push(const ItemDest('100'));
    await wait(t, 4);
    if (await tapText(t, 'Play') || await tapText(t, 'Resume')) {
      await wait(t, 8);
      await t.tapAt(t.view.physicalSize.center(Offset.zero) / t.view.devicePixelRatio);
      await wait(t, 1);
      await shot(t, 'player');
      // Leaves as its back button does.
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await wait(t, 4);
    }

    nav(t).go(const HomeDest());
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
    await wait(t, 3);
    await shot(t, 'home-landscape');
    nav(t).push(const ItemDest('100'));
    await wait(t, 4);
    await shot(t, 'detail-landscape');
    await SystemChrome.setPreferredOrientations(const []);
    await wait(t, 2);
  }, skip: _tour != 'app', timeout: const Timeout(Duration(minutes: 8)));
}
