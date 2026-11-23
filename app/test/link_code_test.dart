import 'package:console_app/platform.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_harness.dart';

/// Signing in on a computer can use a plex.tv/link code too (the browser may be on another
/// device); a TV always does, so it has no such button.
void main() {
  testWidgets('the welcome page offers a link code on a computer', (t) async {
    await tvApp(t, settle: 20, before: (s) => s.settings = const Settings(clientId: 'c'));
    expect(find.text('Sign In with Plex'), findsOneWidget);
    expect(find.text('Use a Link Code'), isTv ? findsNothing : findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
