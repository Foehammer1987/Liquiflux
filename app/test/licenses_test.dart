import 'package:console_app/app_info.dart';
import 'package:console_app/services/native_licenses.dart';
import 'package:console_app/ui/nav.dart';
import 'package:console_app/ui/pages/home_page.dart';
import 'package:console_app/ui/settings/licenses_view.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Settings > Advanced > About: the Open-Source Licenses page (with the player's native
/// libraries) and the privacy policy.
void main() {
  test('the player\'s native libraries: none on a Samsung TV, FFmpeg as LGPL 3 on Apple, AetherEngine on an Apple TV', () async {
    expect(nativeLicenses(tizen: true), isEmpty);
    final tv = nativeLicenses(tizen: false, tvos: true);
    expect(tv.map((l) => l.name), containsAll(['AetherEngine', 'FFmpeg', 'dav1d', 'libdovi']));
    final apple = nativeLicenses(apple: true, tizen: false, tvos: false);
    final ffmpeg = apple.firstWhere((l) => l.name == 'FFmpeg');
    expect(ffmpeg.files, containsAll(['LGPL-3.0.txt', 'GPL-3.0.txt']));
    expect(apple.map((l) => l.name), containsAll(['mpv', 'Mbed TLS', 'dav1d', 'libass', 'FreeType']));
    final other = nativeLicenses(apple: false, tizen: false, tvos: false);
    expect(other.map((l) => l.name), ['mpv', 'FFmpeg']);
    expect(other.last.files, contains('LGPL-2.1.txt'));
    // Every file named is in the app's assets.
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final f in {for (final l in [...apple, ...other, ...tv]) ...l.files}) {
      expect(await rootBundle.loadString('assets/licenses/$f'), isNotEmpty, reason: f);
    }
  });

  test('the privacy policy is one https address', () {
    expect(Uri.parse(privacyPolicyUrl).scheme, 'https');
  });

  testWidgets('Advanced > About opens the licenses; a package shows its text; Back returns to the list', (t) async {
    registerNativeLicenses();
    await tvApp(t);
    ShellNav.of(t.element(find.byType(HomePage))).go(const SettingsDest());
    await settle(t);
    await t.tap(find.text('Advanced'));
    await settle(t);
    expect(find.text('Privacy Policy'), findsOneWidget);
    await t.ensureVisible(find.text('Open-Source Licenses'));
    await settle(t, 5);
    await t.tap(find.byWidgetPredicate((w) => w is ConsoleButton && w.label == 'View'));
    await settle(t);
    expect(find.byType(LicensesView), findsOneWidget);
    // Reading the registry is real work (Flutter's own NOTICES asset too).
    for (var i = 0; i < 50 && find.byType(LoadingNote).evaluate().isNotEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    final list = find.descendant(of: find.byType(LicensesView), matching: find.byType(Scrollable));
    final ffmpeg = find.descendant(of: find.byType(LicensesView), matching: find.text('FFmpeg'));
    await t.scrollUntilVisible(ffmpeg, 200, scrollable: list.first);
    await t.tap(ffmpeg);
    await settle(t);
    expect(find.textContaining('GNU LESSER GENERAL PUBLIC LICENSE'), findsOneWidget);

    // The text has focus: Down scrolls it.
    final scroll = t.widget<SingleChildScrollView>(find.descendant(of: find.byType(LicensesView), matching: find.byType(SingleChildScrollView)));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(t, 5);
    expect(scroll.controller!.offset, greaterThan(0));

    // Escape (a remote's Back) goes back to the list, then closes.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(find.byType(LicensesView), findsOneWidget);
    expect(find.text('FFmpeg'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(find.byType(LicensesView), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
