import 'package:console_core/console_core.dart';
import 'package:console_core/console_core.dart' as core show mpvOptions;

/// How a marker (intro, credits) is handled.
enum SkipMode {
  button('Show Button'),
  auto('Skip Automatically'),
  off('Off');

  const SkipMode(this.label);
  final String label;
  static SkipMode parse(Object? s, SkipMode fallback) => values.firstWhere((m) => m.name == s, orElse: () => fallback);
}

/// Every playback preference, saved as one object in settings.json.
class PlaybackPrefs {
  const PlaybackPrefs({
    this.localQuality = 0,
    this.remoteQuality = 8000,
    this.allowDirectPlay = true,
    this.allowDirectStream = true,
    this.hwdec = 'auto-safe',
    this.videoOutput = 'auto',
    this.skipBack = 10,
    this.skipForward = 30,
    this.skipIntro = SkipMode.button,
    this.skipCredits = SkipMode.button,
    this.autoPlayNext = true,
    this.countdown = 10,
    this.resumeMode = ResumeMode.ask,
    this.audioLanguage = '',
    this.subtitleLanguage = '',
    this.subtitleMode = SubtitleMode.plex,
    this.animeAudio = 'eng',
    this.showTracks = const {},
    this.subtitleSize = 100,
    this.subtitleRaise = 0,
    this.subtitleColor = 'white',
    this.subtitleBackground = 'outline',
    this.restyleSubtitles = false,
    this.passthrough = false,
    this.audioChannels = 'auto',
    this.nightMode = false,
    this.volumeBoost = false,
    this.audioDevice = 'auto',
    this.aspect = 'fit',
    this.deinterlace = false,
    this.highQualityScaling = false,
    this.deband = false,
    this.volume = 100,
    this.mpvOptions = '',
  });

  /// Streaming quality in kbps on this network and away from it; 0 is the original file.
  final int localQuality;
  final int remoteQuality;

  /// Play the file as-is when the player can (it nearly always can).
  final bool allowDirectPlay;

  /// When transcoding, copy the video untouched if only the audio or container needs work.
  final bool allowDirectStream;

  /// mpv hwdec: auto-safe, auto-copy or no.
  final String hwdec;

  /// Android only: how the picture reaches the screen. 'plane' (32-bit TVs only) has the
  /// hardware decoder draw onto a surface of its own behind the app, which the TV's display
  /// shows directly, as Plex's app and Plezy do. 'direct' has the decoder draw onto a
  /// Flutter texture. Both use little memory and leave subtitles to the app. 'mpv' copies
  /// each frame out and renders it with mpv (subtitle styling, HDR tone mapping, picture
  /// filters, but a 4K frame queue can be hundreds of MB). 'auto' is plane on 32-bit TVs,
  /// where 4K through a texture or mpv got the app killed, and mpv elsewhere.
  final String videoOutput;

  static const videoOutputs = ['auto', 'plane', 'direct', 'mpv'];

  /// Whether mpv only decodes, with the picture drawn by the TV (plane or direct); see
  /// [videoOutput]. 'plane' needs the transparent app window 32-bit TVs get, so elsewhere
  /// it falls back to direct.
  bool directVideo({required bool android, required bool lowMemory}) =>
      android && (videoOutput == 'direct' || videoOutput == 'plane' || (videoOutput == 'auto' && lowMemory));

  /// Whether the picture goes on the surface behind the app; see [videoOutput].
  bool planeVideo({required bool android, required bool lowMemory}) => android && lowMemory && (videoOutput == 'plane' || videoOutput == 'auto');

  /// Seconds for the skip back / forward buttons and arrow keys.
  final int skipBack;
  final int skipForward;
  final SkipMode skipIntro;
  final SkipMode skipCredits;

  /// Start the next episode when one ends, after [countdown] seconds.
  final bool autoPlayNext;
  final int countdown;

  /// Playing something left part-way through: ask, carry on, or start again.
  final ResumeMode resumeMode;

  /// ISO 639-2 codes; empty follows the file / Plex account.
  final String audioLanguage;
  final String subtitleLanguage;
  final SubtitleMode subtitleMode;

  /// Audio language for anime, ahead of [audioLanguage]; empty treats anime like anything else.
  final String animeAudio;

  /// The audio and subtitles last picked in each show, keyed by [showKey], oldest first.
  final Map<String, TrackChoice> showTracks;

  /// How many shows [showTracks] keeps; picking in another drops the oldest.
  static const maxShows = 500;

  static String showKey(String server, String show) => '$server/$show';

  /// [showTracks] with [choice] saved for [key] as the newest.
  PlaybackPrefs rememberShow(String key, TrackChoice choice) {
    final next = {...showTracks}..remove(key);
    while (next.length >= maxShows) {
      next.remove(next.keys.first);
    }
    next[key] = choice;
    return copyWith(showTracks: next);
  }

  /// Percent of normal size.
  final int subtitleSize;

  /// Percent of the picture height to lift subtitles off the bottom.
  final int subtitleRaise;

  /// white, yellow, cyan, green, pink, or art (the title's own colour).
  final String subtitleColor;

  /// outline, shadow or box.
  final String subtitleBackground;

  /// Apply the size, colour and background to styled (ASS) subtitles too.
  final bool restyleSubtitles;

  /// Send Dolby / DTS untouched to an AV receiver.
  final bool passthrough;

  /// auto, stereo, 5.1 or 7.1.
  final String audioChannels;

  /// Evens out loud effects and quiet dialogue.
  final bool nightMode;

  /// Lets the volume go to 200%.
  final bool volumeBoost;

  /// mpv audio device name, or auto.
  final String audioDevice;

  /// fit, fill or stretch.
  final String aspect;
  final bool deinterlace;
  final bool highQualityScaling;
  final bool deband;

  /// Last volume, 0..100 (200 with boost).
  final double volume;

  /// Extra mpv options, one name=value per line.
  final String mpvOptions;

  PlaybackPrefs copyWith({
    int? localQuality,
    int? remoteQuality,
    bool? allowDirectPlay,
    bool? allowDirectStream,
    String? hwdec,
    String? videoOutput,
    int? skipBack,
    int? skipForward,
    SkipMode? skipIntro,
    SkipMode? skipCredits,
    bool? autoPlayNext,
    int? countdown,
    ResumeMode? resumeMode,
    String? audioLanguage,
    String? subtitleLanguage,
    SubtitleMode? subtitleMode,
    String? animeAudio,
    Map<String, TrackChoice>? showTracks,
    int? subtitleSize,
    int? subtitleRaise,
    String? subtitleColor,
    String? subtitleBackground,
    bool? restyleSubtitles,
    bool? passthrough,
    String? audioChannels,
    bool? nightMode,
    bool? volumeBoost,
    String? audioDevice,
    String? aspect,
    bool? deinterlace,
    bool? highQualityScaling,
    bool? deband,
    double? volume,
    String? mpvOptions,
  }) => PlaybackPrefs(
    localQuality: localQuality ?? this.localQuality,
    remoteQuality: remoteQuality ?? this.remoteQuality,
    allowDirectPlay: allowDirectPlay ?? this.allowDirectPlay,
    allowDirectStream: allowDirectStream ?? this.allowDirectStream,
    hwdec: hwdec ?? this.hwdec,
    videoOutput: videoOutput ?? this.videoOutput,
    skipBack: skipBack ?? this.skipBack,
    skipForward: skipForward ?? this.skipForward,
    skipIntro: skipIntro ?? this.skipIntro,
    skipCredits: skipCredits ?? this.skipCredits,
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    countdown: countdown ?? this.countdown,
    resumeMode: resumeMode ?? this.resumeMode,
    audioLanguage: audioLanguage ?? this.audioLanguage,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    subtitleMode: subtitleMode ?? this.subtitleMode,
    animeAudio: animeAudio ?? this.animeAudio,
    showTracks: showTracks ?? this.showTracks,
    subtitleSize: subtitleSize ?? this.subtitleSize,
    subtitleRaise: subtitleRaise ?? this.subtitleRaise,
    subtitleColor: subtitleColor ?? this.subtitleColor,
    subtitleBackground: subtitleBackground ?? this.subtitleBackground,
    restyleSubtitles: restyleSubtitles ?? this.restyleSubtitles,
    passthrough: passthrough ?? this.passthrough,
    audioChannels: audioChannels ?? this.audioChannels,
    nightMode: nightMode ?? this.nightMode,
    volumeBoost: volumeBoost ?? this.volumeBoost,
    audioDevice: audioDevice ?? this.audioDevice,
    aspect: aspect ?? this.aspect,
    deinterlace: deinterlace ?? this.deinterlace,
    highQualityScaling: highQualityScaling ?? this.highQualityScaling,
    deband: deband ?? this.deband,
    volume: volume ?? this.volume,
    mpvOptions: mpvOptions ?? this.mpvOptions,
  );

  Map<String, dynamic> toJson() => {
    'localQuality': localQuality,
    'remoteQuality': remoteQuality,
    'allowDirectPlay': allowDirectPlay,
    'allowDirectStream': allowDirectStream,
    'hwdec': hwdec,
    'videoOutput': videoOutput,
    'skipBack': skipBack,
    'skipForward': skipForward,
    'skipIntro': skipIntro.name,
    'skipCredits': skipCredits.name,
    'autoPlayNext': autoPlayNext,
    'countdown': countdown,
    'resumeMode': resumeMode.name,
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
    'subtitleMode': subtitleMode.name,
    'animeAudio': animeAudio,
    'showTracks': {for (final e in showTracks.entries) e.key: e.value.toJson()},
    'subtitleSize': subtitleSize,
    'subtitleRaise': subtitleRaise,
    'subtitleColor': subtitleColor,
    'subtitleBackground': subtitleBackground,
    'restyleSubtitles': restyleSubtitles,
    'passthrough': passthrough,
    'audioChannels': audioChannels,
    'nightMode': nightMode,
    'volumeBoost': volumeBoost,
    'audioDevice': audioDevice,
    'aspect': aspect,
    'deinterlace': deinterlace,
    'highQualityScaling': highQualityScaling,
    'deband': deband,
    'volume': volume,
    'mpvOptions': mpvOptions,
  };

  /// Reads what was saved. The file can be edited by hand, so a value of the wrong type, or
  /// a number outside what Settings offers room for, falls back to the default.
  factory PlaybackPrefs.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const PlaybackPrefs();
    const d = PlaybackPrefs();
    T v<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    int n(String k, int fallback, int min, int max) => j[k] is int && (j[k] as int) >= min && (j[k] as int) <= max ? j[k] as int : fallback;
    int quality(String k, int fallback) => j[k] is int && streamingQualities.any((q) => q.kbps == j[k]) ? j[k] as int : fallback;
    final volume = j['volume'];
    final mpv = v('mpvOptions', d.mpvOptions);
    return PlaybackPrefs(
      localQuality: quality('localQuality', d.localQuality),
      remoteQuality: quality('remoteQuality', d.remoteQuality),
      allowDirectPlay: v('allowDirectPlay', d.allowDirectPlay),
      allowDirectStream: v('allowDirectStream', d.allowDirectStream),
      hwdec: v('hwdec', d.hwdec),
      // 0.9.6's 'overlay' test was a first try at the plane.
      videoOutput: j['videoOutput'] == 'overlay' ? 'plane' : (videoOutputs.contains(j['videoOutput']) ? j['videoOutput'] as String : d.videoOutput),
      // 'external4kApp' (4K in Another App, removed in 0.9.49: it handed the Plex token to
      // whatever video app the TV picked) is ignored in old files and dropped on the next save.
      skipBack: n('skipBack', d.skipBack, 1, 600),
      skipForward: n('skipForward', d.skipForward, 1, 600),
      skipIntro: SkipMode.parse(j['skipIntro'], d.skipIntro),
      skipCredits: SkipMode.parse(j['skipCredits'], d.skipCredits),
      autoPlayNext: v('autoPlayNext', d.autoPlayNext),
      countdown: n('countdown', d.countdown, 1, 120),
      resumeMode: ResumeMode.parse(j['resumeMode']),
      audioLanguage: v('audioLanguage', d.audioLanguage),
      subtitleLanguage: v('subtitleLanguage', d.subtitleLanguage),
      subtitleMode: SubtitleMode.parse(j['subtitleMode'] is String ? j['subtitleMode'] as String : null),
      animeAudio: v('animeAudio', d.animeAudio),
      showTracks: _showTracks(j['showTracks']),
      subtitleSize: n('subtitleSize', d.subtitleSize, 25, 400),
      subtitleRaise: n('subtitleRaise', d.subtitleRaise, 0, 50),
      subtitleColor: v('subtitleColor', d.subtitleColor),
      subtitleBackground: v('subtitleBackground', d.subtitleBackground),
      restyleSubtitles: v('restyleSubtitles', d.restyleSubtitles),
      passthrough: v('passthrough', d.passthrough),
      audioChannels: v('audioChannels', d.audioChannels),
      nightMode: v('nightMode', d.nightMode),
      volumeBoost: v('volumeBoost', d.volumeBoost),
      audioDevice: v('audioDevice', d.audioDevice),
      aspect: v('aspect', d.aspect),
      deinterlace: v('deinterlace', d.deinterlace),
      highQualityScaling: v('highQualityScaling', d.highQualityScaling),
      deband: v('deband', d.deband),
      volume: volume is num && volume >= 0 && volume <= 200 ? volume.toDouble() : d.volume,
      mpvOptions: mpv.length > 20000 ? d.mpvOptions : mpv,
    );
  }

  static Map<String, TrackChoice> _showTracks(Object? j) {
    if (j is! Map) return const {};
    final out = <String, TrackChoice>{};
    for (final e in j.entries) {
      final c = TrackChoice.fromJson(e.value);
      if (e.key is String && c != null) out[e.key as String] = c;
    }
    // Keep the newest (they're saved oldest first).
    return out.length <= maxShows ? out : Map.fromEntries(out.entries.skip(out.length - maxShows));
  }

  /// The name=value lines of [mpvOptions] that may be applied, in order: blank lines,
  /// # comments and options that could run code or touch files ([mpvOptionAllowed]) are
  /// left out, whether typed in Settings or edited into the file.
  List<(String, String)> get mpvOptionPairs => core.mpvOptions(mpvOptions).allowed;
}
