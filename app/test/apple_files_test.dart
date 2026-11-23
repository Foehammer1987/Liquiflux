import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/apple_sync.dart' as apple;

/// The Mac and iPhone/iPad projects carry exactly what app/apple says (privacy manifest,
/// shared Info.plist keys, keychain group): run `dart tools/apple_sync.dart` after editing.
void main() {
  // flutter test runs from app/.
  final app = Directory.current.path;

  test('every Apple target matches app/apple', () {
    expect(apple.stale(app), isEmpty);
  });

  test('the shared keys reach both targets', () {
    for (final plist in ['macos/Runner/Info.plist', 'ios/Runner/Info.plist']) {
      final text = File('$app/$plist').readAsStringSync();
      expect(text, contains('<string>Liquiflux</string>'), reason: plist);
      expect(text, contains('NSLocalNetworkUsageDescription'), reason: plist);
      expect(text, contains('NSAllowsLocalNetworking'), reason: plist);
      expect(text, contains('ITSAppUsesNonExemptEncryption'), reason: plist);
    }
    for (final e in ['macos/Runner/DebugProfile.entitlements', 'macos/Runner/Release.entitlements', 'ios/Runner/Runner.entitlements']) {
      expect(File('$app/$e').readAsStringSync(), contains(r'$(AppIdentifierPrefix)com.foehammer.liquiflux'), reason: e);
    }
  });

  test('a missing block is reported with what to add', () {
    expect(() => apple.splice('<dict>\n</dict>', 'Info.plist.keys', '', file: 'x'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('app/apple/Info.plist.keys'))));
  });

  test('a changed shared key shows up as stale', () {
    final tmp = Directory.systemTemp.createTempSync('apple');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final f in [
      'apple/PrivacyInfo.xcprivacy', 'apple/Info.plist.keys', 'apple/keychain.entitlements',
      'macos/Runner/Info.plist', 'macos/Runner/DebugProfile.entitlements', 'macos/Runner/Release.entitlements', 'macos/Runner/PrivacyInfo.xcprivacy',
    ]) {
      File('${tmp.path}/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync(File('$app/$f').readAsStringSync());
    }
    expect(apple.stale(tmp.path), isEmpty);
    final keys = File('${tmp.path}/apple/Info.plist.keys');
    keys.writeAsStringSync(keys.readAsStringSync().replaceFirst('home network', 'house'));
    expect(apple.stale(tmp.path), ['macos/Runner/Info.plist']);
  });
}
