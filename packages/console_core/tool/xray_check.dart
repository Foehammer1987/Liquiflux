// Checks Liquiflux's X-Ray sign-in against a running X-Ray server, with the app's own
// client code (XRayServer), so it fails the same way the app would.
//
//   dart run tool/xray_check.dart <server address> <file holding a Plex token> [ratingKey]
//
// The token is read from a file so it never lands in shell history or logs, and it is
// never printed.
import 'dart:io';

import 'package:console_core/console_core.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/xray_check.dart <server address> <token file> [ratingKey]');
    exit(2);
  }
  final token = File(args[1]).readAsStringSync().trim();
  final key = args.length > 2 ? args[2] : '1234';
  final server = XRayServer.shared(args[0], token);
  if (server == null) {
    stdout.writeln('FAIL: not a usable address: ${args[0]}');
    exit(1);
  }
  try {
    final signedIn = await server.check();
    stdout.writeln(signedIn ? 'sign-in: OK (session from the X-Ray server)' : 'sign-in: none (plain file server, or http outside this network)');
    final t = await server.timeline(key);
    if (t == null) {
      stdout.writeln('timeline $key: not scanned (404)');
    } else {
      final people = t['people'] is List ? (t['people'] as List).length : 0;
      final spans = t['spans'] is List ? (t['spans'] as List).length : 0;
      stdout.writeln('timeline $key: OK, $people people, $spans spans');
    }
    exit(signedIn && t != null ? 0 : 1);
  } on ApiException catch (e) {
    stdout.writeln('FAIL: ${e.status} ${redactSecrets(e.message)}');
    exit(1);
  }
}
