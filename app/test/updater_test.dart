import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:console_app/services/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = 'https://github.com/Foehammer1987/Liquiflux/releases/download/v99.0.1';

Map<String, dynamic> _release({String tag = 'v99.0.1', String? digest, String? url, int size = 5}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'html_url': 'https://github.com/Foehammer1987/Liquiflux/releases/tag/$tag',
  'body': '- Faster',
  'assets': [
    {'name': 'Liquiflux-Setup-x64.exe', 'size': size, 'digest': digest, 'browser_download_url': url ?? '$_base/Liquiflux-Setup-x64.exe'},
    {'name': 'Liquiflux-android-tv-armeabi-v7a.apk', 'size': size, 'browser_download_url': '$_base/Liquiflux-android-tv-armeabi-v7a.apk'},
  ],
};

void main() {
  test('versions compare by number, and only plain x.y.z counts', () {
    expect(isNewer('v1.0.1', '1.0.0'), isTrue);
    expect(isNewer('1.10.0', '1.9.9'), isTrue);
    expect(isNewer('1.0.0', '1.0.0'), isFalse);
    expect(isNewer('0.9.49', '1.0.0'), isFalse);
    expect(isNewer('v1.1.0-beta', '1.0.0'), isFalse);
    expect(isNewer('nonsense', '1.0.0'), isFalse);
  });

  test('each device takes its own file', () {
    expect(assetNameFor(os: 'windows', abi: Abi.windowsX64), 'Liquiflux-Setup-x64.exe');
    // The 2019 Shield runs 32-bit Android on a 64-bit chip: the 32-bit APK is what's installed.
    expect(assetNameFor(os: 'android', abi: Abi.androidArm), 'Liquiflux-android-tv-armeabi-v7a.apk');
    expect(assetNameFor(os: 'android', abi: Abi.androidArm64), 'Liquiflux-android-tv-arm64-v8a.apk');
    expect(assetNameFor(os: 'android', abi: Abi.androidX64), isNull);
    expect(assetNameFor(os: 'linux', abi: Abi.linuxX64), isNull);
  });

  test('reads a release and its file', () {
    final d = 'a' * 64;
    final info = parseRelease(_release(digest: 'sha256:$d'), current: '1.0.0', assetName: 'Liquiflux-Setup-x64.exe')!;
    expect(info.version, '99.0.1');
    expect(info.asset!.digest, d);
    expect(info.asset!.url, '$_base/Liquiflux-Setup-x64.exe');
    expect(parseRelease(_release(), current: '99.0.1', assetName: 'Liquiflux-Setup-x64.exe'), isNull);
    expect(parseRelease({..._release(), 'prerelease': true}, current: '1.0.0', assetName: null), isNull);
    expect(parseRelease({..._release(), 'draft': true}, current: '1.0.0', assetName: null), isNull);
  });

  test('never takes a file from anywhere but this repository’s release', () {
    for (final url in [
      'https://example.com/Liquiflux-Setup-x64.exe',
      'http://github.com/Foehammer1987/Liquiflux/releases/download/v99.0.1/Liquiflux-Setup-x64.exe',
      'https://github.com/someone/Liquiflux/releases/download/v99.0.1/Liquiflux-Setup-x64.exe',
      'https://github.com/Foehammer1987/Liquiflux/releases/download/v1.0.0/Liquiflux-Setup-x64.exe',
      'https://github.com/Foehammer1987/Liquiflux/releases/download/v99.0.1/../../../evil/x.exe',
    ]) {
      final info = parseRelease(_release(url: url), current: '1.0.0', assetName: 'Liquiflux-Setup-x64.exe');
      expect(info!.asset, isNull, reason: url);
    }
    final huge = parseRelease(_release(size: maxDownload + 1), current: '1.0.0', assetName: 'Liquiflux-Setup-x64.exe');
    expect(huge!.asset, isNull);
  });

  test('SHA256SUMS lines', () {
    final s = '${'b' * 64}  Liquiflux-Setup-x64.exe\n${'C' * 64} *Liquiflux-windows-x64.zip\n';
    expect(sumFor(s, 'Liquiflux-Setup-x64.exe'), 'b' * 64);
    expect(sumFor(s, 'Liquiflux-windows-x64.zip'), 'c' * 64);
    expect(sumFor(s, 'other'), isNull);
  });

  group('download', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('upd'));
    tearDown(() => tmp.deleteSync(recursive: true));

    final payload = utf8.encode('hello');
    final good = sha256.convert(payload).toString();

    Updater updater({required String? sums, String body = 'hello'}) => Updater(
      os: 'windows',
      abi: Abi.windowsX64,
      folder: () async => tmp,
      downloadFolder: () async => tmp,
      client: MockClient((r) async {
        if (r.url.path.endsWith('SHA256SUMS.txt')) return sums == null ? http.Response('', 404) : http.Response(sums, 200);
        if (r.url.path.endsWith('.exe')) return http.Response(body, 200);
        return http.Response('', 404);
      }),
    );

    UpdateInfo info(String? digest) => parseRelease(_release(digest: digest == null ? null : 'sha256:$digest'), current: '1.0.0', assetName: 'Liquiflux-Setup-x64.exe')!;

    test('matching file is kept', () async {
      final f = await updater(sums: '$good  Liquiflux-Setup-x64.exe\n').fetch(info(good), info(good).asset!);
      expect(f.readAsStringSync(), 'hello');
    });

    test('GitHub’s digest alone is enough', () async {
      final f = await updater(sums: null).fetch(info(good), info(good).asset!);
      expect(f.existsSync(), isTrue);
    });

    test('a tampered file is refused and removed', () async {
      final u = updater(sums: '$good  Liquiflux-Setup-x64.exe\n', body: 'hellx');
      await expectLater(u.fetch(info(good), info(good).asset!), throwsA(isA<UpdateException>()));
      expect(tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.exe')), isEmpty);
    });

    test('checksums that disagree are refused', () async {
      final u = updater(sums: '${'0' * 64}  Liquiflux-Setup-x64.exe\n');
      await expectLater(u.fetch(info(good), info(good).asset!), throwsA(isA<UpdateException>()));
    });

    test('no checksum at all is refused', () async {
      await expectLater(updater(sums: null).fetch(info(null), info(null).asset!), throwsA(isA<UpdateException>()));
    });

    test('a longer file than the release says is refused', () async {
      final u = updater(sums: null, body: 'hello world');
      await expectLater(u.fetch(info(good), info(good).asset!), throwsA(isA<UpdateException>()));
    });
  });

  test('the launch check runs at most every 12 hours and announces once', () async {
    final tmp = Directory.systemTemp.createTempSync('upd');
    addTearDown(() => tmp.deleteSync(recursive: true));
    var calls = 0;
    final u = Updater(
      os: 'linux',
      abi: Abi.linuxX64,
      folder: () async => tmp,
      client: MockClient((r) async {
        calls++;
        expect(r.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
        return http.Response(jsonEncode(_release()), 200);
      }),
    );
    final found = <UpdateInfo>[];
    u.found.stream.listen(found.add);
    await u.checkInBackground();
    await u.checkInBackground();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(found.single.version, '99.0.1');
    expect(u.stage, UpdateStage.available);
    // Linux has nothing to install: Settings links to the release instead.
    expect(u.canInstall, isFalse);

    // "Not now" is remembered: a later check stays quiet about that version.
    await u.skip('99.0.1');
    final again = Updater(os: 'linux', abi: Abi.linuxX64, folder: () async => tmp, client: MockClient((r) async => http.Response(jsonEncode(_release()), 200)));
    final later = <UpdateInfo>[];
    again.found.stream.listen(later.add);
    await again.checkInBackground(now: DateTime.now().add(const Duration(hours: 13)));
    await Future<void>.delayed(Duration.zero);
    expect(later, isEmpty);
    expect(again.available?.version, '99.0.1');
  });
}
