import 'dart:io';

import 'package:console_app/services/mpv_tls.dart';
import 'package:console_app/services/trusted_roots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pem = File('assets/tls/cacert.pem').readAsStringSync();
  final labels = RegExp(r'^# Label: "(.*)"$', multiLine: true).allMatches(pem).map((m) => m.group(1)!).toList();

  test('the root list parses and is the size of Mozilla\'s', () {
    expect(RegExp('-----BEGIN CERTIFICATE-----').allMatches(pem).length, labels.length);
    expect(labels.length, inInclusiveRange(100, 200));
    expect(() => TrustedRoots.context(pem.codeUnits), returnsNormally);
    // Roots Plex, Cloudflare, Let's Encrypt and Google sites chain to.
    for (final root in ['USERTrust RSA Certification Authority', 'ISRG Root X1', 'GTS Root R1', 'GlobalSign Root CA - R3']) {
      expect(labels, contains(root));
    }
  });

  test('no eMudhra root, and not the root Sectigo cross-signed its bad intermediates under', () {
    expect(pem, isNot(matches(RegExp('emSign|eMudhra', caseSensitive: false))));
    expect(labels, isNot(contains('AAA Certificate Services')));
  });

  test('the player refuses https to a bare IP, whose name mpv would not check', () {
    expect(MpvTls.canCheck('https://192.168.1.20:32400/library/parts/1/file.mkv'), isFalse);
    expect(MpvTls.canCheck('https://[fd00::1]:32400/x'), isFalse);
    expect(MpvTls.canCheck('https://192-168-1-20.abc.plex.direct:32400/x'), isTrue);
    expect(MpvTls.canCheck('http://192.168.1.20:32400/x'), isTrue);
  });
}
