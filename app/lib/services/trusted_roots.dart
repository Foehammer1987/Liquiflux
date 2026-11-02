import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mpv_tls.dart';

/// The certificate authorities the app's own https requests trust: the list in
/// assets/tls/cacert.pem (Mozilla's, minus the roots Liquiflux removes; see its README),
/// instead of whatever the system store holds. The same list mpv uses ([MpvTls]).
///
/// Every dart:io HttpClient the app makes goes through [HttpOverrides.global], so this
/// covers the http package (JsonHttp), Flutter's NetworkImage and the rest alike.
abstract final class TrustedRoots {
  /// Installs the list for every HttpClient from here on. If the list can't be read (a broken
  /// build), the system's store stays in charge and the failure is logged.
  static Future<void> install() async {
    try {
      final data = await rootBundle.load(MpvTls.asset);
      HttpOverrides.global = _Curated(context(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
    } catch (e) {
      debugPrint('trusted roots: kept the system store: $e');
    }
  }

  /// A context that trusts exactly the certificates in [pem].
  static SecurityContext context(List<int> pem) => SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(pem);
}

class _Curated extends HttpOverrides {
  _Curated(this._context);
  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context ?? _context);
}
