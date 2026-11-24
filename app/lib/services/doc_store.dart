import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'safe_file.dart';

/// Where the app keeps a named document of its own (settings.json, channels.json): the user's
/// data, as opposed to caches it can fetch again.
///
/// Everywhere but an Apple TV these are files in the support folder, read and written by the
/// stores themselves; a store given a [DocStore] keeps its document here instead.
abstract class DocStore {
  /// The document's text, or null when there is none.
  Future<String?> read(String name);

  /// Replaces the document.
  Future<void> write(String name, String text);
}

/// A key-value store of strings: user defaults on an Apple TV ([TvosDefaults]), a map in tests.
abstract class KeyValueStore {
  Future<String?> get(String key);

  /// Stores [value], or removes the key for null.
  Future<void> set(String key, String? value);
}

/// An Apple TV keeps its documents in user defaults: tvOS may purge an app's files (even
/// Application Support) when the box runs short of space, which would sign nobody out (the
/// tokens are in the Keychain) but would lose every setting and channel. Caches stay files.
///
/// A document an earlier build left as a file in [legacy] is moved across the first time
/// it's read: copied into user defaults, then the file is deleted.
class DefaultsDocStore implements DocStore {
  DefaultsDocStore({required this.values, required Future<Directory> Function() legacy}) : _legacy = legacy;

  final KeyValueStore values;
  final Future<Directory> Function() _legacy;

  /// tvOS keeps an app's user defaults small (Apple documents a limit around 500 KB for all
  /// of them together), so one document may use at most this much.
  static const maxChars = 256 * 1024;

  static String key(String name) => 'liquiflux.doc.$name';

  @override
  Future<String?> read(String name) async {
    final v = await values.get(key(name));
    if (v != null) return v;
    return _migrate(name);
  }

  Future<String?> _migrate(String name) async {
    try {
      final f = File('${(await _legacy()).path}${Platform.pathSeparator}$name');
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      if (text.length > maxChars) return text; // too big for defaults: read it, leave the file
      await values.set(key(name), text);
      await f.delete();
      debugPrint('$name moved into user defaults');
      return text;
    } catch (e) {
      debugPrint('$name migration: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> write(String name, String text) async {
    if (text.length > maxChars) {
      // Better a file tvOS might purge than nothing at all.
      debugPrint('$name is too big for user defaults (${text.length} characters); kept as a file');
      await writeAtomically(File('${(await _legacy()).path}${Platform.pathSeparator}$name'), text);
      await values.set(key(name), null);
      return;
    }
    await values.set(key(name), text);
  }
}

/// The Apple TV's user defaults (NSUserDefaults.standard), through the liquiflux_tvos plugin.
class TvosDefaults implements KeyValueStore {
  const TvosDefaults();
  static const _channel = MethodChannel('liquiflux/tvos');

  @override
  Future<String?> get(String key) => _channel.invokeMethod<String>('defaultsGet', {'key': key});

  @override
  Future<void> set(String key, String? value) => _channel.invokeMethod('defaultsSet', {'key': key, 'value': value});
}
