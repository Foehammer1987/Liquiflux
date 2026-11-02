import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:console_core/console_core.dart' show errorText;
import 'package:flutter/foundation.dart';

/// A box on the phone's page.
class PhoneField {
  const PhoneField(this.name, this.label, {this.value = '', this.secret = false, this.multiline = false});
  final String name;
  final String label;
  final String value;
  final bool secret;
  final bool multiline;
}

/// Typing a long key or token with a TV remote is no fun, so the TV serves a small page on
/// the home network for a phone to fill in: the TV shows its address as a QR code.
///
/// The page lives at a random 128-bit path and only while the TV shows it (15 minutes at
/// most); anything else gets a 404, and after 20 wrong paths it closes. It's plain http
/// (a phone would refuse the TV's own certificate), so it's only for the home network.
class PhoneLink {
  PhoneLink._(this._server, this.url, this._path, this._page, this._onSubmit) {
    _server.listen(_handle, onError: (Object e) => debugPrint('phone link: ${errorText(e)}'));
    _timeout = Timer(const Duration(minutes: 15), close);
  }

  final HttpServer _server;

  /// What the QR code opens.
  final String url;
  final String _path;
  final ({String title, String intro, List<(String, String)> links, List<PhoneField> fields}) _page;

  /// Takes what the phone sent; returns an error to show there, or null when it worked.
  final Future<String?> Function(Map<String, String> values) _onSubmit;
  late final Timer _timeout;
  var _misses = 0;
  bool _closed = false;
  bool get closed => _closed;

  /// Starts the page on the first private IPv4 address this device has. Null when there's
  /// no home network to serve it on.
  static Future<PhoneLink?> open({
    required String title,
    required String intro,
    List<(String, String)> links = const [],
    required List<PhoneField> fields,
    required Future<String?> Function(Map<String, String> values) onSubmit,
    String? host,
  }) async {
    final ip = host ?? await lanAddress();
    if (ip == null) return null;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final r = Random.secure();
    final path = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return PhoneLink._(server, 'http://$ip:${server.port}/$path', path, (title: title, intro: intro, links: links, fields: fields), onSubmit);
  }

  /// This device's address on the home network (10.x, 172.16-31.x or 192.168.x).
  static Future<String?> lanAddress() async {
    try {
      final all = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = [for (final i in all) ...i.addresses.map((a) => a.address)];
      bool private(String ip) {
        final p = ip.split('.').map(int.tryParse).toList();
        if (p.length != 4 || p.contains(null)) return false;
        return p[0] == 10 || (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) || (p[0] == 192 && p[1] == 168);
      }

      return ips.where(private).firstOrNull;
    } catch (e) {
      debugPrint('phone link address: ${errorText(e)}');
      return null;
    }
  }

  /// Called once the phone's answer was taken, so the TV can move on.
  void Function()? onDone;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timeout.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('cache-control', 'no-store')
      ..set('referrer-policy', 'no-referrer')
      ..set('x-frame-options', 'DENY')
      ..set('x-content-type-options', 'nosniff')
      ..set('content-security-policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'");
    try {
      if (req.uri.path != '/$_path' || (req.method != 'GET' && req.method != 'POST')) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        if (++_misses >= 20) unawaited(close());
        return;
      }
      if (req.method == 'GET') return await _send(res, _form());
      final type = req.headers.contentType?.mimeType;
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
          await res.close();
          return;
        }
      }
      if (type != 'application/x-www-form-urlencoded') {
        res.statusCode = HttpStatus.unsupportedMediaType;
        await res.close();
        return;
      }
      final values = Uri.splitQueryString(utf8.decode(bytes, allowMalformed: true));
      final wanted = {for (final f in _page.fields) f.name: (values[f.name] ?? '').trim()};
      final error = await _onSubmit(wanted);
      if (error != null) return await _send(res, _form(error: error, values: wanted));
      await _send(res, _doc('<h1>Done</h1><p>Look at your TV. You can close this page.</p>'));
      onDone?.call();
      unawaited(Future<void>.delayed(const Duration(seconds: 1), close));
    } catch (e) {
      debugPrint('phone link: ${errorText(e)}');
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _send(HttpResponse res, String html) async {
    res.headers.contentType = ContentType.html;
    res.write(html);
    await res.close();
  }

  static String _esc(String s) => const HtmlEscape().convert(s);

  String _form({String? error, Map<String, String> values = const {}}) {
    final p = _page;
    final b = StringBuffer('<h1>${_esc(p.title)}</h1><p>${_esc(p.intro)}</p>');
    for (final (label, href) in p.links) {
      b.write('<p><a class="btn" href="${_esc(href)}" target="_blank" rel="noopener noreferrer">${_esc(label)}</a></p>');
    }
    if (error != null) b.write('<p class="err">${_esc(error)}</p>');
    b.write('<form method="post" action="/$_path" autocomplete="off">');
    for (final f in p.fields) {
      final v = _esc(values[f.name] ?? f.value);
      b.write('<label>${_esc(f.label)}');
      b.write(f.multiline
          ? '<textarea name="${_esc(f.name)}" rows="5" spellcheck="false" autocapitalize="off">$v</textarea>'
          : '<input name="${_esc(f.name)}" value="$v" type="${f.secret ? 'password' : 'text'}" spellcheck="false" autocapitalize="off" autocorrect="off">');
      b.write('</label>');
    }
    b.write('<button type="submit">Send to the TV</button></form>');
    return _doc(b.toString());
  }

  static String _doc(String body) => '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Liquiflux</title><style>'
      'body{font:16px/1.5 system-ui,sans-serif;background:#0d0f14;color:#e8eaf0;margin:0;padding:24px;max-width:560px}'
      'h1{font-size:22px}label{display:block;margin:16px 0;font-weight:600}'
      'input,textarea{display:block;width:100%;box-sizing:border-box;margin-top:6px;padding:12px;font:15px ui-monospace,monospace;background:#1a1d26;color:#fff;border:1px solid #333a4a;border-radius:8px}'
      'button,.btn{display:inline-block;padding:12px 18px;border-radius:8px;border:0;background:#4f7cff;color:#fff;font-weight:600;font-size:16px;text-decoration:none}'
      '.err{color:#ff8a8a}'
      '</style></head><body>$body</body></html>';
}
