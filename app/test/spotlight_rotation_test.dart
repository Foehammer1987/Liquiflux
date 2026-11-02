import 'package:console_app/services/trailers.dart';
import 'package:console_app/ui/home/spotlight.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// No title has a trailer, so no player is ever made.
class _NoTrailers extends Trailers {
  _NoTrailers(PlexClient plex) : super(plex: plex);
  @override
  Future<TrailerClip?> forItem(PlexItem item) async => null;
}

PlexItem _movie(int i) => PlexItem.fromJson({'ratingKey': '$i', 'type': 'movie', 'title': 'Film $i', 'year': 2000 + i});

String? _focused() => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  Future<void> spotlight(WidgetTester t, {required bool trailersOn}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final plex = PlexClient(baseUrl: 'http://10.0.0.2:32400', token: 'tok', clientId: 'c');
    await t.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(),
        home: Scaffold(
          body: Spotlight(
            items: [_movie(1), _movie(2), _movie(3)],
            preview: ValueNotifier(null),
            height: 700,
            active: true,
            plex: plex,
            trailers: _NoTrailers(plex),
            trailersOn: trailersOn,
            focusOnly: true,
            onPlay: (_) async {},
            onInfo: (_) {},
          ),
        ),
      ),
    );
    await t.pump();
  }

  Future<void> focusPlay(WidgetTester t) async {
    final node = Focus.of(t.element(find.text('Play').first));
    node.requestFocus();
    await t.pump();
    expect(_focused(), 'spotlight play');
  }

  testWidgets('with trailers on, the spotlight keeps rotating under focus and focus follows to the next Play', (t) async {
    await spotlight(t, trailersOn: true);
    await focusPlay(t);
    expect(find.text('Film 1'), findsOneWidget);
    // A title without a trailer moves on after the usual 9 s.
    await t.pump(const Duration(seconds: 9));
    await t.pump(const Duration(seconds: 1));
    // Past the old title's fade-out.
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Film 2'), findsOneWidget);
    expect(find.text('Film 1'), findsNothing);
    expect(_focused(), 'spotlight play');
    // The new title's own button has focus, not the old one fading out.
    expect(Focus.of(t.element(find.text('Play'))).hasFocus, isTrue);
    await t.pump(const Duration(seconds: 9));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Film 3'), findsOneWidget);
    expect(_focused(), 'spotlight play');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('with trailers off, the title holds while a button has focus', (t) async {
    await spotlight(t, trailersOn: false);
    await focusPlay(t);
    await t.pump(const Duration(seconds: 20));
    expect(find.text('Film 1'), findsOneWidget);
    expect(_focused(), 'spotlight play');
  });
}
