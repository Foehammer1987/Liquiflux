import 'dart:async';
import 'dart:io' show Platform;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../main.dart' show customTitleBar;
import '../../platform.dart';
import '../../services/avplay_player.dart';
import '../../services/network_watch.dart';
import '../../services/pip.dart';
import '../../services/channels.dart';
import '../../state/scope.dart';
import '../player/app_subtitles.dart';
import '../player/player_dock.dart';
import '../player/player_session.dart';
import '../player/sleep_timer.dart';
import '../player/pause_screen.dart';
import '../player/player_sheet.dart';
import '../player/remote.dart';
import '../player/resume_prompt.dart';
import '../player/riptide.dart';
import '../nav.dart';
import '../together/together_link.dart';
import '../../services/open_party.dart';
import '../../services/window_fullscreen.dart';
import '../together/together_panel.dart';
import '../tv_focus.dart';
import '../player/seek_bar.dart';
import '../spoiler.dart';
import '../window_buttons.dart';

/// Plays a Plex item with mpv: direct play first, Plex's transcoder when it has to or when
/// you pick a lower quality. Frosted controls tinted from the title's own artwork.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, this.resume = true, this.choose = true, this.queue = const [], this.at, this.channel, this.tookFullscreen = false});
  final PlexItem item;
  final bool resume;

  /// Nobody picked Resume or Play from Start, so the resume setting decides (and may ask).
  final bool choose;

  /// The player before this one put the window in full screen, so leaving undoes it.
  final bool tookFullscreen;

  /// Titles to play one after another (a collection marathon); empty for a single title.
  final List<PlexItem> queue;

  /// Where [item] is in [queue], when known.
  final int? at;

  /// The shuffle channel this title is part of (its line-up is [queue]).
  final ChannelRun? channel;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WindowListener {
  /// Players on screen (two while one episode fades into the next).
  static final _live = <_PlayerPageState>{};
  static Future<void>? _closing;

  late final PlayerSession _s;
  final _focus = FocusNode(debugLabel: 'player');
  bool _visible = true;
  bool _overControls = false;
  bool _scrubbing = false;
  Timer? _hide;
  SheetTab? _sheet;
  bool _info = false;
  bool _showRemaining = true;
  bool _fullscreen = false;

  /// The player went full screen itself, so it should put the window back on the way out.
  bool _ownsFullscreen = false;
  bool _leaving = false;

  // A big play / pause mark that pops in the middle when you toggle.
  IconData? _pulse;

  /// Android phones and tablets: in the floating picture-in-picture window, where no controls show.
  bool _pip = false;
  Timer? _pulseTimer;

  // After a few seconds paused, the title, synopsis and cast fade in over the picture.
  bool _paused = false;

  /// The pause screen is showing or fading out, so its animation should run.
  bool _pauseLive = false;
  Timer? _pauseTimer;
  StreamSubscription<bool>? _playingSub;

  /// Who's in it, and who's on screen when the scanner has been over it.
  late final Riptide _riptide;

  // Watch Together: the link to the room, and its side panel.
  late final TogetherLink _link;
  late final OpenParty _party;
  bool _together = false;

  // The remote: the buttons the D-pad lands on, and the one a panel hands focus back to.
  final _playFocus = FocusNode(debugLabel: 'play');
  final _seekFocus = FocusNode(debugLabel: 'seek bar');
  final _togetherFocus = FocusNode(debugLabel: 'together');
  final _sheetButtons = {for (final t in SheetTab.values) t: FocusNode(debugLabel: 'sheet button ${t.name}')};
  final _sheetTabs = {for (final t in SheetTab.values) t: FocusNode(debugLabel: 'sheet tab ${t.name}')};
  final _cardArea = FocusNode(debugLabel: 'up next');
  FocusNode? _opener;

  /// The key being handled was pressed while the pause screen showed.
  bool _keyOnPauseScreen = false;

  /// Back hid the controls; the next key brings them back.
  bool _dismissed = false;
  bool _chromeShown = true;
  DateTime? _heldSince;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _s = PlayerSession(
      plex: app.plex!,
      prefs: app.settings.playback,
      local: app.plexIsLocal,
      item: widget.item,
      queue: widget.queue,
      at: widget.at,
      channel: widget.channel,
      resume: widget.resume,
      // In a Watch Together room the room decides where everyone is.
      choose: widget.choose && !app.watchTogether.inRoomFor(widget.item.ratingKey) && !app.openParty.inRoom,
      onExit: _exit,
      onPlay: _playOther,
      onPrefs: app.setPlayback,
      covered: _covered,
      server: app.server?.machineIdentifier ?? '',
      scrobbler: app.scrobbler,
    )..addListener(_changed);
    _riptide = Riptide(plex: app.plex!, server: app.settings.riptideServer, token: app.settings.riptideSignInToken)
      ..follow(widget.item)
      ..addListener(_changed);
    ArtMemory.releaseAll.addListener(_changed);
    final at = widget.at;
    if (at != null) widget.channel?.started(at);
    unawaited(_s.start());
    _link = TogetherLink(_s, app.watchTogether);
    _party = app.openParty..attach(_s);
    _playingSub = _s.player.stream.playing.listen((playing) => playing ? _endPauseScreen() : _armPauseScreen());
    _ownsFullscreen = widget.tookFullscreen;
    if (isDesktop) {
      unawaited(
        windowManager.isFullScreen().then((f) {
          if (mounted) setState(() => _fullscreen = f);
        }, onError: (Object _) {}),
      );
      // Closing the window mid-title waits for the player to tidy up first.
      windowManager.addListener(this);
      if (_live.isEmpty) unawaited(windowManager.setPreventClose(true).catchError((Object e) => debugPrint('prevent close: $e')));
    }
    if (isTv) {
      HardwareKeyboard.instance.addHandler(_anyKey);
      FocusManager.instance.addListener(_keepFocus);
    }
    if (PlayerDock.enabled) PlayerDock.instance.addListener(_dockChanged);
    if (isTizen) NetworkWatch.instance.online.addListener(_networkChanged);
    if (isTouch) _touchStart();
    _live.add(this);
    _poke();
  }

  /// Samsung TVs: with the network gone, network playback stops and the app goes back a page
  /// (Samsung's multitasking guide); the shell then shows the network popup. The place is
  /// saved as when leaving with Back, so Resume picks it up later.
  void _networkChanged() {
    if (NetworkWatch.instance.online.value || !mounted) return;
    unawaited(_s.player.pause());
    final r = _route;
    if (r == null || !r.isActive) return;
    final nav = Navigator.of(context);
    r.isCurrent ? nav.pop() : nav.removeRoute(r);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _changed() {
    if (!mounted) return;
    _riptide.follow(_s.item);
    setState(() {});
    _sleepFocusFollows();
  }

  /// Completes once this page has finished coming in, when the pages behind it are hidden.
  Future<void> _covered() async {
    final animation = _route?.animation;
    if (animation == null || !animation.isAnimating) return;
    final done = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status.isAnimating) return;
      animation.removeStatusListener(onStatus);
      if (!done.isCompleted) done.complete();
    }

    animation.addStatusListener(onStatus);
    await done.future;
  }

  @override
  void dispose() {
    ArtMemory.releaseAll.removeListener(_changed);
    NetworkWatch.instance.online.removeListener(_networkChanged);
    if (PlayerDock.enabled) PlayerDock.instance.removeListener(_dockChanged);
    if (isDesktop) windowManager.removeListener(this);
    if (!_leaving) SleepTimer.instance.cancel();
    if (isTv) {
      HardwareKeyboard.instance.removeHandler(_anyKey);
      FocusManager.instance.removeListener(_keepFocus);
    }
    _live.remove(this);
    if (isTouch) _touchEnd();
    if (isDesktop && _live.isEmpty && _closing == null) unawaited(windowManager.setPreventClose(false).catchError((Object e) => debugPrint('prevent close: $e')));
    for (final n in [_sleepFocus, _playFocus, _seekFocus, _togetherFocus, _cardArea, ..._sheetButtons.values, ..._sheetTabs.values]) {
      n.dispose();
    }
    _pauseTimer?.cancel();
    _link.dispose();
    unawaited(_party.detach(_s));
    unawaited(_playingSub?.cancel());
    _hide?.cancel();
    _pulseTimer?.cancel();
    _focus.dispose();
    _riptide
      ..removeListener(_changed)
      ..dispose();
    _s
      ..removeListener(_changed)
      ..dispose();
    if (!_leaving) _restoreWindow();
    super.dispose();
  }

  /// Leaves full screen if the player entered it; a window that was already full screen stays so.
  void _restoreWindow() {
    if (isDesktop && _fullscreen && _ownsFullscreen) unawaited(WindowFullscreen.instance.set(false));
    _ownsFullscreen = false;
  }

  // ------------------------------------------------------------ phones and tablets

  StreamSubscription<bool>? _touchPlaying;

  /// The player on a phone or tablet: turned on its side and full screen (the status and
  /// navigation bars come back with a swipe), and on Android it floats in a picture-in-picture
  /// window when you go Home while it plays.
  void _touchStart() {
    unawaited(SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    Pip.active.addListener(_pipChanged);
    _touchPlaying = _s.player.stream.playing.listen((on) => unawaited(Pip.playing(on, aspect: _videoAspect)));
  }

  void _touchEnd() {
    Pip.active.removeListener(_pipChanged);
    unawaited(_touchPlaying?.cancel());
    // Only once the last player has gone (Up Next can open the next one first).
    if (_live.isNotEmpty) return;
    unawaited(Pip.playing(false));
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  double? get _videoAspect {
    final w = _s.player.state.width, h = _s.player.state.height;
    return w == null || h == null || w <= 0 || h <= 0 ? null : w / h;
  }

  void _pipChanged() {
    if (!mounted) return;
    setState(() {
      _pip = Pip.active.value;
      if (_pip) _closePanelsQuietly();
    });
  }

  void _closePanelsQuietly() {
    _sheet = null;
    _together = false;
    _info = false;
  }

  /// A tap on the picture shows the controls, or hides them if they're up. (A mouse click
  /// still pauses, as on a desktop.)
  void _touchTap(bool shown) {
    if (!shown) return _poke();
    _hide?.cancel();
    setState(() => _visible = false);
  }

  Offset? _doubleTapAt;

  /// Double-tap the left or right third of the picture to skip back or forward, the middle
  /// to pause or play.
  void _touchDoubleTap(double width) {
    final x = _doubleTapAt?.dx ?? width / 2;
    final p = _s.prefs;
    if (x < width / 3 || x > width * 2 / 3) {
      final back = x < width / 3;
      _s.seekBy(back ? -p.skipBack : p.skipForward);
      _pulseTimer?.cancel();
      setState(() => _pulse = back ? LucideIcons.rotateCcw : LucideIcons.rotateCw);
      _pulseTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _pulse = null);
      });
      return;
    }
    _toggle();
  }

  // ------------------------------------------------------------ mini player

  /// The player is in its corner of the window (see [PlayerDock]), with the library behind.
  bool get _mini => PlayerDock.enabled && PlayerDock.instance.mini;
  bool _wasMini = false;

  /// Shrinks the player into its corner; it keeps playing while the app is used behind it.
  void _minimize() {
    if (!PlayerDock.enabled || _s.resumeOffer != null) return;
    PlayerDock.instance.minimize();
  }

  void _dockChanged() {
    if (!mounted) return;
    final mini = _mini;
    if (mini == _wasMini) return;
    _wasMini = mini;
    if (mini) {
      // Panels, the info and the pause screen don't fit in the corner.
      _pauseTimer?.cancel();
      setState(() {
        _sheet = null;
        _together = false;
        _opener = null;
        _info = false;
        _paused = false;
        _pauseLive = false;
      });
    } else {
      // Full window again: the keyboard comes back to the player.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_mini) _focus.requestFocus();
      });
      setState(() {});
      _poke();
    }
  }

  void _exit() {
    if (!mounted) return;
    _restoreWindow();
    final nav = Navigator.of(context);
    // On a TV the page keeps the system Back for itself (see [_back]), so leaving pops for real.
    if (isTv) {
      if (_route?.isCurrent == true && nav.canPop()) nav.pop();
    } else {
      nav.maybePop();
    }
  }

  // ------------------------------------------------------------ window

  @override
  void onWindowClose() => _closing ??= _closeWindow();

  /// The window is closing under the players: tell Plex we stopped, end any transcode and
  /// leave the room (for two seconds at most), then let it go.
  static Future<void> _closeWindow() async {
    try {
      await Future.wait([for (final p in _live.toList()) p._shutdown()]).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('player close: $e');
    }
    if (isDesktop) await windowManager.destroy();
  }

  Future<void> _shutdown() {
    final done = Future.wait([_s.shutdown(), if (_link.active) _link.together.leave(), if (_party.inRoom) _party.leave()]);
    unawaited(_s.player.pause());
    return done;
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted && !_fullscreen) setState(() => _fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted || !_fullscreen) return;
    setState(() {
      _fullscreen = false;
      _ownsFullscreen = false;
    });
  }

  /// Next / previous episode: swap the page in place, staying full screen.
  void _playOther(PlexItem next) {
    if (!mounted) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => PlayerPage(
          item: next,
          queue: widget.queue,
          at: identical(next, _s.next) ? _s.nextAt : (identical(next, _s.previous) ? _s.previousAt : null),
          channel: widget.channel,
          // A channel's episodes start from the top, like on TV.
          resume: widget.channel == null,
          choose: false,
          tookFullscreen: _ownsFullscreen,
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  // ------------------------------------------------------------ controls visibility

  bool get _keepVisible => !_s.player.state.playing || _sheet != null || _together || _overControls || _scrubbing || _info;

  void _armPauseScreen() {
    _pauseTimer?.cancel();
    if (!AppScope.read(context).settings.pauseScreen) return;
    // Not while the pointer rests on the controls or a panel is open: covering them would
    // count as leaving them and end the pause screen straight away.
    _pauseTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_s.ready || _s.error != null || _s.player.state.playing) return;
      if (_sheet != null || _together || _overControls || _scrubbing || _info || _mini) return;
      setState(() {
        _paused = true;
        _pauseLive = true;
      });
    });
  }

  void _endPauseScreen() {
    _pauseTimer?.cancel();
    if (_paused && mounted) setState(() => _paused = false);
  }

  void _poke() {
    // Moving the pointer or pressing a key brings the controls back; the pause screen
    // returns after a few more quiet seconds.
    if (!_s.player.state.playing) {
      _endPauseScreen();
      _armPauseScreen();
    }
    if (!_visible || _dismissed) {
      setState(() {
        _visible = true;
        _dismissed = false;
      });
    }
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && !_keepVisible) setState(() => _visible = false);
    });
  }

  void _toggle() {
    _s.togglePlay();
    _pulseTimer?.cancel();
    setState(() => _pulse = _s.player.state.playing ? LucideIcons.pause : LucideIcons.play);
    _pulseTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _pulse = null);
    });
    _poke();
  }

  Future<void> _toggleFullscreen() async {
    // A TV is always full screen.
    if (!isDesktop) return;
    _fullscreen = !_fullscreen;
    _ownsFullscreen = _fullscreen;
    await WindowFullscreen.instance.set(_fullscreen);
    if (mounted) setState(() {});
  }

  void _openSheet(SheetTab tab) {
    if (_sheet == tab) {
      _closePanels();
      _poke();
      return;
    }
    _rememberOpener();
    setState(() {
      _sheet = tab;
      _together = false;
    });
    // On a TV the D-pad starts on the open tab.
    if (isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheet != null) _sheetTabs[_sheet!]!.requestFocus();
      });
    }
    _poke();
  }

  void _toggleTogether() {
    if (_together) return _closePanels();
    _rememberOpener();
    setState(() {
      _together = true;
      _sheet = null;
    });
  }

  /// The bar button that opened a panel, for focus to go back to when it closes.
  void _rememberOpener() {
    final f = FocusManager.instance.primaryFocus;
    _opener = f == _togetherFocus || _sheetButtons.containsValue(f) ? f : _playFocus;
  }

  /// Closes the settings and Watch Together panels; on a TV focus goes back to the button
  /// that opened them.
  void _closePanels() {
    final back = _opener;
    _opener = null;
    setState(() {
      _sheet = null;
      _together = false;
    });
    if (isTv && back != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) back.requestFocus();
      });
    }
  }

  // ------------------------------------------------------------ remote

  /// In the sleep timer's last minute the warning holds the focus, so the first key (Back
  /// too) only keeps watching: a HardwareKeyboard handler can't stop the key going on to
  /// the focused control too (Select paused the video). Its release goes with it, then the
  /// picture has the focus again.
  KeyEventResult _onSleepKey(FocusNode _, KeyEvent e) {
    // Exit closes the app from anywhere (Samsung's rule): left unhandled, the TV does it.
    if (isExitKey(e)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      if (_s.sleepWarning) _s.keepWatching();
      _sleepHeld.add(e.logicalKey);
    } else if (e is KeyUpEvent) {
      _sleepHeld.remove(e.logicalKey);
      if (_sleepHeld.isEmpty && !_s.sleepWarning) _focus.requestFocus();
    }
    return KeyEventResult.handled;
  }

  final _sleepFocus = FocusNode(debugLabel: 'sleep warning');
  final _sleepHeld = <LogicalKeyboardKey>{};

  /// The warning takes the focus as it shows, and gives it back if it goes some other way.
  void _sleepFocusFollows() {
    if (_s.sleepWarning) {
      if (!_sleepFocus.hasPrimaryFocus) _sleepFocus.requestFocus();
    } else if (_sleepFocus.hasPrimaryFocus && _sleepHeld.isEmpty) {
      _focus.requestFocus();
    }
  }

  /// On a TV the remote's player keys (the arrows, OK, the media keys and 0-9) bring the
  /// controls up and restart their timer, whichever control the key goes to. Keys the player
  /// doesn't use (colour keys, Channel Up/Down, Info, Guide) do nothing at all: Samsung's
  /// review rule is that keys the app doesn't list must not respond. Keyboard shortcuts bring
  /// the controls up through [_onKeyboard] when they do something.
  bool _anyKey(KeyEvent e) {
    if (!playerKeys.contains(e.logicalKey)) return false;
    // Noted before the key ends the pause screen, for Down there to open Riptide.
    if (e is KeyDownEvent) _keyOnPauseScreen = _paused;
    if (e is! KeyUpEvent && mounted && _route?.isCurrent == true) _poke();
    return false;
  }

  /// On a TV the player keeps the remote's focus: when the focused control goes away (a
  /// closed card or panel), the picture takes it back.
  void _keepFocus() {
    if (!mounted || _focus.hasFocus || _route?.isCurrent != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus && _route?.isCurrent == true) _focus.requestFocus();
    });
  }

  /// Paused with the controls showing and the picture focused: Play takes the focus.
  void _focusPlayIfPaused() {
    if (mounted && _chromeShown && !_s.player.state.playing && _focus.hasPrimaryFocus && _route?.isCurrent == true) _playFocus.requestFocus();
  }

  /// The controls faded out: the D-pad goes back to seeking, unless it's on the Up Next card.
  void _focusPicture() {
    if (mounted && !_cardArea.hasFocus) _focus.requestFocus();
  }

  /// Leaves the player for [person]'s page: their other titles in the library. The page opens
  /// once the player has closed (its position is saved as for any exit), so the page's
  /// artwork doesn't load on top of a 4K picture.
  void _openPerson(PlexTag person) {
    final thumb = person.thumb;
    final dest = PersonDest(
      name: person.tag,
      plexTagId: person.id,
      photoUrl: _s.plex.imageUrl(thumb, width: 240, height: 240),
    );
    // On a desktop the title carries on in the corner while their page opens behind it.
    if (PlayerDock.enabled) {
      _minimize();
      playerHandoff.value = dest;
      return;
    }
    final route = _route;
    _exit();
    if (route == null) return;
    unawaited(route.completed.then((_) => playerHandoff.value = dest));
  }

  /// Back on a remote: closes the top layer (a panel, the info, Up Next, the controls), then
  /// leaves the player. Paused, it leaves straight from the pause screen or the controls
  /// (see [playerBack]).
  void _back() {
    switch (playerBack(
      resumeOffer: _s.resumeOffer != null,
      panel: _sheet != null || _together,
      info: _info,
      upNext: _s.upNextVisible && _s.next != null,
      playing: _s.player.state.playing,
      controls: _chromeShown,
    )) {
      case PlayerBack.leave:
        _exit();
      case PlayerBack.closePanel:
        _closePanels();
      case PlayerBack.closeInfo:
        setState(() => _info = false);
      case PlayerBack.dismissUpNext:
        _s.dismissUpNext();
      case PlayerBack.hideControls:
        _hide?.cancel();
        setState(() {
          _visible = false;
          _dismissed = true;
        });
        _focus.requestFocus();
    }
  }

  static final _arrowKeys = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};

  /// The remote's keys (see [remoteAction]); anything else falls through to the keyboard ones.
  KeyEventResult _onRemote(KeyEvent e) {
    final a = remoteAction(
      e.logicalKey,
      onControl: FocusManager.instance.primaryFocus != _focus,
      upNext: _s.upNextVisible && _s.next != null,
      skip: _s.skipPrompt != null,
      // Android turns an unhandled Back into a route pop, which [PopScope] hands to [_back].
      goBack: !Platform.isAndroid,
    );
    if (a == null) return _onKeyboard(e);
    // Down on the pause screen opens Riptide, the way Prime's does.
    if (_keyOnPauseScreen && e.logicalKey == LogicalKeyboardKey.arrowDown && _riptide.cast.isNotEmpty) {
      if (e is KeyUpEvent) _keyOnPauseScreen = false;
      if (e is KeyDownEvent) _openSheet(SheetTab.riptide);
      return KeyEventResult.handled;
    }
    // Left or Right on the pause screen only brings the controls back, with Play focused.
    if (_keyOnPauseScreen && (a == RemoteAction.seekBack || a == RemoteAction.seekForward) && _arrowKeys.contains(e.logicalKey)) {
      if (e is KeyDownEvent) _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (a == RemoteAction.focus) return KeyEventResult.ignored;
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final repeat = e is KeyRepeatEvent;
    if (repeat && !remoteRepeats(a)) return KeyEventResult.handled;
    final now = DateTime.now();
    if (!repeat) _heldSince = now;
    final held = now.difference(_heldSince ?? now);
    final p = _s.prefs;
    switch (a) {
      case RemoteAction.playPause:
        _toggle();
      case RemoteAction.play:
        if (!_s.player.state.playing) _toggle();
      case RemoteAction.pause:
        if (_s.player.state.playing) _toggle();
      case RemoteAction.seekBack:
        _s.seekBy(-heldSkip(p.skipBack, held));
      case RemoteAction.seekForward:
        _s.seekBy(heldSkip(p.skipForward, held));
      case RemoteAction.showControls:
        _poke();
        _playFocus.requestFocus();
      case RemoteAction.playNow || RemoteAction.next:
        _s.playNext();
      case RemoteAction.skip:
        _s.skipMarker();
      case RemoteAction.previous:
        _s.playPrevious();
      case RemoteAction.stop:
        _exit();
      case RemoteAction.back:
        _back();
      case RemoteAction.focus:
        break;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------ keyboard

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (_s.resumeOffer != null) return _onResumeKey(e);
    return isTv ? _onRemote(e) : _onKeyboard(e);
  }

  /// While Resume / Start Over is up, its buttons take the arrows and Select; Escape or
  /// Back leaves the player.
  KeyEventResult _onResumeKey(KeyEvent e) {
    final back = e.logicalKey == LogicalKeyboardKey.escape || (!Platform.isAndroid && backKeys.contains(e.logicalKey));
    if (!back) return KeyEventResult.ignored;
    if (e is KeyDownEvent) _exit();
    return KeyEventResult.handled;
  }

  /// An open panel keeps a remote's focus until Back closes it. Down from its last control
  /// used to walk out onto the seek bar, and Up onto a button half hidden behind the panel,
  /// with the panel still open.
  Widget _held(Widget panel) => isTv ? FocusPanel(child: panel) : panel;

  KeyEventResult _onKeyboard(KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final repeat = e is KeyRepeatEvent;
    final k = e.logicalKey;
    final p = _s.prefs;
    void done() => _poke();
    if (k == LogicalKeyboardKey.escape) {
      if (repeat) return KeyEventResult.handled;
      if (_sheet != null || _together) {
        _closePanels();
      } else if (_info) {
        setState(() => _info = false);
      } else if (_fullscreen) {
        unawaited(_toggleFullscreen());
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    // Let a focused button in the panel use Space / Enter / arrows itself.
    final inSheet = (_sheet != null || _together) && FocusManager.instance.primaryFocus != _focus;
    if (inSheet && const [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.space, LogicalKeyboardKey.enter].contains(k)) return KeyEventResult.ignored;

    final actions = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.space: _toggle,
      LogicalKeyboardKey.keyK: _toggle,
      LogicalKeyboardKey.mediaPlayPause: _toggle,
      LogicalKeyboardKey.arrowLeft: () => _s.seekBy(-p.skipBack),
      LogicalKeyboardKey.keyJ: () => _s.seekBy(-p.skipBack),
      LogicalKeyboardKey.arrowRight: () => _s.seekBy(p.skipForward),
      LogicalKeyboardKey.keyL: () => _s.seekBy(p.skipForward),
      LogicalKeyboardKey.arrowUp: () => _s.setVolume(_s.player.state.volume + 5),
      LogicalKeyboardKey.arrowDown: () => _s.setVolume(_s.player.state.volume - 5),
      LogicalKeyboardKey.keyM: _s.toggleMute,
      LogicalKeyboardKey.keyF: _toggleFullscreen,
      LogicalKeyboardKey.keyC: _s.cycleSubtitle,
      LogicalKeyboardKey.keyA: _s.cycleAudio,
      LogicalKeyboardKey.keyS: () => _s.upNextVisible ? _s.playNext() : _s.skipMarker(),
      LogicalKeyboardKey.keyN: _s.playNext,
      LogicalKeyboardKey.mediaTrackNext: _s.playNext,
      LogicalKeyboardKey.keyP: _s.playPrevious,
      LogicalKeyboardKey.mediaTrackPrevious: _s.playPrevious,
      LogicalKeyboardKey.keyI: () => setState(() => _info = !_info),
      if (PlayerDock.enabled) LogicalKeyboardKey.keyB: _minimize,
      LogicalKeyboardKey.keyR: () => _riptide.cast.isNotEmpty ? _openSheet(SheetTab.riptide) : null,
      // X opened it while it was called X-Ray; it still does.
      LogicalKeyboardKey.keyX: () => _riptide.cast.isNotEmpty ? _openSheet(SheetTab.riptide) : null,
      LogicalKeyboardKey.bracketLeft: () => unawaited(_stepRate(-0.25)),
      LogicalKeyboardKey.bracketRight: () => unawaited(_stepRate(0.25)),
      LogicalKeyboardKey.home: () => _s.seekTo(Duration.zero),
    };
    // Held keys repeat seeking and volume, not toggles.
    final repeats = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyL};
    final action = actions[k];
    var handled = false;
    if (action != null) {
      if (!repeat || repeats.contains(k)) action();
      handled = true;
    } else if (!repeat) {
      handled = _digit(k);
    }
    if (handled) done();
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// 0–9 jumps to that tenth of the title.
  bool _digit(LogicalKeyboardKey k) {
    const keys = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, //
      LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    final i = keys.indexOf(k);
    if (i < 0) return false;
    unawaited(_s.seekTo(_s.duration * (i / 10)));
    return true;
  }

  Future<void> _stepRate(double by) async {
    final r = (_s.rate + by).clamp(0.5, 2.0);
    await _s.setRate(r);
    // A speed Samsung's player turned down says so itself (see setRateDirect).
    if (!mounted || (isTizen && _s.room == null && _s.rate != r)) return;
    _s.flash(r == 1 ? 'Normal Speed' : '${_trim(r)}× Speed');
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ------------------------------------------------------------ build

  static const _fallbackTint = Color(0xFF4797FF);

  /// Every colour in the player follows the title: [tint] is its artwork's main colour and
  /// accent a second one that stands clearly apart. Both ease in once the art is read.
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: _s.tint ?? _fallbackTint),
    duration: const Duration(milliseconds: 800),
    builder: (context, t, _) => TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _s.accent ?? Color.lerp(_s.tint ?? _fallbackTint, Colors.white, 0.35)),
      duration: const Duration(milliseconds: 800),
      builder: (context, a, _) => _build(context, t ?? _fallbackTint, a ?? _fallbackTint),
    ),
  );

  Widget _build(BuildContext context, Color tint, Color accent) {
    final app = AppScope.of(context);
    final offer = _s.resumeOffer;
    final mini = _mini;
    final showChrome = (_visible || _keepVisible) && !_paused && !_dismissed && offer == null && !mini && !_pip;
    _s.setControlsShown(showChrome);
    if (isTv && _chromeShown && !showChrome) WidgetsBinding.instance.addPostFrameCallback((_) => _focusPicture());
    // Paused, the controls stay up, and the D-pad moves between them from Play. With the
    // picture still focused, Right seeked while the big Play button looked selected (seen on
    // a Fire TV after a pause and resume).
    if (isTv && showChrome && !_s.player.state.playing && _focus.hasPrimaryFocus) WidgetsBinding.instance.addPostFrameCallback((_) => _focusPlayIfPaused());
    _chromeShown = showChrome;
    final it = _s.item;
    // Picture. A click toggles play, a double click full screen; in the corner a click
    // brings it back to full window. Keyed, so it stays the same picture either way.
    final picture = Positioned.fill(
      key: const ValueKey('picture'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (mini) {
            PlayerDock.instance.expand();
          } else if (_sheet != null || _together) {
            _closePanels();
          } else if (isTouch) {
            _touchTap(showChrome);
          } else {
            _toggle();
          }
        },
        onDoubleTapDown: isTouch ? (d) => _doubleTapAt = d.localPosition : null,
        onDoubleTap: isTouch ? () => _touchDoubleTap(MediaQuery.sizeOf(context).width) : (isDesktop && !mini ? _toggleFullscreen : null),
        child: switch (_s.video) {
          final video? => Video(controller: video, controls: NoVideoControls, fill: Colors.black, fit: fitFor(_s.aspect), subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false)),
          // Video plane: the picture is on a surface behind the app, seen through here.
          null => switch (_s.player.platform) {
            // Samsung's player: a hole in the app over the TV's video plane.
            final AvPlayPlayer av => AvPlayView(player: av),
            _ => const SizedBox.expand(),
          },
        },
      ),
    );
    final body = mini
        ? Stack(
            children: [
              picture,
              _MiniControls(
                key: const ValueKey('mini'),
                session: _s,
                tint: tint,
                accent: accent,
                buffering: !_s.ready || _s.player.state.buffering,
                onToggle: _s.togglePlay,
                onExpand: PlayerDock.instance.expand,
                onClose: _exit,
              ),
            ],
          )
        : Stack(
      children: [
        picture,
        // Controls keep clear of a phone's camera cutout and rounded corners; the picture doesn't.
        Positioned.fill(
          child: SafeArea(
            child: Stack(
              children: [
        // Direct video output: mpv draws no subtitles, so text ones are drawn here.
        if (_s.direct) Positioned.fill(child: IgnorePointer(child: AppSubtitles(session: _s))),
        if (!_s.ready || _s.player.state.buffering)
          if (_s.error == null && offer == null)
            Center(
              child: SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3, color: tint, backgroundColor: accent.withValues(alpha: 0.25)),
              ),
            ),
        if (_pulse != null)
          Center(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.7, end: 1),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                builder: (context, t, child) => Opacity(
                  opacity: (1.4 - t).clamp(0, 1),
                  child: Transform.scale(scale: t, child: child),
                ),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: playerShade(tint, 0.6),
                    border: Border.all(color: tint.withValues(alpha: 0.8), width: 2),
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 24)],
                  ),
                  child: Icon(_pulse, size: 38, color: Colors.white),
                ),
              ),
            ),
          ),

        // The pause screen: what you're watching, over a dimmed, softened picture.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_paused || _pip,
            child: AnimatedOpacity(
              opacity: _paused && !_pip ? 1 : 0,
              duration: Duration(milliseconds: _paused ? 900 : 250),
              curve: Curves.easeOut,
              onEnd: () {
                if (!_paused && _pauseLive) setState(() => _pauseLive = false);
              },
              child: TickerMode(
                enabled: _pauseLive,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: PauseScreen(session: _s, riptide: _riptide, tint: tint, accent: accent),
                ),
              ),
            ),
          ),
        ),

        // Top: title, how it's playing, window controls.
        _Fade(
          visible: showChrome,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [playerShade(tint, 0.8), Colors.transparent]),
              ),
              child: Stack(
                children: [
                  if (isDesktop && customTitleBar && !_fullscreen) const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.space4, Space.space4, 0, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RoundButton(icon: LucideIcons.arrowLeft, label: 'Back', onTap: _exit),
                        const SizedBox(width: Space.space3),
                        Expanded(
                          child: _TitleBlock(item: it, session: _s, tint: tint, accent: accent),
                        ),
                        _TogetherButton(tint: tint, ratingKey: it.ratingKey, open: _together, focusNode: _togetherFocus, onTap: _toggleTogether),
                        const SizedBox(width: Space.space2),
                        _RoundButton(icon: LucideIcons.info, label: 'Playback Info (I)', on: _info, tint: tint, onTap: () => setState(() => _info = !_info)),
                        const SizedBox(width: Space.space2),
                        if (Pip.supported) ...[
                          _RoundButton(icon: LucideIcons.pictureInPicture2, label: 'Picture in Picture', tint: tint, onTap: offer == null ? () => unawaited(Pip.enter(aspect: _videoAspect)) : null),
                          const SizedBox(width: Space.space2),
                        ],
                        if (PlayerDock.enabled) ...[
                          _RoundButton(icon: LucideIcons.pictureInPicture2, label: 'Mini Player (B)', tint: tint, onTap: offer == null ? _minimize : null),
                          const SizedBox(width: Space.space2),
                        ],
                        if (isDesktop && customTitleBar && !_fullscreen) const Padding(padding: EdgeInsets.only(top: 0), child: WindowButtons(height: 36)) else const SizedBox(width: Space.space4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (_info)
          Positioned(
            left: Space.space5,
            top: 96,
            child: _InfoPanel(session: _s, tint: tint, accent: accent),
          ),

        // Toasts ("Skipped Intro", "Subtitles: English").
        Positioned(
          top: 96,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _s.toast == null
                    ? const SizedBox.shrink()
                    : Container(
                        key: ValueKey(_s.toast),
                        padding: const EdgeInsets.symmetric(horizontal: Space.space4, vertical: Space.space2),
                        decoration: BoxDecoration(
                          color: playerShade(tint, 0.8),
                          borderRadius: BorderRadius.circular(Radii.radiusFull),
                          border: Border.all(color: tint.withValues(alpha: 0.6)),
                        ),
                        child: Text(_s.toast!, style: ConsoleText.bodyStrong.copyWith(color: Colors.white)),
                      ),
              ),
            ),
          ),
        ),

        // The sleep timer's last minute.
        Positioned(
          top: 150,
          left: 0,
          right: 0,
          child: Focus(
            focusNode: _sleepFocus,
            canRequestFocus: _s.sleepWarning || _sleepHeld.isNotEmpty,
            skipTraversal: true,
            onKeyEvent: _onSleepKey,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                  child: _s.sleepWarning ? _SleepWarning(key: const ValueKey('sleep'), session: _s, tint: tint) : const SizedBox.shrink(),
              ),
            ),
          ),
        ),

        // A soft glow of the title's colours rising behind the controls.
        _Fade(
          visible: showChrome,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.7, 1.3),
                    radius: 1.5,
                    colors: [tint.withValues(alpha: 0.3), accent.withValues(alpha: 0.12), Colors.transparent],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Bottom: scrubber and buttons on a floating frosted bar.
        _Fade(
          visible: showChrome,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [playerShade(tint, 0.75), Colors.transparent]),
              ),
              padding: const EdgeInsets.fromLTRB(Space.space5, Space.space10, Space.space5, Space.space5),
              child: MouseRegion(
                onEnter: (_) => _overControls = true,
                onExit: (_) {
                  _overControls = false;
                  // The pause screen hiding the bar isn't the pointer moving.
                  if (!_paused) _poke();
                },
                child: _BottomBar(
                  session: _s,
                  tint: tint,
                  accent: accent,
                  showRemaining: _showRemaining,
                  fullscreen: _fullscreen,
                  sheet: _sheet,
                  hasCast: _riptide.cast.isNotEmpty,
                  onToggleRemaining: () => setState(() => _showRemaining = !_showRemaining),
                  onPlayPause: _toggle,
                  onFullscreen: _toggleFullscreen,
                  onSheet: _openSheet,
                  onScrub: (v) {
                    _scrubbing = v;
                    // The hide timer may have run out mid-scrub; start it again.
                    if (!v && isTv) _poke();
                  },
                  playFocus: _playFocus,
                  seekFocus: _seekFocus,
                  sheetFocus: _sheetButtons,
                ),
              ),
            ),
          ),
        ),

        // Skip Intro / Skip Credits, and Up Next, sit above the bar.
        Positioned(
          right: Space.space6,
          bottom: showChrome ? 150 : Space.space8,
          child: Focus(
            focusNode: _cardArea,
            canRequestFocus: false,
            skipTraversal: true,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: _s.upNextVisible && _s.next != null
                  ? _UpNextCard(key: const ValueKey('next'), session: _s, spoilers: app.settings.spoilers, tint: tint, accent: accent, thumb: _s.plex.imageUrl(_s.next!.thumb ?? _s.next!.art, width: 400, height: 225))
                  : _s.skipPrompt != null
                  ? _SkipButton(key: ValueKey(_s.skipPrompt!.type), label: _s.skipPrompt!.type == 'intro' ? 'Skip Intro' : 'Skip Credits', tint: tint, onTap: _s.skipMarker)
                  : const SizedBox.shrink(),
            ),
          ),
        ),

        // Settings panel.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          top: Space.space4,
          bottom: 132,
          right: _sheet == null ? -420 : Space.space5,
          width: 380,
          // The region stays mounted so closing the panel under the pointer still counts as
          // leaving it (a removed region never reports an exit).
          child: IgnorePointer(
            ignoring: _sheet == null,
            child: MouseRegion(
              onEnter: (_) => _overControls = true,
              onExit: (_) {
                _overControls = false;
                _poke();
              },
              child: _sheet == null
                  ? const SizedBox.shrink()
                  : _held(
                      PlayerSheet(
                        session: _s,
                        tint: tint,
                        accent: accent,
                        tab: _sheet!,
                        onTab: (t) => setState(() => _sheet = t),
                        onClose: _closePanels,
                        imageUrl: (path, w, h) => _s.plex.imageUrl(path, width: w, height: h),
                        tabFocus: _sheetTabs,
                        riptide: _riptide,
                        onPerson: _openPerson,
                      ),
                    ),
            ),
          ),
        ),

        // Watch Together panel.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          top: 96,
          bottom: 132,
          right: _together ? Space.space5 : -420,
          width: 380,
          child: IgnorePointer(
            ignoring: !_together,
            child: MouseRegion(
              onEnter: (_) => _overControls = true,
              onExit: (_) {
                _overControls = false;
                _poke();
              },
              child: !_together
                  ? const SizedBox.shrink()
                  : _held(
                      GlassSurface(
                        radius: Radii.radiusLg + 4,
                        elevation: 2,
                        fill: playerShade(tint, 0.62),
                        child: TogetherPanel(item: it, tint: tint, focusOnOpen: isTv, onClose: _closePanels),
                      ),
                    ),
            ),
          ),
        ),

        // Resume or start over, before anything plays.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: offer == null ? const SizedBox.shrink() : ResumePrompt(key: const ValueKey('resume'), session: _s, at: offer, tint: tint, accent: accent, onBack: _exit),
          ),
        ),

        if (_s.error != null)
          Positioned(
            left: Space.space6,
            right: Space.space6,
            top: 96,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ErrorNote(_s.error!)]),
          ),
              ],
            ),
          ),
        ),
      ],
    );

    // On a TV, system Back closes one layer at a time (see [_back]) instead of leaving.
    return PopScope(
      canPop: !isTv,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Theme(
        data: ConsoleTheme.dark(glass: app.settings.glass),
        child: Scaffold(
          // With the video plane, the picture and its black bars are behind the app. Black
          // while the pages behind are drawn again for 4K (see GpuMemory), so they don't show.
          backgroundColor: (_s.plane || isTizen) && !ArtMemory.releaseAll.value ? Colors.transparent : Colors.black,
          body: Focus(
            focusNode: _focus,
            autofocus: true,
            // The picture covers the screen, so to the D-pad it lies beside every control: Right
            // from Mute landed on it (which then seeks). It is given focus, never moved to.
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: MouseRegion(cursor: showChrome || mini ? SystemMouseCursors.basic : SystemMouseCursors.none, onHover: (_) => _poke(), child: body),
          ),
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: const Duration(milliseconds: 250), child: child),
  );
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.item, required this.session, required this.tint, required this.accent});
  final Color accent;
  final PlexItem item;
  final PlayerSession session;
  final Color tint;
  @override
  Widget build(BuildContext context) {
    final episode = item.type == 'episode';
    final s = session;
    final q = s.streamQuality;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          episode ? (item.grandparentTitle ?? item.title) : item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ConsoleText.display.copyWith(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: Space.space2,
          runSpacing: Space.space1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              episode ? '${item.episodeCode} · ${item.title}' : [if (item.year != null) '${item.year}', if (item.contentRating != null) item.contentRating!].join(' · '),
              style: ConsoleText.body.copyWith(color: Colors.white.withValues(alpha: 0.8)),
            ),
            if (s.ready) _Tag(s.transcoding ? 'Transcode${q.isOriginal ? '' : ' · ${q.label}'}' : 'Direct Play', color: s.transcoding ? const Color(0xFFFFB547) : accent),
            if (s.rate != 1) _Tag('${s.rate}×', color: accent),
          ],
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.space2, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(Radii.radiusFull),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(
      text,
      style: ConsoleText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.session,
    required this.tint,
    required this.accent,
    required this.showRemaining,
    required this.fullscreen,
    required this.sheet,
    required this.hasCast,
    required this.onToggleRemaining,
    required this.onPlayPause,
    required this.onFullscreen,
    required this.onSheet,
    required this.onScrub,
    required this.playFocus,
    required this.seekFocus,
    required this.sheetFocus,
  });
  final PlayerSession session;
  final Color tint;
  final Color accent;
  final bool showRemaining;
  final bool fullscreen;
  final SheetTab? sheet;

  /// Plex has a cast for the title, so Riptide has something to show.
  final bool hasCast;
  final VoidCallback onToggleRemaining;
  final VoidCallback onPlayPause;
  final VoidCallback onFullscreen;
  final ValueChanged<SheetTab> onSheet;
  final ValueChanged<bool> onScrub;
  final FocusNode playFocus;
  final FocusNode seekFocus;
  final Map<SheetTab, FocusNode> sheetFocus;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final p = s.prefs;
    final mono = ConsoleText.bodyStrong.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]);
    return GlassSurface(
      radius: 18,
      elevation: 2,
      fill: playerShade(tint, 0.55),
      padding: const EdgeInsets.fromLTRB(Space.space4, Space.space2, Space.space4, Space.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only the clocks, scrubber and "Ends at" follow the position, a few times a second.
          StreamBuilder<Duration>(
            stream: s.ticks,
            builder: (context, _) {
              final pos = s.position;
              final total = s.duration;
              final left = total - pos;
              return Row(
                children: [
                  SizedBox(width: 64, child: Text(clock(pos), style: mono)),
                  Expanded(
                    child: SeekBar(
                      position: pos,
                      duration: total,
                      buffered: s.player.state.buffer + s.offset,
                      color: tint,
                      accent: accent,
                      markers: s.markers,
                      chapters: s.chapters,
                      onSeek: s.seekTo,
                      onScrub: onScrub,
                      focusable: isTv,
                      focusNode: seekFocus,
                    ),
                  ),
                  const SizedBox(width: Space.space3),
                  Focusable(
                    onTap: onToggleRemaining,
                    semanticLabel: 'Remaining or total time',
                    builder: (context, hover, focus) => Container(
                      width: 72,
                      foregroundDecoration: tvRing(focus, radius: Radii.radiusSm),
                      child: Text(
                        showRemaining ? clock(-left) : clock(total),
                        textAlign: TextAlign.right,
                        style: mono.copyWith(color: hover ? tint : Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: Space.space1),
          LayoutBuilder(
            builder: (context, box) {
              final leading = <Widget>[
                _RoundButton(icon: s.player.state.playing ? LucideIcons.pause : LucideIcons.play, label: 'Play / Pause (Space)', big: true, tint: tint, focusNode: playFocus, onTap: onPlayPause),
                const SizedBox(width: Space.space2),
                _RoundButton(icon: LucideIcons.rotateCcw, label: 'Back ${p.skipBack}s', badge: '${p.skipBack}', onTap: () => s.seekBy(-p.skipBack)),
                _RoundButton(icon: LucideIcons.rotateCw, label: 'Forward ${p.skipForward}s', badge: '${p.skipForward}', onTap: () => s.seekBy(p.skipForward)),
                if (s.isEpisode) ...[
                  _RoundButton(icon: LucideIcons.skipBack, label: 'Previous Episode (P)', onTap: s.previous == null ? null : s.playPrevious),
                  _RoundButton(icon: LucideIcons.skipForward, label: 'Next Episode (N)', onTap: s.next == null ? null : s.playNext),
                ],
                // A phone or tablet has volume buttons of its own.
                if (!isTouch) ...[const SizedBox(width: Space.space2), _Volume(session: s, tint: tint, accent: accent)],
              ];
              final status = StreamBuilder<Duration>(
                stream: s.ticks,
                builder: (context, _) {
                  final pos = s.position;
                  final left = s.duration - pos;
                  final ends = DateTime.now().add(Duration(milliseconds: (left.inMilliseconds / (s.rate <= 0 ? 1 : s.rate)).round()));
                  final chapter = s.chapterAt(pos);
                  final sleep = s.sleep.left;
                  return Text(
                    [
                      if (chapter != null && chapter.title.isNotEmpty) chapter.title,
                      'Ends at ${TimeOfDay.fromDateTime(ends).format(context)}',
                      if (sleep != null) 'Sleep in ${clock(sleep)}',
                      if (s.sleep.titles != null) s.sleep.titles == 1 ? 'Sleep after this' : 'Sleep after ${s.sleep.titles}',
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                  );
                },
              );
              final trailing = <Widget>[
                _RoundButton(
                  icon: LucideIcons.captions,
                  label: 'Subtitles (C)',
                  on: sheet == SheetTab.subtitles || s.subtitle != null,
                  tint: tint,
                  focusNode: sheetFocus[SheetTab.subtitles],
                  onTap: () => onSheet(SheetTab.subtitles),
                ),
                _RoundButton(icon: LucideIcons.audioLines, label: 'Audio (A)', on: sheet == SheetTab.audio, tint: tint, focusNode: sheetFocus[SheetTab.audio], onTap: () => onSheet(SheetTab.audio)),
                if (hasCast) _RoundButton(icon: LucideIcons.users, label: 'Riptide (R)', on: sheet == SheetTab.riptide, tint: tint, focusNode: sheetFocus[SheetTab.riptide], onTap: () => onSheet(SheetTab.riptide)),
                if (s.chapters.isNotEmpty)
                  _RoundButton(
                    icon: LucideIcons.listVideo,
                    label: 'Chapters',
                    on: sheet == SheetTab.chapters,
                    tint: tint,
                    focusNode: sheetFocus[SheetTab.chapters],
                    onTap: () => onSheet(SheetTab.chapters),
                  ),
                _RoundButton(
                  icon: LucideIcons.moon,
                  label: 'Sleep Timer',
                  on: sheet == SheetTab.playback || s.sleep.active,
                  tint: tint,
                  onTap: () => onSheet(SheetTab.playback),
                ),
                _RoundButton(
                  icon: LucideIcons.settings2,
                  label: 'Playback Settings',
                  on: sheet == SheetTab.video,
                  tint: tint,
                  focusNode: sheetFocus[SheetTab.video],
                  onTap: () => onSheet(SheetTab.video),
                ),
                // A TV is always full screen.
                if (isDesktop) _RoundButton(icon: fullscreen ? LucideIcons.minimize : LucideIcons.maximize, label: 'Full Screen (F)', onTap: onFullscreen),
              ];
              // A phone held upright, or an iPad's narrow Split View or Slide Over: the
              // panel buttons get a row of their own under the playback ones.
              if (box.maxWidth < _twoRowWidth) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [...leading, const SizedBox(width: Space.space3), Expanded(child: status)]),
                    const SizedBox(height: Space.space1),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [...trailing]),
                  ],
                );
              }
              return Row(children: [...leading, const SizedBox(width: Space.space3), Expanded(child: status), ...trailing]);
            },
          ),
        ],
      ),
    );
  }
}

/// Below this width the player's bottom bar takes two rows of buttons.
const _twoRowWidth = 600.0;

class _Volume extends StatefulWidget {
  const _Volume({required this.session, required this.tint, required this.accent});
  final Color accent;
  final PlayerSession session;
  final Color tint;
  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final max = s.prefs.volumeBoost ? 200.0 : 100.0;
    // The slider opens on hover, so a TV (whose volume is the TV's own) keeps just Mute.
    return MouseRegion(
      onEnter: (_) => setState(() => _open = !isTv),
      onExit: (_) => setState(() => _open = false),
      child: StreamBuilder<double>(
        stream: s.player.stream.volume,
        builder: (context, _) {
          final v = s.player.state.volume;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(icon: v == 0 ? LucideIcons.volumeX : (v < 50 ? LucideIcons.volume1 : LucideIcons.volume2), label: 'Mute (M)', onTap: s.toggleMute),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: _open ? 120 : 0,
                // Closed (always, on a TV) it takes no focus: Right would vanish into it.
                child: ExcludeFocus(
                  excluding: !_open,
                  child: ClipRect(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: widget.tint,
                        thumbColor: widget.accent,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(value: v.clamp(0, max), max: max, onChanged: (x) => s.setVolume(x)),
                    ),
                  ),
                ),
              ),
              if (_open)
                SizedBox(
                  width: 40,
                  child: Text('${v.round()}%', style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Sleeping in 0:42", with the way out.
class _SleepWarning extends StatelessWidget {
  const _SleepWarning({super.key, required this.session, required this.tint});
  final PlayerSession session;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final left = session.sleep.left ?? Duration.zero;
    return GestureDetector(
      onTap: session.keepWatching,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.space5, vertical: Space.space3),
        decoration: BoxDecoration(
          color: playerShade(tint, 0.85),
          borderRadius: BorderRadius.circular(Radii.radiusLg),
          border: Border.all(color: tint.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.moon, color: Colors.white, size: 22),
            const SizedBox(width: Space.space3),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sleep timer: stopping in ${clock(left)}', style: ConsoleText.bodyStrong.copyWith(color: Colors.white)),
                Text(isTv ? 'Press any button to keep watching' : 'Press any key or click to keep watching', style: ConsoleText.small.copyWith(color: Colors.white.withValues(alpha: 0.75))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.big = false, this.on = false, this.tint, this.badge, this.focusNode});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool big;
  final bool on;
  final Color? tint;
  final String? badge;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final size = big ? 44.0 : 38.0;
    final t = tint ?? Colors.white;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Focusable(
        onTap: onTap,
        focusNode: focusNode,
        semanticLabel: label,
        builder: (context, hover, focus) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size,
          height: size,
          foregroundDecoration: tvRing(focus, circle: true),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: big ? t.withValues(alpha: hover ? 1 : 0.9) : (on ? t.withValues(alpha: 0.22) : (hover || focus ? Colors.white.withValues(alpha: 0.14) : Colors.transparent)),
            border: focus ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: big ? [BoxShadow(color: t.withValues(alpha: 0.45), blurRadius: hover ? 18 : 10)] : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: big ? 22 : 19,
                color: big ? Colors.black : Colors.white.withValues(alpha: onTap == null ? 0.3 : (on ? 1 : 0.9)),
              ),
              if (badge != null)
                Text(
                  badge!,
                  style: ConsoleText.caption.copyWith(fontSize: 8, height: 1, color: Colors.white, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({super.key, required this.label, required this.tint, required this.onTap});
  final String label;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    semanticLabel: label,
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: Space.space5, vertical: Space.space3),
      foregroundDecoration: tvRing(focus, radius: Radii.radiusFull),
      decoration: BoxDecoration(
        color: hover || focus ? tint : playerShade(tint, 0.75),
        borderRadius: BorderRadius.circular(Radii.radiusFull),
        border: Border.all(color: hover || focus ? Colors.white : tint, width: 1.5),
        boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 18)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: ConsoleText.titleMd.copyWith(color: hover || focus ? Colors.black : Colors.white)),
          const SizedBox(width: Space.space2),
          Icon(LucideIcons.chevronsRight, size: 18, color: hover || focus ? Colors.black : Colors.white),
        ],
      ),
    ),
  );
}

class _UpNextCard extends StatelessWidget {
  const _UpNextCard({super.key, required this.session, required this.spoilers, required this.tint, required this.accent, required this.thumb});
  final Color accent;
  final PlayerSession session;
  final Color tint;
  final String? thumb;
  final SpoilerPrefs spoilers;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final n = s.next!;
    // "End of This" on the sleep timer: no countdown, the credits play out.
    final auto = s.prefs.autoPlayNext && !s.sleepAtEnd;
    final total = s.prefs.countdown <= 0 ? 1 : s.prefs.countdown;
    return SizedBox(
      width: 380,
      child: GlassSurface(
        radius: 16,
        elevation: 2,
        fill: playerShade(tint, 0.7),
        padding: const EdgeInsets.all(Space.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.radiusMd),
                  child: SizedBox(
                    width: 148,
                    height: 84,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumb != null) SpoilerBlur(hide: spoilers.hideImage(n), icon: false, child: ArtImage(thumb!, headers: s.plex.headers, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())),
                        if (auto)
                          Center(
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(end: s.countdown / total),
                                    duration: const Duration(milliseconds: 900),
                                    builder: (context, v, _) => CircularProgressIndicator(value: v, strokeWidth: 3, color: tint, backgroundColor: accent.withValues(alpha: 0.3)),
                                  ),
                                  Text(
                                    '${s.countdown}',
                                    style: ConsoleText.titleMd.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 4)]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Space.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UP NEXT',
                        style: ConsoleText.caption.copyWith(color: accent, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                      Text(
                        spoilers.titleOf(n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ConsoleText.titleMd.copyWith(color: Colors.white),
                      ),
                      Text(n.episodeCode, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.65))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.space3),
            Row(
              children: [
                Expanded(
                  child: _CardButton(label: 'Play Now', icon: LucideIcons.play, primary: true, tint: tint, autofocus: true, onTap: s.playNext),
                ),
                const SizedBox(width: Space.space2),
                Expanded(
                  child: _CardButton(label: 'Watch Credits', tint: tint, onTap: s.dismissUpNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.tint, required this.onTap, this.icon, this.primary = false, this.autofocus = false});
  final String label;
  final IconData? icon;
  final bool primary;
  final bool autofocus;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    autofocus: autofocus,
    semanticLabel: label,
    builder: (context, hover, focus) => AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 34,
      foregroundDecoration: tvRing(focus, radius: Radii.radiusFull),
      decoration: BoxDecoration(
        color: primary ? (hover ? Color.lerp(tint, Colors.white, 0.2) : tint) : Colors.white.withValues(alpha: hover ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(Radii.radiusFull),
        border: focus ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: primary ? Colors.black : Colors.white), const SizedBox(width: Space.space1)],
          Text(label, style: ConsoleText.bodyStrong.copyWith(color: primary ? Colors.black : Colors.white)),
        ],
      ),
    ),
  );
}

/// Live numbers from mpv: codecs, decoder, dropped frames, buffer.
class _InfoPanel extends StatefulWidget {
  const _InfoPanel({required this.session, required this.tint, required this.accent});
  final Color tint;
  final Color accent;
  final PlayerSession session;
  @override
  State<_InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<_InfoPanel> {
  List<(String, String)> _rows = const [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  Future<void> _load() async {
    final r = await widget.session.stats();
    if (mounted) setState(() => _rows = r);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 400,
    child: GlassSurface(
      radius: 14,
      fill: playerShade(widget.tint, 0.72),
      padding: const EdgeInsets.all(Space.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Playback Info', style: ConsoleText.titleMd.copyWith(color: Colors.white)),
          const SizedBox(height: Space.space2),
          for (final (k, v) in _rows)
            if (v.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(k, style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.55))),
                    ),
                    Expanded(
                      child: Text(v, style: ConsoleText.data.copyWith(fontSize: 11, height: 1.5, color: Colors.white)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}

/// Watch Together in the top bar: a round button, or who you're watching with once in a room.
class _TogetherButton extends StatelessWidget {
  const _TogetherButton({required this.tint, required this.ratingKey, required this.open, required this.onTap, this.focusNode});
  final Color tint;
  final String ratingKey;
  final bool open;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wt = app.watchTogether, party = app.openParty;
    return ListenableBuilder(
      listenable: Listenable.merge([wt, party]),
      builder: (context, _) {
        final byCode = party.inRoomFor(ratingKey);
        if (!wt.inRoomFor(ratingKey) && !byCode) return _RoundButton(icon: LucideIcons.usersRound, label: 'Watch Together', on: open, tint: tint, focusNode: focusNode, onTap: onTap);
        final others = byCode
            ? [for (final p in party.people) if (p.peerId != party.state.peerId && p.connected) (name: cleanLabel(p.name, max: 32, fallback: 'Guest'))]
            : [for (final p in wt.peers) if (!p.me) (name: p.name)];
        final label = others.isEmpty
            ? (byCode ? 'Room ${party.code}' : 'Waiting for friends')
            : 'With ${others.map((p) => p.name).take(2).join(' & ')}${others.length > 2 ? ' +${others.length - 2}' : ''}';
        return Focusable(
          onTap: onTap,
          focusNode: focusNode,
          semanticLabel: 'Watch Together: $label',
          builder: (context, hover, focus) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            foregroundDecoration: tvRing(focus, radius: Radii.radiusFull),
            padding: const EdgeInsets.only(left: 6, right: Space.space3),
            decoration: BoxDecoration(
              color: playerShade(tint, hover || open ? 0.5 : 0.7),
              borderRadius: BorderRadius.circular(Radii.radiusFull),
              border: Border.all(color: tint.withValues(alpha: focus ? 1 : 0.6)),
              boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.3), blurRadius: 14)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28.0 + 18 * (others.length.clamp(1, 3) - 1),
                  height: 28,
                  child: Stack(
                    children: [
                      for (var i = 0; i < others.length.clamp(1, 3); i++)
                        Positioned(
                          left: 18.0 * i,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.lerp(Colors.black, tint, 0.45 + 0.15 * i),
                              border: Border.all(color: Colors.black.withValues(alpha: 0.6), width: 2),
                            ),
                            child: Center(
                              child: others.isEmpty
                                  ? const Icon(LucideIcons.usersRound, size: 14, color: Colors.white)
                                  : Text(
                                      others[i].name.characters.first.toUpperCase(),
                                      style: ConsoleText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.space2),
                Text(
                  label,
                  style: ConsoleText.small.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The mini player's own controls: Expand, Close and Play / Pause over the picture while the
/// pointer is on it, and a thin line of progress along the bottom all the time.
class _MiniControls extends StatefulWidget {
  const _MiniControls({
    super.key,
    required this.session,
    required this.tint,
    required this.accent,
    required this.buffering,
    required this.onToggle,
    required this.onExpand,
    required this.onClose,
  });
  final PlayerSession session;
  final Color tint;
  final Color accent;
  final bool buffering;
  final VoidCallback onToggle;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  State<_MiniControls> createState() => _MiniControlsState();
}

class _MiniControlsState extends State<_MiniControls> {
  bool _hover = false;

  /// Who or what is playing, short enough for the corner.
  static String label(PlexItem it) => it.type == 'episode'
      ? '${it.grandparentTitle ?? it.title} · S${it.parentIndex ?? 0} E${it.index ?? 0}'
      : it.title;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Positioned.fill(
      child: StreamBuilder<bool>(
        stream: s.player.stream.playing,
        initialData: s.player.state.playing,
        builder: (context, snap) => _build(s, snap.data ?? false),
      ),
    );
  }

  Widget _build(PlayerSession s, bool playing) {
    // Paused, the controls stay up, so it's clear why the picture has stopped.
    final show = _hover || !playing;
    return MouseRegion(
        // Clicks between the buttons go on to the picture, which expands it.
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: show ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.7)],
                        stops: const [0, 0.4, 0.6, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.buffering)
              Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3, color: widget.tint, backgroundColor: widget.accent.withValues(alpha: 0.25)),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedOpacity(
                  opacity: show ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Stack(
                    children: [
                      Positioned(left: 8, top: 8, child: _MiniButton(icon: LucideIcons.maximize2, label: 'Expand (B)', onTap: widget.onExpand)),
                      Positioned(right: 8, top: 8, child: _MiniButton(icon: LucideIcons.x, label: 'Close', onTap: widget.onClose)),
                      if (!widget.buffering)
                        Center(
                          child: _MiniButton(icon: playing ? LucideIcons.pause : LucideIcons.play, label: playing ? 'Pause' : 'Play', big: true, tint: widget.tint, onTap: widget.onToggle),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: StreamBuilder<Duration>(
                          stream: s.ticks,
                          builder: (context, _) => Row(
                            children: [
                              Expanded(
                                child: Text(label(s.item), maxLines: 1, overflow: TextOverflow.ellipsis, style: ConsoleText.bodyStrong.copyWith(color: Colors.white, fontSize: 13)),
                              ),
                              const SizedBox(width: Space.space2),
                              Text('${clock(s.position)} / ${clock(s.duration)}', style: ConsoleText.caption.copyWith(color: Colors.white.withValues(alpha: 0.85), fontFeatures: const [FontFeature.tabularFigures()])),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Progress, always there.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: IgnorePointer(
                child: StreamBuilder<Duration>(
                  stream: s.ticks,
                  builder: (context, _) {
                    final total = s.duration.inMilliseconds;
                    final f = total <= 0 ? 0.0 : (s.position.inMilliseconds / total).clamp(0.0, 1.0);
                    return ColoredBox(
                      color: Colors.white.withValues(alpha: 0.2),
                      child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: f, child: ColoredBox(color: widget.tint)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.label, required this.onTap, this.big = false, this.tint});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final size = big ? 48.0 : 32.0;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Focusable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hover, focus) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: big ? playerShade(tint ?? Colors.white, hover ? 0.85 : 0.7) : Colors.black.withValues(alpha: hover ? 0.7 : 0.45),
            border: big ? Border.all(color: (tint ?? Colors.white).withValues(alpha: 0.85), width: 2) : null,
          ),
          child: Icon(icon, size: big ? 22 : 16, color: Colors.white),
        ),
      ),
    );
  }
}
