import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Certificate checks for mpv's https streams.
///
/// mpv's `tls-verify` is still off by default, and a direct-play or transcode URL carries
/// the Plex token, so an https stream would go to whoever answered. media_kit's libmpv
/// (Windows and Android alike) does TLS with mbedtls, which can't see the system's store:
/// it needs a file of trusted roots, and with one it refuses any certificate that isn't
/// signed by them or doesn't match the host. The file is Mozilla's list (minus the roots
/// Liquiflux removes, see its README) in assets/tls/cacert.pem, copied out to the app's folder since mpv wants a path and an
/// APK's assets aren't files.
abstract final class MpvTls {
  static const asset = 'assets/tls/cacert.pem';
  static Future<String?>? _file;

  /// Where the bundle is, written when missing or out of date; null if it couldn't be
  /// (asked again next time).
  static Future<String?> caFile() => _file ??= _write();

  static Future<String?> _write() async {
    try {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final sep = Platform.pathSeparator;
      final dir = Directory('${(await getApplicationSupportDirectory()).path}${sep}tls');
      await dir.create(recursive: true);
      final f = File('${dir.path}${sep}cacert.pem');
      if (await f.exists() && listEquals(await f.readAsBytes(), bytes)) return f.path;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      return f.path;
    } catch (e) {
      debugPrint('mpv tls: no certificate list: $e');
      _file = null;
      return null;
    }
  }

  /// Whether mpv can check [url]'s certificate fully. mpv's TLS (FFmpeg on mbedtls) skips
  /// the name check when the host is a bare IP address, so any trusted certificate would do
  /// for https://192.168.x.x; such an address is refused. (The app's own requests do check
  /// it, so a sign-in never lands on one; this is the backstop.) Plain http and names pass.
  static bool canCheck(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.isScheme('https')) return true;
    return InternetAddress.tryParse(u.host.replaceAll(RegExp(r'^\[|\]$'), '')) == null;
  }

  static const bareIp = 'This server\'s https address is a bare IP address, which the player can\'t check the certificate of. Sign in to Plex again in Settings to use its plex.direct address.';

  /// Turns certificate checks on for [player]; call before it opens anything. Without the
  /// file an https stream fails to open instead of going unchecked (http is unaffected).
  static Future<void> apply(NativePlayer player) async {
    final ca = await caFile();
    try {
      await player.setProperty('tls-verify', 'yes');
      if (ca != null) await player.setProperty('tls-ca-file', ca);
    } catch (e) {
      debugPrint('mpv tls: $e');
    }
  }
}
