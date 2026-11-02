import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  tearDown(forgetSecrets);

  group('redactSecrets', () {
    test('hides tokens and keys in addresses', () {
      final out = redactSecrets('Failed to open http://10.0.0.2:32400/library/parts/1/file.mkv?X-Plex-Token=abc123SECRET&X-Plex-Client-Identifier=console-1');
      expect(out, isNot(contains('abc123SECRET')));
      expect(out, contains('X-Plex-Token=<redacted>'));
      expect(out, contains('X-Plex-Client-Identifier=console-1'));
      expect(redactSecrets('https://x.test/a?apiKey=k1k1k1&b=2'), 'https://x.test/a?apiKey=<redacted>&b=2');
      expect(redactSecrets('https://x.test/a?api_key=k1k1k1'), 'https://x.test/a?api_key=<redacted>');
      expect(redactSecrets('https://x.test/a?token=zzz#x'), 'https://x.test/a?token=<redacted>#x');
      expect(redactSecrets('https://x.test/a?TOKEN=zzz'), 'https://x.test/a?TOKEN=<redacted>');
    });

    test('hides headers, cookies and JSON fields', () {
      expect(redactSecrets('{X-Plex-Token: abc123, X-Plex-Product: Liquiflux}'), '{X-Plex-Token: <redacted>, X-Plex-Product: Liquiflux}');
      expect(redactSecrets('X-Api-Key: MTY3NzQ0'), 'X-Api-Key: <redacted>');
      expect(redactSecrets('trakt-api-key: 0123abcd'), 'trakt-api-key: <redacted>');
      expect(redactSecrets('cookie: connect.sid=s%3Aabc.def; Path=/'), isNot(contains('abc.def')));
      expect(redactSecrets('set-cookie: connect.sid=s%3Aabc.def; HttpOnly'), isNot(contains('abc.def')));
      expect(redactSecrets('{"authToken":"plexAccountToken"}'), '{"authToken":"<redacted>"}');
      expect(redactSecrets('Authorization: Bearer eyJhbGciOi'), 'Authorization: Bearer <redacted>');
    });

    test('hides user:password in addresses', () {
      expect(redactSecrets('http://admin:hunter2@seerr.test/api'), 'http://<redacted>@seerr.test/api');
    });

    test('hides remembered secrets wherever they appear', () {
      rememberSecret('Zq9xW2plexToken');
      rememberSecret('ab'); // too short to hide everywhere
      expect(redactSecrets('GET /api/v2/pins/Zq9xW2plexToken failed'), 'GET /api/v2/pins/<redacted> failed');
      expect(redactSecrets('tab and ab'), 'tab and ab');
    });

    test('leaves ordinary text alone', () {
      const s = 'Could not reach http://192.168.1.10:32400 (Connection refused). Tokens: 3 left';
      expect(redactSecrets(s), s);
      expect(redactSecrets('tokenizer=fast'), 'tokenizer=fast');
    });

    test('errors are scrubbed when shown', () {
      expect(errorText(ApiException(401, 'bad X-Api-Key=abcdef')), 'bad X-Api-Key=<redacted>');
      expect('${ApiException(500, 'echo token=abcdef')}', 'echo token=<redacted>');
    });
  });

  group('links from servers', () {
    test('only plain web links open in the browser', () {
      expect(safeExternalUri('https://www.imdb.com/title/tt0133093/'), isNotNull);
      expect(safeExternalUri('http://seerr.local:5055/movie/603'), isNotNull);
      expect(safeExternalUri('file:///C:/Windows/System32/calc.exe'), isNull);
      expect(safeExternalUri('javascript:alert(1)'), isNull);
      expect(safeExternalUri('ms-settings:privacy'), isNull);
      expect(safeExternalUri('smb://evil.test/share'), isNull);
      expect(safeExternalUri('https://user:pw@evil.test/'), isNull);
      expect(safeExternalUri('//evil.test/x'), isNull);
      expect(safeExternalUri(''), isNull);
      expect(safeExternalUri(null), isNull);
    });

    test('yt-dlp only ever gets a YouTube address', () {
      expect(youtubeUrl(key: 'dQw4w9WgXcQ'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(youtubeUrl(key: '../../etc', url: 'https://youtu.be/dQw4w9WgXcQ'), 'https://youtu.be/dQw4w9WgXcQ');
      expect(youtubeUrl(url: 'https://www.youtube.com/watch?v=abc123def'), isNotNull);
      expect(youtubeUrl(url: 'http://www.youtube.com/watch?v=abc123def'), isNull);
      expect(youtubeUrl(url: 'https://youtube.com.evil.test/watch?v=abc'), isNull);
      expect(youtubeUrl(url: 'https://evil.test/?youtube.com'), isNull);
      expect(youtubeUrl(url: 'file:///etc/passwd'), isNull);
      expect(youtubeUrl(url: 'https://www.youtube.com:8443/watch?v=abc123def'), isNull);
      expect(youtubeUrl(key: '-o /tmp/x'), isNull);
    });
  });

  group('plain-text sign-in warning', () {
    test('http to the internet warns; local, VPN and https do not', () {
      expect(sendsCredentialsInClear('http://plex.example.com:32400'), isTrue);
      expect(sendsCredentialsInClear('http://81.2.3.4:32400'), isTrue);
      expect(sendsCredentialsInClear('https://plex.example.com'), isFalse);
      expect(sendsCredentialsInClear('http://192.168.1.10:32400'), isFalse);
      expect(sendsCredentialsInClear('http://10.0.0.5:5055'), isFalse);
      expect(sendsCredentialsInClear('http://100.101.102.103:32400'), isFalse); // Tailscale
      expect(sendsCredentialsInClear('http://nas:32400'), isFalse);
      expect(sendsCredentialsInClear('http://media.lan:32400'), isFalse);
      expect(sendsCredentialsInClear('http://[fd12:3456::1]:32400'), isFalse);
      expect(sendsCredentialsInClear('http://[2001:db8::1]:32400'), isTrue);
      expect(sendsCredentialsInClear('http://localhost:9001'), isFalse);
    });
  });

  group('custom mpv options', () {
    test('ordinary options pass, dangerous ones are refused', () {
      final r = mpvOptions(
        '# comment\n'
        'demuxer-max-bytes=400MiB\n'
        'tone-mapping=bt.2446a\n'
        'glsl-shaders=~~/shaders/FSR.glsl\n'
        'input-ipc-server=\\\\.\\pipe\\mpv\n'
        'script=C:\\evil.lua\n'
        'scripts-append=evil.js\n'
        'ytdl=yes\n'
        'ytdl-raw-options=exec=calc.exe\n'
        'load-unsafe-playlists=yes\n'
        'include=C:\\evil.conf\n'
        'input-conf=evil.conf\n'
        'log-file=C:\\Users\\me\\Startup\\x.bat\n'
        'demuxer-lavf-o=protocol_whitelist=[file,http]\n'
        'http-header-fields=X-Plex-Token: x\n'
        '--Script=x\n'
        'not an option\n',
      );
      expect(r.allowed, [('demuxer-max-bytes', '400MiB'), ('tone-mapping', 'bt.2446a'), ('glsl-shaders', '~~/shaders/FSR.glsl')]);
      expect(r.blocked, [
        'input-ipc-server',
        'script',
        'scripts-append',
        'ytdl',
        'ytdl-raw-options',
        'load-unsafe-playlists',
        'include',
        'input-conf',
        'log-file',
        'demuxer-lavf-o',
        'http-header-fields',
        '--Script',
      ]);
    });

    test('it is an allowlist: what the old block list missed is refused', () {
      // Write files, read local files, or change the network path (and so where the token goes).
      for (final name in const [
        'ao-pcm-file',
        'ao',
        'vo',
        'vo-image-outdir',
        'vo-image-format',
        'external-files',
        'external-file',
        'sub-file',
        'sub-files',
        'audio-file',
        'audio-files',
        'sub-auto',
        'audio-file-auto',
        'cover-art-files',
        'lavfi-complex',
        'vf',
        'af',
        'vf-add',
        'af-append',
        'http-proxy',
        'tls-verify',
        'tls-ca-file',
        'tls-cert-file',
        'user-agent',
        'referrer',
        'cookies',
        'cookies-file',
        'cache-dir',
        'cache-on-disk',
        'sub-fonts-dir',
        'sub-ass-styles',
        'icc-profile',
        'osd-msg1',
        'term-playing-msg',
        'playlist',
        'dump-stats',
        // The certificate checks MpvTls turns on stay out of a hand-edited options box.
        'tls-verify',
        'tls-ca-file',
        'tls-cert-file',
        'tls-key-file',
        'some-option-mpv-adds-next-year',
      ]) {
        expect(mpvOptionAllowed(name), isFalse, reason: name);
        expect(mpvOptionAllowed('--${name.toUpperCase()}'), isFalse, reason: name);
      }
      final r = mpvOptions('vf=movie=/etc/passwd\nao-pcm-file=C:\\Users\\me\\x.bat\nhttp-proxy=http://evil:8080\nsub-font-size=40\n');
      expect(r.allowed, [('sub-font-size', '40')]);
      expect(r.blocked, ['vf', 'ao-pcm-file', 'http-proxy']);
    });

    test('nothing on the allowlist takes a path, a filter graph or a network setting', () {
      final risky = RegExp(r'file|dir|path|script|ipc|ytdl|proxy|tls|header|cookie|agent|referrer|record|dump|log|conf|include|lavfi|playlist|^(vf|af|vo|ao)($|-)');
      for (final name in mpvAllowedOptions) {
        expect(risky.hasMatch(name), isFalse, reason: name);
        expect(name, matches(RegExp(r'^[a-z0-9][a-z0-9-]*$')));
        expect(mpvOptionAllowed(name), isTrue, reason: name);
      }
      // The one path-taking option on purpose: shaders only run on the GPU.
      expect(mpvOptionAllowed('glsl-shaders'), isTrue);
    });

    test('names are matched as typed: case and a leading -- are normalised, nothing else', () {
      expect(mpvOptions('--Deband=yes\nDEBAND-ITERATIONS=2\n').allowed, [('deband', 'yes'), ('deband-iterations', '2')]);
      for (final name in const ['deband\u0000', 'deband=', 'de band', '-deband', '---deband', 'no-deband', 'deband.x']) {
        expect(mpvOptionAllowed(name), isFalse, reason: name);
      }
      expect(mpvOptions('deband=yes\u0000\n').allowed, isEmpty);
    });
  });

  group('JsonHttp redirects', () {
    test('credentials stay behind when a redirect leaves the server', () async {
      final seen = <Uri, Map<String, String>>{};
      final client = MockClient((req) async {
        seen[req.url] = req.headers;
        if (req.url.host == 'seerr.test') return http.Response('', 302, headers: {'location': 'https://sso.evil.test/login'});
        return http.Response('{"ok":true}', 200);
      });
      final h = JsonHttp(client: client);
      expect(await h.send('GET', Uri.parse('http://seerr.test/api/v1/auth/me'), headers: {'X-Api-Key': 'k', 'X-Plex-Token': 't', 'cookie': 'connect.sid=s'}), {'ok': true});
      final sso = seen[Uri.parse('https://sso.evil.test/login')]!;
      expect(sso.keys.map((k) => k.toLowerCase()), isNot(anyOf(contains('x-api-key'), contains('x-plex-token'), contains('cookie'))));
    });

    test('an https upgrade on the same host keeps them', () async {
      final seen = <String, Map<String, String>>{};
      final client = MockClient((req) async {
        seen[req.url.scheme] = req.headers;
        if (req.url.scheme == 'http') return http.Response('', 301, headers: {'location': 'https://plex.test:32400/identity'});
        return http.Response('{}', 200);
      });
      await JsonHttp(client: client).send('GET', Uri.parse('http://plex.test:32400/identity'), headers: {'X-Plex-Token': 't'});
      expect(seen['https']!['X-Plex-Token'], 't');
    });

    test('a redirect to another kind of address is refused', () async {
      final client = MockClient((req) async => http.Response('', 302, headers: {'location': 'file:///etc/passwd'}));
      await expectLater(JsonHttp(client: client).send('GET', Uri.parse('http://plex.test/')), throwsA(isA<ApiException>()));
    });

    test('redirect loops give up', () async {
      var n = 0;
      final client = MockClient((req) async => http.Response('', 302, headers: {'location': '/again${n++}'}));
      await expectLater(JsonHttp(client: client).send('GET', Uri.parse('http://plex.test/')), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Too many'))));
      expect(n, JsonHttp.maxRedirects + 1);
    });

    test('a sign-in POST is not replayed by a redirect', () async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        if (req.url.path == '/api/v1/auth/plex') return http.Response('', 307, headers: {'location': 'https://evil.test/steal'});
        return http.Response('{}', 200);
      });
      await expectLater(JsonHttp(client: client).send('POST', Uri.parse('http://seerr.test/api/v1/auth/plex'), body: {'authToken': 'secret'}), throwsA(isA<ApiException>()));
      expect(bodies, hasLength(1));
    });
  });

  group('PlexClient keeps the token on the server', () {
    final plex = PlexClient(
      baseUrl: 'http://10.0.0.2:32400',
      token: 'tok',
      clientId: 'c',
      http: JsonHttp(client: MockClient((_) async => http.Response('{}', 200))),
    );

    PlexItem withPart(String key) => PlexItem.fromJson({
      'ratingKey': '1',
      'title': 'x',
      'type': 'clip',
      'Media': [
        {
          'id': 1,
          'Part': [
            {'id': 1, 'key': key},
          ],
        },
      ],
    });

    test('headers only go to the server itself', () {
      expect(plex.headersFor('http://10.0.0.2:32400/library/parts/1/file.mkv'), containsPair('X-Plex-Token', 'tok'));
      expect(plex.headersFor('https://trailers.example.com/clip.mp4'), isEmpty);
      expect(plex.headersFor('http://10.0.0.2:32401/x'), isEmpty);
      expect(plex.headersFor('http://10.0.0.2:32400@evil.test/x'), isEmpty);
    });

    test('server paths stay on the server', () {
      expect(plex.directPlayUrl(withPart('@evil.test/x')), isNull);
      expect(Uri.parse(plex.directPlayUrl(withPart('/library/parts/1/file.mkv'))!).host, '10.0.0.2');
      expect(Uri.parse(plex.fileUrl('@evil.test/sub.srt')).host, '10.0.0.2');
      expect(Uri.parse(plex.imageUrl('@evil.test/a.jpg', width: 1, height: 1)!).host, '10.0.0.2');
    });

    test('online extras get no token and must be web addresses', () {
      expect(plex.directPlayUrl(withPart('https://trailers.example.com/clip.mp4')), 'https://trailers.example.com/clip.mp4');
      expect(plex.directPlayUrl(withPart('file:///C:/secret.mkv')), isNull);
      expect(plex.directPlayUrl(withPart('httpx://evil.test/a')), isNull);
      expect(plex.directPlayUrl(withPart('')), isNull);
    });
  });

  test('the Plex token sent to Seerr never follows a redirect to another host', () async {
    final sent = <String, http.Request>{};
    final client = MockClient((req) async {
      sent[req.url.host] = req;
      if (req.url.host == 'seerr.test') return http.Response('', 303, headers: {'location': 'https://evil.test/'});
      return http.Response(jsonEncode({}), 200);
    });
    final seerr = SeerrClient(
      baseUrl: 'http://seerr.test',
      plexToken: 'plexAccountToken',
      http: JsonHttp(client: client),
    );
    await expectLater(seerr.me(), throwsA(isA<ApiException>()));
    expect(sent['seerr.test']!.body, contains('plexAccountToken'));
    expect(sent['evil.test']!.method, 'GET');
    expect(sent['evil.test']!.body, isEmpty);
    expect(sent['evil.test']!.headers.values.join(), isNot(contains('plexAccountToken')));
  });

  group('choosing a Plex address at sign-in', () {
    PlexServerResource server(List<PlexConnection> conns) => PlexServerResource(name: 'Home', machineIdentifier: 'abc123', accessToken: 'serverTok3n', owned: true, connections: conns);

    test('the probe sends no token and checks it is the same server', () async {
      final headers = <Map<String, String>>[];
      final client = MockClient((req) async {
        headers.add(req.headers);
        final id = req.url.host == '192.168.1.10' ? 'someone-elses' : 'abc123';
        return http.Response(
          jsonEncode({
            'MediaContainer': {'machineIdentifier': id},
          }),
          200,
        );
      });
      final picked = await PlexAuth(clientId: 'c').firstReachable(
        server([PlexConnection(uri: 'http://192.168.1.10:32400', local: true, relay: false), PlexConnection(uri: 'https://1-2-3-4.abc.plex.direct:32400', local: false, relay: false)]),
        probe: JsonHttp(client: client),
      );
      expect(picked, 'https://1-2-3-4.abc.plex.direct:32400');
      expect(headers.expand((h) => h.values), isNot(contains('serverTok3n')));
    });

    test('plain http across the internet is the last resort', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'MediaContainer': {'machineIdentifier': 'abc123'},
          }),
          200,
        ),
      );
      final probe = JsonHttp(client: client);
      final auth = PlexAuth(clientId: 'c');
      final both = server([PlexConnection(uri: 'http://81.2.3.4:32400', local: false, relay: false), PlexConnection(uri: 'https://81-2-3-4.abc.plex.direct:32400', local: false, relay: true)]);
      expect(await auth.firstReachable(both, probe: probe), 'https://81-2-3-4.abc.plex.direct:32400');
      final only = server([PlexConnection(uri: 'http://81.2.3.4:32400', local: false, relay: false)]);
      expect(await auth.firstReachable(only, probe: probe), 'http://81.2.3.4:32400');
    });

    test('on the LAN the https plex.direct address wins over plain http, whatever plex.tv\'s order', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'MediaContainer': {'machineIdentifier': 'abc123'},
          }),
          200,
        ),
      );
      final lan = server([
        PlexConnection(uri: 'http://192.168.1.20:32400', local: true, relay: false),
        PlexConnection(uri: 'https://81-2-3-4.abc.plex.direct:32400', local: false, relay: false),
        PlexConnection(uri: 'https://192-168-1-20.abc.plex.direct:32400', local: true, relay: false),
      ]);
      expect(lan.orderedConnections.map((c) => c.uri), ['https://192-168-1-20.abc.plex.direct:32400', 'http://192.168.1.20:32400', 'https://81-2-3-4.abc.plex.direct:32400']);
      expect(await PlexAuth(clientId: 'c').firstReachable(lan, probe: JsonHttp(client: client)), 'https://192-168-1-20.abc.plex.direct:32400');
    });

    test('a router that cannot resolve plex.direct falls back to the http address', () async {
      final client = MockClient((req) async {
        if (req.url.host.endsWith('plex.direct')) throw http.ClientException('Failed host lookup');
        return http.Response(
          jsonEncode({
            'MediaContainer': {'machineIdentifier': 'abc123'},
          }),
          200,
        );
      });
      final lan = server([
        PlexConnection(uri: 'https://192-168-1-20.abc.plex.direct:32400', local: true, relay: false),
        PlexConnection(uri: 'http://192.168.1.20:32400', local: true, relay: false),
      ]);
      expect(await PlexAuth(clientId: 'c').firstReachable(lan, probe: JsonHttp(client: client)), 'http://192.168.1.20:32400');
    });
  });

  group('the saved Plex address is checked before the token goes to it', () {
    http.Response identity(String id) => http.Response(
      jsonEncode({
        'MediaContainer': {'machineIdentifier': id},
      }),
      200,
    );

    test('another machine at the same LAN address never sees the token', () async {
      final sent = <http.Request>[];
      final client = MockClient((req) async {
        sent.add(req);
        return req.url.path == '/identity' ? identity('someone-elses') : http.Response(jsonEncode({'MediaContainer': {}}), 200);
      });
      final plex = PlexClient(baseUrl: 'http://192.168.1.20:32400', token: 'serverTok3n', clientId: 'c', http: JsonHttp(client: client), expectMachineId: 'abc123');
      await expectLater(plex.server(), throwsA(isA<ApiException>().having((e) => e.message, 'message', PlexClient.wrongServer)));
      await expectLater(plex.sections(), throwsA(isA<ApiException>()));
      await plex.markWatched(PlexItem.fromJson({'ratingKey': '1', 'title': 'x', 'type': 'movie'}));
      expect(sent.map((r) => r.url.path), ['/identity']);
      expect(sent.expand((r) => [...r.headers.values, r.url.query]).join(), isNot(contains('serverTok3n')));
    });

    test('the right server is asked once, then used as before', () async {
      final paths = <String>[];
      final client = MockClient((req) async {
        paths.add(req.url.path);
        if (req.url.path == '/identity') {
          expect(req.headers.containsKey('X-Plex-Token') || req.headers.containsKey('x-plex-token'), isFalse);
          return identity('abc123');
        }
        expect(req.headers['X-Plex-Token'] ?? req.headers['x-plex-token'], 'serverTok3n');
        return http.Response(
          jsonEncode({
            'MediaContainer': {'friendlyName': 'Homeserver', 'machineIdentifier': 'abc123'},
          }),
          200,
        );
      });
      final plex = PlexClient(baseUrl: 'http://192.168.1.20:32400', token: 'serverTok3n', clientId: 'c', http: JsonHttp(client: client), expectMachineId: 'abc123');
      expect((await plex.server()).name, 'Homeserver');
      await plex.sections();
      expect(paths, ['/identity', '/', '/library/sections']);
    });

    test('offline is asked again next time instead of being taken for a wrong server', () async {
      var up = false;
      final client = MockClient((req) async {
        if (!up) throw http.ClientException('Network is unreachable');
        return req.url.path == '/identity' ? identity('abc123') : http.Response(jsonEncode({'MediaContainer': {'friendlyName': 'Homeserver'}}), 200);
      });
      final plex = PlexClient(baseUrl: 'http://192.168.1.20:32400', token: 't', clientId: 'c', http: JsonHttp(client: client), expectMachineId: 'abc123');
      await expectLater(plex.server(), throwsA(isA<ApiException>().having((e) => e.message, 'message', isNot(PlexClient.wrongServer))));
      up = true;
      expect((await plex.server()).name, 'Homeserver');
    });

    test('a server that wants a token for /identity passes only over https', () async {
      final client = MockClient((req) async => req.url.path == '/identity' ? http.Response('', 401) : http.Response(jsonEncode({'MediaContainer': {}}), 200));
      final secure = PlexClient(baseUrl: 'https://192-168-1-20.abc.plex.direct:32400', token: 't', clientId: 'c', http: JsonHttp(client: client), expectMachineId: 'abc123');
      final plain = PlexClient(baseUrl: 'http://192.168.1.20:32400', token: 't', clientId: 'c', http: JsonHttp(client: client), expectMachineId: 'abc123');
      expect(await secure.isServer('abc123'), isTrue);
      expect(await plain.isServer('abc123'), isFalse);
    });

    test('with no saved id (an older sign-in) nothing extra is asked', () async {
      final paths = <String>[];
      final client = MockClient((req) async {
        paths.add(req.url.path);
        return http.Response(jsonEncode({'MediaContainer': {}}), 200);
      });
      await PlexClient(baseUrl: 'http://192.168.1.20:32400', token: 't', clientId: 'c', http: JsonHttp(client: client)).sections();
      expect(paths, ['/library/sections']);
    });
  });
}
