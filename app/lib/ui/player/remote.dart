import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform.dart';

/// What a key on a TV remote does in the player.
enum RemoteAction {
  /// Leave the key to the focused control: the D-pad moves focus, Select presses it.
  focus,
  playPause,
  play,
  pause,
  seekBack,
  seekForward,

  /// Bring the controls up with the play / pause button focused.
  showControls,

  /// Up Next's "Play Now".
  playNow,

  /// Skip Intro / Skip Credits.
  skip,
  next,
  previous,
  stop,

  /// Close the top layer: a panel, the controls, then the player.
  back,
}

/// The remote's Select / OK button, and the keys that stand in for it.
final selectKeys = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA};

/// Back on a remote, and Esc on a keyboard.
final backKeys = {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape, LogicalKeyboardKey.browserBack};

final _arrows = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};

final _media = {
  LogicalKeyboardKey.mediaPlayPause: RemoteAction.playPause,
  LogicalKeyboardKey.mediaPlay: RemoteAction.play,
  LogicalKeyboardKey.mediaPause: RemoteAction.pause,
  LogicalKeyboardKey.mediaFastForward: RemoteAction.seekForward,
  LogicalKeyboardKey.mediaRewind: RemoteAction.seekBack,
  LogicalKeyboardKey.mediaTrackNext: RemoteAction.next,
  LogicalKeyboardKey.mediaTrackPrevious: RemoteAction.previous,
  LogicalKeyboardKey.mediaStop: RemoteAction.stop,
};

/// The remote keys the player answers to: the arrows, OK, the media keys and 0-9. Any other
/// key (colour keys, Channel Up/Down, Info, Guide) leaves the player as it is.
final playerKeys = {
  ..._arrows,
  ...selectKeys,
  ..._media.keys,
  LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, //
  LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
};

/// The remote's Exit key. flutter-tizen gives Samsung's Exit (XF86Exit) no logical key, only
/// the physical one, and closes the app when the app leaves its key-up unhandled.
bool isExitKey(KeyEvent e) => e.physicalKey == PhysicalKeyboardKey.exit || e.logicalKey == LogicalKeyboardKey.exit;

/// What [key] does on a TV. [onControl]: a button or the seek bar has focus, rather than
/// the picture. [upNext] and [skip]: the Up Next card or a Skip button is showing, so Select
/// takes it. [goBack] false leaves the Back key to the system, which reaches the player as a
/// route pop instead. Null for keys the remote doesn't own (the keyboard shortcuts keep those).
///
/// [samsung]: on a Samsung remote the track keys are what a long press of Rewind or Fast
/// Forward sends (Samsung's remote control guide), so there they seek like Rewind and Fast
/// Forward instead of changing episode.
RemoteAction? remoteAction(LogicalKeyboardKey key, {bool onControl = false, bool upNext = false, bool skip = false, bool goBack = true, bool? samsung}) {
  if (samsung ?? isTizen) {
    if (key == LogicalKeyboardKey.mediaTrackNext) return RemoteAction.seekForward;
    if (key == LogicalKeyboardKey.mediaTrackPrevious) return RemoteAction.seekBack;
  }
  final media = _media[key];
  if (media != null) return media;
  if (backKeys.contains(key)) return key == LogicalKeyboardKey.goBack && !goBack ? null : RemoteAction.back;
  final select = selectKeys.contains(key);
  if (!select && !_arrows.contains(key)) return null;
  if (onControl) return RemoteAction.focus;
  if (select) return upNext ? RemoteAction.playNow : (skip ? RemoteAction.skip : RemoteAction.playPause);
  return switch (key) {
    LogicalKeyboardKey.arrowLeft => RemoteAction.seekBack,
    LogicalKeyboardKey.arrowRight => RemoteAction.seekForward,
    _ => RemoteAction.showControls,
  };
}

/// Whether a held key keeps doing [action] (seeking does; toggles and Back don't).
bool remoteRepeats(RemoteAction action) => action == RemoteAction.seekBack || action == RemoteAction.seekForward || action == RemoteAction.focus;

/// How far a held seek key jumps: the normal [seconds] at first, double after two seconds
/// held, four times after four.
int heldSkip(int seconds, Duration held) => seconds * (held >= const Duration(seconds: 4) ? 4 : (held >= const Duration(seconds: 2) ? 2 : 1));

/// A focused control on a TV wears a thick white ring just outside it, so it reads from across
/// the room and never shifts the layout. Null on desktop and when not focused.
Decoration? tvRing(bool focused, {double radius = 0, bool circle = false}) => isTv && focused
    ? BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: Colors.white, width: 4, strokeAlign: BorderSide.strokeAlignOutside),
      )
    : null;

/// Puts [tvRing] around a control from elsewhere (a [ConsoleButton], a switch) while it or
/// anything inside it has focus. Does nothing on desktop.
class TvRing extends StatefulWidget {
  const TvRing({super.key, required this.child, this.radius = 0, this.circle = false});
  final Widget child;
  final double radius;
  final bool circle;
  @override
  State<TvRing> createState() => _TvRingState();
}

class _TvRingState extends State<TvRing> {
  bool _on = false;
  @override
  Widget build(BuildContext context) {
    if (!isTv) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _on = f),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: tvRing(_on, radius: widget.radius, circle: widget.circle) ?? const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}

/// What Back does in the player, top layer first.
enum PlayerBack { leave, closePanel, closeInfo, dismissUpNext, hideControls }

/// Back on a remote closes the top layer (a panel, the info, Up Next, the controls), then
/// leaves. A paused movie is left straight away: hiding the controls of a paused picture
/// only brought the pause screen back, so Back could never get out (0.9.35).
PlayerBack playerBack({
  required bool resumeOffer,
  required bool panel,
  required bool info,
  required bool upNext,
  required bool playing,
  required bool controls,
}) {
  if (resumeOffer) return PlayerBack.leave;
  if (panel) return PlayerBack.closePanel;
  if (info) return PlayerBack.closeInfo;
  if (upNext) return PlayerBack.dismissUpNext;
  if (!playing) return PlayerBack.leave;
  if (controls) return PlayerBack.hideControls;
  return PlayerBack.leave;
}
