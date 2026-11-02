// Downloads the real latest release through the updater's checks (network; skipped unless
// LIQUIFLUX_LIVE_UPDATE=1):  LIQUIFLUX_LIVE_UPDATE=1 flutter test test/updater_live_test.dart
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:console_app/services/updater.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final live = Platform.environment['LIQUIFLUX_LIVE_UPDATE'] == '1';
  for (final (os, abi) in [('windows', Abi.windowsX64), ('android', Abi.androidArm), ('android', Abi.androidArm64)]) {
    test('latest release for $os $abi downloads and verifies', () async {
      final tmp = Directory.systemTemp.createTempSync('upd');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final client = http.Client();
      final r = await client.get(Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'), headers: {'User-Agent': 'Liquiflux-test'});
      expect(r.statusCode, 200);
      final info = parseRelease(jsonDecode(r.body) as Map<String, dynamic>, current: '0.0.1', assetName: assetNameFor(os: os, abi: abi))!;
      final asset = info.asset!;
      final u = Updater(client: client, os: os, abi: abi, folder: () async => tmp, downloadFolder: () async => tmp);
      final f = await u.fetch(info, asset);
      expect(f.lengthSync(), asset.size);
      debugPrint('${asset.name} ${info.version}: ${asset.size} bytes, sha256 ${asset.digest ?? '(from SHA256SUMS)'} verified');
    }, skip: live ? false : 'set LIQUIFLUX_LIVE_UPDATE=1', timeout: const Timeout(Duration(minutes: 5)));
  }
}
