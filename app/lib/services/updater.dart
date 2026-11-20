import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:console_core/console_core.dart' show errorText;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../platform.dart' show formBuild;
import 'safe_file.dart';

/// Where releases come from. Only this repository's releases are ever downloaded.
const updateRepo = 'Foehammer1987/Liquiflux';

/// The version the updater compares against: [appVersion], or a lower one a test build was
/// given with `--dart-define=LIQUIFLUX_PRETEND_VERSION=0.9.0`, to try updating to the latest
/// real release.
const _pretend = String.fromEnvironment('LIQUIFLUX_PRETEND_VERSION');
String get currentVersion => _pretend.isNotEmpty ? _pretend : appVersion;

/// A newer release and the one file this device would install from it.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.pageUrl, required this.notes, this.asset});
  final String version;

  /// The release's page on GitHub.
  final String pageUrl;

  /// The release notes (Markdown), cut short.
  final String notes;

  /// What to download here, or null when this platform has nothing to install (Linux, or a
  /// release without APKs): then Settings links to [pageUrl].
  final UpdateAsset? asset;
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.url, required this.size, this.digest});
  final String name;
  final String url;
  final int size;

  /// The sha256 GitHub computed for the uploaded file, lower-case hex, if it says.
  final String? digest;
}

/// Splits "1.2.3" (or "v1.2.3") into numbers; null for anything else, pre-releases included.
List<int>? parseVersion(String v) {
  final m = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Whether [candidate] is a later version than [current].
bool isNewer(String candidate, String current) {
  final a = parseVersion(candidate), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The release file for this device: the installer on Windows, the APK for this system's
/// ABI on Android (armeabi-v7a on a 32-bit system like the 2019 Shield, even on a 64-bit chip,
/// since that's what is installed), nothing elsewhere. The phone/tablet build ([mobile]) takes
/// its own APK, never a TV one, which would swap its layout and manifest for the TV build's;
/// that APK is 64-bit only, so a 32-bit phone gets no update offer.
String? assetNameFor({required String os, required Abi abi, bool mobile = false}) {
  switch (os) {
    case 'windows':
      return 'Liquiflux-Setup-x64.exe';
    case 'android':
      if (mobile) return abi == Abi.androidArm64 ? 'Liquiflux-android-mobile-arm64-v8a.apk' : null;
      return switch (abi) {
        Abi.androidArm => 'Liquiflux-android-tv-armeabi-v7a.apk',
        Abi.androidArm64 => 'Liquiflux-android-tv-arm64-v8a.apk',
        _ => null,
      };
  }
  return null;
}

/// Reads GitHub's "latest release" answer. Null when it isn't newer than [current], or isn't
/// a release we'd take (a draft, a pre-release, a tag that isn't plain x.y.z).
UpdateInfo? parseRelease(Map<String, dynamic> j, {required String current, required String? assetName}) {
  if (j['draft'] == true || j['prerelease'] == true) return null;
  final tag = j['tag_name'];
  if (tag is! String || parseVersion(tag) == null || !isNewer(tag, current)) return null;
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  UpdateAsset? asset;
  final assets = j['assets'];
  if (assetName != null && assets is List) {
    for (final a in assets.whereType<Map<String, dynamic>>()) {
      if (a['name'] != assetName) continue;
      final url = a['browser_download_url'];
      final size = a['size'];
      if (url is! String || !isReleaseDownload(url, version) || size is! int || size <= 0 || size > maxDownload) break;
      final d = a['digest'];
      final digest = d is String && RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(d) ? d.substring(7).toLowerCase() : null;
      asset = UpdateAsset(name: assetName, url: url, size: size, digest: digest);
      break;
    }
  }
  final page = j['html_url'];
  final body = j['body'];
  return UpdateInfo(
    version: version,
    pageUrl: page is String && page.startsWith('https://github.com/$updateRepo/releases/') ? page : 'https://github.com/$updateRepo/releases/latest',
    notes: body is String ? (body.length > 4000 ? '${body.substring(0, 4000)}…' : body) : '',
    asset: asset,
  );
}

/// Biggest file the updater will download (the APKs and installer are 30-40 MB).
const maxDownload = 300 << 20;

/// Only files attached to this repository's release of [version], over https.
bool isReleaseDownload(String url, String version) => url.startsWith('https://github.com/$updateRepo/releases/download/v$version/') && !url.contains('..');

/// The checksum SHA256SUMS.txt (sha256sum's format) gives [name], lower-case hex.
String? sumFor(String sums, String name) {
  for (final line in const LineSplitter().convert(sums)) {
    final m = RegExp(r'^([0-9a-fA-F]{64}) [ *]?(.+)$').firstMatch(line.trim());
    if (m != null && m.group(2) == name) return m.group(1)!.toLowerCase();
  }
  return null;
}

enum UpdateStage { idle, checking, upToDate, available, downloading, installing, failed }

/// Checks GitHub for a newer Liquiflux, and downloads and installs it.
///
/// Nothing is signed in: the release list is public, so no token is ever sent. A download is
/// installed only when its sha256 matches both what GitHub recorded for the upload and the
/// release's SHA256SUMS.txt (whichever of the two exist; at least one must). On Android the
/// package installer also insists the APK carries the same signing key as the installed
/// app, and the app checks that first itself (AppUpdater.kt).
class Updater extends ChangeNotifier {
  Updater({http.Client? client, Future<Directory> Function()? folder, Future<Directory> Function()? downloadFolder, String? os, Abi? abi, MethodChannel? channel})
    : _client = client ?? http.Client(),
      _downloadFolder = downloadFolder,
      _folder = folder ?? getApplicationSupportDirectory,
      _os = os ?? Platform.operatingSystem,
      _abi = abi ?? Abi.current(),
      _channel = channel ?? const MethodChannel('liquiflux/update');

  final http.Client _client;
  final Future<Directory> Function() _folder;
  final Future<Directory> Function()? _downloadFolder;
  final String _os;
  final Abi _abi;
  final MethodChannel _channel;

  /// How often the automatic check runs at most.
  static const interval = Duration(hours: 12);

  UpdateStage stage = UpdateStage.idle;
  UpdateInfo? available;
  String? error;

  /// 0..1 while downloading.
  double progress = 0;

  /// Check for updates at launch (Settings > Advanced).
  bool auto = true;
  DateTime? _checkedAt;

  /// A version the user said "Not now" to: no card for it again, Settings still offers it.
  String _skipped = '';

  /// False where this build mustn't update itself (an app store installed it, or the
  /// store build without the installer permission); Settings then just says what's new.
  bool selfUpdate = true;

  /// Fires once per automatic check that found a version the user hasn't skipped.
  final found = StreamController<UpdateInfo>.broadcast();

  bool _loaded = false;

  Future<File> _file() async => File('${(await _folder()).path}${Platform.pathSeparator}update.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) {
          auto = j['auto'] is bool ? j['auto'] as bool : true;
          _checkedAt = j['checkedAt'] is String ? DateTime.tryParse(j['checkedAt'] as String) : null;
          _skipped = j['skipped'] is String ? j['skipped'] as String : '';
        }
      }
    } catch (e) {
      debugPrint('update settings: ${e.runtimeType}');
    }
    if (storeBuild.isNotEmpty) {
      selfUpdate = false;
    } else if (_os == 'android') {
      _channel.setMethodCallHandler(_fromAndroid);
      try {
        selfUpdate = await _channel.invokeMethod<bool>('selfUpdate') ?? false;
      } catch (e) {
        selfUpdate = false;
      }
    }
    unawaited(_cleanDownloads());
  }

  /// How Android's installer ended, when it didn't replace the app.
  Future<void> _fromAndroid(MethodCall call) async {
    if (call.method != 'finished') return;
    final a = call.arguments;
    if (a is Map && a['ok'] != true) _fail(a['message'] is String ? a['message'] as String : 'Android didn’t install the update.');
  }

  final _saves = SaveQueue();

  Future<void> _save() => _saves.run(() async {
    try {
      await writeAtomically(
        await _file(),
        jsonEncode({'auto': auto, if (_checkedAt != null) 'checkedAt': _checkedAt!.toUtc().toIso8601String(), 'skipped': _skipped}),
      );
    } catch (e) {
      debugPrint('update settings save: ${e.runtimeType}');
    }
  });

  Future<void> setAuto(bool on) async {
    auto = on;
    notifyListeners();
    await _save();
  }

  /// "Not now" on the card for [version].
  Future<void> skip(String version) async {
    _skipped = version;
    await _save();
  }

  /// The launch check: at most every [interval], and only if [auto].
  Future<void> checkInBackground({DateTime? now}) async {
    await load();
    final t = now ?? DateTime.now();
    if (!auto || (_checkedAt != null && t.difference(_checkedAt!) < interval && !t.isBefore(_checkedAt!))) return;
    final info = await check();
    if (info != null && info.version != _skipped) found.add(info);
  }

  /// Asks GitHub for the latest release. Returns the update, or null (up to date or failed:
  /// see [stage] and [error]).
  Future<UpdateInfo?> check() async {
    if (stage == UpdateStage.checking || stage == UpdateStage.downloading || stage == UpdateStage.installing) return available;
    stage = UpdateStage.checking;
    error = null;
    notifyListeners();
    try {
      final r = await _client
          .get(
            Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': '$appName/$appVersion', 'X-GitHub-Api-Version': '2022-11-28'},
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) {
        available = null;
      } else if (r.statusCode != 200) {
        throw HttpException('GitHub answered ${r.statusCode}');
      } else {
        final j = jsonDecode(r.body);
        if (j is! Map<String, dynamic>) throw const FormatException('unexpected answer');
        available = parseRelease(j, current: currentVersion, assetName: assetNameFor(os: _os, abi: _abi, mobile: formBuild == 'mobile'));
      }
      _checkedAt = DateTime.now();
      unawaited(_save());
      stage = available == null ? UpdateStage.upToDate : UpdateStage.available;
    } catch (e) {
      debugPrint('update check: ${errorText(e)}');
      error = 'Couldn’t reach GitHub to check for updates.';
      stage = UpdateStage.failed;
    }
    notifyListeners();
    return available;
  }

  /// Whether [install] can do the whole job here (else Settings offers the release page).
  bool get canInstall => selfUpdate && available?.asset != null && (_os == 'android' || (_os == 'windows' && installedWithSetup));

  /// A Windows copy put there by the installer (its uninstaller sits beside the exe), as
  /// opposed to the portable zip, which the installer would not replace.
  static bool get installedWithSetup {
    if (!Platform.isWindows) return false;
    final dir = File(Platform.resolvedExecutable).parent.path;
    return File('$dir\\unins000.exe').existsSync();
  }

  Future<Directory> _downloads() async {
    final base = _downloadFolder != null ? await _downloadFolder() : _os == 'android' ? await getApplicationCacheDirectory() : await getTemporaryDirectory();
    return Directory('${base.path}${Platform.pathSeparator}liquiflux-update');
  }

  /// Removes what an earlier update left (the installer can't delete itself).
  Future<void> _cleanDownloads() async {
    try {
      final d = await _downloads();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  /// Downloads [available]'s file, checks it, and hands it to the system installer.
  /// On Windows the app closes so the installer can replace it, and the installer starts
  /// the new version when it's done.
  Future<void> install({Future<void> Function()? beforeExit}) async {
    final info = available;
    final asset = info?.asset;
    if (info == null || asset == null || !canInstall) return;
    if (stage == UpdateStage.downloading || stage == UpdateStage.installing) return;
    error = null;
    progress = 0;
    stage = UpdateStage.downloading;
    notifyListeners();
    File? file;
    try {
      if (_os == 'android' && await _channel.invokeMethod<bool>('canInstall') != true) {
        // Android wants the user to allow installs from Liquiflux once.
        await _channel.invokeMethod<bool>('allowInstalls');
        _fail('Allow Liquiflux to install apps. Android closes Liquiflux when you do, so open it again and choose Update once more.');
        return;
      }
      file = await fetch(info, asset);
      stage = UpdateStage.installing;
      notifyListeners();
      if (_os == 'android') {
        final r = await _channel.invokeMethod<String>('install', {'path': file.path});
        if (r != 'ok') {
          _fail(r ?? 'The update couldn’t be installed.');
          return;
        }
        // Android shows its installer now; once it's done, this process is replaced.
        stage = UpdateStage.available;
        notifyListeners();
      } else {
        await beforeExit?.call();
        // Silent, no restart prompt, and /RELAUNCH starts Liquiflux again afterwards.
        await Process.start(file.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RELAUNCH=1'], mode: ProcessStartMode.detached);
        exit(0);
      }
    } on PlatformException catch (e) {
      debugPrint('update install: ${e.code} ${e.message}');
      _fail(e.message ?? 'The update couldn’t be installed.');
    } catch (e) {
      debugPrint('update install: ${errorText(e)}');
      _fail(e is UpdateException ? e.message : 'The download failed. Check the connection and try again.');
      if (file != null) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  /// Downloads [asset] and checks its sha256; throws [UpdateException] when it doesn't match.
  @visibleForTesting
  Future<File> fetch(UpdateInfo info, UpdateAsset asset) async => _download(asset, await _expectedSum(info, asset));

  void _fail(String message) {
    error = message;
    stage = UpdateStage.failed;
    notifyListeners();
  }

  /// The checksum the file must have: GitHub's record of the upload and SHA256SUMS.txt must
  /// agree where both exist, and at least one must.
  Future<String> _expectedSum(UpdateInfo info, UpdateAsset asset) async {
    String? listed;
    final sumsUrl = 'https://github.com/$updateRepo/releases/download/v${info.version}/SHA256SUMS.txt';
    try {
      final r = await _client.get(Uri.parse(sumsUrl), headers: {'User-Agent': '$appName/$appVersion'}).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 && r.bodyBytes.length < 64 << 10) listed = sumFor(utf8.decode(r.bodyBytes, allowMalformed: true), asset.name);
    } catch (e) {
      debugPrint('update sums: ${errorText(e)}');
    }
    final digest = asset.digest;
    if (digest != null && listed != null && digest != listed) throw const UpdateException('The release’s checksums don’t agree, so it wasn’t installed.');
    final expected = digest ?? listed;
    if (expected == null) throw const UpdateException('The release has no checksum for this file, so it wasn’t installed.');
    return expected;
  }

  Future<File> _download(UpdateAsset asset, String expected) async {
    final dir = await _downloads();
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    try {
      return await _downloadTo(file, asset, expected);
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<File> _downloadTo(File file, UpdateAsset asset, String expected) async {
    final req = http.Request('GET', Uri.parse(asset.url))..headers['User-Agent'] = '$appName/$appVersion';
    final res = await _client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('download answered ${res.statusCode}');
    final sink = file.openWrite();
    final hash = _DigestSink();
    final hasher = sha256.startChunkedConversion(hash);
    var got = 0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        got += chunk.length;
        if (got > asset.size || got > maxDownload) throw const UpdateException('The download was bigger than the release says, so it wasn’t installed.');
        hasher.add(chunk);
        sink.add(chunk);
        final p = got / asset.size;
        if (p - progress >= 0.01 || got == asset.size) {
          progress = p;
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    if (got != asset.size) throw const UpdateException('The download stopped early. Try again.');
    final sum = hash.value.toString();
    if (sum != expected) throw const UpdateException('The download didn’t match the release’s checksum, so it wasn’t installed.');
    return file;
  }

  @override
  void dispose() {
    found.close();
    super.dispose();
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
