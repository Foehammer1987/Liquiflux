// Plex Media Server JSON models (only the fields the apps use).

// A server can send anything: a wrong type, a huge or negative number, or none at all.
// These helpers turn what doesn't fit into null rather than throwing.

import '../format.dart' show cleanLabel;

int? _int(dynamic v) => v is int ? v : (v is num && v.isFinite ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null));
double? _dbl(dynamic v) {
  final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  return d != null && d.isFinite ? d : null;
}

/// A length, offset, size or count: never below zero.
int? _pos(dynamic v) {
  final n = _int(v);
  return n == null || n < 0 ? null : n;
}

/// A score out of ten.
double? _score(dynamic v) => _dbl(v)?.clamp(0.0, 10.0);
String? _str(dynamic v) => v is String ? v : null;
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class PlexSection {
  PlexSection({required this.key, required this.title, required this.type});
  factory PlexSection.fromJson(Map<String, dynamic> j) => PlexSection(key: '${j['key']}', title: '${j['title'] ?? ''}', type: '${j['type'] ?? ''}');
  final String key;
  final String title;

  /// movie, show, artist, photo
  final String type;
  bool get isVideo => type == 'movie' || type == 'show';
}

/// One video, audio or subtitle track of a file.
class PlexStream {
  PlexStream({
    required this.streamType,
    this.id = 0,
    this.index,
    this.key,
    this.codec,
    this.displayTitle,
    this.title,
    this.language,
    this.languageCode,
    this.channels,
    this.bitrate,
    this.forced = false,
    this.hearingImpaired = false,
    this.selected = false,
    this.isDefault = false,
  });
  factory PlexStream.fromJson(Map<String, dynamic> j) => PlexStream(
    streamType: _int(j['streamType']) ?? 0,
    id: _int(j['id']) ?? 0,
    index: _int(j['index']),
    key: _str(j['key']),
    codec: _str(j['codec']),
    displayTitle: _str(j['extendedDisplayTitle']) ?? _str(j['displayTitle']),
    title: _str(j['title']),
    language: _str(j['language']),
    languageCode: _str(j['languageCode']),
    channels: _pos(j['channels']),
    bitrate: _pos(j['bitrate']),
    forced: j['forced'] == true || j['forced'] == 1 || j['forced'] == '1',
    hearingImpaired: j['hearingImpaired'] == true || j['hearingImpaired'] == 1 || j['hearingImpaired'] == '1',
    selected: j['selected'] == true || j['selected'] == 1,
    isDefault: j['default'] == true || j['default'] == 1,
  );

  /// 1 video, 2 audio, 3 subtitle.
  final int streamType;

  /// Plex's stream id, used to select it (`audioStreamID`, `subtitleStreamID`).
  final int id;

  /// Position inside the file; null for a subtitle file sitting next to the video.
  final int? index;

  /// Download path for a sidecar subtitle (e.g. /library/streams/123).
  final String? key;
  final String? codec;

  /// Plex's own label, e.g. "1080p (HEVC Main 10)" or "English (AAC 5.1)".
  final String? displayTitle;

  /// The track name in the file, e.g. "Commentary" or "SDH".
  final String? title;
  final String? language;

  /// ISO 639-2, e.g. eng, spa.
  final String? languageCode;
  final int? channels;
  final int? bitrate;
  final bool forced;
  final bool hearingImpaired;
  final bool selected;
  final bool isDefault;

  bool get isVideo => streamType == 1;
  bool get isAudio => streamType == 2;
  bool get isSubtitle => streamType == 3;

  /// A subtitle file next to the video rather than inside it.
  bool get isExternal => isSubtitle && index == null && key != null;

  /// Bitmap subtitles (Blu-ray PGS, DVD VobSub) can't be restyled.
  bool get isImageSubtitle => isSubtitle && const ['pgs', 'hdmv_pgs_subtitle', 'vobsub', 'dvd_subtitle', 'dvb_subtitle'].contains(codec?.toLowerCase());

  String get label => displayTitle ?? title ?? language ?? codec?.toUpperCase() ?? 'Track ${index ?? id}';
}

/// An intro or credits span Plex detected (includeMarkers=1).
class PlexMarker {
  PlexMarker({required this.type, required this.startMs, required this.endMs, this.isFinal = false});
  factory PlexMarker.fromJson(Map<String, dynamic> j) =>
      PlexMarker(type: '${j['type'] ?? ''}', startMs: _pos(j['startTimeOffset']) ?? 0, endMs: _pos(j['endTimeOffset']) ?? 0, isFinal: j['final'] == true || j['final'] == 1);

  /// intro, credits, commercial
  final String type;
  final int startMs;
  final int endMs;

  /// The last credits marker, which runs to the end of the file.
  final bool isFinal;

  bool contains(int ms) => ms >= startMs && ms < endMs;
}

/// A chapter of the file (includeChapters=1).
class PlexChapter {
  PlexChapter({required this.title, required this.startMs, required this.endMs, this.thumb, this.index});
  factory PlexChapter.fromJson(Map<String, dynamic> j) =>
      PlexChapter(title: '${j['tag'] ?? ''}', startMs: _pos(j['startTimeOffset']) ?? 0, endMs: _pos(j['endTimeOffset']) ?? 0, thumb: _str(j['thumb']), index: _int(j['index']));
  final String title;
  final int startMs;
  final int endMs;
  final String? thumb;
  final int? index;
}

class PlexPart {
  PlexPart({required this.id, required this.key, this.container, this.duration, this.file, this.size, this.streams = const []});
  factory PlexPart.fromJson(Map<String, dynamic> j) => PlexPart(
    id: _int(j['id']) ?? 0,
    key: '${j['key'] ?? ''}',
    container: _str(j['container']),
    duration: _pos(j['duration']),
    file: _str(j['file']),
    size: _pos(j['size']),
    streams: _list(j['Stream']).map(PlexStream.fromJson).toList(),
  );
  final int id;
  final String key;
  final String? container;
  final int? duration;
  final String? file;
  final int? size;
  final List<PlexStream> streams;
}

/// A person or tag on an item (Role, Director, Writer…).
class PlexTag {
  PlexTag({this.id, required this.tag, this.role, this.thumb});
  factory PlexTag.fromJson(Map<String, dynamic> j) => PlexTag(id: _int(j['id']), tag: '${j['tag'] ?? ''}', role: _str(j['role']), thumb: _str(j['thumb']));
  final int? id;
  final String tag;

  /// Character name for cast.
  final String? role;

  /// Usually an absolute https URL for people.
  final String? thumb;
}

/// One score from Plex's Rating array, e.g. image "imdb://image.rating", value 7.5.
class PlexRating {
  PlexRating({required this.image, required this.value, required this.type});
  factory PlexRating.fromJson(Map<String, dynamic> j) => PlexRating(image: '${j['image'] ?? ''}', value: _score(j['value']) ?? 0, type: '${j['type'] ?? ''}');
  final String image;
  final double value;

  /// critic or audience
  final String type;
}

/// A critic review (includeReviews=1).
class PlexReview {
  PlexReview({required this.author, required this.text, this.source, this.image});
  factory PlexReview.fromJson(Map<String, dynamic> j) => PlexReview(author: '${j['tag'] ?? ''}', text: '${j['text'] ?? ''}', source: _str(j['source']), image: _str(j['image']));
  final String author;
  final String text;
  final String? source;

  /// rottentomatoes://image.review.fresh / .rotten
  final String? image;
}

class PlexMedia {
  PlexMedia({required this.id, this.videoResolution, this.videoCodec, this.audioCodec, this.container, this.bitrate, this.audioChannels, required this.parts});
  factory PlexMedia.fromJson(Map<String, dynamic> j) => PlexMedia(
    id: _int(j['id']) ?? 0,
    bitrate: _pos(j['bitrate']),
    audioChannels: _pos(j['audioChannels']),
    videoResolution: j['videoResolution']?.toString(),
    videoCodec: _str(j['videoCodec']),
    audioCodec: _str(j['audioCodec']),
    container: _str(j['container']),
    parts: _list(j['Part']).map(PlexPart.fromJson).toList(),
  );
  final int id;
  final String? videoResolution;
  final String? videoCodec;
  final String? audioCodec;
  final String? container;

  /// kbps
  final int? bitrate;
  final int? audioChannels;
  final List<PlexPart> parts;

  List<PlexStream> get streams => [for (final p in parts) ...p.streams];

  String? get resolutionLabel {
    final r = videoResolution;
    if (r == null || r.isEmpty) return null;
    return RegExp(r'^\d+$').hasMatch(r) ? '${r}p' : r.toUpperCase();
  }
}

class PlexItem {
  PlexItem({
    required this.ratingKey,
    required this.key,
    required this.type,
    required this.title,
    this.year,
    this.summary,
    this.thumb,
    this.art,
    this.parentThumb,
    this.grandparentThumb,
    this.grandparentTitle,
    this.grandparentRatingKey,
    this.parentTitle,
    this.parentRatingKey,
    this.index,
    this.parentIndex,
    this.duration,
    this.viewOffset,
    this.viewCount,
    this.leafCount,
    this.viewedLeafCount,
    this.childCount,
    this.contentRating,
    this.audienceRating,
    this.genres = const [],
    this.media = const [],
    this.guids = const [],
    this.plexGuid,
    this.tagline,
    this.studio,
    this.originallyAvailableAt,
    this.rating,
    this.ratingImage,
    this.audienceRatingImage,
    this.librarySectionId,
    this.librarySectionTitle,
    this.subtype,
    this.roles = const [],
    this.directors = const [],
    this.writers = const [],
    this.producers = const [],
    this.countries = const [],
    this.ratings = const [],
    this.reviews = const [],
    this.clearLogo,
    this.addedAt,
    this.updatedAt,
    this.lastViewedAt,
    this.markers = const [],
    this.chapters = const [],
  });

  factory PlexItem.fromJson(Map<String, dynamic> j) => PlexItem(
    ratingKey: '${j['ratingKey'] ?? ''}',
    key: '${j['key'] ?? ''}',
    type: '${j['type'] ?? ''}',
    title: '${j['title'] ?? ''}',
    year: _int(j['year']),
    summary: _str(j['summary']),
    thumb: _str(j['thumb']),
    art: _str(j['art']),
    parentThumb: _str(j['parentThumb']),
    grandparentThumb: _str(j['grandparentThumb']),
    grandparentTitle: _str(j['grandparentTitle']),
    grandparentRatingKey: j['grandparentRatingKey']?.toString(),
    parentTitle: _str(j['parentTitle']),
    parentRatingKey: j['parentRatingKey']?.toString(),
    index: _int(j['index']),
    parentIndex: _int(j['parentIndex']),
    duration: _pos(j['duration']),
    viewOffset: _pos(j['viewOffset']),
    viewCount: _pos(j['viewCount']),
    leafCount: _pos(j['leafCount']),
    viewedLeafCount: _pos(j['viewedLeafCount']),
    childCount: _pos(j['childCount']),
    contentRating: _str(j['contentRating']),
    audienceRating: _score(j['audienceRating']),
    genres: _list(j['Genre']).map((g) => '${g['tag']}').toList(),
    media: _list(j['Media']).map(PlexMedia.fromJson).toList(),
    guids: _list(j['Guid']).map((g) => '${g['id']}').toList(),
    plexGuid: _str(j['guid']),
    tagline: _str(j['tagline']),
    studio: _str(j['studio']),
    originallyAvailableAt: _str(j['originallyAvailableAt']),
    rating: _score(j['rating']),
    ratingImage: _str(j['ratingImage']),
    audienceRatingImage: _str(j['audienceRatingImage']),
    librarySectionId: j['librarySectionID']?.toString(),
    librarySectionTitle: _str(j['librarySectionTitle']),
    subtype: _str(j['subtype']),
    roles: _list(j['Role']).map(PlexTag.fromJson).toList(),
    directors: _list(j['Director']).map(PlexTag.fromJson).toList(),
    writers: _list(j['Writer']).map(PlexTag.fromJson).toList(),
    producers: _list(j['Producer']).map(PlexTag.fromJson).toList(),
    countries: _list(j['Country']).map((g) => '${g['tag']}').toList(),
    ratings: _list(j['Rating']).map(PlexRating.fromJson).toList(),
    reviews: _list(j['Review']).map(PlexReview.fromJson).toList(),
    clearLogo: _list(j['Image']).where((i) => i['type'] == 'clearLogo').map((i) => '${i['url']}').firstOrNull,
    addedAt: _int(j['addedAt']),
    updatedAt: _int(j['updatedAt']),
    lastViewedAt: _int(j['lastViewedAt']),
    markers: _list(j['Marker']).map(PlexMarker.fromJson).toList(),
    chapters: _list(j['Chapter']).map(PlexChapter.fromJson).toList(),
  );

  final String ratingKey;
  final String key;

  /// movie, show, season, episode
  final String type;
  final String title;
  final int? year;
  final String? summary;
  final String? thumb;
  final String? art;
  final String? parentThumb;
  final String? grandparentThumb;
  final String? grandparentTitle;
  final String? grandparentRatingKey;
  final String? parentTitle;
  final String? parentRatingKey;
  final int? index;
  final int? parentIndex;
  final int? duration;
  final int? viewOffset;
  final int? viewCount;
  final int? leafCount;
  final int? viewedLeafCount;
  final int? childCount;
  final String? contentRating;
  final double? audienceRating;
  final List<String> genres;
  final List<PlexMedia> media;
  final List<String> guids;

  /// Plex's own id for the title, e.g. plex://movie/5d776…, the same on every server.
  final String? plexGuid;
  final String? tagline;
  final String? studio;

  /// yyyy-mm-dd
  final String? originallyAvailableAt;

  /// Critic score 0..10 (with [ratingImage] naming the source).
  final double? rating;
  final String? ratingImage;
  final String? audienceRatingImage;
  final String? librarySectionId;

  /// The library's name; only full metadata reads carry it.
  final String? librarySectionTitle;

  /// For extras: trailer, behindTheScenes, featurette, deletedScene, interview…
  final String? subtype;
  final List<PlexTag> roles;
  final List<PlexTag> directors;
  final List<PlexTag> writers;
  final List<PlexTag> producers;
  final List<String> countries;
  final List<PlexRating> ratings;
  final List<PlexReview> reviews;

  /// Transparent title logo (newer servers list it in the Image array).
  final String? clearLogo;

  /// Unix seconds.
  final int? addedAt;

  /// Unix seconds; when Plex last changed the item's details.
  final int? updatedAt;

  /// Unix seconds; null when never played.
  final int? lastViewedAt;

  /// Intro and credits spans (only on a metadata call with markers).
  final List<PlexMarker> markers;

  /// Chapters of the first file (only on a metadata call with chapters).
  final List<PlexChapter> chapters;

  bool get isPlayable => type == 'movie' || type == 'episode' || type == 'clip';
  bool get isWatched => (viewCount ?? 0) > 0;

  /// 0..1 watched fraction for a partly watched item.
  double? get watchProgress => (viewOffset != null && duration != null && duration! > 0) ? (viewOffset! / duration!).clamp(0.0, 1.0) : null;

  /// tmdb://123 → 123
  int? get tmdbId {
    for (final g in guids) {
      if (g.startsWith('tmdb://')) {
        final id = int.tryParse(g.substring(7));
        return id != null && id > 0 ? id : null;
      }
    }
    return null;
  }

  /// imdb://tt0111161 → tt0111161 (only a well-formed id, since it ends up in a link).
  String? get imdbId => guids.where((g) => g.startsWith('imdb://')).map((g) => g.substring(7)).where(isImdbId).firstOrNull;

  String get episodeCode => 'S${parentIndex ?? 0} · E${index ?? 0}';

  /// The main title a card shows: the show for episodes, "Show · Season 1" for seasons.
  String get cardTitle => switch (type) {
    'episode' => grandparentTitle ?? title,
    'season' => '${parentTitle ?? ''} · $title',
    _ => title,
  };

  String get cardSubtitle => switch (type) {
    'episode' => '$episodeCode · $title',
    'season' => parentTitle ?? '',
    'show' => (childCount ?? 0) > 0 ? '$childCount Season${childCount == 1 ? '' : 's'}' : (year?.toString() ?? ''),
    _ => year?.toString() ?? '',
  };

  /// Poster art; episodes use their show's poster.
  String? get posterPath => type == 'episode' ? (grandparentThumb ?? thumb) : (thumb ?? parentThumb);
}

/// One play in the server's watch history (any account). Episodes count toward their show.
class PlexView {
  PlexView({required this.titleKey, required this.type, required this.viewedAt, this.accountId});

  /// Null for anything that isn't a movie or an episode (music, photos) or has no key.
  static PlexView? fromJson(Map<String, dynamic> j) {
    final type = _str(j['type']);
    final viewedAt = _pos(j['viewedAt']);
    if (viewedAt == null) return null;
    String? key;
    if (type == 'movie') {
      key = '${j['ratingKey'] ?? ''}';
    } else if (type == 'episode') {
      key = '${j['grandparentRatingKey'] ?? ''}';
      // History often only has the show's path, /library/metadata/<key>.
      if (key.isEmpty) key = RegExp(r'/library/metadata/(\d+)$').firstMatch(_str(j['grandparentKey']) ?? '')?.group(1) ?? '';
    }
    if (key == null || !RegExp(r'^\d{1,12}$').hasMatch(key)) return null;
    return PlexView(titleKey: key, type: type == 'movie' ? 'movie' : 'show', viewedAt: viewedAt, accountId: _int(j['accountID']));
  }

  /// The movie's or the show's ratingKey.
  final String titleKey;

  /// 'movie' or 'show'.
  final String type;

  /// Seconds since the epoch.
  final int viewedAt;
  final int? accountId;
}

class PlexServerInfo {
  PlexServerInfo({required this.name, required this.version, required this.machineIdentifier});
  final String name;
  final String version;
  final String machineIdentifier;
  String get shortVersion => version.split('-').first;
}

/// True for an IMDb title id such as tt0111161.
bool isImdbId(String? s) => s != null && RegExp(r'^tt\d{1,12}$').hasMatch(s);

/// A subtitle Plex found online for a title (Plex's own search, via OpenSubtitles), not yet
/// on the server. Everything in it came from the internet, so it's read defensively.
class OnlineSubtitle {
  const OnlineSubtitle({required this.key, required this.label, this.language = '', this.languageCode, this.codec, this.provider = '', this.score = 0, this.hearingImpaired = false, this.forced = false, this.perfectMatch = false, this.downloaded = false});

  /// Null when the answer can't be used: no key, or one that isn't a plain server value.
  static OnlineSubtitle? fromJson(Map<String, dynamic> j) {
    final key = _str(j['key']) ?? _str(j['sourceKey']);
    if (key == null || key.isEmpty || key.length > 1024 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(key)) return null;
    final title = _str(j['title']) ?? _str(j['displayTitle']);
    final code = _str(j['languageCode']);
    return OnlineSubtitle(
      key: key,
      label: cleanLabel(title, max: 120, fallback: 'Subtitle'),
      language: cleanLabel(_str(j['language']) ?? _str(j['displayTitle']), max: 40),
      languageCode: code != null && RegExp(r'^[a-zA-Z]{2,3}$').hasMatch(code) ? code.toLowerCase() : null,
      codec: _codec(_str(j['codec'])),
      provider: cleanLabel(_str(j['providerTitle']), max: 40),
      score: (_int(j['score']) ?? 0).clamp(0, 100),
      hearingImpaired: _flag(j['hearingImpaired']),
      forced: _flag(j['forced']),
      perfectMatch: _flag(j['perfectMatch']),
      downloaded: _flag(j['downloaded']),
    );
  }

  /// What Plex wants back to fetch it onto the server.
  final String key;

  /// The release name it was made for, usually; the closer to your file, the better it lines up.
  final String label;
  final String language;
  final String? languageCode;
  final String? codec;
  final String provider;

  /// Plex's 0–100 guess at how well it matches the file.
  final int score;
  final bool hearingImpaired;
  final bool forced;

  /// Made for this exact file, so the timing should be right.
  final bool perfectMatch;

  /// Already fetched onto the server.
  final bool downloaded;
}

bool _flag(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

String? _codec(String? c) => c != null && RegExp(r'^[a-zA-Z0-9]{1,10}$').hasMatch(c) ? c.toLowerCase() : null;
