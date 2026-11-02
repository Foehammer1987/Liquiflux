import 'dart:async';
import 'dart:io';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';
import 'package:openwatchparty/openwatchparty.dart' as owp;

import '../app_info.dart';
import '../state/app_state.dart';
import '../ui/player/player_session.dart';

/// Watch Together by room code, through Open Watch Party (the rooms Plezy uses): anyone with
/// the code joins from Liquiflux or Plezy, on their own server. Each person plays their own
/// copy and the relay keeps the copies in step.
///
/// The room picks the title. When it names one, [opens] asks the app to open the player on
/// it, and the player [attach]es. While attached, the viewer's play, pause and jumps go to the
/// room (see [PlayerSession.room]) and the room drives the player.
class OpenParty extends ChangeNotifier implements RoomControl {
  OpenParty(this.app);
  final AppState app;

  owp.WatchParty<String>? _party;
  owp.PartyState<String> state = const owp.PartyState.initial();
  StreamSubscription<owp.PartyState<String>>? _states;
  StreamSubscription<owp.PartyEvent>? _events;

  /// The room's code, as shown (K7M-Q2X).
  String? code;
  bool busy = false;
  String? error;

  /// The title the room plays, for the player to open.
  final opens = StreamController<PlexItem>.broadcast();

  PlayerSession? _session;
  _SessionAdapter? _adapter;
  Timer? _leaveTimer;
  bool _opening = false;
  String? _openedKey;

  static final _env = Platform.environment;

  /// The public relays, or one of your own (CONSOLE_OWP_RELAY, for testing).
  static final owp.Relays relays = _env['CONSOLE_OWP_RELAY'] != null ? owp.Relays.at(_env['CONSOLE_OWP_RELAY']!) : owp.Relays.public();

  bool get inRoom => _party != null && code != null;
  bool get isHost => state.isHost;
  bool get canControl => state.canControl;
  bool inRoomFor(String ratingKey) => inRoom && state.choice?.ref == ratingKey;

  /// The player showing now, if any.
  PlayerSession? get session => _session;

  /// Everyone in the room, connected or not.
  List<owp.Participant> get people => state.room?.participants ?? const [];

  @override
  bool get leads => isHost;

  /// Why it didn't work, in words for the viewer.
  static String explain(Object e) {
    if (e is owp.PartyException) {
      return switch (e.code) {
        'room_not_found' => 'There’s no room with that code. Check it and try again.',
        'room_full' => 'That room is full.',
        'room_locked' => 'The host has locked that room.',
        'unreachable' => 'Couldn’t reach the Watch Together relay. Check the connection and try again.',
        'invalid_code' => 'That isn’t a room code. Codes are six letters and numbers, like K7M-Q2X.',
        'rate_limited' => 'Too many tries. Wait a moment and try again.',
        'not_host' => 'Only the host can do that.',
        _ => 'Watch Together didn’t work (${e.code}).',
      };
    }
    return 'Watch Together didn’t work: ${errorText(e)}';
  }

  Future<owp.WatchParty<String>> _newParty() async {
    await _drop();
    var name = appName;
    try {
      name = (await app.watchTogether.me())?.title ?? appName;
    } catch (_) {}
    name = roomText(name) ?? appName;
    if (name.length > 32) name = name.substring(0, 32);
    final p = owp.WatchParty<String>(relays: relays, client: '$appName/$appVersion', name: name, resolver: _PlexResolver(app));
    _party = p;
    _states = p.states.listen(_onState);
    _events = p.events.listen(_onEvent);
    return p;
  }

  /// Opens a room playing [item] and makes you its host. The player opens on its own.
  Future<bool> start(PlexItem item) => _run(() async {
    final media = await _describe(item);
    final p = await _newParty();
    code = owp.formatCode(await p.create());
    debugPrint('room: opened for a ${media.kind.name} (ids ${media.ids.keys.join('/')})');
    p.setMedia(media, item.ratingKey, positionMs: _session?.item.ratingKey == item.ratingKey ? _session!.position.inMilliseconds : 0);
  });

  /// Joins a room by its code, as typed.
  Future<bool> join(String typed) => _run(() async {
    final c = roomCode(typed);
    if (c == null) throw const owp.PartyException(owp.ErrorCode.invalidCode, 'bad code');
    final p = await _newParty();
    await p.join(c);
    code = c;
  });

  Future<owp.Media> _describe(PlexItem item) async {
    final plex = app.plex;
    final machine = app.server?.machineIdentifier ?? '';
    if (plex == null) throw StateError('Connect to your Plex server first.');
    if (!roomKind(item)) throw StateError('Only movies and episodes can be watched together.');
    final full = item.media.isEmpty || item.guids.isEmpty ? (await plex.metadata(item.ratingKey) ?? item) : item;
    PlexItem? show;
    if (full.type == 'episode' && full.grandparentRatingKey != null) {
      show = await plex.metadata(full.grandparentRatingKey!).catchError((Object _) => null);
    }
    final media = describeForRoom(full, show: show, machineId: machine);
    if (media == null) throw StateError('Plex didn’t say how long this title is, so it can’t be shared.');
    return media;
  }

  Future<bool> _run(Future<void> Function() job) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await job();
      return true;
    } catch (e) {
      debugPrint('room: $e');
      error = e is StateError ? e.message : explain(e);
      await _drop();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ the room

  void _onState(owp.PartyState<String> s) {
    if (s.connection != state.connection || s.match != state.match || s.choice?.ref != state.choice?.ref) {
      debugPrint('room: ${s.connection.name}, match ${s.match?.state.name ?? '-'}, choice ${s.choice?.ref ?? '-'}, ${s.room?.participants.length ?? 0} people');
    }
    state = s;
    if (s.room?.code case final c? when c.isNotEmpty) code = owp.formatCode(c);
    notifyListeners();
    unawaited(_follow());
  }

  /// Opens the room's title when it isn't the one playing, and attaches the player that is.
  Future<void> _follow() async {
    final ref = state.choice?.ref;
    final s = _session;
    if (ref == null || _party == null) return;
    if (s != null && s.item.ratingKey == ref) {
      _attach(s);
      return;
    }
    if (_opening || _openedKey == ref) return;
    _opening = true;
    try {
      final item = await app.plex?.metadata(ref);
      if (item == null || state.choice?.ref != ref || _party == null) return;
      _openedKey = ref;
      opens.add(item);
    } catch (e) {
      debugPrint('room title: $e');
    } finally {
      _opening = false;
    }
  }

  void _onEvent(owp.PartyEvent e) {
    if (e is! owp.ActionEvent) debugPrint('room event: $e');
    String who(owp.Participant? p) => p == null ? 'Someone' : cleanLabel(p.name, max: 32, fallback: 'Someone');
    final text = switch (e) {
      owp.ActionEvent(byMe: false, :final kind, :final by) => switch (kind) {
        'play' => '${who(by)} pressed play',
        'pause' => '${who(by)} paused',
        'seek' => '${who(by)} jumped to ${_clock(e.room.positionMs)}',
        'rate' => '${who(by)} set the speed to ${e.room.rate}×',
        'media' => '${who(by)} picked something new',
        'stall' => 'Waiting for ${e.room.waitingOn.length == 1 ? 'someone' : 'everyone'} to catch up',
        'host' => '${who(e.room.host)} is the host now',
        _ => null,
      },
      owp.ParticipantJoinedEvent(:final participant) => '${who(participant)} joined',
      owp.ParticipantLeftEvent(:final participant) => '${who(participant)} left',
      owp.ErrorEvent(:final error) => error.code == 'not_host' ? 'Only the host can do that in this room.' : null,
      owp.PlayBlockedEvent() => 'Press play to join in',
      owp.ResolveFailedEvent() => 'Couldn’t look for this title on your server.',
      owp.EndedEvent(:final reason) => switch (reason) {
        owp.EndReason.left => null,
        owp.EndReason.ended => 'The host ended the room.',
        owp.EndReason.kicked => 'You were removed from the room.',
        owp.EndReason.expired => 'The room ran out of time.',
        _ => 'Lost the Watch Together room.',
      },
      _ => null,
    };
    if (e is owp.EndedEvent) {
      if (text != null) error = text;
      unawaited(_drop());
    }
    if (text != null) _session?.flash(text);
  }

  static String _clock(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  // ------------------------------------------------------------------ the player

  /// A player opened. If it plays the room's title, the room drives it from now on. If the
  /// host started something else (Up Next, another episode), the room moves to it.
  void attach(PlayerSession s) {
    _leaveTimer?.cancel();
    _session = s;
    if (_party == null) return;
    final ref = state.choice?.ref;
    if (ref == s.item.ratingKey) {
      _attach(s);
    } else if (isHost) {
      unawaited(_moveTo(s));
    } else {
      // A guest who wanders off to something else has left the room.
      unawaited(leave());
      s.flash('You left the Watch Together room');
    }
  }

  void _attach(PlayerSession s) {
    final p = _party;
    if (p == null || (identical(_adapter?.session, s) && s.room == this)) return;
    final a = _SessionAdapter(s);
    _adapter = a;
    s.room = this;
    p.attachPlayer(a, s.item.ratingKey);
  }

  Future<void> _moveTo(PlayerSession s) async {
    try {
      final media = await _describe(s.item);
      if (!identical(_session, s) || _party == null) return;
      _openedKey = s.item.ratingKey;
      _party!.setMedia(media, s.item.ratingKey);
    } catch (e) {
      s.flash('Couldn’t share this title with the room');
    }
  }

  /// The player is closing. The room is left a moment later unless another player takes over
  /// (Up Next swaps the player for a new one).
  Future<void> detach(PlayerSession s) async {
    if (!identical(_session, s)) return;
    _session = null;
    s.room = null;
    final a = _adapter;
    _adapter = null;
    if (a != null) await _party?.detachPlayer(a);
    _leaveTimer?.cancel();
    if (_party != null) _leaveTimer = Timer(const Duration(seconds: 3), () => unawaited(leave()));
  }

  /// Leaves the room (the host leaving hands it to someone else).
  Future<void> leave() async {
    _leaveTimer?.cancel();
    _session?.room = null;
    await _drop();
    notifyListeners();
  }

  /// Plays your copy though its length differs from the host's.
  void acceptMismatch() => _party?.acceptMismatch();

  /// Ends the room for everyone (host only).
  void end() {
    if (isHost) _party?.end();
  }

  Future<void> _drop() async {
    final p = _party;
    _party = null;
    code = null;
    _openedKey = null;
    _adapter = null;
    _session?.room = null;
    state = const owp.PartyState.initial();
    await _states?.cancel();
    await _events?.cancel();
    _states = null;
    _events = null;
    await p?.close();
  }

  // ------------------------------------------------------------------ RoomControl

  @override
  void play() => _command((p) => p.play());

  @override
  void pause() => _command((p) => p.pause());

  @override
  Future<void> seek(Duration to) async => _command((p) => p.seek(to.inMilliseconds));

  @override
  Future<void> setRate(double rate) async => _command((p) => p.setRate(rate.clamp(owpMinRate, owpMaxRate).toDouble()));

  static const owpMinRate = 0.5, owpMaxRate = 2.0;

  void _command(void Function(owp.WatchParty<String> p) run) {
    final p = _party;
    if (p == null) return;
    if (!canControl) {
      _session?.flash('Only the host can do that in this room.');
      return;
    }
    try {
      run(p);
    } catch (e) {
      _session?.flash(explain(e));
    }
  }

  @override
  void dispose() {
    _leaveTimer?.cancel();
    unawaited(_drop());
    unawaited(opens.close());
    super.dispose();
  }
}

/// Our player as the room sees it. The room's moves use the player's Direct calls, so they
/// don't come back to the room as the viewer's.
final class _SessionAdapter extends owp.PlayerAdapter {
  _SessionAdapter(this.session);
  final PlayerSession session;

  @override
  int get positionMs => session.position.inMilliseconds;

  @override
  int? get durationMs {
    final d = session.duration.inMilliseconds;
    return d > 0 ? d : null;
  }

  @override
  bool get paused => !session.player.state.playing;

  @override
  bool get buffering => session.player.state.buffering;

  @override
  bool get firstFrameShown => session.ready && session.resumeOffer == null;

  @override
  bool get canSetRate => true;

  /// A transcode restarts at a keyframe, so it lands a few seconds off.
  @override
  int get seekAccuracyMs => session.transcoding ? 3000 : 0;

  @override
  Future<void> play() => session.player.play();

  @override
  Future<void> pause() => session.player.pause();

  @override
  Future<void> setRate(double rate) => session.setRateDirect(rate);

  /// Done once the player is there (or ten seconds on).
  @override
  Future<void> seek(int positionMs) async {
    final to = Duration(milliseconds: positionMs);
    await session.seekDirect(to);
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 10)) {
      final off = (session.position - to).abs();
      if (watch.elapsedMilliseconds >= 200 && !session.player.state.buffering && off <= Duration(milliseconds: 1500 + seekAccuracyMs)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Finds your own copy of the room's title on your Plex server: the exact item when the host
/// is on the same server, else by catalogue ids, else by title.
final class _PlexResolver implements owp.Resolver<String> {
  _PlexResolver(this.app);
  final AppState app;

  @override
  Future<List<owp.Candidate<String>>> resolve(owp.Media media, owp.Cancellation cancel) async {
    final plex = app.plex;
    if (plex == null) return const [];
    final out = <owp.Candidate<String>>[];
    final seen = <String>{};
    void add(PlexItem i) {
      if (seen.add(i.ratingKey)) out.add(_candidate(plex, i));
    }

    final shared = sharedCopy(media);
    if (shared != null && shared.server == app.server?.machineIdentifier) {
      final i = await plex.metadata(shared.item).catchError((Object _) => null);
      if (cancel.isCancelled) return const [];
      if (i != null && roomKind(i)) add(i);
    }
    final all = [for (final l in (await app.library()).bySection) ...l];
    if (cancel.isCancelled) return const [];
    switch (media.kind) {
      case owp.MediaKind.movie:
        sameTitles(all, type: 'movie', title: media.title, year: media.year, ids: media.ids).forEach(add);
      case owp.MediaKind.episode:
        final series = media.series;
        if (series == null) break;
        for (final show in sameTitles(all, type: 'show', title: series.title, year: series.year, ids: series.ids).take(3)) {
          final eps = await plex.episodes(show.ratingKey);
          if (cancel.isCancelled) return const [];
          final e = sameEpisode(eps, media);
          if (e != null) add(e);
        }
      case owp.MediaKind.video:
        break;
    }
    return out;
  }

  /// A file whose length the list didn't carry is read again for it.
  owp.Candidate<String> _candidate(PlexClient plex, PlexItem i) {
    final c = candidateFor(i);
    if (c.durationMs != null) return c;
    return owp.Candidate<String>(
      id: c.id,
      ref: c.ref,
      sizeBytes: c.sizeBytes,
      name: c.name,
      probe: (cancel) async {
        final fresh = await plex.metadata(i.ratingKey);
        return cancel.isCancelled ? null : (fresh == null ? null : candidateFor(fresh).durationMs);
      },
    );
  }
}
