import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'tv_harness.dart';

/// A Plex server with libraries and nothing in them.
http.Client emptyServer() => MockClient((req) async {
  final p = req.url.path;
  final dirs = p == '/library/sections'
      ? [
          {'key': '1', 'title': 'Movies', 'type': 'movie'},
        ]
      : const <Map<String, dynamic>>[];
  return http.Response(
    jsonEncode({
      'MediaContainer': {'size': 0, 'totalSize': 0, 'friendlyName': 'Homeserver', 'machineIdentifier': 'm', 'Metadata': const [], 'Directory': dirs},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
});

/// Home on an empty library says so, instead of "Picking something good…" for ever.
void main() {
  testWidgets('an empty library shows an empty state, not endless loading', (t) async {
    await tvApp(
      t,
      before: (s) => s
        ..plex = PlexClient(baseUrl: 'http://plex.test:32400', token: 'tok', clientId: 'c', http: JsonHttp(client: emptyServer()))
        ..sections = [PlexSection(key: '1', title: 'Movies', type: 'movie')],
    );
    expect(find.textContaining('Picking something good'), findsNothing);
    expect(find.textContaining('Nothing to show yet'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a library with titles still gets its spotlight', (t) async {
    await tvApp(t);
    expect(find.textContaining('Nothing to show yet'), findsNothing);
    expect(find.textContaining('Picking something good'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
