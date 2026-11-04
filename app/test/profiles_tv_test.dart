import 'package:console_app/platform.dart';
import 'package:console_app/ui/profiles.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

const _sam = PlexHomeUser(uuid: 'aaaa1111', title: 'Sam', admin: true);
const _kid = PlexHomeUser(uuid: 'bbbb2222', title: 'Kid', protected: true);

/// The remote reaches the profile button in the rail, starts on whoever's watching, and gets
/// into the PIN pad and back out. Run as a TV: CONSOLE_TV=1 flutter test test/profiles_tv_test.dart
void main() {
  testWidgets('profiles by remote: rail button, picker, PIN pad and Back', skip: !isTv, (t) async {
    await tvApp(
      t,
      before: (app) {
        app.homeList = const [_sam, _kid];
        app.settings = app.settings.copyWith(plexOwnerId: _sam.uuid);
      },
    );
    // Into the rail and down to the avatar above Settings.
    await press(t, LogicalKeyboardKey.arrowLeft);
    for (var i = 0; i < 20 && focused() != 'rail:profile'; i++) {
      await press(t, LogicalKeyboardKey.arrowDown, wait: const Duration(milliseconds: 250));
    }
    expect(focused(), 'rail:profile');
    await press(t, LogicalKeyboardKey.select, wait: const Duration(milliseconds: 900));
    expect(find.byType(ProfilePicker), findsOneWidget);
    expect(focused(), 'profile ${_sam.uuid}', reason: 'starts on whoever is watching');

    await press(t, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'profile ${_kid.uuid}');
    await press(t, LogicalKeyboardKey.select);
    expect(find.text('Enter Kid’s PIN'), findsOneWidget);
    expect(focused(), 'pin 1');

    // The remote's Back reaches a dialog as Android's system Back.
    Future<void> back() async {
      await t.binding.handlePopRoute();
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    await back();
    expect(find.text('Enter Kid’s PIN'), findsNothing);
    expect(find.byType(ProfilePicker), findsOneWidget);
    expect(focused(), 'profile ${_kid.uuid}');

    await back();
    expect(find.byType(ProfilePicker), findsNothing);
  });
}
