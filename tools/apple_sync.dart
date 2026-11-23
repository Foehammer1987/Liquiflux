// Writes the files every Apple target shares (app/apple/) into each Xcode project, so the
// Mac, iPhone/iPad and (later) Apple TV apps can't drift apart:
//
//   app/apple/PrivacyInfo.xcprivacy   copied whole into each target's Runner folder
//   app/apple/Info.plist.keys         the keys between the app/apple markers in each Info.plist
//   app/apple/keychain.entitlements   the keys between the markers in each entitlements file
//
// Everything outside the markers stays the target's own (macOS's sandbox keys, iOS's
// orientations and scene manifest, and so on).
//
//   dart tools/apple_sync.dart            write them
//   dart tools/apple_sync.dart --check    only say what differs (exit 1 if anything does)
//   dart tools/apple_sync.dart --icons    also redraw every target's app icon (needs a Mac:
//                                         tools/make-apple-icons.swift)
//
// A new target (tvos/) is one more entry in [targets]. No packages: dart:io only, so CI runs
// it as it is.

import 'dart:io';

/// One Apple target: its folder under app/ and which of its files take which shared piece.
class AppleTarget {
  const AppleTarget(this.dir, {required this.plists, required this.entitlements, required this.iconMode, required this.iconSet});

  /// The Xcode project folder under app/ (macos, ios, tvos).
  final String dir;

  /// Info.plist files (relative to app/) that take app/apple/Info.plist.keys.
  final List<String> plists;

  /// Entitlements files (relative to app/) that take app/apple/keychain.entitlements.
  final List<String> entitlements;

  /// tools/make-apple-icons.swift's mode for this target, and the icon set it fills.
  final String iconMode;
  final String iconSet;

  String get privacy => '$dir/Runner/PrivacyInfo.xcprivacy';
}

const targets = [
  AppleTarget('macos',
      plists: ['macos/Runner/Info.plist'],
      entitlements: ['macos/Runner/DebugProfile.entitlements', 'macos/Runner/Release.entitlements'],
      iconMode: 'mac',
      iconSet: 'macos/Runner/Assets.xcassets/AppIcon.appiconset'),
  AppleTarget('ios',
      plists: ['ios/Runner/Info.plist'],
      entitlements: ['ios/Runner/Runner.entitlements'],
      iconMode: 'ios',
      iconSet: 'ios/Runner/Assets.xcassets/AppIcon.appiconset'),
];

String begin(String piece) => '\t<!-- Shared by every Apple target: app/apple/$piece (tools/apple_sync.dart writes this block). -->\n';
String end(String piece) => '\t<!-- End of app/apple/$piece. -->\n';

/// [text] with the block between [piece]'s markers replaced by [shared]. Throws when the
/// markers are missing, with what to add.
String splice(String text, String piece, String shared, {required String file}) {
  final b = begin(piece), e = end(piece);
  final i = text.indexOf(b), j = text.indexOf(e);
  if (i < 0 || j < i) {
    throw StateError('$file has no app/apple/$piece block. Put these two lines inside its top <dict>:\n$b$e');
  }
  return text.substring(0, i + b.length) + shared + text.substring(j);
}

/// Every shared file's wanted contents, by path relative to [appDir].
Map<String, String> wanted(String appDir) {
  String read(String p) => File('$appDir/$p').readAsStringSync();
  final privacy = read('apple/PrivacyInfo.xcprivacy');
  final keys = read('apple/Info.plist.keys');
  final keychain = read('apple/keychain.entitlements');
  final out = <String, String>{};
  for (final t in targets) {
    if (!Directory('$appDir/${t.dir}').existsSync()) continue;
    out[t.privacy] = privacy;
    for (final p in t.plists) {
      out[p] = splice(read(p), 'Info.plist.keys', keys, file: p);
    }
    for (final p in t.entitlements) {
      out[p] = splice(read(p), 'keychain.entitlements', keychain, file: p);
    }
  }
  return out;
}

/// The files under [appDir] that differ from what app/apple says they should be.
List<String> stale(String appDir) => [
      for (final MapEntry(:key, :value) in wanted(appDir).entries)
        if (!File('$appDir/$key').existsSync() || File('$appDir/$key').readAsStringSync() != value) key,
    ];

void main(List<String> args) {
  final appDir = '${File.fromUri(Platform.script).parent.parent.path}/app';
  final check = args.contains('--check');
  try {
    if (check) {
      final bad = stale(appDir);
      if (bad.isEmpty) {
        stdout.writeln('Apple targets match app/apple.');
        return;
      }
      stderr.writeln('These differ from app/apple (run dart tools/apple_sync.dart):\n  ${bad.join('\n  ')}');
      exitCode = 1;
      return;
    }
    for (final MapEntry(:key, :value) in wanted(appDir).entries) {
      final f = File('$appDir/$key');
      if (f.existsSync() && f.readAsStringSync() == value) continue;
      f.writeAsStringSync(value);
      stdout.writeln('wrote app/$key');
    }
    if (args.contains('--icons')) {
      final root = File.fromUri(Platform.script).parent.parent.path;
      for (final t in targets) {
        if (!Directory('$appDir/${t.dir}').existsSync()) continue;
        final r = Process.runSync('swift', ['$root/tools/make-apple-icons.swift', t.iconMode, '$root/docs/brand/liquiflux-mark.svg', '$appDir/${t.iconSet}']);
        stdout.write(r.stdout);
        stderr.write(r.stderr);
        if (r.exitCode != 0) exitCode = r.exitCode;
      }
    }
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
  }
}
