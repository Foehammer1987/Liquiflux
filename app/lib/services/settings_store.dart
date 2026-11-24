import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:console_core/console_core.dart' show SpoilerPrefs, Taste, errorText, isWebUrl;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import 'doc_store.dart';
import 'playback_prefs.dart';
import 'safe_file.dart';

export 'playback_prefs.dart';

/// Everything the app needs to reconnect on launch.
class Settings {
  const Settings({
    this.plexUrl = '',
    this.plexToken = '',
    this.plexAccountToken = '',
    this.plexServerName = '',
    this.plexMachineId = '',
    this.seerrUrl = '',
    this.seerrApiKey = '',
    this.seerrUsePlexLogin = true,
    this.seerrEnabled = false,
    this.theme = 'dark',
    this.glass = true,
    this.homeTrailers = true,
    this.spotlightTrailers = false,
    this.traktClientId = '',
    this.traktClientSecret = '',
    this.anilistClientId = '',
    this.region = 'US',
    this.playback = const PlaybackPrefs(),
    this.taste = const Taste(),
    this.notifyReady = 'mine',
    this.pauseScreen = true,
    this.spoilers = const SpoilerPrefs(),
    this.watchName = '',
    this.riptideUrl = '',
    this.riptideEnabled = false,
    this.plexHomeToken = '',
    this.plexOwnerId = '',
    this.plexUserId = '',
    this.plexUserName = '',
    this.plexUserThumb = '',
    this.askProfile = false,
    this.profiles = const {},
    required this.clientId,
  });

  final String plexUrl;
  final String plexToken;

  /// The plex.tv account token from the Plex sign-in. [plexToken] is what the server gave
  /// us for itself (for a shared user, a token only that server knows); this one is what
  /// other services that "sign in with Plex" (the Riptide server) can check with plex.tv.
  /// Empty when the sign-in was a pasted token or made before this was kept.
  final String plexAccountToken;
  final String plexServerName;

  /// The machine id of the server [plexUrl] belongs to, from the sign-in (or the first
  /// launch that found it). Checked before the token goes to that address, so a different
  /// machine at the same LAN address on another network never sees it. Empty = learn it.
  final String plexMachineId;
  final String seerrUrl;
  final String seerrApiKey;

  /// Sign in to Seerr with the Plex account instead of an API key.
  final bool seerrUsePlexLogin;

  /// Seerr is an add-on for people who run one: off until turned on in Settings. Off keeps
  /// the address and sign-in but hides everything Seerr adds and never contacts it.
  final bool seerrEnabled;
  final String theme;

  /// Frosted, floating surfaces (off = flat panels, lighter on old GPUs).
  final bool glass;

  /// Play trailer clips behind the Home spotlight.
  final bool homeTrailers;

  /// On 32-bit Android, where [homeTrailers] can't apply: trailers only while focus is on the
  /// spotlight's buttons, their player freed when it leaves. Off until it has proved itself.
  final bool spotlightTrailers;

  /// A Trakt app's client ID; turns on Trakt's live trending charts. Kept with the other
  /// credentials, since it's what Trakt counts your usage against.
  final String traktClientId;

  /// That Trakt app's Client Secret: with the ID, lets Liquiflux sign in to Trakt for
  /// scrobbling (Settings > Tracking). Empty uses one baked into the build, if any.
  final String traktClientSecret;

  /// An AniList API client of the user's own (empty uses one baked into the build, if any). Not a secret.
  final String anilistClientId;

  /// Country for "Popular on Netflix" and friends, as a two-letter code.
  final String region;

  /// Player defaults: quality, tracks, subtitles, skipping, audio and video.
  final PlaybackPrefs playback;

  /// Thumbs up and down on recommendations.
  final Taste taste;

  /// Which finished requests pop a notification: mine, everyone or off.
  final String notifyReady;

  /// Show the title, synopsis and cast after a few seconds paused.
  final bool pauseScreen;

  /// What to keep hidden about episodes you haven't watched yet.
  final SpoilerPrefs spoilers;

  /// The name friends see in Watch Together (the Plex account name when empty).
  final String watchName;

  /// Where the Riptide scanner's who's-on-screen files are served from (empty = cast list only).
  final String riptideUrl;

  /// The Riptide server is an add-on too: off until turned on (the cast list needs only Plex).
  final bool riptideEnabled;

  /// The Riptide server to ask, or empty while it's turned off.
  String get riptideServer => riptideEnabled ? riptideUrl : '';

  /// The plex.tv token of the account that signed in, kept while another Plex Home user is
  /// in use so the Home can be listed and switched again. Empty = [plexTvToken] (no switch yet).
  final String plexHomeToken;

  /// The plex.tv uuid of the account that signed in (learned the first time the Home is listed).
  final String plexOwnerId;

  /// The Plex Home user in use: uuid, name and avatar. Empty id = the account that signed in.
  final String plexUserId;
  final String plexUserName;
  final String plexUserThumb;

  /// Ask "Who's watching?" each time Liquiflux opens (when the Home has more than one user).
  final bool askProfile;

  /// The other Home users' own settings (thumbs, spoilers, Watch Together name, per-show
  /// audio and subtitles), by uuid, kept while someone else is in use. See [profileData].
  final Map<String, Map<String, dynamic>> profiles;

  /// Stable per-install id that Plex shows under Authorized Devices.
  final String clientId;

  /// What lists and switches Plex Home users.
  String get homeToken => plexHomeToken.isNotEmpty ? plexHomeToken : plexTvToken;

  /// Which profile's things are in use: '' for the account that signed in.
  String get profileKey => plexUserId.isEmpty || plexUserId == plexOwnerId ? '' : plexUserId;

  /// The settings that belong to one person rather than to the device.
  Map<String, dynamic> profileData() => {
    'taste': taste.toJson(),
    'spoilers': spoilers.toJson(),
    'watchName': watchName,
    'showTracks': playback.toJson()['showTracks'],
  };

  /// These settings with the profile [to] in use: what belongs to the person in use now is put
  /// away under their key, and [to]'s comes out ('' = the account that signed in).
  Settings swapProfile(String to) {
    final from = profileKey;
    if (from == to) return this;
    final kept = {...profiles, from: profileData()};
    final next = withProfileData(kept.remove(to));
    return next.copyWith(profiles: kept);
  }

  /// Back to the account that signed in, forgetting which Home user was in use and the token
  /// kept for switching (before signing out, or signing in again).
  Settings backToOwner() {
    final s = swapProfile('');
    return Settings(
      plexUrl: s.plexUrl,
      plexToken: s.plexToken,
      plexAccountToken: s.plexAccountToken,
      plexServerName: s.plexServerName,
      plexMachineId: s.plexMachineId,
      seerrUrl: s.seerrUrl,
      seerrApiKey: s.seerrApiKey,
      seerrUsePlexLogin: s.seerrUsePlexLogin,
      seerrEnabled: s.seerrEnabled,
      theme: s.theme,
      glass: s.glass,
      homeTrailers: s.homeTrailers,
      spotlightTrailers: s.spotlightTrailers,
      traktClientId: s.traktClientId,
      traktClientSecret: s.traktClientSecret,
      anilistClientId: s.anilistClientId,
      region: s.region,
      playback: s.playback,
      taste: s.taste,
      notifyReady: s.notifyReady,
      pauseScreen: s.pauseScreen,
      spoilers: s.spoilers,
      watchName: s.watchName,
      riptideUrl: s.riptideUrl,
      riptideEnabled: s.riptideEnabled,
      askProfile: s.askProfile,
      profiles: s.profiles,
      clientId: s.clientId,
    );
  }

  /// These settings with [j]'s per-person part (a profile never used here starts fresh).
  Settings withProfileData(Map<String, dynamic>? j) {
    final d = j ?? const <String, dynamic>{};
    return copyWith(
      taste: Taste.fromJson(d['taste'] is Map<String, dynamic> ? d['taste'] as Map<String, dynamic> : null),
      spoilers: SpoilerPrefs.fromJson(d['spoilers']),
      watchName: d['watchName'] is String ? d['watchName'] as String : '',
      playback: playback.copyWith(showTracks: PlaybackPrefs.fromJson({'showTracks': d['showTracks']}).showTracks),
    );
  }

  bool get plexReady => plexUrl.isNotEmpty && plexToken.isNotEmpty;

  /// What to sign in to the Riptide server with: the account token when we have it, so the
  /// server can check with plex.tv who it is (allow lists work), else the server token.
  String get riptideSignInToken => plexTvToken;

  /// What plex.tv services (Seerr's Plex sign-in, Watch Together) are given: the account
  /// token when we have it, else the server token (the same thing for the server's owner).
  String get plexTvToken => plexAccountToken.isNotEmpty ? plexAccountToken : plexToken;
  bool get seerrReady => seerrEnabled && seerrUrl.isNotEmpty && (seerrApiKey.isNotEmpty || (seerrUsePlexLogin && plexToken.isNotEmpty));

  Settings copyWith({
    String? plexUrl,
    String? plexToken,
    String? plexAccountToken,
    String? plexServerName,
    String? plexMachineId,
    String? seerrUrl,
    String? seerrApiKey,
    bool? seerrUsePlexLogin,
    bool? seerrEnabled,
    String? theme,
    bool? glass,
    bool? homeTrailers,
    bool? spotlightTrailers,
    String? traktClientId,
    String? traktClientSecret,
    String? anilistClientId,
    String? region,
    PlaybackPrefs? playback,
    Taste? taste,
    String? notifyReady,
    bool? pauseScreen,
    SpoilerPrefs? spoilers,
    String? watchName,
    String? riptideUrl,
    bool? riptideEnabled,
    String? plexHomeToken,
    String? plexOwnerId,
    String? plexUserId,
    String? plexUserName,
    String? plexUserThumb,
    bool? askProfile,
    Map<String, Map<String, dynamic>>? profiles,
  }) => Settings(
    plexHomeToken: plexHomeToken ?? this.plexHomeToken,
    plexOwnerId: plexOwnerId ?? this.plexOwnerId,
    plexUserId: plexUserId ?? this.plexUserId,
    plexUserName: plexUserName ?? this.plexUserName,
    plexUserThumb: plexUserThumb ?? this.plexUserThumb,
    askProfile: askProfile ?? this.askProfile,
    profiles: profiles ?? this.profiles,
    playback: playback ?? this.playback,
    taste: taste ?? this.taste,
    notifyReady: notifyReady ?? this.notifyReady,
    pauseScreen: pauseScreen ?? this.pauseScreen,
    spoilers: spoilers ?? this.spoilers,
    watchName: watchName ?? this.watchName,
    riptideUrl: riptideUrl ?? this.riptideUrl,
    riptideEnabled: riptideEnabled ?? this.riptideEnabled,
    traktClientId: traktClientId ?? this.traktClientId,
    traktClientSecret: traktClientSecret ?? this.traktClientSecret,
    anilistClientId: anilistClientId ?? this.anilistClientId,
    region: region ?? this.region,
    plexUrl: plexUrl ?? this.plexUrl,
    plexToken: plexToken ?? this.plexToken,
    plexAccountToken: plexAccountToken ?? this.plexAccountToken,
    plexServerName: plexServerName ?? this.plexServerName,
    plexMachineId: plexMachineId ?? this.plexMachineId,
    seerrUrl: seerrUrl ?? this.seerrUrl,
    seerrApiKey: seerrApiKey ?? this.seerrApiKey,
    seerrUsePlexLogin: seerrUsePlexLogin ?? this.seerrUsePlexLogin,
    seerrEnabled: seerrEnabled ?? this.seerrEnabled,
    theme: theme ?? this.theme,
    glass: glass ?? this.glass,
    homeTrailers: homeTrailers ?? this.homeTrailers,
    spotlightTrailers: spotlightTrailers ?? this.spotlightTrailers,
    clientId: clientId,
  );
}

/// The country from the system locale (en_GB → GB), else US.
String _localRegion() {
  final m = RegExp(r'[_-]([A-Z]{2})').firstMatch(Platform.localeName);
  return m?.group(1) ?? 'US';
}

/// Where credentials are kept. [OsSecretStore] by default; tests hand in their own.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Every credential Liquiflux has stored (settings, Trakt and AniList sign-ins).
  Future<void> deleteAll();
}

/// The OS credential store: a DPAPI-encrypted file only this Windows account can read,
/// the Keychain on macOS, the Keystore on Android, and the Secret Service keyring
/// (GNOME Keyring, KWallet) through libsecret on Linux.
class OsSecretStore implements SecretStore {
  const OsSecretStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
  @override
  Future<void> deleteAll() => _s.deleteAll();
}

/// Addresses and preferences go in a JSON file; the Plex token, Seerr key and Trakt
/// client ID go in the OS credential store and nowhere else.
///
/// Older builds kept a credential in settings.json when the store wasn't there; such a file
/// is moved into the store on load and rewritten without it. With no credential store at
/// all (a Linux desktop without a keyring), credentials are never written in plain text:
/// they last until Liquiflux closes and [secureStorageOk] turns false so Settings can say so.
class SettingsStore {
  SettingsStore({SecretStore? secrets, Future<Directory> Function()? folder, this.forgetOnFreshInstall = false, DocStore? docs})
    : _secrets = secrets ?? const OsSecretStore(),
      _folder = folder ?? getApplicationSupportDirectory,
      _docs = docs;

  final SecretStore _secrets;
  final Future<Directory> Function() _folder;

  /// Where settings.json lives when it isn't a file of its own: user defaults on an Apple TV
  /// ([DefaultsDocStore]). Null keeps it in the support folder.
  final DocStore? _docs;
  static const _name = 'settings.json';

  /// Apple's keychain outlives the app: deleting Liquiflux from an iPhone, iPad or Mac
  /// leaves its sign-ins behind, and a reinstall would find them. With this set (on Apple
  /// platforms, see main.dart), a launch with no settings file, which is a fresh install,
  /// first clears whatever credentials an earlier install left, so deleting the app signs
  /// you out as you'd expect.
  final bool forgetOnFreshInstall;

  /// Credential store key for each secret setting.
  static const _keys = {'plexToken': 'plex_token', 'plexAccountToken': 'plex_account_token', 'plexHomeToken': 'plex_home_token', 'seerrApiKey': 'seerr_api_key', 'traktClientId': 'trakt_client_id', 'traktClientSecret': 'trakt_client_secret'};

  /// Where older builds left each secret inside settings.json.
  static const _plain = {
    'plexToken': ['_plexToken', 'plexToken'],
    'plexAccountToken': <String>[],
    'plexHomeToken': <String>[],
    'seerrApiKey': ['_seerrApiKey', 'seerrApiKey'],
    'traktClientId': ['traktClientId'],
    'traktClientSecret': <String>[],
  };

  /// False while the credential store can't be read or written: sign-ins then aren't
  /// remembered after closing.
  bool get secureStorageOk => _broken.isEmpty;

  /// Credential store keys whose last read or write failed.
  final _broken = <String>{};

  /// Credentials a dev build took from the environment (mock servers); never saved over
  /// the real ones.
  final _fromEnv = <String, String>{};

  /// What the credential store is known to hold, so an unchanged token isn't written again.
  final _stored = <String, String>{};
  final _saves = SaveQueue();
  Settings? _pending;

  Future<File> _file() async {
    final dir = await _folder();
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}$_name');
    if (!await f.exists()) await _carryOver(dir);
    return f;
  }

  /// The support folder is named after the app, so a rename would start from scratch.
  /// Copy the first build's folder (settings and any stored keys) across once.
  Future<void> _carryOver(Directory dir) async {
    final parent = dir.parent;
    for (final name in previousAppNames) {
      final old = Directory('${parent.path}${Platform.pathSeparator}$name');
      if (old.path == dir.path || !await old.exists()) continue;
      try {
        await for (final e in old.list()) {
          if (e is File) await e.copy('${dir.path}${Platform.pathSeparator}${e.uri.pathSegments.last}');
        }
        return;
      } catch (e) {
        debugPrint('settings carry-over: $e');
      }
    }
  }

  Future<Settings> load() async {
    Map<String, dynamic> j = {};
    try {
      final String? text;
      if (_docs case final docs?) {
        text = await docs.read(_name);
      } else {
        final f = await _file();
        text = await f.exists() ? await f.readAsString() : null;
      }
      if (forgetOnFreshInstall && text == null) await _forgetAll();
      if (text != null) {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) j = decoded;
      }
    } catch (e) {
      debugPrint('settings: ${e.runtimeType}'); // the message can quote the file
    }
    final env = Platform.environment; // lets a dev build point at mock servers
    var clientId = _str(j, 'clientId');
    if (clientId == null || !RegExp(r'^[\w.-]{1,64}$').hasMatch(clientId)) {
      final r = Random.secure();
      clientId = 'console-${List.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    }
    final secrets = <String, String>{};
    var plaintext = false;
    for (final field in _keys.keys) {
      final old = _plain[field]!.map((k) => _str(j, k)).firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      plaintext |= _plain[field]!.any(j.containsKey);
      secrets[field] = await _read(_keys[field]!) ?? old ?? '';
    }
    for (final (field, name) in const [('plexToken', 'CONSOLE_PLEX_TOKEN'), ('seerrApiKey', 'CONSOLE_SEERR_KEY'), ('traktClientId', 'CONSOLE_TRAKT_ID')]) {
      final v = env[name];
      if (v != null) _fromEnv[field] = v;
    }
    final seerrUrl = env['CONSOLE_SEERR_URL'] ?? _url(j, 'seerrUrl');
    // Riptide was called X-Ray before 1.1.2, and its settings were xrayUrl and xrayEnabled: read
    // those while the new keys aren't there. Saving writes only the new keys.
    final riptideUrl = j.containsKey('riptideUrl') ? _url(j, 'riptideUrl') : _url(j, 'xrayUrl');
    final s = Settings(
      plexUrl: env['CONSOLE_PLEX_URL'] ?? _url(j, 'plexUrl'),
      plexToken: env['CONSOLE_PLEX_TOKEN'] ?? secrets['plexToken']!,
      plexAccountToken: secrets['plexAccountToken']!,
      plexHomeToken: secrets['plexHomeToken']!,
      plexOwnerId: _id(j, 'plexOwnerId'),
      plexUserId: _id(j, 'plexUserId'),
      plexUserName: _str(j, 'plexUserName') ?? '',
      plexUserThumb: (_str(j, 'plexUserThumb') ?? '').startsWith('https://') ? _str(j, 'plexUserThumb')! : '',
      askProfile: _bool(j, 'askProfile') ?? false,
      profiles: {
        if (j['profiles'] is Map)
          for (final e in (j['profiles'] as Map).entries)
            if (e.key is String && RegExp(r'^[A-Za-z0-9-]{0,64}$').hasMatch(e.key as String) && e.value is Map<String, dynamic>) e.key as String: e.value as Map<String, dynamic>,
      },
      plexServerName: _str(j, 'plexServerName') ?? '',
      plexMachineId: env['CONSOLE_PLEX_URL'] != null ? '' : RegExp(r'^[\w.-]{1,128}$').hasMatch(_str(j, 'plexMachineId') ?? '') ? _str(j, 'plexMachineId')! : '',
      seerrUrl: seerrUrl,
      // Files from before the switches: an add-on with an address saved stays on.
      seerrEnabled: env['CONSOLE_SEERR_URL'] != null || (_bool(j, 'seerrEnabled') ?? seerrUrl.isNotEmpty),
      seerrApiKey: env['CONSOLE_SEERR_KEY'] ?? secrets['seerrApiKey']!,
      seerrUsePlexLogin: _bool(j, 'seerrUsePlexLogin') ?? true,
      theme: _str(j, 'theme') ?? 'dark',
      glass: _bool(j, 'glass') ?? true,
      homeTrailers: _bool(j, 'homeTrailers') ?? true,
      spotlightTrailers: _bool(j, 'spotlightTrailers') ?? false,
      traktClientId: env['CONSOLE_TRAKT_ID'] ?? secrets['traktClientId']!,
      traktClientSecret: secrets['traktClientSecret']!,
      anilistClientId: RegExp(r'^\d{1,10}$').hasMatch(_str(j, 'anilistClientId') ?? '') ? _str(j, 'anilistClientId')! : '',
      region: _str(j, 'region') ?? _localRegion(),
      playback: PlaybackPrefs.fromJson(j['playback'] is Map<String, dynamic> ? j['playback'] as Map<String, dynamic> : null),
      taste: Taste.fromJson(j['taste'] is Map<String, dynamic> ? j['taste'] as Map<String, dynamic> : null),
      notifyReady: _str(j, 'notifyReady') ?? 'mine',
      pauseScreen: _bool(j, 'pauseScreen') ?? true,
      spoilers: SpoilerPrefs.fromJson(j['spoilers']),
      watchName: _str(j, 'watchName') ?? '',
      riptideUrl: riptideUrl,
      riptideEnabled: _bool(j, 'riptideEnabled') ?? _bool(j, 'xrayEnabled') ?? riptideUrl.isNotEmpty,
      clientId: clientId,
    );
    // An older file with a credential in it: move it to the credential store and rewrite
    // the file without it. The first build's folder may hold a copy too.
    if (plaintext) await save(s);
    await _scrubPreviousFolders();
    return s;
  }

  static String? _str(Map<String, dynamic> j, String k) => j[k] is String ? j[k] as String : null;
  static bool? _bool(Map<String, dynamic> j, String k) => j[k] is bool ? j[k] as bool : null;

  /// A plex.tv uuid, or empty.
  static String _id(Map<String, dynamic> j, String k) {
    final v = _str(j, k) ?? '';
    return RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(v) ? v : '';
  }

  /// A saved server address, if it's a web address at all (never file: or the like).
  static String _url(Map<String, dynamic> j, String k) {
    final v = _str(j, k) ?? '';
    return v.isEmpty || isWebUrl(v) ? v : '';
  }

  /// Saves run one at a time; when several pile up, only the newest is written.
  Future<void> save(Settings s) {
    _pending = s;
    return _saves.run(() async {
      final next = _pending;
      _pending = null;
      if (next != null) await _saveNow(next);
    });
  }

  Future<void> _saveNow(Settings s) async {
    final j = <String, dynamic>{
      'plexUrl': s.plexUrl,
      'plexServerName': s.plexServerName,
      'plexMachineId': s.plexMachineId,
      'seerrUrl': s.seerrUrl,
      'seerrUsePlexLogin': s.seerrUsePlexLogin,
      'seerrEnabled': s.seerrEnabled,
      'theme': s.theme,
      'glass': s.glass,
      'homeTrailers': s.homeTrailers,
      'spotlightTrailers': s.spotlightTrailers,
      'region': s.region,
      'playback': s.playback.toJson(),
      'taste': s.taste.toJson(),
      'notifyReady': s.notifyReady,
      'pauseScreen': s.pauseScreen,
      'spoilers': s.spoilers.toJson(),
      'watchName': s.watchName,
      'riptideUrl': s.riptideUrl,
      'riptideEnabled': s.riptideEnabled,
      'anilistClientId': s.anilistClientId,
      'plexOwnerId': s.plexOwnerId,
      'plexUserId': s.plexUserId,
      'plexUserName': s.plexUserName,
      'plexUserThumb': s.plexUserThumb,
      'askProfile': s.askProfile,
      'profiles': s.profiles,
      'clientId': s.clientId,
    };
    final values = {'plexToken': s.plexToken, 'plexAccountToken': s.plexAccountToken, 'plexHomeToken': s.plexHomeToken, 'seerrApiKey': s.seerrApiKey, 'traktClientId': s.traktClientId, 'traktClientSecret': s.traktClientSecret};
    for (final e in values.entries) {
      if (_fromEnv[e.key] != e.value) await _write(_keys[e.key]!, e.value);
    }
    final text = const JsonEncoder.withIndent('  ').convert(j);
    if (_docs case final docs?) {
      await docs.write(_name, text);
    } else {
      await writeAtomically(await _file(), text);
    }
  }

  /// Takes credentials out of settings.json in the folders of the app's earlier names.
  Future<void> _scrubPreviousFolders() async {
    try {
      final parent = (await _folder()).parent;
      for (final name in previousAppNames) {
        final f = File('${parent.path}${Platform.pathSeparator}$name${Platform.pathSeparator}settings.json');
        if (!await f.exists()) continue;
        final j = jsonDecode(await f.readAsString());
        if (j is! Map<String, dynamic>) continue;
        final before = j.length;
        for (final names in _plain.values) {
          names.forEach(j.remove);
        }
        if (j.length != before) await writeAtomically(f, const JsonEncoder.withIndent('  ').convert(j));
      }
    } catch (e) {
      debugPrint('settings scrub: ${e.runtimeType}');
    }
  }

  Future<void> _forgetAll() async {
    try {
      await _secrets.deleteAll();
      debugPrint('settings: a fresh install, so sign-ins left by an earlier one are gone');
    } catch (e) {
      debugPrint('secure storage clear failed: ${errorText(e)}');
    }
  }

  Future<String?> _read(String key) async {
    try {
      final v = await _secrets.read(key);
      _stored[key] = v ?? '';
      return v == null || v.isEmpty ? null : v;
    } catch (e) {
      _broken.add(key);
      debugPrint('secure storage read failed: ${errorText(e)}');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    if (_stored[key] == value) return;
    // Couldn't read it at launch, so empty here means unknown, not signed out: leave it be.
    if (value.isEmpty && !_stored.containsKey(key)) return;
    try {
      if (value.isEmpty) {
        await _secrets.delete(key);
      } else {
        await _secrets.write(key, value);
      }
      _stored[key] = value;
      _broken.remove(key);
    } catch (e) {
      _stored.remove(key);
      _broken.add(key);
      debugPrint('secure storage write failed: ${errorText(e)}');
    }
  }
}
