import 'dart:async';
import 'dart:io' show Platform;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app_info.dart';
import '../../platform.dart';
import 'decoders.dart';
import '../../services/channels.dart';
import '../../services/display_match.dart';
import '../../services/gpu_memory.dart';
import '../../services/aether_player.dart';
import '../../services/avplay_player.dart';
import '../../services/live_players.dart';
import '../../services/mpv_tls.dart';
import '../../services/playback_prefs.dart';
import '../../services/probe.dart';
import '../../services/scrobbler.dart';
import '../../services/tv_sleep.dart';
import 'sleep_timer.dart';
import 'video_plane.dart';

/// Everything about one play of one file, apart from how it looks: mpv, direct play or
/// transcode, tracks, intro/credits markers, Up Next, sleep timer and Plex progress reports.
class PlayerSession extends ChangeNotifier {
  PlayerSession({
    required this.plex,
    required this.prefs,
    required this.local,
    required this.item,
    this.queue = const [],
    this.at,
    this.channel,
    required this.resume,
    this.choose = true,
    required this.onExit,
    required this.onPlay,
    required this.onPrefs,
    this.covered,
    this.server = '',
    this.scrobbler,
    SleepTimer? sleep,
  }) : sleep = sleep ?? SleepTimer.instance,
       quality = local ? prefs.localQuality : prefs.remoteQuality,
       subtitleSize = prefs.subtitleSize,
       subtitleRaise = prefs.subtitleRaise,
       subtitleColor = prefs.subtitleColor,
       subtitleBackground = prefs.subtitleBackground,
       aspect = prefs.aspect,
       deinterlace = prefs.deinterlace;

  final PlexClient plex;
  final bool local;
  final bool resume;

  /// No one has picked Resume or Play from Start yet, so the resume setting decides (and
  /// may ask). False for a Resume button, Up Next and Watch Together.
  final bool choose;
  final VoidCallback onExit;
  final void Function(PlexItem next) onPlay;
  final void Function(PlaybackPrefs prefs) onPrefs;

  /// Completes once the player page has finished coming in and hides the pages behind it.
  final Future<void> Function()? covered;

  /// The Plex server's machine id, so per-show track choices don't mix between servers.
  final String server;

  /// Trakt and AniList, told what plays (nothing goes out unless one is signed in).
  final Scrobbler? scrobbler;
  ScrobblePlay? _scrobble;
  PlaybackPrefs prefs;
  PlexItem item;

  /// A run of titles to play in order; next and previous come from here when it's set.
  final List<PlexItem> queue;

  /// Where this title is in [queue], when known (a title can be in a channel's line-up
  /// more than once).
  final int? at;

  /// The shuffle channel playing, if any; it says which titles are bumpers.
  final ChannelRun? channel;

  /// A bumper: a short clip between a channel's episodes. Plex, Trakt and AniList never
  /// hear about it, it has no Skip Intro or Up Next, and it always plays from the start.
  late final bool bumper = channel?.isBumperAt(at) ?? false;

  /// Where [next] and [previous] are in [queue].
  int? nextAt;
  int? previousAt;

  /// The next title is a bumper, so no Up Next card: the episode plays out into it.
  bool get nextIsBumper => channel?.isBumperAt(nextAt) ?? false;

  /// The TV's hardware decoder draws straight onto the picture's surface instead of mpv
  /// copying every frame out and rendering it again (see [PlaybackPrefs.videoOutput]). On
  /// the 2019 Shield the copy path got the app killed within seconds of starting a 4K file.
  /// Fixed for the session, since mpv's output is set up once. mpv draws no subtitles this
  /// way, so the player page draws text ones and Plex burns in picture-based ones.
  /// On a Samsung TV, Samsung's player always works this way: it draws on the TV's own
  /// video plane and the app draws the subtitles ([AvPlayPlayer]).
  late final bool direct = isTizen || isTvOS || prefs.directVideo(android: Platform.isAndroid, lowMemory: isLowMemoryTv);

  late final Player player = () {
    // Streams may only pull in more over the web, never local files.
    // A low-memory TV gets half the read-ahead: Android kills the app outright when memory runs low.
    final config = PlayerConfiguration(title: appName, bufferSize: (isLowMemoryTv ? 32 : 64) * 1024 * 1024, libass: !direct, protocolWhitelist: streamProtocols);
    // A Samsung TV and an Apple TV have no mpv: the system's own player stands in behind the
    // same API (Samsung's AVPlay, AetherEngine on tvOS).
    final p = Player(
      configuration: config,
      platformPlayer: isTizen ? AvPlayPlayer(configuration: config) : (isTvOS ? AetherPlayer(configuration: config) : null),
    );
    // Leaving the app lets it go first, if the page hasn't yet (see LivePlayers).
    LivePlayers.add(p, _releasePlayer);
    return p;
  }();

  Future<void>? _playerReleased;

  /// Match Frame Rate's switch for this title, which the first play waits for (paused, so
  /// the TV's blank moment while it changes mode doesn't eat the opening seconds).
  Future<bool>? _displayReady;

  /// The display was matched, or tried, for this title: once is enough.
  bool _displayTried = false;

  /// Lets go of mpv, once: the decoder lets go of the plane's surface before the player goes.
  Future<void> _releasePlayer() =>
      _playerReleased ??= LivePlayers.going(player, plane ? _closePlane().whenComplete(player.dispose) : player.dispose());
  /// The picture is on a surface of its own behind the app ([VideoPlane]), which reports
  /// itself through [_planeSurface]; there is no media_kit [video] controller then. This is
  /// how Plex's app and Plezy show 4K on the 2019 Shield, where a texture got Liquiflux killed.
  late final bool plane = prefs.planeVideo(android: Platform.isAndroid, lowMemory: isLowMemoryTv);

  late final VideoController? video = plane || isTizen || isTvOS
      ? null
      : VideoController(
          player,
          configuration: direct ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec') : VideoControllerConfiguration(hwdec: prefs.hwdec),
        );
  NativePlayer? get _native => player.platform is NativePlayer ? player.platform as NativePlayer : null;

  final _subs = <StreamSubscription<Object?>>[];

  /// The graphics memory this player took from the rest of the app (low-memory TVs).
  PlaybackHold? _gpu;
  Timer? _report;
  Timer? _probeVideo;
  bool _probeSought = false;
  bool _disposed = false;
  bool _finished = false;

  /// Marked watched on Plex, so the closing report says it played to the end.
  bool _watched = false;

  /// The final "stopped" report has gone (the window closed under us).
  bool _stopped = false;

  // How the file is reaching the player.
  int mediaIndex = 0;

  /// kbps, 0 = original.
  int quality;
  bool transcoding = false;
  bool _directFailed = false;
  String? _session;

  /// Where a transcode stream starts in the title; mpv's clock counts from here.
  Duration offset = Duration.zero;

  /// Where the last open asked to start, for reopening before anything has played.
  Duration _openedAt = Duration.zero;

  /// A seek that needs a new transcode, waiting for held keys to settle.
  Duration? _pendingSeek;
  Timer? _seekTimer;
  bool ready = false;
  String? error;

  /// The saved place, while the player waits for Resume or Start Over to be picked.
  Duration? resumeOffer;

  PlexStream? audio;

  /// Null is off.
  PlexStream? subtitle;

  double rate = 1;
  int audioDelayMs = 0;
  int subtitleDelayMs = 0;
  int subtitleSize;
  int subtitleRaise;
  String subtitleColor;
  String subtitleBackground;
  String aspect;
  bool deinterlace;

  /// The title's own colour, from its poster, and a second colour from it that stands
  /// clearly apart (used for accents beside the main one).
  Color? tint;
  Color? accent;

  PlexItem? previous;
  PlexItem? next;

  /// Intro / credits marker whose Skip button is showing.
  PlexMarker? skipPrompt;
  final _autoSkipped = <PlexMarker>{};

  /// A short note over the picture ("Skipped Intro").
  String? toast;
  Timer? _toastTimer;

  bool upNextVisible = false;
  bool upNextDismissed = false;
  int countdown = 0;
  Timer? _countdownTimer;

  /// Shared by every player, so a running timer carries on into the next episode.
  final SleepTimer sleep;
  Timer? _sleepCheck;

  /// The volume before the last minute's fade began; null while not fading.
  double? _fadeFrom;

  /// "End of This": the credits play out with no countdown to the next title.
  bool get sleepAtEnd => sleep.stopsAtEnd;

  /// The sleep timer's last minute is running out: the warning shows.
  bool get sleepWarning => sleep.warning;

  Duration get position => _pendingSeek ?? _streamPosition() + offset;

  /// The last position from mpv that made sense, held while it reports one that doesn't.
  Duration _goodPosition = Duration.zero;

  /// mpv's position in the stream, or the last sensible one while it reports nonsense (see
  /// [sanePosition]).
  Duration _streamPosition() {
    final mpv = player.state.position;
    if (!transcoding) return mpv;
    final p = sanePosition(mpv, length: duration - offset);
    if (p != null) _goodPosition = p;
    return p ?? _goodPosition;
  }

  /// Where a stream that hasn't started yet should pick up again.
  Duration get _resumeAt => _pendingSeek ?? (player.state.duration > Duration.zero ? position : _openedAt);

  /// The position, a few times a second: enough for clocks and the scrubber.
  late final Stream<Duration> ticks = _ticks.stream;
  final _ticks = StreamController<Duration>.broadcast();
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _tickTimer;

  void _throttleTick() {
    final since = DateTime.now().difference(_lastTick);
    const every = Duration(milliseconds: 250);
    if (since >= every) {
      _emitTick();
    } else {
      _tickTimer ??= Timer(every - since, _emitTick);
    }
  }

  void _emitTick() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _lastTick = DateTime.now();
    if (!_ticks.isClosed) _ticks.add(position);
  }

  /// The file's own length when playing it directly (most exact); Plex's figure while
  /// transcoding, since the stream only covers what's left.
  Duration get duration {
    final mpv = player.state.duration;
    if (!transcoding && mpv > Duration.zero) return mpv;
    final d = item.duration ?? 0;
    return d > 0 ? Duration(milliseconds: d) : mpv + offset;
  }

  PlexMedia? get media => mediaIndex < item.media.length ? item.media[mediaIndex] : null;
  PlexPart? get part => media?.parts.firstOrNull;
  List<PlexStream> get streams => part?.streams ?? const [];
  List<PlexStream> get audioStreams => streams.where((s) => s.isAudio).toList();
  List<PlexStream> get subtitleStreams => streams.where((s) => s.isSubtitle).toList();
  List<PlexMarker> get markers => item.markers;
  List<PlexChapter> get chapters => item.chapters;
  bool get isEpisode => item.type == 'episode';
  StreamQuality get streamQuality => qualityFor(quality);

  PlexChapter? chapterAt(Duration t) {
    final ms = t.inMilliseconds;
    return chapters.where((c) => ms >= c.startMs && ms < c.endMs).firstOrNull;
  }

  // ---------------------------------------------------------------- start / stop

  Future<void> start() async {
    sleep.addListener(_sleepChanged);
    if (TvSleep.supported) unawaited(TvSleep.check());
    _sleepCheck = Timer.periodic(const Duration(seconds: 1), (_) => _checkSleep());
    final probeSleep = int.tryParse(Probe.value('sleep') ?? '');
    if (probeSleep != null && !sleep.active) sleep.setFor(Duration(seconds: probeSleep));
    _subs
      ..add(player.stream.error.listen(_onError))
      ..add(player.stream.completed.listen(_onCompleted))
      ..add(
        player.stream.playing.listen((p) {
          _keepScreenOn(p);
          _sendTimeline(p ? 'playing' : 'paused');
          _scrobbleState(p);
          notifyListeners();
        }),
      )
      ..add(
        player.stream.position.listen((p) {
          _tick(p);
          _throttleTick();
        }),
      )
      ..add(player.stream.buffering.listen((_) => notifyListeners()))
      ..add(
        player.stream.duration.listen((d) {
          if (d > Duration.zero && !ready) {
            ready = true;
            _scrobbleState(player.state.playing);
            notifyListeners();
          }
        }),
      );
    _report = Timer.periodic(const Duration(seconds: 10), (_) => _sendTimeline(player.state.playing ? 'playing' : 'paused'));
    if (Probe.on) _probeVideo = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_logVideo()));

    // Anime gets its own audio language, unless this show already has a choice saved.
    final show = isEpisode && item.grandparentRatingKey != null && prefs.animeAudio.isNotEmpty && _remembered == null
        ? plex.metadata(item.grandparentRatingKey!).timeout(const Duration(seconds: 5)).then<PlexItem?>((v) => v, onError: (Object e) {
            debugPrint('player show: $e');
            return null;
          })
        : Future<PlexItem?>.value();
    // The list views don't carry markers, chapters or every stream, so read the item fresh.
    try {
      item = await plex.metadata(item.ratingKey, playback: true) ?? item;
    } catch (e) {
      debugPrint('player metadata: $e');
    }
    if (_disposed) return;
    _anime = prefs.animeAudio.isNotEmpty && isAnime(isEpisode ? await show : item, library: item.librarySectionTitle);
    if (_disposed) return;
    final picked = _pickTracks();
    audio = picked.audio;
    subtitle = picked.subtitle;
    // An old save could hold 0 from muting; never start a title silent.
    final volume = prefs.volume.clamp(0, prefs.volumeBoost ? 200 : 100).toDouble();
    // A title the probe starts by itself plays silent.
    await player.setVolume(Probe.playing ? 0 : (volume > 0 ? volume : 100));
    if (_disposed) return;
    // A low-memory TV needs the graphics memory the app's artwork holds for the video
    // decoder, including the artwork on the pages behind the player. Until 1.0.4 that was
    // only for a 4K file; a cloud Fire TV still grew by 350 MB playing a 1080p one.
    _gpu = GpuMemory.startPlayback(releaseArt: true);
    if (_gpu != null) {
      // For the log: what the decoder had to fit in.
      _subs.add(player.stream.videoParams.where((v) => (v.w ?? 0) > 0).take(1).listen((_) => debugPrint('graphics memory as the video starts: ${GpuMemory.status()}')));
    }
    await GpuMemory.forPlayback(_gpu, covered: covered?.call());
    if (_disposed) return;
    if (plane) await _setUpPlane();
    if (_disposed) return;
    await applyMpvPrefs();
    if (_disposed) return;
    _displayReady = _matchDisplay(stream: _videoStream?.frameRate);
    final start = startPoint(viewOffsetMs: item.viewOffset, durationMs: item.duration, resume: resume && !bumper, choose: choose && !bumper, mode: prefs.resumeMode);
    if (start.ask) {
      resumeOffer = start.from;
      notifyListeners();
    } else {
      await _open(start.from);
      if (_disposed) return;
    }
    unawaited(_findNeighbours());
    final poster = plex.imageUrl(item.posterPath, width: 200, height: 300);
    if (poster != null) {
      unawaited(
        ArtColor.paletteOf(poster, headers: plex.headers).then((p) {
          if (_disposed || p.isEmpty) return;
          tint = p.first;
          accent = ArtColor.accent(p, p.first);
          if (subtitleColor == 'art') unawaited(applySubtitleStyle());
          notifyListeners();
        }),
      );
    }
  }

  Future<void> _findNeighbours() async {
    final given = this.at;
    final at = given != null && given >= 0 && given < queue.length && queue[given].ratingKey == item.ratingKey ? given : queue.indexWhere((q) => q.ratingKey == item.ratingKey);
    if (at >= 0) {
      previousAt = at > 0 ? at - 1 : null;
      nextAt = at + 1 < queue.length ? at + 1 : null;
      previous = at > 0 ? queue[at - 1] : null;
      next = at + 1 < queue.length ? queue[at + 1] : null;
      if (!_disposed) notifyListeners();
      return;
    }
    final show = item.grandparentRatingKey;
    if (!isEpisode || show == null) return;
    try {
      final n = neighbours(await plex.episodes(show), item.ratingKey);
      previous = n.previous;
      next = n.next;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('episodes: $e');
    }
  }

  bool _screenOn = false;

  /// Samsung TVs: no screensaver while a video plays ("mandatory" in Samsung's checklist).
  /// It may come back while paused. Elsewhere the video widget or the TV sees to this.
  void _keepScreenOn(bool on) {
    if (!isTizen || on == _screenOn) return;
    _screenOn = on;
    unawaited(WakelockPlus.toggle(enable: on).catchError((Object e) => debugPrint('screensaver: $e')));
  }

  @override
  void dispose() {
    _keepScreenOn(false);
    _disposed = true;
    _report?.cancel();
    _probeVideo?.cancel();
    _toastTimer?.cancel();
    _countdownTimer?.cancel();
    _sleepCheck?.cancel();
    sleep.removeListener(_sleepChanged);
    _seekTimer?.cancel();
    // A choice made in the last moment before leaving still gets saved.
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      onPrefs(prefs);
    }
    _tickTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_ticks.close());
    unawaited(shutdown());
    unawaited(_releasePlayer());
    unawaited(GpuMemory.afterPlayback(_gpu));
    DisplayMatch.release();
    super.dispose();
  }

  /// Tells Plex we've stopped and ends any transcode. Also run before the window closes,
  /// since nothing unawaited survives that.
  Future<void> shutdown() async {
    final ms = _watched ? duration.inMilliseconds : position.inMilliseconds;
    final s = _session;
    _session = null;
    final report = !_stopped && ms > 0 && !bumper;
    _stopped = true;
    final scrobbled = _scrobbleStop(watched: _watched);
    await Future.wait([
      if (report) plex.timeline(item, state: 'stopped', timeMs: ms),
      if (s != null) plex.stopTranscode(s),
      // Trakt's stop (and AniList) gets a moment while the window closes; it carries on after.
      if (scrobbled != null) scrobbled.timeout(const Duration(seconds: 3), onTimeout: () {}),
    ]);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---------------------------------------------------------------- opening

  Future<void> _open(Duration from) async {
    if (_disposed) return;
    _seekTimer?.cancel();
    _pendingSeek = null;
    _openedAt = from;
    error = null;
    if (player.platform case final AetherPlayer ae) {
      unawaited(ae.setFit(aspect));
      final (title, subtitle) = nowPlayingText(item);
      unawaited(ae.nowPlaying(title: title, subtitle: subtitle, artwork: plex.imageUrl(item.grandparentThumb ?? item.thumb, width: 600, height: 900)));
    }
    final old = _session;
    // The server refuses the file itself (503) to a client whose transcode it's still
    // running, so the old one is ended before anything else opens (a moment at most).
    if (old != null) await plex.stopTranscode(old).timeout(const Duration(seconds: 3), onTimeout: () {});
    if (_disposed) return;
    _session = null;
    final waitFor = _displayReady;
    _displayReady = null;
    final url = quality == 0 && prefs.allowDirectPlay && !_directFailed && !needsServer ? plex.directPlayUrl(item, mediaIndex: mediaIndex) : null;
    if (!MpvTls.canCheck(plex.baseUrl)) {
      error = MpvTls.bareIp;
      notifyListeners();
      return;
    }
    // For the probe's log: which way the stream goes (never the address's query, which holds the token).
    if (Probe.on) debugPrint('probe stream: ${url != null ? 'direct' : 'transcode'} ${Uri.tryParse(plex.baseUrl)?.scheme} ${Uri.tryParse(plex.baseUrl)?.host}');
    if (url != null) {
      transcoding = false;
      offset = Duration.zero;
      notifyListeners();
      // The token's headers only go with a file on the server, not an online extra.
      await player.open(Media(url, httpHeaders: plex.headersFor(url), start: from), play: waitFor == null);
      if (_disposed) return;
      await _applyTracks();
    } else {
      transcoding = true;
      _session = PlexClient.newSessionId();
      offset = Duration(seconds: from.inSeconds);
      _goodPosition = Duration.zero;
      final q = streamQuality;
      notifyListeners();
      final start = plex.transcodeUrl(
        item,
        session: _session!,
        offsetSec: from.inSeconds,
        // At Original, a conversion for the sound alone keeps the picture as it is: the
        // bitrate allowed is far above any film's, so Plex copies the video across.
        maxBitrateKbps: q.isOriginal ? (_pictureAsIs ? 200000 : 20000) : q.kbps,
        resolution: q.resolution,
        mediaIndex: mediaIndex,
        directStream: prefs.allowDirectStream,
        remote: !local,
        audioStreamId: audio?.id,
        subtitleStreamId: subtitle?.id ?? 0,
        subtitleSize: subtitleSize,
      );
      // Asked first, as Plex's own apps do: start.m3u8 may just close the connection when the
      // server won't convert the title, and the decision says why. No answer doesn't stop it.
      final decision = await plex.transcodeDecision(start).then<TranscodeDecision?>((d) => d, onError: (Object e) {
        debugPrint('transcode decision: ${errorText(e)}');
        return null;
      });
      if (_disposed) return;
      if (decision != null) debugPrint('transcode decision: $decision');
      if (decision != null && decision.refused) {
        error = 'Your Plex server can’t convert this title. ${decision.reason}';
        notifyListeners();
        return;
      }
      await player.open(Media(start, httpHeaders: plex.headers), play: waitFor == null);
    }
    if (waitFor != null) {
      await waitFor;
      if (_disposed) return;
      await player.play();
    }
    if (rate != 1 && !_disposed) await player.setRate(rate);
    _matchDisplayFromMpv();
  }

  PlexStream? get _videoStream => streams.where((s) => s.isVideo).firstOrNull;

  /// Match Frame Rate (Settings > Video): asks the display for a mode that suits this
  /// title's frame rate, from Plex's [stream] rate before playing or mpv's once it has
  /// opened the file. Completes with whether the display switched.
  Future<bool> _matchDisplay({double? stream, double? mpv, String? label, Future<void> Function()? before}) {
    final mode = DisplayMatch.effective(prefs.displayMatch);
    final fps = contentFrameRate(stream: stream, mpv: mpv, label: label);
    if (mode == DisplayMatchMode.off || fps == null || _displayTried) return Future.value(false);
    _displayTried = true;
    final v = _videoStream;
    var (w, h) = (v?.width ?? media?.width, v?.height ?? media?.height);
    // A transcode at a set quality comes at that size.
    final box = !streamQuality.isOriginal ? RegExp(r'^(\d+)x(\d+)$').firstMatch(streamQuality.resolution ?? '') : null;
    if (box != null && w != null && h != null && w > 0 && h > 0) {
      final scale = [int.parse(box[1]!) / w, int.parse(box[2]!) / h, 1.0].reduce((a, b) => a < b ? a : b);
      (w, h) = ((w * scale).round(), (h * scale).round());
    }
    return DisplayMatch.match(mode: mode, fps: fps, width: w, height: h, before: before);
  }

  /// Plex didn't say the frame rate: once mpv has the picture, its rate decides, and the
  /// player pauses through the switch.
  void _matchDisplayFromMpv() {
    if (_displayTried || DisplayMatch.effective(prefs.displayMatch) == DisplayMatchMode.off) return;
    final n = _native;
    if (n == null) return;
    _subs.add(
      player.stream.videoParams.where((v) => (v.w ?? 0) > 0).take(1).listen((_) async {
        if (_disposed || _displayTried) return;
        double? fps;
        try {
          fps = double.tryParse(await n.getProperty('container-fps'));
        } catch (_) {}
        if (_disposed) return;
        var resume = false;
        final switched = await _matchDisplay(
          mpv: fps,
          label: media?.videoFrameRate,
          before: () async {
            resume = player.state.playing;
            if (resume) await player.pause();
          },
        );
        if (resume && !_disposed) await player.play();
        if (switched) debugPrint('display matched from mpv\'s ${fps?.toStringAsFixed(3)} fps');
      }),
    );
  }

  Future<void> _reopen() => _open(_resumeAt);

  /// Video codecs the TV's own decoder takes (Plex's names). Anything else would need
  /// mpv's software decoder, whose frames the direct path can't show.
  static const hardwareCodecs = {'h264', 'hevc', 'vp8', 'vp9', 'mpeg2video', 'mpeg4'};

  /// With [direct] output, what the player can't show itself goes through Plex: a
  /// picture-based subtitle (burned in) or a video codec the hardware decoder doesn't take.
  bool get needsServer => directNeedsServer(direct: direct, subtitle: subtitle, video: _video, audio: audio, samsung: isTizen) || decodersNeedServer(PlayerDecoders.current, audio: audio, video: _video);

  PlexStream? get _video => streams.where((s) => s.isVideo).firstOrNull;

  /// Only the sound has to go through Plex (this platform's player has no decoder for it, see
  /// [PlayerDecoders]): Plex converts the sound and sends the picture as it is (see [_open]).
  bool get soundNeedsServer => !PlayerDecoders.current.playsAudio(audio?.codec);

  /// The sound goes through Plex but nothing about the picture does.
  bool get _pictureAsIs => soundNeedsServer && PlayerDecoders.current.playsVideo(_video?.codec) && !directNeedsServer(direct: direct, subtitle: subtitle, video: _video, samsung: isTizen);

  /// Whether a track [decoders] can't decode sends the title through Plex. On a Mac, iPhone
  /// or iPad a film with Dolby TrueHD sound played silently ("Failed to initialize a decoder
  /// for codec 'truehd'"); everywhere else [PlayerDecoders.all] decodes everything.
  @visibleForTesting
  static bool decodersNeedServer(PlayerDecoders decoders, {PlexStream? audio, PlexStream? video}) => !decoders.playsAudio(audio?.codec) || !decoders.playsVideo(video?.codec);

  /// Audio Samsung TVs don't play (Plex's names): "The DTS Audio codec is not supported on
  /// 2025 TVs" (and 2026), and TrueHD isn't on Samsung's list. Plex converts the sound and
  /// sends the picture as it is.
  static const samsungUnplayableAudio = {'dca', 'dts', 'dca-ma', 'truehd', 'mlp'};

  /// AV1 and VC-1 aren't in [hardwareCodecs] (for Android), but Samsung's player takes AV1 on
  /// 2021 and later sets; VC-1 is gone from 2025 sets, so it still goes through Plex.
  static const samsungExtraCodecs = {'av1'};

  @visibleForTesting
  static bool directNeedsServer({required bool direct, PlexStream? subtitle, PlexStream? video, PlexStream? audio, bool samsung = false}) {
    if (!direct) return false;
    if (subtitle?.isImageSubtitle ?? false) return true;
    if (samsung && samsungUnplayableAudio.contains(audio?.codec?.toLowerCase())) return true;
    final codec = video?.codec?.toLowerCase();
    return codec != null && !hardwareCodecs.contains(codec) && !(samsung && samsungExtraCodecs.contains(codec));
  }

  /// Answers the resume question: carry on from the saved place, or start again.
  Future<void> chooseStart({required bool resume}) async {
    final at = resumeOffer;
    if (at == null) return;
    resumeOffer = null;
    notifyListeners();
    if (_gpu?.art ?? false) {
      // The prompt and its artwork fade out first, so a 4K decoder doesn't open beside them.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_disposed) return;
      await GpuMemory.forPlayback(_gpu);
      if (_disposed) return;
    }
    await _open(resume ? at : Duration.zero);
  }

  /// mpv reports recoverable problems (a hardware decoder it skipped, a bad packet) on the
  /// same stream as fatal ones, so only act if nothing has started playing.
  void _onError(String e) {
    debugPrint('player: $e');
    final wasTranscoding = transcoding;
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (_disposed || player.state.duration > Duration.zero || transcoding != wasTranscoding) return;
      if (!transcoding) {
        _directFailed = true;
        unawaited(_open(_resumeAt));
      } else {
        error = 'Playback failed. ${errorText(e)}';
        notifyListeners();
      }
    });
  }

  void _onCompleted(bool done) {
    if (!done || _finished || !ready) return;
    _finished = true;
    final n = next;
    if (bumper) {
      // A bumper isn't a title: nothing is marked, and the sleep timer doesn't count it.
      n != null ? onPlay(n) : onExit();
      return;
    }
    _watched = true;
    unawaited(plex.markWatched(item));
    unawaited(_scrobbleStop(watched: true));
    final stop = sleep.finishedTitle();
    // A channel keeps going, like TV does.
    if (!stop && n != null && (channel != null || (prefs.autoPlayNext && !upNextDismissed))) {
      onPlay(n);
    } else {
      onExit();
      if (stop) _sleepTv();
    }
  }

  void _sendTimeline(String state) {
    if (bumper) return;
    final ms = position.inMilliseconds;
    if (ms > 0 && !_finished && !_stopped) unawaited(plex.timeline(item, state: state, timeMs: ms));
  }

  /// How far in, in percent, for Trakt.
  double get _percent {
    final total = duration.inMilliseconds;
    return total > 0 ? (position.inMilliseconds * 100 / total).clamp(0, 100).toDouble() : 0;
  }

  /// Playing or paused, once the title is open (a probe run with noscrobble sends nothing).
  void _scrobbleState(bool playing) {
    if (!ready || _finished || _stopped || _disposed || bumper || Probe.has('noscrobble')) return;
    final s = _scrobble ??= scrobbler?.play(plex, item, server: server);
    playing ? s?.playing(_percent) : s?.paused(_percent);
  }

  /// The play is over; [watched] counts it as finished.
  Future<void>? _scrobbleStop({bool watched = false}) {
    if (bumper || Probe.has('noscrobble')) return null;
    final s = _scrobble ?? (watched ? _scrobble = scrobbler?.play(plex, item, server: server) : null);
    return s?.stopped(_percent, watched: watched);
  }

  // ---------------------------------------------------------------- transport

  /// An Open Watch Party room this player is in: the viewer's play, pause, jumps and speed
  /// go to the room, and the room moves the player (through the Direct calls below).
  RoomControl? room;

  void togglePlay() {
    final r = room;
    if (r == null) return unawaited(player.playOrPause());
    player.state.playing ? r.pause() : r.play();
  }

  Future<void> seekTo(Duration t) async {
    final r = room;
    if (r != null) return r.seek(t < Duration.zero ? Duration.zero : t);
    return seekDirect(t);
  }

  /// Seeks this player only, whatever room it's in.
  Future<void> seekDirect(Duration t) async {
    final total = duration;
    var to = t < Duration.zero ? Duration.zero : t;
    if (total > Duration.zero && to > total) to = total - const Duration(seconds: 1);
    if (transcoding && !seekStaysInStream(to: to, offset: offset, playing: _streamPosition(), buffered: player.state.buffer)) {
      // Not safely inside this transcode: restart it there, once held keys stop repeating.
      _pendingSeek = to;
      _seekTimer?.cancel();
      _seekTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_open(to)));
      _emitTick();
      notifyListeners();
      return;
    }
    if (_pendingSeek != null) {
      _seekTimer?.cancel();
      _pendingSeek = null;
    }
    await player.seek(to - offset);
  }

  /// Whether a seek to [to] can be made inside the running transcode, which starts at
  /// [offset] in the title, is playing at [playing] and has been read up to [buffered] (both
  /// on the stream's own clock).
  ///
  /// Asked for a part of the stream the player doesn't hold, Plex restarts its transcoder
  /// there, but counts from the title's start instead of from [offset]. A title resumed at
  /// 9:40 and skipped ahead to 11:06 showed 1:26 of the film with the clock stuck, and a
  /// skip back of 10 s did the same once the player had let go of that part (seen on a Fire
  /// TV, reproduced on a Shield). So in a transcode that started partway in, only a skip
  /// ahead into what is already read stays in the stream; any other seek starts a new
  /// transcode at [to]. A transcode from the title's start has nothing to miscount, and
  /// every seek stays in it.
  @visibleForTesting
  static bool seekStaysInStream({required Duration to, required Duration offset, required Duration playing, required Duration buffered}) {
    if (offset == Duration.zero) return true;
    final at = to - offset;
    return at >= playing && at <= buffered;
  }

  void seekBy(int seconds) => unawaited(seekTo(position + Duration(seconds: seconds)));

  /// The volume control listens to mpv itself, so this doesn't rebuild the page. Silence
  /// isn't saved: the next title shouldn't start muted.
  Future<void> setVolume(double v) async {
    final max = prefs.volumeBoost ? 200.0 : 100.0;
    final next = v.clamp(0, max).toDouble();
    await player.setVolume(next);
    if (next > 0) _savePrefs(prefs.copyWith(volume: next));
  }

  double _beforeMute = 100;
  void toggleMute() {
    final v = player.state.volume;
    if (v > 0) {
      _beforeMute = v;
      unawaited(player.setVolume(0));
    } else {
      unawaited(setVolume(_beforeMute > 0 ? _beforeMute : 100));
    }
  }

  Future<void> setRate(double r) async {
    final room = this.room;
    if (room != null) return room.setRate(r);
    return setRateDirect(r);
  }

  /// Sets this player's speed only.
  /// Samsung's player can turn a speed down; then the speed stays as it was, so the badge
  /// and the Speed chips show what is really playing.
  Future<void> setRateDirect(double r) async {
    rate = r;
    await player.setRate(r);
    if (isTizen && player.state.rate != r) {
      rate = player.state.rate;
      flash('This TV can’t play at ${r == r.roundToDouble() ? r.toInt() : r}× speed');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- tracks

  List<PlexStream> _inFile(List<PlexStream> l) => l.where((s) => s.index != null).toList()..sort((a, b) => a.index!.compareTo(b.index!));

  /// Points mpv at the chosen Plex streams. mpv numbers each kind of track 1, 2, 3… in file
  /// order, which is the same order as Plex's stream index; sidecar files are added by URL.
  Future<void> _applyTracks() async {
    if (transcoding) return;
    if (player.state.tracks.video.length <= 2 && player.state.tracks.audio.length <= 2) {
      try {
        await player.stream.tracks.firstWhere((t) => t.video.length > 2 || t.audio.length > 2).timeout(const Duration(seconds: 15));
      } catch (_) {
        return;
      }
    }
    final a = audio;
    if (a != null) {
      final k = _inFile(audioStreams).indexWhere((s) => s.id == a.id);
      if (k >= 0) await player.setAudioTrack(AudioTrack('${k + 1}', null, null));
    }
    await _applySubtitle();
  }

  Future<void> _applySubtitle() async {
    final s = subtitle;
    if (s == null) {
      if (subtitleStreams.isNotEmpty) await player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    if (s.isExternal) {
      final tag = 'plex-${s.id}';
      final loaded = player.state.tracks.subtitle.where((t) => t.title == tag).firstOrNull;
      if (loaded != null) return player.setSubtitleTrack(SubtitleTrack(loaded.id, null, null));
      return player.setSubtitleTrack(SubtitleTrack.uri(plex.fileUrl(s.key!), title: tag, language: s.languageCode));
    }
    final k = _inFile(subtitleStreams).indexWhere((x) => x.id == s.id);
    if (k >= 0) await player.setSubtitleTrack(SubtitleTrack('${k + 1}', null, null));
  }

  bool _anime = false;

  /// Where this show's track choice is saved; null outside a show.
  String? get _showKey => isEpisode && item.grandparentRatingKey != null ? PlaybackPrefs.showKey(server, item.grandparentRatingKey!) : null;
  TrackChoice? get _remembered => prefs.showTracks[_showKey];

  /// What to start with: this show's saved choice, else the anime or usual audio language.
  ({PlexStream? audio, PlexStream? subtitle}) _pickTracks() => pickTracks(
    streams,
    audioLanguage: _anime ? prefs.animeAudio : prefs.audioLanguage,
    subtitleLanguage: prefs.subtitleLanguage,
    mode: prefs.subtitleMode,
    remembered: _remembered,
  );

  /// Remember the choice for the rest of the show, and on the server for this file, as
  /// Plex's own apps do.
  void _remember({int? audioId, int? subtitleId}) {
    final key = _showKey;
    if (key != null) {
      final choice = TrackChoice.of(audio, subtitle);
      if (_remembered != choice) _savePrefs(prefs.rememberShow(key, choice));
    }
    final p = part;
    if (p == null) return;
    unawaited(plex.selectStreams(p.id, audioStreamId: audioId, subtitleStreamId: subtitleId).catchError((Object e) => debugPrint('select streams: $e')));
  }

  Future<void> selectAudio(PlexStream s) async {
    if (s.id == audio?.id) return;
    audio = s;
    notifyListeners();
    _remember(audioId: s.id);
    // On a Samsung TV a DTS or TrueHD track goes through Plex ([needsServer]).
    if (transcoding || needsServer) return _reopen();
    final k = _inFile(audioStreams).indexWhere((x) => x.id == s.id);
    if (k >= 0) await player.setAudioTrack(AudioTrack('${k + 1}', null, null));
  }

  Future<void> selectSubtitle(PlexStream? s) async {
    if (s?.id == subtitle?.id) return;
    subtitle = s;
    notifyListeners();
    _remember(subtitleId: s?.id ?? 0);
    // A transcode burns subtitles in, and direct output hands picture-based ones to Plex.
    if (transcoding || needsServer) return _reopen();
    await _applySubtitle();
  }

  // ---------------------------------------------------------------- online subtitles

  /// Plex can look for subtitles online (OpenSubtitles) for library titles, not extras.
  bool get canSearchOnline => item.type == 'movie' || item.type == 'episode';

  /// Two-letter code to search in: the subtitle language from Settings, else English.
  late String onlineLanguage = twoLetterLanguage(prefs.subtitleLanguage) ?? 'en';
  List<OnlineSubtitle>? onlineResults;
  bool onlineSearching = false;
  String? onlineNote;

  /// The result being fetched onto the server.
  OnlineSubtitle? onlineFetching;

  /// Languages worth offering: Settings' choice, English, then the title's own audio.
  List<String> get onlineLanguages => {
    ?twoLetterLanguage(prefs.subtitleLanguage),
    'en',
    for (final a in audioStreams) ?twoLetterLanguage(a.languageCode),
  }.take(6).toList();

  Future<void> searchOnline([String? language]) async {
    if (!canSearchOnline || onlineSearching) return;
    if (language != null) onlineLanguage = language;
    onlineSearching = true;
    onlineNote = null;
    onlineResults = null;
    notifyListeners();
    final key = item.ratingKey;
    try {
      final found = await plex.searchSubtitles(key, language: onlineLanguage);
      if (_disposed || item.ratingKey != key) return;
      onlineResults = found;
      if (found.isEmpty) onlineNote = 'Nothing found in that language.';
    } catch (e) {
      if (_disposed) return;
      onlineNote = 'Couldn’t search: ${errorText(e)}';
    } finally {
      onlineSearching = false;
      notifyListeners();
    }
  }

  /// Has Plex fetch [sub] onto the server, waits for it to show up as a track, and turns
  /// it on. Plex answers before the file has arrived, so this checks back for a while.
  Future<void> fetchOnline(OnlineSubtitle sub) async {
    if (onlineFetching != null) return;
    onlineFetching = sub;
    onlineNote = null;
    notifyListeners();
    final key = item.ratingKey;
    final before = {for (final t in subtitleStreams) t.id};
    try {
      await plex.downloadSubtitle(key, sub);
      PlexStream? added;
      for (var i = 0; i < 12 && added == null; i++) {
        await Future<void>.delayed(Duration(milliseconds: i == 0 ? 800 : 1500));
        if (_disposed || item.ratingKey != key) return;
        final fresh = await plex.metadata(key, playback: true);
        if (_disposed || item.ratingKey != key || fresh == null) continue;
        final media = mediaIndex < fresh.media.length ? fresh.media[mediaIndex] : null;
        added = media?.parts.firstOrNull?.streams.where((t) => t.isSubtitle && !before.contains(t.id)).lastOrNull;
        if (added != null) item = fresh;
      }
      if (added == null) {
        onlineNote = 'Plex is still fetching it. It will show under Track in a moment.';
      } else {
        onlineResults = onlineResults?.where((r) => r.key != sub.key).toList();
        onlineFetching = null;
        await selectSubtitle(added);
        flash('Subtitles: ${added.label}');
      }
    } catch (e) {
      if (!_disposed) onlineNote = 'Couldn’t get it: ${errorText(e)}';
    } finally {
      onlineFetching = null;
      notifyListeners();
    }
  }

  /// Files Plex knows nothing about (some extras) list mpv's own tracks instead.
  List<AudioTrack> get mpvAudio => player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
  List<SubtitleTrack> get mpvSubtitles => player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();

  void cycleSubtitle() {
    final list = [null, ...subtitleStreams];
    if (list.length < 2) return;
    final i = list.indexWhere((s) => s?.id == subtitle?.id);
    final n = list[(i + 1) % list.length];
    unawaited(selectSubtitle(n));
    flash(n == null ? 'Subtitles Off' : 'Subtitles: ${n.label}');
  }

  void cycleAudio() {
    final list = audioStreams;
    if (list.length < 2) return;
    final i = list.indexWhere((s) => s.id == audio?.id);
    final n = list[(i + 1) % list.length];
    unawaited(selectAudio(n));
    flash('Audio: ${n.label}');
  }

  // ---------------------------------------------------------------- quality / version

  Future<void> setQuality(int kbps) async {
    if (kbps == quality && !(kbps == 0 && _directFailed)) return;
    quality = kbps;
    await _reopen();
  }

  Future<void> setVersion(int index) async {
    if (index == mediaIndex || index >= item.media.length) return;
    final at = _resumeAt;
    mediaIndex = index;
    _directFailed = false;
    final picked = _pickTracks();
    audio = picked.audio;
    subtitle = picked.subtitle;
    await _open(at);
  }

  // ---------------------------------------------------------------- video plane

  /// No video until the plane's surface exists: without one mpv decodes the picture in
  /// software into memory (which media_kit's texture path does for the first frames), and
  /// at 4K that is hundreds of MB on top of the hardware decoder's 500.
  Future<void> _setUpPlane() async {
    await _set('vo', 'null');
    await _set('vid', 'no');
    await _set('hwdec', 'mediacodec');
    // media_kit's Android controller's list: mpv's own leaves out MPEG-2 and MPEG-4.
    await _set('hwdec-codecs', 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1');
    await _set('force-window', 'yes');
    _subs.add(player.stream.videoParams.listen((_) => _planeAspect()));
    await VideoPlane.show(_planeSurface);
  }

  /// The plane takes the picture's shape, since the decoder fills whatever surface it gets.
  /// Fill shows as Fit there.
  void _planeAspect() {
    if (_disposed) return;
    if (player.platform case final AvPlayPlayer av) unawaited(av.setFit(aspect));
    if (player.platform case final AetherPlayer ae) unawaited(ae.setFit(aspect));
    if (!plane) return;
    final v = player.state.videoParams;
    final turned = v.rotate == 90 || v.rotate == 270;
    final w = (turned ? v.dh : v.dw) ?? 0;
    final h = (turned ? v.dw : v.dh) ?? 0;
    unawaited(VideoPlane.aspect(aspect == 'stretch' || w <= 0 || h <= 0 ? 0 : w / h));
  }

  void _planeSurface(int wid, int width, int height) => unawaited(attachSurface(wid, width, height));

  int _wid = 0;
  Future<void> _surfaceQueue = Future.value();

  /// The plane's surface appeared ([wid] is its JNI reference), changed size, or went (0).
  /// The order of mpv properties follows media_kit's own Android controller.
  @visibleForTesting
  Future<void> attachSurface(int wid, int width, int height) => _surfaceQueue = _surfaceQueue.then((_) async {
    if (_disposed || !plane) return;
    if (wid == _wid) {
      if (wid != 0) await _set('android-surface-size', '${width}x$height');
      return;
    }
    _wid = wid;
    await _set('vo', 'null');
    if (wid == 0) {
      await _set('vid', 'no');
      await _set('wid', '0');
      return;
    }
    await _set('android-surface-size', '${width}x$height');
    await _set('wid', '$wid');
    await _set('vo', 'mediacodec_embed');
    await _set('vid', 'auto');
    // The decoder restarts on the new surface; carry on from where playback is.
    if (ready && !_disposed) await player.seek(player.state.position);
  });

  /// Detaches mpv from the plane, then removes it.
  Future<void> _closePlane() async {
    await _surfaceQueue;
    if (_wid != 0) {
      _wid = 0;
      await _set('vo', 'null');
      await _set('vid', 'no');
      await _set('wid', '0');
    }
    await VideoPlane.hide(_planeSurface);
  }

  // ---------------------------------------------------------------- mpv options

  Future<void> _set(String name, String value) async {
    try {
      await _native?.setProperty(name, value);
    } catch (e) {
      debugPrint('mpv $name: $e');
    }
  }

  /// Applies the saved audio, video and advanced options to mpv.
  Future<void> applyMpvPrefs() async {
    final p = prefs;
    // https streams carry the token: check the server's certificate (see MpvTls).
    final n = _native;
    if (n != null) await MpvTls.apply(n);
    // Direct output only works with the hardware decoder it was set up with.
    if (!direct) await _set('hwdec', p.hwdec);
    // mpv keeps as much already-played video as it reads ahead; at 4K bitrates that is a lot
    // of memory a low-memory TV doesn't have, for little more than instant short skips back.
    if (isLowMemoryTv) await _set('demuxer-max-back-bytes', '${8 * 1024 * 1024}');
    await _set('audio-spdif', p.passthrough ? 'ac3,eac3,dts,dts-hd,truehd' : '');
    await _set('audio-exclusive', p.passthrough ? 'yes' : 'no');
    await _set('audio-channels', switch (p.audioChannels) {
      'stereo' => 'stereo',
      '5.1' => '5.1,stereo',
      '7.1' => '7.1,5.1,stereo',
      _ => 'auto-safe',
    });
    await _set('af', p.nightMode ? 'lavfi=[dynaudnorm=f=200:g=11:p=0.9]' : '');
    await _set('volume-max', p.volumeBoost ? '200' : '100');
    await _set('deinterlace', deinterlace ? 'yes' : 'no');
    if (p.highQualityScaling) {
      await _set('scale', 'ewa_lanczossharp');
      await _set('cscale', 'ewa_lanczossharp');
      await _set('dscale', 'mitchell');
      await _set('correct-downscaling', 'yes');
      await _set('sigmoid-upscaling', 'yes');
    } else {
      await _set('scale', 'bilinear');
      await _set('cscale', 'bilinear');
      await _set('dscale', 'bilinear');
    }
    await _set('deband', p.deband ? 'yes' : 'no');
    await _setAudioDevice(p.audioDevice);
    await applySubtitleStyle();
    // Only Home's trailer player may hand a link to yt-dlp; this one plays Plex files.
    await _set('ytdl', 'no');
    for (final (name, value) in p.mpvOptionPairs) {
      if (mpvOptionAllowed(name) && !(direct && name == 'hwdec')) await _set(name, value);
    }
  }

  Future<void> _setAudioDevice(String name) async {
    final d = player.state.audioDevices.where((x) => x.name == name).firstOrNull;
    if (d != null) await player.setAudioDevice(d);
  }

  List<AudioDevice> get audioDevices => player.state.audioDevices;
  String get audioDevice => player.state.audioDevice.name;

  Future<void> setAudioDevice(AudioDevice d) async {
    await player.setAudioDevice(d);
    _savePrefs(prefs.copyWith(audioDevice: d.name));
    notifyListeners();
  }

  static const subtitleColors = {'white': Color(0xFFFFFFFF), 'yellow': Color(0xFFFFE14D), 'cyan': Color(0xFF7FE8FF), 'green': Color(0xFF8CF58C), 'pink': Color(0xFFFF9AD5)};

  Color get subtitleSwatch => subtitleColor == 'art' ? (tint ?? subtitleColors['white']!) : (subtitleColors[subtitleColor] ?? subtitleColors['white']!);

  static String _hex(Color c, [double alpha = 1]) {
    String h(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${h(alpha)}${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
  }

  /// Size, height, colour and background of text subtitles (libass draws them in mpv).
  Future<void> applySubtitleStyle() async {
    await _set('sub-scale', (subtitleSize / 100).toStringAsFixed(2));
    await _set('sub-pos', '${100 - subtitleRaise - (_controlsShown ? 12 : 0)}');
    await _set('sub-color', _hex(subtitleSwatch));
    await _set('sub-ass-override', prefs.restyleSubtitles ? 'force' : 'yes');
    switch (subtitleBackground) {
      case 'box':
        await _set('sub-border-style', 'background-box');
        await _set('sub-back-color', '#B0000000');
        await _set('sub-border-size', '0');
        await _set('sub-shadow-offset', '0');
      case 'shadow':
        await _set('sub-border-style', 'outline-and-shadow');
        await _set('sub-border-size', '1.2');
        await _set('sub-border-color', '#FF000000');
        await _set('sub-shadow-offset', '2.5');
        await _set('sub-shadow-color', '#C0000000');
        await _set('sub-back-color', '#C0000000');
      default:
        await _set('sub-border-style', 'outline-and-shadow');
        await _set('sub-border-size', '3');
        await _set('sub-border-color', '#FF000000');
        await _set('sub-shadow-offset', '0');
        await _set('sub-back-color', '#00000000');
    }
  }

  bool _controlsShown = false;
  bool get controlsShown => _controlsShown;

  /// Lifts subtitles above the control bar while it's showing.
  void setControlsShown(bool shown) {
    if (shown == _controlsShown) return;
    _controlsShown = shown;
    unawaited(_set('sub-pos', '${100 - subtitleRaise - (shown ? 12 : 0)}'));
    // With direct output the player page draws the subtitles, so it needs to move them.
    if (direct) notifyListeners();
  }

  void setSubtitleLook({int? size, int? raise, String? color, String? background}) {
    subtitleSize = size ?? subtitleSize;
    subtitleRaise = raise ?? subtitleRaise;
    subtitleColor = color ?? subtitleColor;
    subtitleBackground = background ?? subtitleBackground;
    unawaited(applySubtitleStyle());
    // What you set while watching becomes the default, as in Plex's players.
    _savePrefs(prefs.copyWith(subtitleSize: subtitleSize, subtitleRaise: subtitleRaise, subtitleColor: subtitleColor, subtitleBackground: subtitleBackground));
    notifyListeners();
  }

  void setAudioDelay(int ms) {
    audioDelayMs = ms;
    unawaited(_set('audio-delay', (ms / 1000).toStringAsFixed(3)));
    notifyListeners();
  }

  void setSubtitleDelay(int ms) {
    subtitleDelayMs = ms;
    unawaited(_set('sub-delay', (ms / 1000).toStringAsFixed(3)));
    notifyListeners();
  }

  void setAspect(String a) {
    aspect = a;
    _planeAspect();
    notifyListeners();
  }

  void setDeinterlace(bool on) {
    deinterlace = on;
    unawaited(_set('deinterlace', on ? 'yes' : 'no'));
    notifyListeners();
  }

  void setNightMode(bool on) {
    _savePrefs(prefs.copyWith(nightMode: on));
    unawaited(_set('af', on ? 'lavfi=[dynaudnorm=f=200:g=11:p=0.9]' : ''));
    notifyListeners();
  }

  void setVolumeBoost(bool on) {
    _savePrefs(prefs.copyWith(volumeBoost: on));
    unawaited(_set('volume-max', on ? '200' : '100'));
    if (!on && player.state.volume > 100) unawaited(setVolume(100));
    notifyListeners();
  }

  Timer? _saveTimer;
  void _savePrefs(PlaybackPrefs p) {
    prefs = p;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => onPrefs(prefs));
  }

  // ---------------------------------------------------------------- markers / Up Next

  bool _inUpNextZone = false;

  void _tick(Duration _) {
    if (!ready || bumper) return;
    // Up Next only offers a real title; before a bumper the episode just plays out into it.
    final next = nextIsBumper ? null : this.next;
    final ms = position.inMilliseconds;
    final total = duration.inMilliseconds;
    PlexMarker? prompt;
    var upNextZone = false;
    for (final m in markers) {
      if (!m.contains(ms)) continue;
      final endsTitle = m.type == 'credits' && (m.isFinal || m.endMs >= total - 2000);
      if (endsTitle && next != null) {
        upNextZone = true;
        break;
      }
      final mode = switch (m.type) {
        'intro' => prefs.skipIntro,
        'credits' => prefs.skipCredits,
        _ => SkipMode.off,
      };
      if (mode == SkipMode.auto && !_autoSkipped.contains(m)) {
        _autoSkipped.add(m);
        unawaited(seekTo(Duration(milliseconds: m.endMs)));
        flash(m.type == 'intro' ? 'Skipped Intro' : 'Skipped Credits');
      } else if (mode == SkipMode.button) {
        prompt = m;
      }
      break;
    }
    // Without credits markers, offer the next episode near the end.
    if (next != null && !markers.any((m) => m.type == 'credits') && total > 0 && total - ms <= 20000) upNextZone = true;

    if (upNextZone != _inUpNextZone) {
      _inUpNextZone = upNextZone;
      upNextZone ? _showUpNext() : _hideUpNext();
    }
    if (prompt != skipPrompt) {
      skipPrompt = prompt;
      notifyListeners();
    }
  }

  void skipMarker() {
    final m = skipPrompt;
    if (m == null) return;
    skipPrompt = null;
    unawaited(seekTo(Duration(milliseconds: m.endMs)));
    notifyListeners();
  }

  void _showUpNext() {
    if (upNextVisible || upNextDismissed || next == null || bumper || nextIsBumper) return;
    upNextVisible = true;
    countdown = prefs.countdown;
    _startCountdown();
    notifyListeners();
  }

  /// Counts down to the next title, unless the sleep timer stops at the end of this one.
  void _startCountdown() {
    _countdownTimer?.cancel();
    // In a room only its host moves everyone on; the others follow.
    if (!prefs.autoPlayNext || sleepAtEnd || (room != null && !room!.leads)) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!player.state.playing) return;
      countdown--;
      if (countdown <= 0) {
        playNext();
      } else {
        notifyListeners();
      }
    });
  }

  void _hideUpNext() {
    if (!upNextVisible) return;
    upNextVisible = false;
    _countdownTimer?.cancel();
    notifyListeners();
  }

  /// "Watch Credits": stay on this episode.
  void dismissUpNext() {
    upNextDismissed = true;
    _hideUpNext();
  }

  void playNext() => _jump(next, watched: true);
  void playPrevious() => _jump(previous);

  void _jump(PlexItem? to, {bool watched = false}) {
    if (to == null || _finished) return;
    _countdownTimer?.cancel();
    _finished = true;
    if (watched && !bumper) {
      // Going on to the next title counts as finishing this one. Pressed on the last one
      // the timer allowed, someone's awake: it just ends the timer.
      sleep.finishedTitle();
      _watched = true;
      unawaited(plex.markWatched(item));
      unawaited(_scrobbleStop(watched: true));
    }
    onPlay(to);
  }

  // ---------------------------------------------------------------- sleep timer / notes

  /// Off with neither; [minutes] for a clock, [titles] to stop after that many titles end
  /// (1 is "End of This").
  void setSleep({int? minutes, int? titles}) {
    _restoreVolume();
    if (minutes != null) {
      sleep.setMinutes(minutes);
      flash('Stopping in $minutes min');
    } else if (titles != null) {
      sleep.setTitles(titles);
      flash(titles == 1 ? 'Stopping at the end' : 'Stopping after $titles episodes');
    } else {
      sleep.cancel();
    }
  }

  /// Any button in the warning's last minute: the timer is off and the volume comes back.
  void keepWatching() {
    if (Probe.on) debugPrint('probe sleep: kept watching');
    sleep.cancel();
    _restoreVolume();
    flash('Sleep timer off');
  }

  void _sleepChanged() {
    // "End of This" picked or dropped while Up Next is counting.
    if (sleepAtEnd) {
      _countdownTimer?.cancel();
    } else if (upNextVisible && _countdownTimer?.isActive != true) {
      _startCountdown();
    }
    if (sleep.deadline == null) _restoreVolume();
    if (!_disposed) notifyListeners();
  }

  /// Once a second: in the last minute fade the volume and keep the warning's clock going;
  /// at the deadline stop and leave the player, so the TV can go to sleep.
  void _checkSleep() {
    final left = sleep.left;
    if (left == null || _disposed || _finished) return;
    if (Probe.on) debugPrint('probe sleep left=${left.inSeconds}s volume=${player.state.volume.toStringAsFixed(0)} playing=${player.state.playing}');
    if (left > SleepTimer.warnFor) return;
    _fadeFrom ??= player.state.volume;
    if (left == Duration.zero) {
      if (Probe.on) debugPrint('probe sleep: time up, leaving the player');
      sleep.cancel();
      _fadeFrom = null;
      unawaited(player.pause());
      onExit();
      _sleepTv();
      return;
    }
    final share = left.inMilliseconds / SleepTimer.warnFor.inMilliseconds;
    // Not through setVolume: the saved volume stays what it was before the fade.
    unawaited(player.setVolume(_fadeFrom! * share));
    notifyListeners();
  }

  /// The timer is done and the player has closed: on an Android TV allowed to, the TV goes to
  /// sleep, a moment later so Plex hears we stopped first. Otherwise the TV's own screen
  /// saver and sleep setting take over, now that nothing keeps the screen on.
  void _sleepTv() {
    if (!TvSleep.supported) return;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1500), () async {
        final ok = await TvSleep.now();
        debugPrint('sleep timer: ${ok ? 'TV going to sleep' : 'not allowed to sleep the TV'}');
      }),
    );
  }

  void _restoreVolume() {
    final v = _fadeFrom;
    _fadeFrom = null;
    if (v != null && !_disposed) unawaited(player.setVolume(v));
  }

  void flash(String text) {
    toast = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------- stats

  /// For the probe's log: how smoothly mpv is getting frames on screen.
  Future<void> _logVideo() async {
    final n = _native;
    if (n == null || _disposed) return;
    final at = int.tryParse(Probe.value('at') ?? '');
    if (at != null && !_probeSought && ready && Probe.playing) {
      _probeSought = true;
      debugPrint('probe: seeking to ${at}s');
      await seekDirect(Duration(seconds: at));
    }
    Future<String> g(String p) async {
      try {
        return await n.getProperty(p);
      } catch (_) {
        return '?';
      }
    }

    final r = await Future.wait([
      g('frame-drop-count'), g('decoder-frame-drop-count'), g('mistimed-frame-count'), g('vo-delayed-frame-count'), //
      g('container-fps'), g('estimated-vf-fps'), g('display-fps'), g('video-sync'), g('hwdec-current'), g('video-params/w'), g('video-params/h'),
      g('avsync'), g('time-pos'),
    ]);
    debugPrint(
      'probe video: dropped ${r[0]} (decoder ${r[1]}), mistimed ${r[2]}, delayed ${r[3]}, fps ${r[4]} file / ${r[5]} shown, display ${r[6]}, '
      'sync ${r[7]}, hwdec ${r[8]}, ${r[9]}x${r[10]}, avsync ${r[11]}, at ${r[12]}',
    );
  }

  /// What mpv is actually doing, for the info overlay.
  Future<List<(String, String)>> stats() async {
    final n = _native;
    if (n == null) return playerStats();
    Future<String> g(String p) async {
      try {
        return await n.getProperty(p);
      } catch (_) {
        return '';
      }
    }

    final r = await Future.wait([
      g('video-codec'), g('video-params/w'), g('video-params/h'), g('container-fps'), g('estimated-vf-fps'), g('video-params/pixelformat'), g('video-params/gamma'), //
      g('hwdec-current'), g('video-bitrate'), g('audio-codec-name'), g('audio-params/channel-count'), g('audio-params/samplerate'), g('audio-bitrate'), //
      g('current-ao'), g('frame-drop-count'), g('decoder-frame-drop-count'), g('demuxer-cache-duration'), g('cache-speed'), g('audio-device'),
      g('video-params/hw-pixelformat'),
    ]);
    String kbps(String v) => double.tryParse(v) == null ? '' : '${(double.parse(v) / 1000).round()} kbps';
    String fps(String v) => double.tryParse(v)?.toStringAsFixed(3) ?? '';
    final m = media;
    return [
      ('Playback', transcoding ? 'Transcode · ${streamQuality.isOriginal ? 'Original' : streamQuality.label}' : 'Direct Play'),
      if (m != null) ('File', [m.container?.toUpperCase(), m.resolutionLabel, if (m.bitrate != null) '${(m.bitrate! / 1000).toStringAsFixed(1)} Mbps'].whereType<String>().join(' · ')),
      ('Video', [mpvCodecLabel(r[0]), if (r[1].isNotEmpty) '${r[1]}×${r[2]}', if (r[3].isNotEmpty) '${fps(r[3])} fps'].where((s) => s.isNotEmpty).join(' · ')),
      ('Colour', [mpvPixelFormat(r[5], r[19]), if (r[6] == 'pq') 'HDR10 / PQ' else if (r[6] == 'hlg') 'HLG' else if (r[6].isNotEmpty) 'SDR'].where((s) => s.isNotEmpty).join(' · ')),
      ('Decoder', r[7].isEmpty || r[7] == 'no' ? 'Software' : 'Hardware (${r[7]})'),
      ('Video Rate', [kbps(r[8]), if (r[4].isNotEmpty) 'showing ${fps(r[4])} fps'].where((s) => s.isNotEmpty).join(' · ')),
      ('Audio', [r[9], if (r[10].isNotEmpty) '${r[10]} ch', if (r[11].isNotEmpty) '${(int.tryParse(r[11]) ?? 0) / 1000} kHz', kbps(r[12])].where((s) => s.isNotEmpty).join(' · ')),
      ('Output', [r[13], r[18]].where((s) => s.isNotEmpty).join(' · ')),
      ('Dropped', '${r[14].isEmpty ? 0 : r[14]} shown · ${r[15].isEmpty ? 0 : r[15]} decoder'),
      (
        'Buffer',
        [
          if (double.tryParse(r[16]) != null) '${double.parse(r[16]).toStringAsFixed(1)} s ahead',
          if (int.tryParse(r[17]) != null) '${(int.parse(r[17]) * 8 / 1e6).toStringAsFixed(1)} Mbps in',
        ].join(' · '),
      ),
    ];
  }
}

/// Playback Info where there is no mpv to ask (Samsung's player): what Plex says about the
/// file and the picked tracks, and the size of the picture the player is showing.
extension on PlayerSession {
  List<(String, String)> playerStats() {
    final m = media;
    final v = _videoStream;
    final a = audio;
    final sub = subtitle;
    final st = player.state;
    String up(String? s) => s?.toUpperCase() ?? '';
    return [
      ('Playback', transcoding ? 'Transcode · ${streamQuality.isOriginal ? 'Original' : streamQuality.label}' : 'Direct Play'),
      if (m != null) ('File', [m.container?.toUpperCase(), m.resolutionLabel, if (m.bitrate != null) '${(m.bitrate! / 1000).toStringAsFixed(1)} Mbps'].whereType<String>().join(' · ')),
      ('Video', [up(v?.codec ?? m?.videoCodec), if (v?.width != null && v?.height != null) '${v!.width}×${v.height}', if (v?.frameRate != null) '${v!.frameRate!.toStringAsFixed(3)} fps'].where((s) => s.isNotEmpty).join(' · ')),
      ('Picture', st.width != null && st.height != null && st.width! > 0 ? '${st.width}×${st.height}' : ''),
      ('Audio', a == null ? '' : [a.label, if (a.channels != null) '${a.channels} ch', if (a.bitrate != null) '${a.bitrate} kbps'].join(' · ')),
      ('Subtitles', sub == null ? 'Off' : [sub.label, if (sub.isImageSubtitle || transcoding) 'burned in by the server'].join(' · ')),
      if (rate != 1) ('Speed', '$rate×'),
      ('Player', isTizen ? 'Samsung TV player' : 'System player'),
    ];
  }
}

/// A deep shade of the title's colour for frosted panels and fades, at [alpha].
Color playerShade(Color tint, double alpha) => Color.alphaBlend(tint.withValues(alpha: 0.2), const Color(0xFF05060A)).withValues(alpha: alpha);

/// The picture fit for each aspect choice.
/// What the system's Now Playing card says for [item]: an episode under its show's name with
/// its season, number and title beneath; anything else under its own title, with its year.
(String, String?) nowPlayingText(PlexItem item) {
  if (item.type == 'episode') {
    final se = [if (item.parentIndex != null) 'S${item.parentIndex}', if (item.index != null) 'E${item.index}'].join(' · ');
    return (item.grandparentTitle ?? item.title, [if (se.isNotEmpty) se, item.title].join(' · '));
  }
  return (item.title, item.year?.toString());
}

BoxFit fitFor(String aspect) => switch (aspect) {
  'fill' => BoxFit.cover,
  'stretch' => BoxFit.fill,
  _ => BoxFit.contain,
};

/// What a player needs from the Open Watch Party room it's in.
abstract interface class RoomControl {
  /// May this viewer move the room on to another title (the host)?
  bool get leads;
  void play();
  void pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);
}

/// MPEG-TS clocks count 2^33 ticks of 90 kHz and then wrap: about 26 h 30 min 44 s.
const ptsWrap = Duration(microseconds: 95443717689);

/// A transcode stream's position as mpv reports it ([mpv]), made sensible for a stream
/// [length] long, or null when it can't be. Plex sends a transcode as MPEG-TS, and after a
/// pause and resume a cloud Fire TV's mpv reported 26:30:43 into a 3-hour film (the clock had
/// wrapped below zero) until the next seek; the player showed that, and would have told Plex
/// and Trakt the same. A wrapped clock is unwrapped; anything else past the end is no use.
Duration? sanePosition(Duration mpv, {required Duration length}) {
  const slack = Duration(minutes: 1);
  var p = mpv;
  if (p > ptsWrap ~/ 2) p -= ptsWrap;
  if (p < Duration.zero) return p > -slack ? Duration.zero : null;
  if (length > Duration.zero && p > length + slack) return null;
  return p;
}

/// mpv's video-codec ("hevc (H.265 / HEVC (High Efficiency Video Coding))") cut to its first
/// part for Playback Info. A build of FFmpeg without codec descriptions (the Mac and iPhone
/// ones, --enable-small) says "hevc ((null))": just the codec then.
String mpvCodecLabel(String codec) => codec.replaceAll(RegExp(r'\s*\(*\(null\)\)*'), '').split(' / ').first.trim();

/// The picture's pixel format for Playback Info. With hardware decoding mpv's pixelformat is
/// the decoder's ("videotoolbox", "d3d11", "mediacodec"); the frames' own format is
/// hw-pixelformat ("p010", "nv12"), which is what's worth showing.
String mpvPixelFormat(String pixelformat, String hwPixelformat) => hwPixelformat.isNotEmpty ? hwPixelformat : pixelformat;

