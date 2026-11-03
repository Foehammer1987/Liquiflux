import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'security.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.uri, this.body});
  final int status;
  final String message;
  final Uri? uri;

  /// The decoded error body, when the server sent JSON (plex.tv's error codes are in it).
  final Object? body;

  /// The message, with any token or key a server echoed back scrubbed out.
  @override
  String toString() => redactSecrets(message);
}

/// Small JSON-over-HTTP helper shared by the Plex and Seerr clients.
class JsonHttp {
  JsonHttp({http.Client? client, this.timeout = const Duration(seconds: 15)}) : _client = client ?? http.Client();
  final http.Client _client;

  /// How long a whole request may take, body included.
  final Duration timeout;

  /// Redirects followed before giving up.
  static const maxRedirects = 5;

  /// Returns the decoded JSON body and the response headers. [timeout] overrides the
  /// default for one request (a big library listing, say).
  ///
  /// Redirects are followed here rather than by the HTTP client, which would carry custom
  /// headers such as X-Plex-Token and X-Api-Key along to whatever host it's sent to. When a
  /// redirect leaves the server (an https upgrade on the same host is fine), [headers]
  /// stay behind, so credentials only ever reach the server they were meant for.
  Future<({dynamic body, Map<String, String> headers})> sendRaw(String method, Uri uri, {Map<String, String> headers = const {}, Object? body, Duration? timeout}) async {
    final limit = timeout ?? this.timeout;
    final clock = Stopwatch()..start();
    var at = uri;
    var verb = method;
    var extra = headers;
    var payload = body;
    http.StreamedResponse streamed;
    for (var hops = 0; ; hops++) {
      final req = http.Request(verb, at)
        ..followRedirects = false
        ..headers.addAll({'accept': 'application/json', ...extra});
      if (payload != null) {
        req.headers['content-type'] = 'application/json';
        req.body = jsonEncode(payload);
      }
      try {
        final left = limit - clock.elapsed;
        streamed = await _client.send(req).timeout(left.isNegative ? Duration.zero : left);
      } on TimeoutException {
        throw ApiException(0, 'Timed out reaching ${uri.origin}', uri: uri);
      } catch (_) {
        throw ApiException(0, 'Could not reach ${uri.origin}', uri: uri);
      }
      final location = streamed.headers['location'];
      final code = streamed.statusCode;
      final reads = verb == 'GET' || verb == 'HEAD';
      final follow = location != null && (code == 303 || (reads && (code == 301 || code == 302 || code == 307 || code == 308)));
      if (!follow) break;
      unawaited(streamed.stream.listen(null).cancel().catchError((Object _) {}));
      final next = Uri.tryParse(location);
      final to = next == null ? null : at.resolveUri(next);
      if (to == null || !isWebUrl('$to')) throw ApiException(0, '${uri.origin} sent us to an address we can\'t use', uri: uri);
      if (hops >= maxRedirects) throw ApiException(0, 'Too many redirects from ${uri.origin}', uri: uri);
      if (!_sameServer(at, to)) extra = const {};
      // "See other" means fetch the answer with a plain GET.
      if (code == 303 && !reads) {
        verb = 'GET';
        payload = null;
      }
      at = to;
    }
    Uint8List bytes;
    try {
      bytes = await _read(streamed.stream, limit - clock.elapsed);
    } on TimeoutException {
      throw ApiException(0, 'Timed out reading from ${uri.origin}', uri: uri);
    } catch (_) {
      throw ApiException(0, 'Lost the connection to ${uri.origin}', uri: uri);
    }
    dynamic parsed;
    if (bytes.isNotEmpty) {
      try {
        parsed = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        parsed = null;
      }
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final msg = parsed is Map ? (parsed['message'] ?? parsed['error'] ?? '').toString() : '';
      throw ApiException(streamed.statusCode, msg.isNotEmpty ? msg : _statusText(streamed.statusCode), uri: uri, body: parsed);
    }
    return (body: parsed, headers: streamed.headers);
  }

  /// Reads the whole body, giving up (and letting go of the connection) after [limit].
  static Future<Uint8List> _read(Stream<List<int>> stream, Duration limit) {
    final out = BytesBuilder(copy: false);
    final done = Completer<Uint8List>();
    late final StreamSubscription<List<int>> sub;
    final timer = Timer(limit.isNegative ? Duration.zero : limit, () {
      if (done.isCompleted) return;
      unawaited(sub.cancel());
      done.completeError(TimeoutException('body', limit));
    });
    sub = stream.listen(
      out.add,
      onError: (Object e, StackTrace st) {
        timer.cancel();
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        timer.cancel();
        if (!done.isCompleted) done.complete(out.takeBytes());
      },
      cancelOnError: true,
    );
    return done.future;
  }

  Future<dynamic> send(String method, Uri uri, {Map<String, String> headers = const {}, Object? body, Duration? timeout}) async =>
      (await sendRaw(method, uri, headers: headers, body: body, timeout: timeout)).body;

  void close() => _client.close();

  /// [body] as a JSON object, or an ApiException with [message] when it's something else
  /// (an HTML page from the wrong address, say).
  static Map<String, dynamic> object(Object? body, String message) => body is Map<String, dynamic> ? body : throw ApiException(0, message);

  /// [body] as a JSON array, or an ApiException with [message].
  static List<dynamic> array(Object? body, String message) => body is List ? body : throw ApiException(0, message);

  /// The same host, and the same scheme and port or an upgrade from http to https.
  static bool _sameServer(Uri from, Uri to) => sameOrigin(from, to) || (from.isScheme('http') && to.isScheme('https') && from.host.toLowerCase() == to.host.toLowerCase());

  static String _statusText(int s) => switch (s) {
    401 => 'Not authorized (401). Check the token or API key.',
    403 => 'Access denied (403). Check the token or API key.',
    404 => 'Not found (404)',
    _ => 'Request failed ($s)',
  };
}
