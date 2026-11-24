import 'dart:convert';
import 'dart:io';

import 'package:console_app/services/channels.dart';
import 'package:console_app/services/doc_store.dart';
import 'package:console_app/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_store_test.dart' show FakeSecrets;

/// User defaults in memory.
class MemoryValues implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

/// The Apple TV keeps settings and channels in user defaults ([DefaultsDocStore]), since
/// tvOS may purge the app's files; a file an earlier build left is moved across.
void main() {
  late Directory dir;
  late MemoryValues defaults;
  late DefaultsDocStore docs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('liquiflux-tvos');
    defaults = MemoryValues();
    docs = DefaultsDocStore(values: defaults, legacy: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File file(String name) => File('${dir.path}/$name');

  test('settings are saved in user defaults, with no file and no credential in them', () async {
    final secrets = FakeSecrets();
    final store = SettingsStore(secrets: secrets, folder: () async => dir, forgetOnFreshInstall: true, docs: docs);
    final s = await store.load();
    await store.save(s.copyWith(plexUrl: 'https://plex.example:32400', plexToken: 'secret-token', theme: 'light'));

    final saved = defaults.values[DefaultsDocStore.key('settings.json')]!;
    expect(jsonDecode(saved), containsPair('plexUrl', 'https://plex.example:32400'));
    expect(saved, isNot(contains('secret-token')));
    expect(secrets.values['plex_token'], 'secret-token');
    expect(file('settings.json').existsSync(), isFalse);

    final again = await SettingsStore(secrets: secrets, folder: () async => dir, forgetOnFreshInstall: true, docs: docs).load();
    expect(again.plexUrl, 'https://plex.example:32400');
    expect(again.theme, 'light');
    expect(again.plexToken, 'secret-token');
  });

  test('a settings.json from an earlier build moves into user defaults on first run', () async {
    file('settings.json').writeAsStringSync(jsonEncode({'plexUrl': 'https://old.example:32400', 'theme': 'light', 'clientId': 'console-abc'}));
    final secrets = FakeSecrets()..values['plex_token'] = 'kept';
    final s = await SettingsStore(secrets: secrets, folder: () async => dir, forgetOnFreshInstall: true, docs: docs).load();

    expect(s.plexUrl, 'https://old.example:32400');
    expect(s.clientId, 'console-abc');
    // Not a fresh install: the sign-in stays.
    expect(s.plexToken, 'kept');
    expect(file('settings.json').existsSync(), isFalse);
    expect(defaults.values[DefaultsDocStore.key('settings.json')], contains('old.example'));
  });

  test('with nothing in user defaults or on disk it is a fresh install: old sign-ins go', () async {
    final secrets = FakeSecrets()..values['plex_token'] = 'left by a deleted install';
    final s = await SettingsStore(secrets: secrets, folder: () async => dir, forgetOnFreshInstall: true, docs: docs).load();
    expect(s.plexToken, isEmpty);
    expect(secrets.values, isEmpty);
  });

  test('channels are kept in user defaults and read back', () async {
    final a = ChannelStore(docs: docs);
    await a.load('server-1');
    await a.save();
    expect(defaults.values[DefaultsDocStore.key('channels.json')], contains('server-1'));
    expect(file('channels.json').existsSync(), isFalse);

    // An earlier build's channels.json moves across the same way.
    final old = DefaultsDocStore(values: MemoryValues(), legacy: () async => dir);
    file('channels.json').writeAsStringSync(
      jsonEncode({
        'servers': {'server-2': <String, dynamic>{}},
      }),
    );
    final b = ChannelStore(docs: old);
    await b.load('server-2');
    expect(file('channels.json').existsSync(), isFalse);
    expect(await old.read('channels.json'), contains('server-2'));
  });

  test('a document too big for user defaults stays a file', () async {
    final big = 'x' * (DefaultsDocStore.maxChars + 1);
    await docs.write('channels.json', big);
    expect(defaults.values, isEmpty);
    expect(file('channels.json').readAsStringSync(), big);
    expect(await docs.read('channels.json'), big);
  });
}
