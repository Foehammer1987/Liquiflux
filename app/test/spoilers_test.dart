import 'package:console_app/ui/detail/episode_list.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PlexItem _ep(int index, {bool watched = false}) => PlexItem.fromJson({
  'ratingKey': '$index',
  'type': 'episode',
  'title': 'Twist $index',
  'index': index,
  'parentIndex': 1,
  'summary': 'Everyone was a ghost in $index.',
  'viewCount': watched ? 1 : 0,
});

void main() {
  Future<void> list(WidgetTester tester, SpoilerPrefs spoilers) => tester.pumpWidget(
    MaterialApp(
      theme: ConsoleTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: EpisodeList(episodes: [_ep(1, watched: true), _ep(2)], spoilers: spoilers, imageUrl: (_) => null, onOpen: (_) {}, onPlay: (_) {}),
        ),
      ),
    ),
  );

  testWidgets('with spoilers hidden, unwatched episodes keep their name and story back until asked', (tester) async {
    await list(tester, const SpoilerPrefs(images: true, summaries: true, titles: true));
    // Watched: everything shows.
    expect(find.text('1. Twist 1'), findsOneWidget);
    expect(find.text('Everyone was a ghost in 1.'), findsOneWidget);
    // Unwatched: a plain name and a hidden story.
    expect(find.textContaining('Twist 2'), findsNothing);
    expect(find.text('Episode 2'), findsOneWidget);
    expect(find.text('Everyone was a ghost in 2.'), findsNothing);
    await tester.tap(find.textContaining('Story hidden'));
    await tester.pump();
    expect(find.text('Everyone was a ghost in 2.'), findsOneWidget);
  });

  testWidgets('with spoilers shown, nothing is held back', (tester) async {
    await list(tester, const SpoilerPrefs());
    expect(find.text('2. Twist 2'), findsOneWidget);
    expect(find.text('Everyone was a ghost in 2.'), findsOneWidget);
    expect(find.textContaining('Story hidden'), findsNothing);
  });
}
