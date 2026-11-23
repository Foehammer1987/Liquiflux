import 'dart:convert';

import 'package:console_core/console_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

PlexItem movie() => PlexItem(ratingKey: '42', key: '/library/metadata/42', type: 'movie', title: 'Film');

void main() {
  group('transcodeDecision', () {
    late List<http.Request> seen;
    PlexClient client(Map<String, dynamic> container) {
      seen = [];
      return PlexClient(
        baseUrl: 'https://plex.example:32400',
        token: 'tok',
        clientId: 'c',
        http: JsonHttp(
          client: MockClient((req) async {
            seen.add(req);
            return http.Response(jsonEncode({'MediaContainer': container}), 200, headers: {'content-type': 'application/json'});
          }),
        ),
      );
    }

    test('asks /decision with the same request as start.m3u8, token in the headers only', () async {
      final plex = client({'generalDecisionCode': 1001, 'generalDecisionText': 'Direct play not available; Conversion OK.', 'transcodeDecisionCode': 1001});
      final start = plex.transcodeUrl(movie(), session: 's1', maxBitrateKbps: 3000, resolution: '1280x720');
      final d = await plex.transcodeDecision(start);
      expect(d.refused, isFalse);
      expect(d.generalCode, 1001);
      final r = seen.single;
      expect(r.url.path, '/video/:/transcode/universal/decision');
      expect(r.url.queryParameters['session'], 's1');
      expect(r.url.queryParameters['maxVideoBitrate'], '3000');
      expect(r.url.queryParameters['protocol'], 'hls');
      expect(r.url.queryParameters.containsKey('X-Plex-Token'), isFalse);
      expect(r.headers['X-Plex-Token'], 'tok');
    });

    test('a 2xxx or 3xxx code is a refusal, with the server\'s most specific reason', () async {
      final plex = client({'generalDecisionCode': 2000, 'generalDecisionText': 'Neither direct play nor conversion is available.', 'transcodeDecisionCode': 4005, 'transcodeDecisionText': 'No transcode target for this client.'});
      final d = await plex.transcodeDecision(plex.transcodeUrl(movie(), session: 's2'));
      expect(d.refused, isTrue);
      expect(d.reason, 'No transcode target for this client.');
    });

    test('a server without decision codes is not a refusal', () async {
      final plex = client({});
      final d = await plex.transcodeDecision(plex.transcodeUrl(movie(), session: 's3'));
      expect(d.refused, isFalse);
      expect(d.reason, isNotEmpty);
    });

    test('only for a transcode address on this server', () async {
      final plex = client({});
      expect(() => plex.transcodeDecision('https://elsewhere.example/video/:/transcode/universal/start.m3u8'), throwsArgumentError);
      expect(() => plex.transcodeDecision('https://plex.example:32400/library/parts/1/file.mkv'), throwsArgumentError);
      expect(seen, isEmpty);
    });
  });

  group('client profile', () {
    PlexClient on(String platform) => PlexClient(baseUrl: 'https://plex.example:32400', token: 'tok', clientId: 'c', platform: platform);

    test('macOS and Linux ask for the Generic profile and state the HLS target', () {
      for (final p in ['macOS', 'Linux']) {
        final plex = on(p);
        expect(plex.headers['X-Plex-Client-Profile-Name'], 'Generic', reason: p);
        expect(plex.headers['X-Plex-Platform'], p, reason: 'the dashboard still shows the real system');
        final q = Uri.parse(plex.transcodeUrl(movie(), session: 's')).queryParameters;
        expect(q['X-Plex-Client-Profile-Extra'], contains('protocol=hls'), reason: p);
        expect(q['X-Plex-Client-Profile-Extra'], contains('videoCodec=h264'), reason: p);
      }
    });

    test('Windows, Android and iOS keep the server\'s own profile, as before', () {
      for (final p in ['Windows', 'Android', 'iOS']) {
        final plex = on(p);
        expect(plex.headers.containsKey('X-Plex-Client-Profile-Name'), isFalse, reason: p);
        expect(Uri.parse(plex.transcodeUrl(movie(), session: 's')).queryParameters.containsKey('X-Plex-Client-Profile-Extra'), isFalse, reason: p);
      }
    });

    test('the decision is asked with the same profile', () async {
      final seen = <http.Request>[];
      final plex = PlexClient(
        baseUrl: 'https://plex.example:32400',
        token: 'tok',
        clientId: 'c',
        platform: 'macOS',
        http: JsonHttp(
          client: MockClient((req) async {
            seen.add(req);
            return http.Response(jsonEncode({'MediaContainer': {'generalDecisionCode': 1001}}), 200, headers: {'content-type': 'application/json'});
          }),
        ),
      );
      await plex.transcodeDecision(plex.transcodeUrl(movie(), session: 's'));
      expect(seen.single.headers['X-Plex-Client-Profile-Name'], 'Generic');
      expect(seen.single.url.queryParameters['X-Plex-Client-Profile-Extra'], PlexClient.hlsProfileExtra);
    });
  });
}

