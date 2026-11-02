// Playback choices shared by every player: which tracks to start with, streaming quality
// steps, and what plays next.

import 'plex/plex_models.dart';

/// One step of Plex's quality ladder. [kbps] 0 means the original file.
class StreamQuality {
  const StreamQuality(this.label, this.kbps, [this.resolution]);
  final String label;
  final int kbps;

  /// The transcoder's videoResolution, e.g. 1920x1080.
  final String? resolution;
  bool get isOriginal => kbps == 0;
}

/// The same steps the official Plex apps offer.
const streamingQualities = [
  StreamQuality('Original', 0),
  StreamQuality('4K · 40 Mbps', 40000, '3840x2160'),
  StreamQuality('1080p · 20 Mbps', 20000, '1920x1080'),
  StreamQuality('1080p · 12 Mbps', 12000, '1920x1080'),
  StreamQuality('1080p · 8 Mbps', 8000, '1920x1080'),
  StreamQuality('720p · 4 Mbps', 4000, '1280x720'),
  StreamQuality('720p · 3 Mbps', 3000, '1280x720'),
  StreamQuality('720p · 2 Mbps', 2000, '1280x720'),
  StreamQuality('480p · 1.5 Mbps', 1500, '720x480'),
  StreamQuality('328p · 0.7 Mbps', 720, '576x320'),
];

StreamQuality qualityFor(int kbps) => streamingQualities.firstWhere((q) => q.kbps == kbps, orElse: () => streamingQualities.first);

/// True for a server on this network: private and loopback addresses, .local names, and
/// plex.direct names that encode a private address (192-168-1-10.abc.plex.direct).
bool isLocalAddress(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return true;
  if (host == 'localhost' || host.endsWith('.local')) return true;
  var ip = host;
  if (host.endsWith('.plex.direct')) ip = host.split('.').first.replaceAll('-', '.');
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 10 || a == 127 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

/// Languages offered for audio and subtitle preferences, as ISO 639-2 codes.
const playbackLanguages = [
  ('eng', 'English'),
  ('spa', 'Spanish'),
  ('fre', 'French'),
  ('ger', 'German'),
  ('ita', 'Italian'),
  ('por', 'Portuguese'),
  ('dut', 'Dutch'),
  ('swe', 'Swedish'),
  ('nor', 'Norwegian'),
  ('dan', 'Danish'),
  ('fin', 'Finnish'),
  ('pol', 'Polish'),
  ('rus', 'Russian'),
  ('ukr', 'Ukrainian'),
  ('tur', 'Turkish'),
  ('gre', 'Greek'),
  ('ara', 'Arabic'),
  ('heb', 'Hebrew'),
  ('hin', 'Hindi'),
  ('jpn', 'Japanese'),
  ('kor', 'Korean'),
  ('chi', 'Chinese'),
  ('tha', 'Thai'),
  ('vie', 'Vietnamese'),
];

// ISO 639-2 has two codes for some languages; files use either.
const _sameLanguage = {'fra': 'fre', 'deu': 'ger', 'nld': 'dut', 'ell': 'gre', 'zho': 'chi', 'ces': 'cze', 'fas': 'per', 'ron': 'rum', 'slk': 'slo', 'msa': 'may', 'nob': 'nor', 'nno': 'nor'};
String _lang(String? code) => _sameLanguage[code?.toLowerCase()] ?? code?.toLowerCase() ?? '';

bool sameLanguage(String? a, String? b) => a != null && b != null && a.isNotEmpty && _lang(a) == _lang(b);

/// When subtitles come on by themselves.
enum SubtitleMode {
  /// Whatever Plex has selected for this file (your Plex account's language settings).
  plex('Plex Default'),
  off('Off'),

  /// Only forced subtitles (signs and foreign-language lines).
  forced('Forced Only'),

  /// When the audio isn't in your subtitle language.
  foreign('Foreign Audio'),
  always('Always');

  const SubtitleMode(this.label);
  final String label;
  static SubtitleMode parse(String? s) => values.firstWhere((m) => m.name == s, orElse: () => plex);
}

/// The audio and subtitles someone picked while watching one episode of a show, so the
/// rest of the show starts the same way (an anime's English dub with signs-only subtitles).
class TrackChoice {
  const TrackChoice({this.audio = '', this.subtitles = false, this.subtitleLanguage = '', this.forced = false, this.hearingImpaired = false});

  /// What's playing now, as a choice to carry over.
  factory TrackChoice.of(PlexStream? audio, PlexStream? subtitle) => TrackChoice(
    audio: audio?.languageCode ?? '',
    subtitles: subtitle != null,
    subtitleLanguage: subtitle?.languageCode ?? '',
    forced: subtitle != null && isSignsOnly(subtitle),
    hearingImpaired: subtitle?.hearingImpaired ?? false,
  );

  /// ISO 639-2 code; empty when the track didn't say.
  final String audio;

  /// False: subtitles off.
  final bool subtitles;
  final String subtitleLanguage;

  /// Forced or signs-and-songs subtitles rather than every line.
  final bool forced;
  final bool hearingImpaired;

  Map<String, dynamic> toJson() => {
    'audio': audio,
    'subtitles': subtitles,
    if (subtitles) 'subtitleLanguage': subtitleLanguage,
    if (forced) 'forced': true,
    if (hearingImpaired) 'hearingImpaired': true,
  };

  /// Null for anything that isn't a saved choice (the file can be edited by hand).
  static TrackChoice? fromJson(Object? j) {
    if (j is! Map) return null;
    String text(String k) => j[k] is String && (j[k] as String).length <= 12 ? j[k] as String : '';
    return TrackChoice(audio: text('audio'), subtitles: j['subtitles'] == true, subtitleLanguage: text('subtitleLanguage'), forced: j['forced'] == true, hearingImpaired: j['hearingImpaired'] == true);
  }

  @override
  bool operator ==(Object other) =>
      other is TrackChoice && other.audio == audio && other.subtitles == subtitles && other.subtitleLanguage == subtitleLanguage && other.forced == forced && other.hearingImpaired == hearingImpaired;

  @override
  int get hashCode => Object.hash(audio, subtitles, subtitleLanguage, forced, hearingImpaired);
}

/// Forced subtitles, or a track named for signs and songs (how anime releases label the
/// subtitles meant to go with the dub; they are often not flagged forced).
bool isSignsOnly(PlexStream s) {
  if (s.forced) return true;
  final t = '${s.title ?? ''} ${s.displayTitle ?? ''}'.toLowerCase();
  if (t.contains('full') || t.contains('dialog')) return false;
  return t.contains('sign') || t.contains('song');
}

/// Anime by its genres (Plex's agents tag it "Anime") or by sitting in a library named for it.
bool isAnime(PlexItem? show, {String? library}) =>
    (show?.genres.any((g) => g.toLowerCase().contains('anime')) ?? false) || (library?.toLowerCase().contains('anime') ?? false);

/// The audio track and subtitle (null = off) to start a file with. [remembered] is what was
/// picked last time in the same show; it wins wherever this file has a matching track.
({PlexStream? audio, PlexStream? subtitle}) pickTracks(
  List<PlexStream> streams, {
  String audioLanguage = '',
  String subtitleLanguage = '',
  SubtitleMode mode = SubtitleMode.plex,
  TrackChoice? remembered,
}) {
  final audios = streams.where((s) => s.isAudio).toList();
  final subs = streams.where((s) => s.isSubtitle).toList();

  // Prefer the main track over commentary in the wanted language.
  PlexStream? audioIn(String lang) => (audios.where((s) => sameLanguage(s.languageCode, lang)).toList()..sort((a, b) => (_isCommentary(a) ? 1 : 0).compareTo(_isCommentary(b) ? 1 : 0))).firstOrNull;
  final plexAudio = audios.where((s) => s.selected).firstOrNull ?? audios.where((s) => s.isDefault).firstOrNull ?? audios.firstOrNull;
  PlexStream? audio = plexAudio;
  final wanted = (remembered?.audio.isNotEmpty ?? false) && audioIn(remembered!.audio) != null ? remembered.audio : audioLanguage;
  if (wanted.isNotEmpty && !sameLanguage(audio?.languageCode, wanted)) audio = audioIn(wanted) ?? audio;

  final subLang = subtitleLanguage.isNotEmpty ? subtitleLanguage : (audioLanguage.isNotEmpty ? audioLanguage : audio?.languageCode ?? '');
  PlexStream? forcedIn(String? lang) => subs.where((s) => isSignsOnly(s) && (lang == null || sameLanguage(s.languageCode, lang))).firstOrNull;
  PlexStream? fullIn(String lang) {
    final m = subs.where((s) => !isSignsOnly(s) && sameLanguage(s.languageCode, lang)).toList()..sort((a, b) => (a.hearingImpaired ? 1 : 0).compareTo(b.hearingImpaired ? 1 : 0));
    return m.firstOrNull;
  }

  if (remembered != null) {
    if (!remembered.subtitles) return (audio: audio, subtitle: null);
    // Same language, then the same kind (signs only or every line), then the same SDH.
    final same = subs.where((s) => sameLanguage(s.languageCode, remembered.subtitleLanguage)).toList()
      ..sort((a, b) {
        int score(PlexStream s) => (isSignsOnly(s) == remembered.forced ? 2 : 0) + (s.hearingImpaired == remembered.hearingImpaired ? 1 : 0);
        return score(b) - score(a);
      });
    if (same.isNotEmpty) return (audio: audio, subtitle: same.first);
  }

  final PlexStream? subtitle = switch (mode) {
    // Plex's pick went with Plex's audio: once the audio moves to the language those
    // subtitles are in (a dub), keep only the signs.
    SubtitleMode.plex => switch (subs.where((s) => s.selected).firstOrNull) {
      final s? when audio?.id != plexAudio?.id && !isSignsOnly(s) && sameLanguage(s.languageCode, audio?.languageCode) => forcedIn(s.languageCode),
      final s => s,
    },
    SubtitleMode.off => null,
    SubtitleMode.forced => forcedIn(audio?.languageCode) ?? forcedIn(subLang),
    SubtitleMode.foreign => sameLanguage(audio?.languageCode, subLang) || audio?.languageCode == null ? forcedIn(audio?.languageCode) : (fullIn(subLang) ?? forcedIn(subLang)),
    SubtitleMode.always => fullIn(subLang) ?? forcedIn(subLang) ?? subs.where((s) => s.selected).firstOrNull,
  };
  return (audio: audio, subtitle: subtitle);
}

bool _isCommentary(PlexStream s) => '${s.title ?? ''} ${s.displayTitle ?? ''}'.toLowerCase().contains('commentary');

/// The episode before and after [ratingKey] in a show's full episode list.
({PlexItem? previous, PlexItem? next}) neighbours(List<PlexItem> episodes, String ratingKey) {
  final i = episodes.indexWhere((e) => e.ratingKey == ratingKey);
  if (i < 0) return (previous: null, next: null);
  return (previous: i > 0 ? episodes[i - 1] : null, next: i + 1 < episodes.length ? episodes[i + 1] : null);
}

/// 1:02:03 or 4:05.
String clock(Duration d) {
  final neg = d.isNegative;
  final t = d.abs();
  final h = t.inHours, m = t.inMinutes % 60, s = t.inSeconds % 60;
  final body = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
  return neg ? '-$body' : body;
}

/// ISO 639-1 codes for [playbackLanguages], which Plex's online subtitle search wants.
const _twoLetter = {
  'eng': 'en', 'spa': 'es', 'fre': 'fr', 'ger': 'de', 'ita': 'it', 'por': 'pt', 'dut': 'nl', 'swe': 'sv', //
  'nor': 'no', 'dan': 'da', 'fin': 'fi', 'pol': 'pl', 'rus': 'ru', 'ukr': 'uk', 'tur': 'tr', 'gre': 'el',
  'ara': 'ar', 'heb': 'he', 'hin': 'hi', 'jpn': 'ja', 'kor': 'ko', 'chi': 'zh', 'tha': 'th', 'vie': 'vi',
};

/// The two-letter code for an ISO 639-2 one (either spelling), or null if it isn't offered.
String? twoLetterLanguage(String? code) => _twoLetter[_lang(code)];

/// What happens when you play something you stopped part-way through, without picking
/// Resume or Play from Start yourself.
enum ResumeMode {
  ask('Ask'),
  resume('Resume'),
  start('Start Over');

  const ResumeMode(this.label);
  final String label;
  static ResumeMode parse(Object? s) => values.firstWhere((m) => m.name == s, orElse: () => ResumeMode.ask);
}

/// Less than this in, there's nothing worth resuming (or asking about).
const minResume = Duration(seconds: 10);

/// Where to start a title Plex says was left at [viewOffsetMs]. [resume] false always
/// starts from the beginning; [choose] is false when the person already chose (a Resume
/// button, Up Next, a Watch Together room), so a saved place is simply used. Otherwise
/// [mode] decides, and `ask` is true when the player should offer both.
({Duration from, bool ask}) startPoint({required int? viewOffsetMs, int? durationMs, bool resume = true, bool choose = true, ResumeMode mode = ResumeMode.ask}) {
  const zero = (from: Duration.zero, ask: false);
  final at = viewOffsetMs ?? 0;
  if (!resume || at < minResume.inMilliseconds) return zero;
  // A place at (or past) the end, from a damaged or odd server answer, isn't one.
  if (durationMs != null && durationMs > 0 && at >= durationMs) return zero;
  final from = Duration(milliseconds: at);
  if (!choose) return (from: from, ask: false);
  return switch (mode) {
    ResumeMode.resume => (from: from, ask: false),
    ResumeMode.start => zero,
    ResumeMode.ask => (from: from, ask: true),
  };
}

/// What to keep hidden about episodes you haven't seen yet, so lists and Up Next don't give
/// the story away. All off unless chosen in Settings.
class SpoilerPrefs {
  const SpoilerPrefs({this.images = false, this.summaries = false, this.titles = false});

  /// Blur episode stills.
  final bool images;

  /// Hide episode synopses.
  final bool summaries;

  /// Show "Episode 4" instead of the episode's name.
  final bool titles;

  bool get any => images || summaries || titles;

  /// True for an episode you haven't finished: the only kind with spoilers to hide.
  bool covers(PlexItem item) => any && item.type == 'episode' && !item.isWatched;
  bool hideImage(PlexItem item) => images && covers(item);
  bool hideSummary(PlexItem item) => summaries && covers(item);
  bool hideTitle(PlexItem item) => titles && covers(item);

  /// [item]'s name, or a plain "Episode 4" when its name is hidden.
  String titleOf(PlexItem item) => hideTitle(item) ? (item.index != null ? 'Episode ${item.index}' : 'Episode') : item.title;

  SpoilerPrefs copyWith({bool? images, bool? summaries, bool? titles}) => SpoilerPrefs(images: images ?? this.images, summaries: summaries ?? this.summaries, titles: titles ?? this.titles);

  Map<String, dynamic> toJson() => {'images': images, 'summaries': summaries, 'titles': titles};

  /// The settings file can be edited by hand: anything that isn't true or false is off.
  factory SpoilerPrefs.fromJson(Object? j) {
    if (j is! Map) return const SpoilerPrefs();
    return SpoilerPrefs(images: j['images'] == true, summaries: j['summaries'] == true, titles: j['titles'] == true);
  }
}
