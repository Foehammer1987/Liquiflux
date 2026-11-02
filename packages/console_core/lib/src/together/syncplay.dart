import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../format.dart';

/// Someone in a Watch Together room.
class SyncPeer {
  SyncPeer({required this.name, required this.userId, required this.device, required this.ready, required this.me});
  final String name;
  final int? userId;
  final String device;
  final bool ready;
  final bool me;
}

sealed class SyncEvent {}

/// The room's play state, set by someone else: follow it.
class SyncRemote extends SyncEvent {
  SyncRemote({required this.position, required this.paused, required this.seek, this.by});
  final Duration position;
  final bool paused;

  /// They jumped: go to [position] whatever the gap.
  final bool seek;

  /// Who did it, for "Alex paused".
  final SyncPeer? by;
}

class SyncRoster extends SyncEvent {
  SyncRoster(this.peers);
  final List<SyncPeer> peers;
}

/// "Alex joined", "Sam left".
class SyncNotice extends SyncEvent {
  SyncNotice(this.text);
  final String text;
}

class SyncClosed extends SyncEvent {
  SyncClosed([this.error]);
  final String? error;
}

/// One player's side of a Plex Watch Together relay, which speaks the Syncplay protocol
/// (JSON messages, one per frame). The relay sends the room's state about once a second and
/// each player answers with its own; a player that pauses or jumps says so straight away.
///
/// This class is only the protocol, so it can be tested without a network: [connect] wires
/// it to a websocket.
class SyncplaySession {
  SyncplaySession({required this.roomId, required this.deviceId, required this.deviceName, required this.userId, required this.send, this.names = const {}, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String roomId;
  final String deviceId;
  final String deviceName;
  final int userId;

  /// Writes one message to the relay.
  final void Function(String frame) send;

  /// Display names by plex.tv user id (the room's members), so peers show as people.
  final Map<int, String> names;
  final DateTime Function() _clock;

  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  /// The relay and everyone in the room are strangers to this class: frames bigger than this
  /// are dropped unread, and the roster stops growing at [maxPeers].
  static const maxFrame = 256 * 1024;
  static const maxPeers = 64;

  /// The furthest into a title a room can ask us to go (48 hours); a position past it is
  /// nonsense and is ignored rather than followed.
  static const maxPosition = 48 * 3600.0;

  /// The name we go by in the room: who we are, as Plex Web expects it.
  late String username = _identity();

  String _identity() {
    // Plex keeps this under 150 bytes; a long device name is cut to fit.
    var name = deviceName.length > 150 ? deviceName.substring(0, 150) : deviceName;
    String build() => jsonEncode({'deviceIdentifier': deviceId, 'deviceName': name, 'userID': userId});
    while (utf8.encode(build()).length >= 150 && name.isNotEmpty) {
      name = name.substring(0, name.length - 1);
    }
    return build();
  }

  bool _helloDone = false;
  bool get joined => _helloDone;
  int _clientIgnore = 0;
  int _serverIgnore = 0;
  double? _latencyCalc;
  double _rtt = 0;
  double _forwardDelay = 0;
  DateTime _lastState = DateTime.fromMillisecondsSinceEpoch(0);
  final _peers = <String, SyncPeer>{};

  /// What our player is doing now; asked for each time we answer the relay. Null while no
  /// player is attached, so we never hold up the room.
  ({Duration position, bool paused})? Function()? local;

  double _now() => _clock().microsecondsSinceEpoch / 1e6;

  void _send(Map<String, Object?> m) => send(jsonEncode(m));

  void start() {
    _send({
      'Hello': {
        'username': username,
        'room': {'name': roomId},
        'version': '1.6.4',
        'realversion': '1.6.4',
        'features': {'sharedPlaylists': false, 'chat': false, 'readiness': true, 'managedRooms': false},
      },
    });
  }

  /// Our side changed because the viewer did something (play, pause, a jump): tell the room.
  void changed({required Duration position, required bool paused, bool seek = false}) => _sendState(position, paused, seek: seek, change: true);

  /// The relay stopped answering: speak up so it notices us again.
  void heartbeat() {
    if (!_helloDone || _clock().difference(_lastState) < const Duration(seconds: 3)) return;
    final l = local?.call();
    _sendState(l?.position, l?.paused);
  }

  void _sendState(Duration? position, bool? paused, {bool seek = false, bool change = false}) {
    if (!_helloDone) return;
    final state = <String, Object?>{};
    if ((_clientIgnore == 0 || _serverIgnore != 0) && position != null && paused != null) {
      state['playstate'] = {'position': position.inMilliseconds / 1000, 'paused': paused, if (seek) 'doSeek': true};
    }
    state['ping'] = {if (_latencyCalc != null) 'latencyCalculation': _latencyCalc, 'clientLatencyCalculation': _now(), 'clientRtt': _rtt};
    if (change) _clientIgnore++;
    if (_serverIgnore != 0 || _clientIgnore != 0) {
      state['ignoringOnTheFly'] = {if (_serverIgnore != 0) 'server': _serverIgnore, if (_clientIgnore != 0) 'client': _clientIgnore};
      _serverIgnore = 0;
    }
    _send({'State': state});
  }

  /// The relay may tack underscores onto a name it has seen twice.
  static String _plain(String name) => name.replaceAll(RegExp(r'_+$'), '');

  bool _isMe(String? name) => name != null && (name == username || _plain(name) == _plain(username));

  SyncPeer _peer(String name, {bool ready = false}) {
    int? id;
    var device = '';
    try {
      final j = jsonDecode(_plain(name));
      if (j is Map) {
        id = j['userID'] is int ? j['userID'] as int : int.tryParse('${j['userID']}');
        device = cleanLabel(j['deviceName'] is String ? j['deviceName'] as String : null, max: 40);
      }
    } catch (_) {}
    final known = id != null ? names[id] : null;
    final display = cleanLabel(known, max: 40).isNotEmpty ? cleanLabel(known, max: 40) : (device.isNotEmpty ? device : cleanLabel(_plain(name), max: 40, fallback: 'Someone'));
    return SyncPeer(name: display, userId: id, device: device, ready: ready, me: _isMe(name));
  }

  /// A finite number from the relay, or null for anything else.
  static double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

  void handle(String frame) {
    if (frame.length > maxFrame) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(frame) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    if (m['Hello'] is Map) {
      final given = (m['Hello'] as Map)['username'];
      if (given is String && given.isNotEmpty) username = given;
      _helloDone = true;
      _send({
        'Set': {
          'ready': {'isReady': true, 'manuallyInitiated': true},
        },
      });
      _send({'List': <String, Object?>{}});
    }
    if (m['Error'] is Map) {
      final message = (m['Error'] as Map)['message'];
      _events.add(SyncClosed(cleanLabel(message is String ? message : null, max: 200, fallback: 'The room closed')));
    }
    if (m['List'] is Map) _onList((m['List'] as Map).cast<String, dynamic>());
    if (m['Set'] is Map) _onSet((m['Set'] as Map).cast<String, dynamic>());
    if (m['State'] is Map) _onState((m['State'] as Map).cast<String, dynamic>());
  }

  void _onList(Map<String, dynamic> rooms) {
    _peers.clear();
    final room = rooms[roomId] ?? (rooms.length == 1 ? rooms.values.first : null);
    if (room is Map) {
      for (final e in room.entries.take(maxPeers)) {
        final info = e.value is Map ? e.value as Map : const {};
        _peers['${e.key}'] = _peer('${e.key}', ready: info['isReady'] == true);
      }
    }
    _events.add(SyncRoster(_peers.values.toList()));
  }

  void _onSet(Map<String, dynamic> set) {
    final user = set['user'];
    if (user is Map) {
      // A handful of notices per message is plenty; a flood would bury the player in them.
      for (final e in user.entries.take(8)) {
        final ev = e.value is Map ? (e.value as Map)['event'] : null;
        if (ev is! Map || _isMe('${e.key}')) continue;
        final p = _peer('${e.key}');
        if (ev['joined'] == true) _events.add(SyncNotice('${p.name} joined'));
        if (ev['left'] == true) _events.add(SyncNotice('${p.name} left'));
      }
      _send({'List': <String, Object?>{}});
    }
    final ready = set['ready'];
    if (ready is Map && ready['username'] is String) {
      final name = ready['username'] as String;
      if (!_peers.containsKey(name) && _peers.length >= maxPeers) return;
      _peers[name] = _peer(name, ready: ready['isReady'] == true);
      _events.add(SyncRoster(_peers.values.toList()));
    }
  }

  void _onState(Map<String, dynamic> s) {
    _lastState = _clock();
    final ignore = s['ignoringOnTheFly'];
    if (ignore is Map) {
      final server = _num(ignore['server']), client = _num(ignore['client']);
      if (server != null) {
        _serverIgnore = server.toInt().clamp(0, 1000);
        _clientIgnore = 0;
      } else if (client != null && client.toInt() == _clientIgnore) {
        _clientIgnore = 0;
      }
    }
    final ping = s['ping'];
    if (ping is Map) {
      // Echoed back as is, so only a plain number is kept (Infinity can't be sent as JSON).
      final latency = _num(ping['latencyCalculation']);
      if (latency != null) _latencyCalc = latency;
      final sentAt = _num(ping['clientLatencyCalculation']);
      if (sentAt != null) {
        final rtt = _now() - sentAt;
        final serverRtt = _num(ping['serverRtt']) ?? rtt;
        if (rtt >= 0 && rtt < 10) {
          _rtt = _rtt == 0 ? rtt : _rtt * 0.85 + rtt * 0.15;
          _forwardDelay = (_rtt / 2 + (serverRtt - _rtt).clamp(0, 2) / 2).clamp(0, 2).toDouble();
        }
      }
    }
    final ps = s['playstate'];
    // A position that isn't a number, or is further in than any title runs, is ignored: we
    // never jump somewhere nonsensical because someone said so. Before the start means the start.
    final rawPos = ps is Map ? ps['position'] : null;
    final given = rawPos == null ? 0.0 : _num(rawPos);
    if (ps is Map && _clientIgnore == 0 && given != null && given <= maxPosition) {
      final by = ps['setBy'] is String ? ps['setBy'] as String : null;
      final paused = ps['paused'] == true;
      var pos = given < 0 ? 0.0 : given;
      // The state left the relay a moment ago; a playing room has moved on since.
      if (!paused) pos += _forwardDelay;
      if (!_isMe(by)) {
        _events.add(
          SyncRemote(
            position: Duration(milliseconds: (pos * 1000).round()),
            paused: paused,
            seek: ps['doSeek'] == true,
            by: by == null ? null : _peer(by),
          ),
        );
      }
    }
    final l = local?.call();
    _sendState(l?.position, l?.paused);
  }

  /// Opens the relay at wss://[host]:[port]/ws and runs [session] over it until it closes.
  static Future<SyncplaySession> connect({
    required String host,
    required int port,
    required String roomId,
    required String deviceId,
    required String deviceName,
    required int userId,
    Map<int, String> names = const {},
    bool secure = true,
  }) async {
    // The relay's address comes from the room: a plain host name and a real port only.
    if (!RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]{0,252})$').hasMatch(host) || port < 1 || port > 65535) {
      throw ArgumentError('Not a usable Watch Together relay: $host:$port');
    }
    final opening = WebSocket.connect('${secure ? 'wss' : 'ws'}://$host:$port/ws');
    final WebSocket ws;
    try {
      ws = await opening.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Given up on, but it may still open: close it then rather than leave it dangling.
      unawaited(opening.then((w) => w.close(), onError: (Object _) {}));
      rethrow;
    }
    ws.pingInterval = const Duration(seconds: 20);
    final session = SyncplaySession(roomId: roomId, deviceId: deviceId, deviceName: deviceName, userId: userId, names: names, send: (f) => ws.readyState == WebSocket.open ? ws.add(f) : null);
    final beat = Timer.periodic(const Duration(seconds: 1), (_) => session.heartbeat());
    session._close = () async {
      beat.cancel();
      await ws.close();
    };
    ws.listen(
      (data) {
        // Text frames only, within reason. Some relays send several messages in one frame, a line each.
        if (data is! String || data.length > maxFrame) return;
        for (final line in data.split('\n')) {
          try {
            if (line.trim().isNotEmpty) session.handle(line.trim());
          } catch (_) {
            // One bad message mustn't take the room down.
            session._events.add(SyncNotice('Watch Together skipped a message it couldn’t read'));
          }
        }
      },
      onDone: () {
        beat.cancel();
        if (!session._closing) session._events.add(SyncClosed(ws.closeReason));
        session._events.close();
      },
      onError: (Object e) => session._events.add(SyncClosed('$e')),
    );
    session.start();
    return session;
  }

  Future<void> Function()? _close;
  bool _closing = false;

  Future<void> close() async {
    _closing = true;
    await _close?.call();
    if (_close == null && !_events.isClosed) await _events.close();
  }
}
