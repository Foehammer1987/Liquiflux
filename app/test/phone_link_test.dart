import 'dart:io';

import 'package:console_app/services/phone_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('the phone page: only at its random address, takes the form once', () async {
    final got = <Map<String, String>>[];
    var done = false;
    final link = (await PhoneLink.open(
      host: '127.0.0.1',
      title: 'Connect <AniList>',
      intro: 'Paste it',
      links: const [('Sign in', 'https://anilist.co/api/v2/oauth/authorize?client_id=1&response_type=token')],
      fields: const [PhoneField('token', 'Token', multiline: true)],
      onSubmit: (v) async {
        got.add(v);
        return v['token'] == 'bad' ? 'Not a token' : null;
      },
    ))!;
    link.onDone = () => done = true;
    final url = Uri.parse(link.url);
    expect(url.path.length, 33); // a slash and 32 hex digits

    final wrong = await http.get(url.replace(path: '/nope'));
    expect(wrong.statusCode, 404);

    final page = await http.get(url);
    expect(page.statusCode, 200);
    expect(page.body, contains('Connect &lt;AniList&gt;'));
    expect(page.body, contains('client_id=1&amp;response_type=token'));
    expect(page.headers['content-security-policy'], contains("default-src 'none'"));
    expect(page.headers['cache-control'], 'no-store');

    final json = await http.post(url, headers: {'content-type': 'application/json'}, body: '{}');
    expect(json.statusCode, HttpStatus.unsupportedMediaType);

    final bad = await http.post(url, body: {'token': 'bad', 'extra': 'ignored'});
    expect(bad.body, contains('Not a token'));
    expect(done, isFalse);

    final ok = await http.post(url, body: {'token': '  aa.bb.cc  '});
    expect(ok.body, contains('Look at your TV'));
    expect(got.last, {'token': 'aa.bb.cc'});
    expect(done, isTrue);
    await link.close();
    expect(link.closed, isTrue);
  });

  test('closes after 20 wrong addresses', () async {
    final link = (await PhoneLink.open(host: '127.0.0.1', title: 't', intro: 'i', fields: const [], onSubmit: (_) async => null))!;
    final url = Uri.parse(link.url);
    for (var i = 0; i < 20; i++) {
      await http.get(url.replace(path: '/guess$i'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(link.closed, isTrue);
  });
}
