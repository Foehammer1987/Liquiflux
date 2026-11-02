import 'dart:async';

import 'package:console_core/console_core.dart';

import '../../services/watch_together.dart';
import '../player/player_session.dart';

/// Keeps one player in step with its Watch Together room: what the viewer does goes to the
/// room, and what others do (play, pause, a jump) happens here, with a word about who did it.
class TogetherLink {
  TogetherLink(this.session, this.together) {
    together.local = () => active ? (position: session.position, paused: !session.player.state.playing) : null;
    _events = together.events.listen(_onEvent);
    _playing = session.player.stream.playing.listen(_onPlaying);
    _watch = Timer.periodic(const Duration(milliseconds: 500), (_) => _watchJumps());
  }

  final PlayerSession session;
  final WatchTogether together;
  late final StreamSubscription<SyncEvent> _events;
  late final StreamSubscription<bool> _playing;
  late final Timer _watch;

  /// While we're carrying out the room's change, our own player events aren't the viewer's.
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _quiet => DateTime.now().isBefore(_quietUntil);

  /// The room we've lined up with (or, for our own room, told where we are).
  String? _inStepWith;
  bool get _caughtUp => _inStepWith != null && _inStepWith == together.room?.id;

  /// We made the room: the others follow us to start with.
  bool get _host {
    final by = together.room?.createdBy?.id;
    return by != null && by == together.account?.id;
  }

  Duration? _last;
  DateTime _lastAt = DateTime.now();

  /// When we last jumped for the room: a room that sends jump after jump is followed at most
  /// twice a second, so it can't keep the player seeking (or a transcode restarting) forever.
  DateTime _jumpedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get active => together.inRoomFor(session.item.ratingKey);

  void _onPlaying(bool playing) {
    if (!active || _quiet || !session.ready || !_caughtUp) return;
    together.sync?.changed(position: session.position, paused: !playing);
  }

  /// A scrub or skip shows up as the position landing somewhere it couldn't have played to.
  void _watchJumps() {
    final now = DateTime.now();
    final pos = session.position;
    final last = _last;
    final playing = session.player.state.playing && !session.player.state.buffering;
    if (active && _host && !_caughtUp && session.ready) announce();
    if (last != null && active && !_quiet && session.ready && _caughtUp) {
      final expected = last + (playing ? now.difference(_lastAt) * session.rate : Duration.zero);
      if ((pos - expected).abs() > const Duration(milliseconds: 2500)) {
        together.sync?.changed(position: pos, paused: !session.player.state.playing, seek: true);
      }
    }
    _last = pos;
    _lastAt = now;
  }

  void _onEvent(SyncEvent e) {
    if (!active) return;
    switch (e) {
      case SyncRemote():
        // A brand-new room has nothing to follow yet: what we do sets it.
        if (e.by == null && !_caughtUp) {
          if (!_host) _inStepWith = together.room?.id;
          return;
        }
        _apply(e);
      case SyncNotice():
        session.flash(e.text);
      case SyncRoster() || SyncClosed():
        break;
    }
  }

  void _apply(SyncRemote e) {
    final p = session.player;
    final gap = (e.position - session.position).abs();
    final now = DateTime.now();
    final tooSoon = _caughtUp && now.difference(_jumpedAt) < const Duration(milliseconds: 500);
    final jump = !tooSoon && (e.seek || !_caughtUp || gap > const Duration(seconds: 2));
    final pauseChange = e.paused == p.state.playing;
    if (!jump && !pauseChange) return;
    if (jump) _jumpedAt = now;
    _quietUntil = DateTime.now().add(Duration(milliseconds: jump && session.transcoding ? 4000 : 1500));
    _last = null;
    final who = e.by?.name ?? 'The room';
    if (jump) unawaited(session.seekTo(e.position));
    if (pauseChange) unawaited(e.paused ? p.pause() : p.play());
    if (!_caughtUp) {
      _inStepWith = together.room?.id;
      session.flash('In step with $who');
    } else if (e.seek) {
      session.flash('$who jumped to ${_clock(e.position)}');
    } else if (pauseChange) {
      session.flash(e.paused ? '$who paused' : '$who pressed play');
    }
  }

  /// The room we're starting: tell it where we are once we're playing.
  void announce() {
    _inStepWith = together.room?.id;
    if (active) together.sync?.changed(position: session.position, paused: !session.player.state.playing);
  }

  static String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// Closing the player leaves its room: a member who's stopped would hold everyone else up.
  void dispose() {
    if (active) unawaited(together.leave());
    _watch.cancel();
    unawaited(_events.cancel());
    unawaited(_playing.cancel());
    together.local = null;
  }
}
