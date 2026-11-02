import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: ConsoleTheme.dark(),
  home: Scaffold(body: SizedBox(width: 600, child: child)),
);

void main() {
  tearDown(forgetSecrets);

  testWidgets('ErrorNote scrubs credentials even when a caller forgets errorText', (t) async {
    rememberSecret('s3cretPlexToken');
    await t.pumpWidget(
      wrap(
        const ErrorNote(
          'ClientException: Connection refused, uri=http://10.0.0.5:32400/library/sections?X-Plex-Token=abc123def&x=1 '
          'http://me:hunter2@seerr.example.com s3cretPlexToken',
        ),
      ),
    );
    final shown = t.widget<Text>(find.byType(Text).first).data!;
    expect(shown, isNot(contains('abc123def')));
    expect(shown, isNot(contains('hunter2')));
    expect(shown, isNot(contains('s3cretPlexToken')));
    expect(shown, contains('Connection refused'));
  });
}
