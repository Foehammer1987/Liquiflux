import 'dart:convert';
import 'dart:io';

import 'package:console_app/services/settings_store.dart';
import 'package:console_core/console_core.dart' show ResumeMode, SpoilerPrefs;
import 'package:flutter_test/flutter_test.dart';

/// An in-memory credential store; [broken] makes every call fail like a missing keyring.
class FakeSecrets implements SecretStore {
  final values = <String, String>{};
  bool broken = false;

  void _check() {
    if (broken) throw Exception('The name org.freedesktop.secrets was not provided by any .service files');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    values.remove(key);
  }
}

void main() {
  late Directory root;
  late Directory dir;
  late File file;

  setUp(() {
    root = Directory.systemTemp.createTempSync('liquiflux-settings');
    dir = Directory('${root.path}/Liquiflux')..createSync();
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => root.deleteSync(recursive: true));

  SettingsStore store(FakeSecrets secrets) => SettingsStore(secrets: secrets, folder: () async => dir);

  Future<Map<String, dynamic>> saved() async => jsonDecode(await file.readAsString()) as Map<String, dynamic>;

  test('credentials go to the credential store, never settings.json', () async {
    final secrets = FakeSecrets();
    final s = store(secrets);
    final loaded = await s.load();
    await s.save(loaded.copyWith(plexUrl: 'http://10.0.0.2:32400', plexToken: 'plexTok3n', plexAccountToken: 'acctTok3n', seerrApiKey: 'seerrK3y', traktClientId: 'traktId1'));
    final text = await file.readAsString();
    expect(text, isNot(contains('plexTok3n')));
    expect(text, isNot(contains('acctTok3n')));
    expect(text, isNot(contains('seerrK3y')));
    expect(text, isNot(contains('traktId1')));
    expect(secrets.values, {'plex_token': 'plexTok3n', 'plex_account_token': 'acctTok3n', 'seerr_api_key': 'seerrK3y', 'trakt_client_id': 'traktId1'});
    final again = await store(secrets).load();
    expect(again.plexToken, 'plexTok3n');
    expect(again.plexAccountToken, 'acctTok3n');
    expect(again.riptideSignInToken, 'acctTok3n');
    expect(again.seerrApiKey, 'seerrK3y');
    expect(again.traktClientId, 'traktId1');
    expect(again.plexUrl, 'http://10.0.0.2:32400');
  });

  test('an older settings.json holding credentials is moved and scrubbed', () async {
    file.writeAsStringSync(jsonEncode({'plexUrl': 'http://10.0.0.2:32400', '_plexToken': 'oldTok3n', 'seerrApiKey': 'oldK3y', 'traktClientId': 'oldTrakt', 'clientId': 'console-abc'}));
    final old = Directory('${root.path}/Console')..createSync();
    File('${old.path}/settings.json').writeAsStringSync(jsonEncode({'_plexToken': 'oldTok3n', 'theme': 'light'}));
    final secrets = FakeSecrets();
    final s = await store(secrets).load();
    expect(s.plexToken, 'oldTok3n');
    expect(s.seerrApiKey, 'oldK3y');
    expect(s.traktClientId, 'oldTrakt');
    expect(s.clientId, 'console-abc');
    expect(secrets.values, {'plex_token': 'oldTok3n', 'seerr_api_key': 'oldK3y', 'trakt_client_id': 'oldTrakt'});
    final j = await saved();
    expect(j.keys, isNot(anyOf(contains('_plexToken'), contains('plexToken'), contains('seerrApiKey'), contains('_seerrApiKey'), contains('traktClientId'))));
    expect(j['plexUrl'], 'http://10.0.0.2:32400');
    final oldText = File('${old.path}/settings.json').readAsStringSync();
    expect(oldText, isNot(contains('oldTok3n')));
    expect(oldText, contains('light'));
  });

  test('the credential store wins over a stale copy in the file', () async {
    file.writeAsStringSync(jsonEncode({'_plexToken': 'stale'}));
    final secrets = FakeSecrets()..values['plex_token'] = 'current';
    expect((await store(secrets).load()).plexToken, 'current');
    expect(await file.readAsString(), isNot(contains('stale')));
  });

  test('without a credential store nothing is written in plain text', () async {
    file.writeAsStringSync(jsonEncode({'_plexToken': 'linuxTok3n', 'plexUrl': 'http://10.0.0.2:32400'}));
    final secrets = FakeSecrets()..broken = true;
    final s = store(secrets);
    final loaded = await s.load();
    // Still signed in for this session…
    expect(loaded.plexToken, 'linuxTok3n');
    expect(s.secureStorageOk, isFalse);
    // …but the token never stays on disk.
    expect(await file.readAsString(), isNot(contains('linuxTok3n')));
    await s.save(loaded.copyWith(seerrApiKey: 'k3yk3y'));
    expect(await file.readAsString(), isNot(contains('k3yk3y')));
  });

  test('a credential that could not be read is not wiped by the next save', () async {
    final secrets = FakeSecrets()
      ..values['plex_token'] = 'keepMe'
      ..broken = true;
    final s = store(secrets);
    final loaded = await s.load();
    expect(loaded.plexToken, '');
    secrets.broken = false; // the keyring unlocks later
    await s.save(loaded.copyWith(theme: 'light'));
    expect(secrets.values['plex_token'], 'keepMe');
  });

  test('a tampered settings file loads with defaults instead of failing', () async {
    file.writeAsStringSync(
      jsonEncode({
        'plexUrl': 'file:///etc/passwd',
        'seerrUrl': 42,
        'theme': ['dark'],
        'glass': 'yes',
        'playback': 'oops',
        'taste': [1, 2],
        'clientId': 'bad\r\nX-Injected: 1',
        'region': null,
      }),
    );
    final s = await store(FakeSecrets()).load();
    expect(s.plexUrl, '');
    expect(s.seerrUrl, '');
    expect(s.theme, 'dark');
    expect(s.glass, isTrue);
    expect(s.clientId, matches(RegExp(r'^console-[0-9a-f]{24}$')));
  });

  test('spoiler and resume choices are saved, and tampered ones read as off / ask', () async {
    final st = store(FakeSecrets());
    final s = await st.load();
    await st.save(s.copyWith(spoilers: const SpoilerPrefs(images: true, titles: true), playback: s.playback.copyWith(resumeMode: ResumeMode.start)));
    final back = await store(FakeSecrets()).load();
    expect((back.spoilers.images, back.spoilers.summaries, back.spoilers.titles), (true, false, true));
    expect(back.playback.resumeMode, ResumeMode.start);

    final j = await saved();
    file.writeAsStringSync(jsonEncode({...j, 'spoilers': {'images': 'yes', 'titles': 1}, 'playback': {...(j['playback'] as Map), 'resumeMode': '../start'}}));
    final odd = await store(FakeSecrets()).load();
    expect(odd.spoilers.any, isFalse);
    expect(odd.playback.resumeMode, ResumeMode.ask);
  });

  test('a settings file that is not JSON loads with defaults', () async {
    file.writeAsStringSync('{"plexUrl": "http://x", "_plexToken": "abc'); // cut short
    final s = await store(FakeSecrets()).load();
    expect(s.plexUrl, '');
    expect(s.plexToken, '');
  });

  test("the server's machine id is kept with the address, and a tampered one is dropped", () async {
    final secrets = FakeSecrets();
    final s = store(secrets);
    await s.save((await s.load()).copyWith(plexUrl: 'https://192-168-1-20.abc.plex.direct:32400', plexToken: 'tok', plexMachineId: '0123456789abcdef0123456789abcdef01234567'));
    expect((await store(secrets).load()).plexMachineId, '0123456789abcdef0123456789abcdef01234567');
    await file.writeAsString(jsonEncode({...await saved(), 'plexMachineId': '../../x y'}));
    expect((await store(secrets).load()).plexMachineId, '');
  });

  test('plex.tv services get the account token when there is one', () {
    const owner = Settings(clientId: 'c', plexToken: 'server');
    const friend = Settings(clientId: 'c', plexToken: 'server', plexAccountToken: 'account');
    expect(owner.plexTvToken, 'server');
    expect(friend.plexTvToken, 'account');
    expect(friend.riptideSignInToken, 'account');
  });

  test('the Riptide server is kept, and only as a web address', () async {
    final secrets = FakeSecrets();
    final s = store(secrets);
    await s.save((await s.load()).copyWith(riptideUrl: 'http://riptide.local:8089'));
    expect((await store(secrets).load()).riptideUrl, 'http://riptide.local:8089');
    await file.writeAsString(jsonEncode({...await saved(), 'riptideUrl': 'file:///etc/passwd'}));
    expect((await store(secrets).load()).riptideUrl, '');
  });

  test('Seerr and Riptide start off, and older files that set them up keep them on', () async {
    final secrets = FakeSecrets();
    final fresh = await store(secrets).load();
    expect(fresh.seerrEnabled, isFalse);
    expect(fresh.riptideEnabled, isFalse);
    // From before the switches (and before the rename, so the old key): an address saved
    // means it was in use.
    await file.writeAsString(jsonEncode({'seerrUrl': 'http://seerr.local:5055', 'xrayUrl': 'http://riptide.local:8089', 'clientId': 'console-abc'}));
    final old = await store(secrets).load();
    expect(old.seerrEnabled, isTrue);
    expect(old.riptideEnabled, isTrue);
    expect(old.riptideServer, 'http://riptide.local:8089');
    // Turned off, the addresses stay for next time.
    final s = store(secrets);
    await s.save(old.copyWith(seerrEnabled: false, riptideEnabled: false));
    final off = await store(secrets).load();
    expect(off.seerrEnabled, isFalse);
    expect(off.riptideEnabled, isFalse);
    expect(off.seerrUrl, 'http://seerr.local:5055');
    expect(off.riptideUrl, 'http://riptide.local:8089');
    expect(off.riptideServer, '');
  });

  group('settings saved before X-Ray became Riptide', () {
    test('old keys only are read', () async {
      await file.writeAsString(jsonEncode({'xrayUrl': 'http://riptide.local:8089', 'xrayEnabled': false, 'clientId': 'console-abc'}));
      final s = await store(FakeSecrets()).load();
      expect(s.riptideUrl, 'http://riptide.local:8089');
      expect(s.riptideEnabled, isFalse);
      await file.writeAsString(jsonEncode({'xrayUrl': 'http://riptide.local:8089', 'xrayEnabled': true, 'clientId': 'console-abc'}));
      expect((await store(FakeSecrets()).load()).riptideServer, 'http://riptide.local:8089');
    });

    test('new keys only', () async {
      await file.writeAsString(jsonEncode({'riptideUrl': 'https://riptide.example.com', 'riptideEnabled': true, 'clientId': 'console-abc'}));
      final s = await store(FakeSecrets()).load();
      expect(s.riptideUrl, 'https://riptide.example.com');
      expect(s.riptideServer, 'https://riptide.example.com');
    });

    test('both present: the new keys win', () async {
      await file.writeAsString(jsonEncode({
        'xrayUrl': 'http://old.local:8089',
        'xrayEnabled': true,
        'riptideUrl': 'https://riptide.example.com',
        'riptideEnabled': false,
        'clientId': 'console-abc',
      }));
      final s = await store(FakeSecrets()).load();
      expect(s.riptideUrl, 'https://riptide.example.com');
      expect(s.riptideEnabled, isFalse);
      // A cleared new address isn't filled in from the old key.
      await file.writeAsString(jsonEncode({'xrayUrl': 'http://old.local:8089', 'riptideUrl': '', 'clientId': 'console-abc'}));
      expect((await store(FakeSecrets()).load()).riptideUrl, '');
    });

    test('saving writes the new keys and drops the old ones', () async {
      final secrets = FakeSecrets();
      await file.writeAsString(jsonEncode({'xrayUrl': 'http://riptide.local:8089', 'xrayEnabled': true, 'clientId': 'console-abc'}));
      final s = store(secrets);
      await s.save(await s.load());
      final j = await saved();
      expect(j['riptideUrl'], 'http://riptide.local:8089');
      expect(j['riptideEnabled'], isTrue);
      expect(j.containsKey('xrayUrl'), isFalse);
      expect(j.containsKey('xrayEnabled'), isFalse);
      final again = await store(secrets).load();
      expect(again.riptideServer, 'http://riptide.local:8089');
    });
  });
}
