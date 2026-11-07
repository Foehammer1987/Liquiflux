import 'dart:async';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../state/app_state.dart';

/// Watch Together through Plex's own rooms, so friends on Plex Web can join in too.
/// Holds the room you're in and its sync link; the player follows it while it plays the
/// room's title. Invitations are checked every minute.
class WatchTogether extends ChangeNotifier {
  WatchTogether(this.app);
  final AppState app;

  TogetherClient? _client;
  PlexAccount? account;
  List<PlexFriend>? friends;

  TogetherRoom? room;
  SyncplaySession? sync;
  List<SyncPeer> peers = const [];
  bool busy = false;
  String? error;

  final _events = StreamController<SyncEvent>.broadcast();

  /// The room's play state and comings and goings, for the player.
  Stream<SyncEvent> get events => _events.stream;

  /// Invitations from friends, once each.
  final invites = StreamController<TogetherRoom>.broadcast();
  final _seen = <String>{};
  Timer? _poll;
  bool _primed = false;

  /// Our player's state, handed to the relay whenever it asks.
  ({Duration position, bool paused})? Function()? local;

  static final _env = Platform.environment;

  TogetherClient? get client {
    final s = app.settings;
    if (s.plexToken.isEmpty) return null;
    if (_client?.token != s.plexTvToken) {
      _client?.close();
      _client = TogetherClient(token: s.plexTvToken, clientId: s.clientId, product: appName, baseUrl: _env['CONSOLE_TOGETHER_URL'], plexTvUrl: _env['CONSOLE_PLEXTV_URL']);
    }
    return _client;
  }

  /// A dev relay runs without TLS.
  bool get _secure => !(_env['CONSOLE_TOGETHER_URL'] ?? '').startsWith('http://');

  bool inRoomFor(String ratingKey) => room?.ratingKey == ratingKey && sync != null;

  /// Why it didn't work, in words for the viewer.
  static String explain(Object e) {
    if (e is ApiException && (e.status == 401 || e.status == 403)) {
      return 'Plex turned this down. Watch Together needs Liquiflux signed in with your own Plex account (Settings, Servers, Plex Media Server, Sign In Again).';
    }
    if (e is ApiException && e.status == 400) return 'Plex only lets you invite friends and people in your Plex Home.';
    if (e is ApiException && e.status == 410) return 'Plex has switched off this part of Watch Together. Room codes still work.';
    if (e is ApiException && e.status == 0) return 'Couldn’t reach Plex’s Watch Together service.';
    return 'Watch Together didn’t work: ${errorText(e)}';
  }

  Future<PlexAccount?> me() async {
    final c = client;
    if (c == null) return null;
    return account ??= await c.me();
  }

  Future<List<PlexFriend>> loadFriends() async {
    final c = client;
    if (c == null) return const [];
    return friends ??= await c.friends();
  }

  /// Looks for invitations now and every minute. The first look counts rooms you're
  /// already in as known, apart from ones friends made for you.
  void watchInvites() {
    _poll?.cancel();
    if (client == null) return;
    unawaited(_checkInvites());
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => _checkInvites());
  }

  Future<void> _checkInvites() async {
    final c = client;
    if (c == null) return;
    try {
      final me = await this.me();
      final list = await c.rooms();
      if (!_primed) debugPrint('watch together: plex rooms answered, ${list.length} open');
      var shown = 0;
      for (final r in list) {
        if (!_seen.add(r.id)) continue;
        // Only a room that says who made it is offered, and only a few at a time: a flood of
        // rooms would otherwise become a flood of cards and notifications.
        final from = r.createdBy;
        if (from == null || from.id == 0 || from.id == me?.id || r.id == room?.id || r.id.isEmpty) continue;
        if (shown++ < 3) invites.add(r);
      }
      _primed = true;
    } on ApiException catch (e) {
      debugPrint('watch together: plex rooms ${e.status}: ${errorText(e)}');
      // Not a plex.tv account token (or no Watch Together): stop asking.
      if (e.status == 401 || e.status == 403 || e.status == 404) _poll?.cancel();
    } catch (e) {
      debugPrint('invites: $e');
    }
  }

  bool get primed => _primed;

  /// Makes a room for [item], asks [invite] in, and joins it.
  Future<bool> start(PlexItem item, List<int> invite) async {
    final c = client;
    final machine = app.server?.machineIdentifier;
    if (c == null || machine == null || machine.isEmpty) {
      error = 'Connect to your Plex server first.';
      notifyListeners();
      return false;
    }
    final title = item.type == 'episode' ? '${item.grandparentTitle ?? ''} · ${item.title}' : item.title;
    return _run(() async {
      await leave();
      final r = await c.create(machineId: machine, ratingKey: item.ratingKey, title: title, users: invite);
      _seen.add(r.id);
      // Some Plex versions skip the invite list on create; asking again is harmless.
      if (invite.isNotEmpty && r.users.length <= 1) await c.invite(r.id, invite).catchError((Object _) {});
      await _connect(r);
    });
  }

  /// Joins a room a friend asked you into.
  Future<bool> join(TogetherRoom r) => _run(() async {
    await leave();
    await _connect(r);
  });

  Future<bool> invite(List<int> users) async {
    final c = client, r = room;
    if (c == null || r == null || users.isEmpty) return false;
    return _run(() => c.invite(r.id, users));
  }

  /// Can this room's title be played here? Only when it's on the server Liquiflux uses.
  bool playableHere(TogetherRoom r) => r.machineId != null && r.machineId == app.server?.machineIdentifier;

  Future<bool> _run(Future<void> Function() job) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await job();
      return true;
    } catch (e) {
      debugPrint('watch together: ${errorText(e)}');
      error = explain(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// A bare host name or IP address for the sync relay, as Plex hands out; anything else
  /// (a path, user info, odd characters) isn't connected to.
  static final _relayHost = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$');

  Future<void> _connect(TogetherRoom r) async {
    if (!_relayHost.hasMatch(r.host) || r.port <= 0 || r.port > 65535) throw ApiException(0, 'Plex gave an unusable address for the Watch Together relay.');
    debugPrint('watch together: room ${r.id} relay ${r.host}:${r.port}');
    final me = await this.me();
    final names = {for (final u in r.users) u.id: u.title, if (r.createdBy != null) r.createdBy!.id: r.createdBy!.title, if (me != null) me.id: me.title};
    final host = Platform.localHostname;
    final s = await SyncplaySession.connect(
      host: r.host,
      port: r.port,
      roomId: r.id,
      deviceId: app.settings.clientId,
      deviceName: '$appName on ${host.isEmpty ? 'PC' : host}',
      userId: me?.id ?? 0,
      names: names,
      secure: _secure,
    );
    s.local = () => local?.call();
    room = r;
    sync = s;
    peers = const [];
    s.events.listen((e) {
      if (e is SyncRoster) {
        peers = e.peers;
        notifyListeners();
      }
      if (e is SyncClosed && identical(sync, s)) {
        error = e.error == null || e.error!.isEmpty ? 'The Watch Together room closed.' : 'The Watch Together room closed: ${errorText(e.error)}';
        sync = null;
        room = null;
        peers = const [];
        notifyListeners();
      }
      if (!_events.isClosed) _events.add(e);
    });
    notifyListeners();
  }

  /// Leaves the room you're in, if any.
  Future<void> leave() async {
    final s = sync, r = room;
    sync = null;
    room = null;
    peers = const [];
    notifyListeners();
    await s?.close();
    if (r != null) await client?.leave(r.id).catchError((Object _) {});
  }

  /// A fresh connection (another account or server): forget everything.
  void reset() {
    unawaited(leave());
    _poll?.cancel();
    _seen.clear();
    _primed = false;
    account = null;
    friends = null;
    error = null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(sync?.close());
    _client?.close();
    unawaited(_events.close());
    unawaited(invites.close());
    super.dispose();
  }
}
