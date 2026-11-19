import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app_info.dart';
import '../../platform.dart';
import '../../services/live_players.dart';
import '../../services/mpv_tls.dart';
import '../../services/trailers.dart';

const _rotateEvery = Duration(seconds: 9);
/// How long a trailer plays before the spotlight moves on to its next title.
const _clipLength = Duration(seconds: 20);

/// The hero's art, fetched at the screen's width; 720p on a 32-bit TV, where a 1080p copy
/// takes 8 MB of the graphics memory a 4K video needs.
final _artWidth = isLowMemoryTv ? 1280 : 1920;
final _artHeight = _artWidth * 9 ~/ 16;

/// The full-bleed Home hero. Rotates through [items], switches to whatever title is
/// [preview]ed in the rows below, and plays a muted trailer clip behind the details.
class Spotlight extends StatefulWidget {
  const Spotlight({
    super.key,
    required this.items,
    required this.preview,
    required this.height,
    required this.active,
    required this.plex,
    required this.trailers,
    required this.trailersOn,
    this.focusOnly = false,
    required this.onPlay,
    required this.onInfo,
    this.onReroll,
    this.rerolling = false,
  });

  final List<PlexItem> items;
  final ValueListenable<PlexItem?> preview;
  final double height;

  /// On screen and not covered by another page; trailers only play while true.
  final bool active;
  final PlexClient plex;
  final Trailers trailers;
  final bool trailersOn;

  /// Trailers only while focus is on the spotlight's own buttons, and the clip's player is
  /// freed (not just stopped) as soon as focus leaves, the page is covered, or a title plays.
  /// For 32-bit TVs, where a second video player's memory is otherwise held all along.
  final bool focusOnly;
  final Future<void> Function(PlexItem) onPlay;
  final void Function(PlexItem) onInfo;

  /// Picks a fresh set of spotlight titles.
  final VoidCallback? onReroll;
  final bool rerolling;

  @override
  State<Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<Spotlight> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: _rotateEvery)..addStatusListener(_onClock);
  int _index = 0;
  PlexItem? _previewing;
  Timer? _previewDwell;
  Timer? _previewEnd;
  bool _hoverHero = false;

  /// Focus is on one of the spotlight's buttons.
  bool _focusIn = false;

  /// The shown title's Play and More Info buttons. Each title gets fresh ones, so when the
  /// spotlight moves on under focus, focus goes to the same button of the next title (the old
  /// title's buttons fade out with it and are disposed after).
  FocusNode _playNode = FocusNode(debugLabel: 'spotlight play');
  FocusNode _infoNode = FocusNode(debugLabel: 'spotlight info');

  Player? _player;
  VideoController? _video;
  StreamSubscription<bool>? _completed;
  bool _videoOn = false;
  bool _muted = true;
  String? _clipFor;
  Timer? _trailerDelay;
  Timer? _clipEnd;
  int _trailerSeq = 0;

  /// The call that last opened a clip in the player.
  int _openSeq = 0;

  /// Player calls run one at a time, in order. On Android, stopping or disposing the player
  /// while a clip is still opening crashed the app (mpv swaps its video surface mid-open).
  Future<void> _ops = Future.value();
  Future<T> _serial<T>(Future<T> Function() op) {
    final r = _ops.then((_) => op());
    _ops = r.then<void>((_) {}, onError: (Object _) {});
    return r;
  }
  BackdropController? _backdrop;

  PlexItem? get _shown => _previewing ?? (widget.items.isEmpty ? null : widget.items[_index % widget.items.length]);

  @override
  void initState() {
    super.initState();
    widget.preview.addListener(_onPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backdrop = BackdropScope.maybeOf(context);
      _changed();
    });
  }

  @override
  void didUpdateWidget(Spotlight old) {
    super.didUpdateWidget(old);
    if (old.preview != widget.preview) {
      old.preview.removeListener(_onPreview);
      widget.preview.addListener(_onPreview);
    }
    final itemsChanged = old.items.map((i) => i.ratingKey).join() != widget.items.map((i) => i.ratingKey).join();
    if (itemsChanged) {
      // A new set (first load or a re-roll) starts from its first title.
      _index = 0;
      _previewing = null;
    }
    if (old.active != widget.active || old.trailersOn != widget.trailersOn || old.focusOnly != widget.focusOnly || itemsChanged) _changed();
  }

  @override
  void dispose() {
    widget.preview.removeListener(_onPreview);
    _clock.dispose();
    _previewDwell?.cancel();
    _previewEnd?.cancel();
    _trailerDelay?.cancel();
    _clipEnd?.cancel();
    _completed?.cancel();
    _playNode.dispose();
    _infoNode.dispose();
    final p = _player;
    if (p != null) LivePlayers.going(p, _serial(p.dispose));
    final b = _backdrop;
    scheduleMicrotask(() => b?.clear(this));
    super.dispose();
  }

  // ---- rotation ----

  void _onClock(AnimationStatus s) {
    if (s == AnimationStatus.completed) _go(_index + 1);
  }

  void _go(int i) {
    if (widget.items.isEmpty) return;
    final before = _shown?.ratingKey;
    final onPlay = _playNode.hasFocus, onInfo = _infoNode.hasFocus;
    setState(() {
      _index = (i + widget.items.length) % widget.items.length;
      _previewing = null;
    });
    if (_shown?.ratingKey != before && (onPlay || onInfo)) _carryFocus(onPlay);
    debugPrint('spotlight: next ${_index + 1}/${widget.items.length}${onPlay || onInfo ? ' (focus on ${onPlay ? 'Play' : 'More Info'})' : ''}');
    _changed();
  }

  /// Focus was on the old title's [play] (or More Info) button: give it to the new title's.
  void _carryFocus(bool play) {
    final oldPlay = _playNode, oldInfo = _infoNode;
    _playNode = FocusNode(debugLabel: 'spotlight play');
    _infoNode = FocusNode(debugLabel: 'spotlight info');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (play ? _playNode : _infoNode).requestFocus();
    });
    // After the old title's fade-out (450 ms), when its buttons have left the tree.
    Future<void>.delayed(const Duration(seconds: 2), () {
      oldPlay.dispose();
      oldInfo.dispose();
    });
  }

  /// Whether a trailer may play now.
  bool get _trailerWanted => widget.active && widget.trailersOn && (!widget.focusOnly || _focusIn);

  /// The title holds still while a button has focus only with trailers off. With trailers on
  /// it keeps rotating: a trailer plays for [_clipLength], a title without one for [_rotateEvery].
  bool get _holdForFocus => _focusIn && !widget.trailersOn;

  void _resumeClock() {
    if (widget.active && _previewing == null && !_hoverHero && !_holdForFocus && !_videoOn) _clock.forward();
  }

  /// The shown title changed (or we became visible): reset the clock and the trailer.
  void _changed() {
    if (!mounted) return;
    _stopTrailer(release: widget.focusOnly && !_trailerWanted);
    final item = _shown;
    // The hero's own art URL, so the window backdrop shares its download. Only while Home is on top: a late timer mustn't repaint another page's backdrop.
    if (ModalRoute.isCurrentOf(context) ?? true) {
      final url = item == null ? null : widget.plex.imageUrl(item.art ?? item.thumb, width: _artWidth, height: _artHeight);
      // From didUpdateWidget, mid-build: the backdrop above us can't rebuild until the frame is done.
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _backdrop?.set(this, url);
        });
      } else {
        _backdrop?.set(this, url);
      }
    }
    _clock.reset();
    if (!widget.active) return;
    if (_previewing == null && !_hoverHero && !_holdForFocus) _clock.forward();
    if (item != null && _trailerWanted) {
      _trailerDelay = Timer(_previewing != null ? const Duration(milliseconds: 900) : const Duration(milliseconds: 2500), () => _startTrailer(item));
    }
  }

  void _onPreview() {
    final p = widget.preview.value;
    _previewDwell?.cancel();
    if (p == null) {
      // Leaving the rows: hold the preview a moment, then go back to the rotation.
      _previewEnd?.cancel();
      _previewEnd = Timer(const Duration(seconds: 6), () {
        if (mounted && _previewing != null && widget.preview.value == null) {
          setState(() => _previewing = null);
          _changed();
        }
      });
      return;
    }
    _previewEnd?.cancel();
    _previewDwell = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || widget.preview.value != p || _previewing?.ratingKey == p.ratingKey) return;
      setState(() => _previewing = p);
      _changed();
    });
  }

  // ---- trailer ----

  Player _newTrailerPlayer() {
    final player = _player = Player(
      // On a 32-bit TV the same 8 MB read-ahead as the main player.
      configuration: PlayerConfiguration(title: appName, bufferSize: (widget.focusOnly ? 8 : 24) * 1024 * 1024, protocolWhitelist: streamProtocols),
    );
    // Leaving the app lets it go first (see LivePlayers).
    LivePlayers.add(player, () => _stopTrailer(release: true));
    return player;
  }

  Future<void> _startTrailer(PlexItem item) async {
    final seq = ++_trailerSeq;
    final clip = await widget.trailers.forItem(item);
    if (!mounted || seq != _trailerSeq || clip == null || !_trailerWanted) return;
    // A clip is coming: the rotation waits while it opens (slow on a TV), and resumes if it fails.
    _clock.stop();
    final player = _player ?? _newTrailerPlayer();
    _video ??= VideoController(player);
    _completed ??= player.stream.completed.listen((done) {
      if (done) _endTrailer();
    });
    try {
      final opened = await _serial(() async {
        // Stopped while waiting for its turn.
        if (!mounted || seq != _trailerSeq) return false;
        // yt-dlp is on only for a YouTube trailer, and off again for the next Plex clip.
        final ytdl = clip.viaYtdl && youtubeUrl(url: clip.url) != null;
        if (player.platform is NativePlayer) {
          final native = player.platform as NativePlayer;
          // A Plex clip's address carries the token; a YouTube one is checked the same way.
          await MpvTls.apply(native);
          if (ytdl) {
            await native.setProperty('ytdl', 'yes');
            await native.setProperty('ytdl-format', 'bv*[height<=1080]+ba/b[height<=1080]/b');
          } else {
            // An mpv without yt-dlp support has no such option, which is just as good.
            await native.setProperty('ytdl', 'no').catchError((Object _) {});
          }
        }
        if (clip.viaYtdl && !ytdl) return false;
        if (!MpvTls.canCheck(clip.url)) return false;
        await player.setVolume(_muted ? 0 : 70);
        // Stopped while getting ready: don't start a clip nobody will see.
        if (!mounted || seq != _trailerSeq) return false;
        _openSeq = seq;
        await player.open(Media(clip.url, httpHeaders: clip.headers, start: clip.start));
        return true;
      });
      if (!opened) {
        if (mounted && seq == _trailerSeq) _resumeClock();
        return;
      }
      await _video!.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('trailer: $e');
      if (mounted && seq == _trailerSeq) _resumeClock();
      return;
    }
    if (!mounted || seq != _trailerSeq) {
      // Stopped while it opened: stop it, unless a newer clip has opened since.
      if (mounted && _openSeq == seq) unawaited(_serial(player.stop));
      return;
    }
    _clock.stop(); // the clip sets the pace now
    setState(() {
      _videoOn = true;
      _clipFor = item.ratingKey;
    });
    debugPrint('trailer: playing (${_clipLength.inSeconds} s)');
    _clipEnd = Timer(_clipLength, _endTrailer);
  }

  void _endTrailer() {
    if (!mounted || !_videoOn) return;
    _clipEnd?.cancel();
    setState(() => _videoOn = false);
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      final p = _player;
      if (mounted && !_videoOn && p != null) unawaited(_serial(p.stop));
    });
    if (_previewing == null && !_hoverHero && !_holdForFocus) _go(_index + 1);
  }

  /// Stops the clip. With [release], the player goes too, decoder and video surface with it;
  /// the future completes once it has.
  Future<void> _stopTrailer({bool release = false}) {
    _trailerSeq++;
    _trailerDelay?.cancel();
    _clipEnd?.cancel();
    if (_videoOn && mounted) setState(() => _videoOn = false);
    _clipFor = null;
    final p = _player;
    if (p == null) return Future.value();
    if (!release) {
      unawaited(_serial(p.stop));
      return Future.value();
    }
    _player = null;
    _video = null;
    _completed?.cancel();
    _completed = null;
    debugPrint('trailer: player released');
    if (!mounted) return LivePlayers.going(p, _serial(p.dispose));
    // The Video widget goes in the next frame; the player after that, so nothing draws a
    // disposed controller.
    setState(() {});
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => done.complete(_serial(p.dispose)));
    LivePlayers.going(p, done.future);
    return done.future;
  }

  void _onFocus(bool on) {
    if (_focusIn == on) return;
    _focusIn = on;
    // Up from the rows onto the buttons: show the whole spotlight again, not just its bottom edge
    // (Home counts it as off screen, with its rotation and trailer paused, once scrolled past).
    // Its buttons don't scroll themselves into view; the D-pad's glide towards the middle,
    // which starts with this focus change, is replaced next frame: one move to the top.
    if (on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusIn) return;
        final s = Scrollable.maybeOf(context);
        // (Still at the top with that glide only just starting, as at launch, counts too.)
        if (s != null && (s.position.pixels > 0 || s.position.isScrollingNotifier.value)) s.position.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      });
    }
    // With trailers off the title holds still while a button has focus. With trailers on it
    // keeps rotating, and _go hands focus to the next title's buttons.
    if (widget.focusOnly && widget.trailersOn) {
      _changed();
    } else if (_holdForFocus) {
      _clock.stop();
    } else {
      _resumeClock();
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    final p = _player;
    if (p != null) await _serial(() => p.setVolume(_muted ? 0 : 70));
  }

  Future<void> _play(PlexItem item) async {
    final freed = _stopTrailer(release: widget.focusOnly);
    _clock.stop();
    // A 4K title needs the trailer's memory back before its decoder opens.
    if (widget.focusOnly) await freed.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (!mounted) return;
    await widget.onPlay(item);
    if (mounted) _changed();
  }

  void _setHover(bool v) {
    // The edge arrows follow this.
    if (_hoverHero != v) setState(() => _hoverHero = v);
    if (!widget.active || _previewing != null || _videoOn || _holdForFocus) return;
    v ? _clock.stop() : _clock.forward();
  }

  @override
  Widget build(BuildContext context) {
    final item = _shown;
    final c = context.c;
    final base = c.surface000;
    // The hero stays dark in both themes (white type over art); only its bottom edge takes the page colour.
    final dark = Theme.of(context).brightness == Brightness.dark;
    const ink = Color(0xFF0A0C0F);
    if (item == null) {
      return SizedBox(
        height: widget.height * 0.5,
        child: const Center(child: LoadingNote(label: 'Picking something good')),
      );
    }
    final detail = TitleDetail.fromPlex(
      item,
      image: (p, w, h) => widget.plex.imageUrl(p, width: w, height: h),
    );
    if (ConsoleDensity.compactOf(context)) return _compact(context, item, detail);
    final art = widget.plex.imageUrl(item.art ?? item.thumb, width: _artWidth, height: _artHeight);
    final showVideo = _videoOn && _clipFor == item.ratingKey && _video != null;

    return Focus(
      // Not a stop for the D-pad itself; it only notices focus coming and going among the buttons.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocus,
      child: MouseRegion(
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Art (or the trailer), fading out at the bottom into the blurred window backdrop.
              _fadeOut(
                Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      child: art == null
                          ? const SizedBox.expand()
                          : ArtImage(art, key: ValueKey(art), fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
                    ),
                    if (_video != null)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 700),
                        opacity: showVideo ? 1 : 0,
                        child: IgnorePointer(
                          child: Video(controller: _video!, fit: BoxFit.cover, controls: NoVideoControls, fill: Colors.transparent),
                        ),
                      ),
                    // Video textures can skip the mask, so a wash darkens the bottom under it too.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [base.withValues(alpha: 0), base.withValues(alpha: 0.7), base],
                          // Light pages fade later so the buttons keep their dark ground.
                          stops: dark ? const [0.5, 0.82, 1] : const [0.72, 0.9, 1],
                        ),
                      ),
                    ),
                    // Keeps the text readable over bright art.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [ink.withValues(alpha: 0.9), ink.withValues(alpha: 0.5), ink.withValues(alpha: 0)], stops: const [0, 0.38, 0.7]),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 48,
                bottom: widget.height * 0.2,
                width: (MediaQuery.sizeOf(context).width * 0.46).clamp(360, 640),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                  child: _HeroInfo(
                    key: ValueKey(item.ratingKey),
                    item: item,
                    detail: detail,
                    logoUrl: widget.plex.imageUrl(item.clearLogo, width: 900, height: 360),
                    previewing: _previewing != null,
                    playNode: _playNode,
                    infoNode: _infoNode,
                    onPlay: () => _play(item),
                    onInfo: () => widget.onInfo(item),
                  ),
                ),
              ),
              Positioned(
                right: 48,
                bottom: widget.height * 0.2,
                child: Row(
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: showVideo ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !showVideo,
                        // Hidden, it's no stop for the D-pad either (Right from More Info went to it).
                        child: ExcludeFocus(
                          excluding: !showVideo,
                          child: _RoundButton(icon: _muted ? LucideIcons.volumeX : LucideIcons.volume2, label: _muted ? 'Unmute' : 'Mute', onTap: _toggleMute),
                        ),
                      ),
                    ),
                    if (widget.onReroll != null) ...[const SizedBox(width: Space.space2), _RerollButton(spinning: widget.rerolling, onTap: widget.onReroll!)],
                    if ((detail.contentRating ?? '').isNotEmpty) ...[const SizedBox(width: Space.space3), _RatingFlag(detail.contentRating!)],
                  ],
                ),
              ),
              if (widget.items.length > 1)
                Positioned(
                  right: 48,
                  bottom: widget.height * 0.2 - 36,
                  // The tint comes from a thumbnail of the art (the colour needs only a few
                  // pixels), worked out once; just the pager follows the clock.
                  child: ArtTint(
                    url: widget.plex.imageUrl(item.art ?? item.thumb, width: 64, height: 36),
                    fallback: Colors.white,
                    builder: (context, tint) => AnimatedBuilder(
                      animation: _clock,
                      builder: (context, _) => _Pager(count: widget.items.length, index: _index, progress: _previewing == null ? _clock.value : 0, dim: _previewing != null, tint: tint, onTap: _go),
                    ),
                  ),
                ),
              if (widget.items.length > 1) ...[
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: widget.height * 0.2,
                  child: Center(
                    child: _EdgeArrow(icon: LucideIcons.chevronLeft, visible: _hoverHero, onTap: () => _go(_index - 1)),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: widget.height * 0.2,
                  child: Center(
                    child: _EdgeArrow(icon: LucideIcons.chevronRight, visible: _hoverHero, onTap: () => _go(_index + 1)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone spotlight: the title's poster across the screen (its backdrop when the phone is
/// on its side), the name and Play / More Info centred at the bottom, swiped sideways to the
/// next title. No trailer clips (they'd use mobile data); the pager dots show where you are.
extension on _SpotlightState {
  Widget _compact(BuildContext context, PlexItem item, TitleDetail detail) {
    final base = context.c.surface000;
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height >= size.width;
    final art = portrait ? widget.plex.imageUrl(item.posterPath ?? item.art, width: 720, height: 1080) : widget.plex.imageUrl(item.art ?? item.thumb, width: 1280, height: 720);
    final logo = widget.plex.imageUrl(item.clearLogo, width: 720, height: 288);
    final series = item.type == 'show' || item.type == 'season' || item.type == 'episode';
    final resumeMs = item.isPlayable ? (item.viewOffset ?? 0) : 0;
    final meta = <String>[
      if (detail.year != null) '${detail.year}',
      ...detail.genres.take(2),
      if (item.type == 'show' && (item.childCount ?? 0) > 0) '${item.childCount} Season${item.childCount == 1 ? '' : 's'}' else if (detail.runtimeMs != null) formatDuration(detail.runtimeMs),
    ];
    final title = Text(
      detail.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: portrait ? TextAlign.center : TextAlign.start,
      style: ConsoleText.display.copyWith(fontSize: portrait ? 34 : 26, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Colors.white, shadows: _shadow),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.onInfo(item),
      // A swipe sideways moves to the next (or last) title.
      onHorizontalDragEnd: widget.items.length < 2
          ? null
          : (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 150) return;
              _go(_index + (v < 0 ? 1 : -1));
            },
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
              child: art == null
                  ? const SizedBox.expand()
                  : ArtImage(art, key: ValueKey(art), fit: BoxFit.cover, alignment: portrait ? Alignment.topCenter : Alignment.center, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
            ),
            if (!portrait)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.8), Colors.black.withValues(alpha: 0)], stops: const [0, 0.6]),
                ),
              ),
            // Shade under the status bar at the top, and into the page at the bottom.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0), base.withValues(alpha: 0), base.withValues(alpha: 0.85), base],
                  stops: const [0, 0.2, 0.45, 0.8, 1],
                ),
              ),
            ),
            Positioned(
              left: Space.space5,
              // On its side the details keep to the left half, over a darker edge.
              right: portrait ? Space.space5 : size.width - Space.space5 - (size.width * 0.5).clamp(0, 400),
              bottom: portrait ? Space.space6 : Space.space4,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                layoutBuilder: (current, previous) => Stack(alignment: portrait ? Alignment.bottomCenter : Alignment.bottomLeft, children: [...previous, ?current]),
                child: Column(
                  key: ValueKey(item.ratingKey),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: portrait ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ConsoleLogo(height: 14, ink: LogoInk.white),
                        const SizedBox(width: Space.space2),
                        Text(
                          series ? 'SERIES' : 'FILM',
                          style: ConsoleText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.8, color: Colors.white.withValues(alpha: 0.85), shadows: _shadow),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.space2),
                    if (logo != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: portrait ? 84 : 56, maxWidth: 280),
                        child: ArtImage(logo, fit: BoxFit.contain, alignment: portrait ? Alignment.center : Alignment.centerLeft, errorBuilder: (_, _, _) => title),
                      )
                    else
                      title,
                    const SizedBox(height: Space.space2),
                    Text(
                      meta.join('  ·  '),
                      textAlign: portrait ? TextAlign.center : TextAlign.start,
                      style: ConsoleText.bodyStrong.copyWith(fontSize: 13, color: Colors.white.withValues(alpha: 0.9), shadows: _shadow),
                    ),
                    const SizedBox(height: Space.space4),
                    Row(
                      children: [
                        Expanded(child: _PillButton(label: resumeMs > 0 ? 'Resume' : 'Play', icon: LucideIcons.play, solid: true, focusNode: _playNode, onTap: () => _play(item), center: true)),
                        const SizedBox(width: Space.space3),
                        Expanded(child: _PillButton(label: 'More Info', icon: LucideIcons.info, focusNode: _infoNode, onTap: () => widget.onInfo(item), center: true)),
                      ],
                    ),
                    if (portrait && widget.items.length > 1 && _previewing == null) ...[
                      const SizedBox(height: Space.space3),
                      AnimatedBuilder(
                        animation: _clock,
                        builder: (context, _) => _Pager(count: widget.items.length, index: _index, progress: _clock.value, dim: false, tint: Colors.white, onTap: _go),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _shadow = [Shadow(color: Color(0xAA000000), blurRadius: 18, offset: Offset(0, 2))];

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({super.key, required this.item, required this.detail, required this.logoUrl, required this.previewing, required this.playNode, required this.infoNode, required this.onPlay, required this.onInfo});
  final PlexItem item;
  final FocusNode playNode;
  final FocusNode infoNode;
  final TitleDetail detail;
  final String? logoUrl;
  final bool previewing;
  final VoidCallback onPlay;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final series = item.type == 'show' || item.type == 'season' || item.type == 'episode';
    final titleText = Text(
      detail.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: ConsoleText.display.copyWith(fontSize: 54, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -1.6, color: Colors.white, shadows: _shadow),
    );
    final score = detail.scores.where((s) => s.source == ScoreSource.imdb).firstOrNull ?? detail.scores.firstOrNull;
    final rt = detail.scores.where((s) => s.source == ScoreSource.rtCritic).firstOrNull;
    final meta = <String>[
      if (detail.year != null) '${detail.year}',
      ...detail.genres.take(2),
      if (item.type == 'show' && (item.childCount ?? 0) > 0) '${item.childCount} Season${item.childCount == 1 ? '' : 's'}' else if (detail.runtimeMs != null) formatDuration(detail.runtimeMs),
    ];
    final resumeMs = item.isPlayable ? (item.viewOffset ?? 0) : 0;
    final metaStyle = ConsoleText.bodyStrong.copyWith(fontSize: 14, color: Colors.white.withValues(alpha: 0.92), shadows: _shadow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ConsoleLogo(height: 18, ink: LogoInk.white),
            const SizedBox(width: Space.space2),
            Text(
              previewing ? (item.viewOffset != null ? 'CONTINUE WATCHING' : 'IN YOUR LIBRARY') : (series ? 'SERIES' : 'FILM'),
              style: ConsoleText.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 3.2, color: Colors.white.withValues(alpha: 0.85), shadows: _shadow),
            ),
          ],
        ),
        const SizedBox(height: Space.space3),
        if (logoUrl != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130, maxWidth: 480),
            child: ArtImage(logoUrl!, fit: BoxFit.contain, alignment: Alignment.bottomLeft, errorBuilder: (_, _, _) => titleText),
          )
        else
          titleText,
        if (detail.subtitle != null) ...[
          const SizedBox(height: Space.space2),
          Text(
            '${item.type == 'episode' ? '${item.episodeCode}  ' : ''}${detail.subtitle}',
            style: ConsoleText.titleLg.copyWith(fontSize: 20, color: Colors.white, shadows: _shadow),
          ),
        ],
        const SizedBox(height: Space.space4),
        Wrap(
          spacing: Space.space2,
          runSpacing: Space.space1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (score != null) ScoreChip(score),
            if (rt != null && rt != score) ScoreChip(rt),
            for (final (i, m) in meta.indexed) ...[if (i > 0 || score != null) Text('·', style: metaStyle.copyWith(color: Colors.white54)), Text(m, style: metaStyle)],
          ],
        ),
        if ((detail.summary ?? '').isNotEmpty) ...[
          const SizedBox(height: Space.space3),
          Text(
            detail.summary!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.body.copyWith(fontSize: 15, height: 1.5, color: Colors.white.withValues(alpha: 0.9), shadows: _shadow),
          ),
        ],
        if (item.watchProgress != null) ...[
          const SizedBox(height: Space.space3),
          SizedBox(
            width: 260,
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: item.watchProgress, minHeight: 3, backgroundColor: Colors.white24, color: c.primary),
                  ),
                ),
                const SizedBox(width: Space.space2),
                Text('${formatDuration((item.duration ?? 0) - (item.viewOffset ?? 0))} left', style: ConsoleText.caption.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.space5),
        Wrap(
          spacing: Space.space3,
          runSpacing: Space.space2,
          children: [
            _PillButton(label: resumeMs > 0 ? 'Resume' : 'Play', icon: LucideIcons.play, solid: true, focusNode: playNode, onTap: onPlay),
            _PillButton(label: 'More Info', icon: LucideIcons.info, focusNode: infoNode, onTap: onInfo),
          ],
        ),
      ],
    );
  }
}

/// Netflix-style big pill: white solid for Play, frosted for the rest.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.icon, required this.onTap, this.focusNode, this.solid = false, this.center = false});
  final FocusNode? focusNode;

  /// Centred in a full-width button (the phone spotlight).
  final bool center;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool solid;

  @override
  Widget build(BuildContext context) => Focusable(
    onTap: onTap,
    focusNode: focusNode,
    semanticLabel: label,
    // The spotlight scrolls Home to the top when it gets focus ([_SpotlightState._onFocus]).
    reveal: false,
    builder: (context, hover, focus) {
      final bg = solid ? (hover ? Colors.white.withValues(alpha: 0.82) : Colors.white) : Colors.white.withValues(alpha: hover ? 0.32 : 0.2);
      final fg = solid ? Colors.black : Colors.white;
      return withFocusRing(
        context,
        focused: focus,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 46,
          width: center ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: Space.space6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
            border: solid ? null : Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: fg, fill: solid ? 1 : 0),
              const SizedBox(width: Space.space2),
              Text(
                label,
                style: ConsoleText.titleMd.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Focusable(
      onTap: onTap,
      semanticLabel: label,
      reveal: false,
      builder: (context, hover, focus) => withFocusRing(
        context,
        focused: focus,
        radius: 20,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: hover ? 0.5 : 0.3),
            border: Border.all(color: Colors.white70),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    ),
  );
}

/// Content rating on the right edge, behind a light bar, as streaming apps show it.
class _RatingFlag extends StatelessWidget {
  const _RatingFlag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.only(left: Space.space3, right: Space.space8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      border: const Border(left: BorderSide(color: Colors.white70, width: 3)),
    ),
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: ConsoleText.titleMd.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.count, required this.index, required this.progress, required this.dim, required this.tint, required this.onTap});
  final int count;

  /// The current title's art colour fills the active segment.
  final Color tint;
  final int index;
  final double progress;
  final bool dim;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dim ? 0.45 : 1,
    child: Row(
      children: [
        for (var i = 0; i < count; i++)
          Focusable(
            onTap: () => onTap(i),
            semanticLabel: 'Spotlight ${i + 1}',
            reveal: false,
            builder: (context, hover, focus) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == index ? 36 : 18,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: Colors.white.withValues(alpha: hover || focus ? 0.7 : 0.35),
                ),
                alignment: Alignment.centerLeft,
                child: i == index
                    ? FractionallySizedBox(
                        widthFactor: dim ? 1 : progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.6), blurRadius: 8)],
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Dice that tumble while a new set of titles loads.
class _RerollButton extends StatefulWidget {
  const _RerollButton({required this.spinning, required this.onTap});
  final bool spinning;
  final VoidCallback onTap;
  @override
  State<_RerollButton> createState() => _RerollButtonState();
}

class _RerollButtonState extends State<_RerollButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void didUpdateWidget(_RerollButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_spin.isAnimating) _spin.repeat();
    if (!widget.spinning && _spin.isAnimating) _spin.forward(from: _spin.value).then((_) => _spin.reset());
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: CurvedAnimation(parent: _spin, curve: Curves.easeInOutBack),
    child: _RoundButton(
      icon: LucideIcons.dices,
      label: 'Re-roll Spotlight',
      onTap: () {
        _spin.forward(from: 0);
        widget.onTap();
      },
    ),
  );
}

class _EdgeArrow extends StatelessWidget {
  const _EdgeArrow({required this.icon, required this.visible, required this.onTap});
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 200),
    opacity: visible ? 1 : 0,
    child: IgnorePointer(
      ignoring: !visible,
      // On a TV the pager dots change the spotlight; these hover arrows stay out of the way.
      child: ExcludeFocus(
        excluding: !visible || isTv,
        child: Focusable(
          onTap: onTap,
          semanticLabel: icon == LucideIcons.chevronLeft ? 'Previous' : 'Next',
          builder: (context, hover, _) => Container(
            width: 36,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: hover ? 0.45 : 0.2),
              borderRadius: BorderRadius.circular(Radii.radiusMd),
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

/// [child] fading out at the bottom; drawn without the fade when measuring ([DrawProbe.noBlur]).
Widget _fadeOut(Widget child) => DrawProbe.noBlur
    ? child
    : ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) =>
            const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Colors.white, Colors.transparent], stops: [0, 0.62, 1]).createShader(r),
        child: child,
      );
