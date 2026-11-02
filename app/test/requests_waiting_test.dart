import 'package:console_app/state/app_state.dart';
import 'package:console_app/ui/request_list.dart';
import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a title not out on streaming shows its date and no bar', (t) async {
    final digital = DateTime.now().add(const Duration(days: 30));
    final d = SeerrResult.fromJson({
      'id': 1,
      'mediaType': 'movie',
      'title': 'Coming Soon',
      'releases': {
        'results': [
          {
            'iso_3166_1': 'US',
            'release_dates': [
              {'type': 4, 'release_date': '${digital.toIso8601String().substring(0, 10)}T00:00:00.000Z'},
            ],
          },
        ],
      },
    });
    final r = SeerrRequest.fromJson({
      'id': 5,
      'status': RequestStatus.approved,
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'movie',
      'media': {'tmdbId': 1, 'mediaType': 'movie', 'status': MediaStatus.processing},
    });
    final row = RequestRow(r, d);
    expect(row.state.notOnStreaming, isTrue);
    await t.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(),
        home: Scaffold(body: SizedBox(width: 900, child: RequestList(rows: [row]))),
      ),
    );
    expect(find.text('Coming Soon'), findsOneWidget);
    expect(find.text(notOnStreamingLabel), findsOneWidget);
    expect(find.text(formatShortDate(DateTime(digital.year, digital.month, digital.day))), findsOneWidget);
    expect(find.textContaining('Digital release'), findsOneWidget);
    expect(find.byType(RequestProgress), findsNothing);
  });

  testWidgets('Down from the filter lands on the first row, wherever its title sits', (t) async {
    RequestRow row(int id, String title) => RequestRow(
      SeerrRequest.fromJson({
        'id': id,
        'status': RequestStatus.approved,
        'createdAt': DateTime.now().toIso8601String(),
        'type': 'movie',
        'media': {'tmdbId': id, 'mediaType': 'movie', 'status': MediaStatus.processing},
      }),
      SeerrResult.fromJson({'id': id, 'mediaType': 'movie', 'title': title}),
    );
    final chip = FocusNode();
    await t.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerRight, child: Focus(focusNode: chip, child: const SizedBox(width: 200, height: 30))),
                RequestList(rows: [row(1, 'First'), row(2, 'Second'), row(3, 'Third')]),
              ],
            ),
          ),
        ),
      ),
    );
    chip.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(find.descendant(of: find.byWidget(focused.widget), matching: find.text('First')), findsOneWidget);
  });
}
