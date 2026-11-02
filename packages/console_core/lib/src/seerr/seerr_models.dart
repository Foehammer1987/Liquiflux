// Seerr / Overseerr / Jellyseerr API models.

// A server can send anything: a wrong type, a huge or negative number, or none at all.
// These helpers turn what doesn't fit into null rather than throwing.

int? _int(dynamic v) => v is int ? v : (v is num && v.isFinite ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null));
double? _dbl(dynamic v) {
  final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  return d != null && d.isFinite ? d : null;
}

/// A size, count or popularity: never below zero.
double? _posDbl(dynamic v) {
  final d = _dbl(v);
  return d == null || d < 0 ? null : d;
}

int? _pos(dynamic v) {
  final n = _int(v);
  return n == null || n < 0 ? null : n;
}

/// A run time in minutes; past 100,000 (more than two months) it's nonsense.
int? _minutes(dynamic v) {
  final n = _pos(v);
  return n != null && n <= 100000 ? n : null;
}

String? _str(dynamic v) => v is String ? v : null;
Map<String, dynamic>? _map(dynamic v) => v is Map<String, dynamic> ? v : (v is Map ? v.map((k, v) => MapEntry('$k', v)) : null);
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v) : null;

/// A Plex ratingKey is a plain id; anything else (a path, a query) is dropped, since it ends
/// up in a Plex URL.
String? _ratingKey(dynamic v) {
  final s = v is String ? v : (v is int ? '$v' : null);
  return s != null && RegExp(r'^\w{1,64}$').hasMatch(s) ? s : null;
}

abstract final class MediaStatus {
  static const unknown = 1, pending = 2, processing = 3, partiallyAvailable = 4, available = 5;
}

abstract final class RequestStatus {
  static const pending = 1, approved = 2, declined = 3, failed = 4, completed = 5;
}

class DownloadStatus {
  DownloadStatus({required this.size, required this.sizeLeft, this.estimatedCompletionTime, this.status, this.title});
  factory DownloadStatus.fromJson(Map<String, dynamic> j) => DownloadStatus(
    size: _posDbl(j['size']) ?? 0,
    sizeLeft: _posDbl(j['sizeLeft']) ?? 0,
    estimatedCompletionTime: _date(j['estimatedCompletionTime']),
    status: _str(j['status']),
    title: _str(j['title']),
  );
  final double size;
  final double sizeLeft;
  final DateTime? estimatedCompletionTime;
  final String? status;
  final String? title;
}

class SeerrMediaInfo {
  SeerrMediaInfo({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    required this.status,
    this.downloads = const [],
    this.requests = const [],
    this.ratingKey,
    this.seasonStatus = const {},
  });
  factory SeerrMediaInfo.fromJson(Map<String, dynamic> j) => SeerrMediaInfo(
    id: _int(j['id']) ?? 0,
    tmdbId: _int(j['tmdbId']) ?? 0,
    mediaType: '${j['mediaType'] ?? 'movie'}',
    status: _int(j['status']) ?? MediaStatus.unknown,
    downloads: _list(j['downloadStatus']).map(DownloadStatus.fromJson).toList(),
    requests: _list(j['requests']).map(SeerrRequest.fromJson).toList(),
    ratingKey: _ratingKey(j['ratingKey']),
    seasonStatus: {for (final s in _list(j['seasons'])) _int(s['seasonNumber']) ?? 0: _int(s['status']) ?? MediaStatus.unknown},
  );
  final int id;
  final int tmdbId;
  final String mediaType;
  final int status;
  final List<DownloadStatus> downloads;
  final List<SeerrRequest> requests;

  /// The Plex ratingKey once Seerr has matched the title in the library.
  final String? ratingKey;

  /// Season number → MediaStatus, for series.
  final Map<int, int> seasonStatus;
}

/// TMDB paths look like /abc123.jpg; anything else (a full URL, a ../ path) is dropped
/// rather than glued onto the image host.
String? _tmdbImage(String? path, String size) => path == null || !_imagePath.hasMatch(path) ? null : '${SeerrImages.base}/$size$path';

final _imagePath = RegExp(r'^(/[\w-][\w.-]*)+$');

bool _isImdbId(String? s) => s != null && RegExp(r'^tt\d{1,12}$').hasMatch(s);

/// Where TMDB artwork comes from. Override to route images through a proxy or a test server.
abstract final class SeerrImages {
  static String base = 'https://image.tmdb.org/t/p';
}

/// Cast or crew from TMDB credits.
class SeerrCredit {
  SeerrCredit({required this.id, required this.name, this.character, this.job, this.department, this.profilePath});
  factory SeerrCredit.fromJson(Map<String, dynamic> j) =>
      SeerrCredit(id: _int(j['id']) ?? 0, name: '${j['name'] ?? ''}', character: _str(j['character']), job: _str(j['job']), department: _str(j['department']), profilePath: _str(j['profilePath']));
  final int id;
  final String name;
  final String? character;
  final String? job;
  final String? department;
  final String? profilePath;
  String? profileUrl({String size = 'w185'}) => _tmdbImage(profilePath, size);
}

/// A trailer or clip (usually YouTube).
class SeerrVideo {
  SeerrVideo({required this.name, required this.url, this.type, this.site, this.key});
  factory SeerrVideo.fromJson(Map<String, dynamic> j) => SeerrVideo(name: '${j['name'] ?? ''}', url: '${j['url'] ?? ''}', type: _str(j['type']), site: _str(j['site']), key: _str(j['key']));
  final String name;
  final String url;

  /// Trailer, Teaser, Clip, Featurette, Behind the Scenes…
  final String? type;
  final String? site;
  final String? key;

  /// YouTube still for the card.
  String? get thumbUrl => site == 'YouTube' && key != null && RegExp(r'^[\w-]{1,32}$').hasMatch(key!) ? 'https://img.youtube.com/vi/$key/hqdefault.jpg' : null;
}

class SeerrSeason {
  SeerrSeason({required this.seasonNumber, required this.name, this.episodeCount, this.airDate, this.posterPath});
  factory SeerrSeason.fromJson(Map<String, dynamic> j) => SeerrSeason(
    seasonNumber: _int(j['seasonNumber']) ?? 0,
    name: '${j['name'] ?? 'Season ${j['seasonNumber']}'}',
    episodeCount: _pos(j['episodeCount']),
    airDate: _str(j['airDate']),
    posterPath: _str(j['posterPath']),
  );
  final int seasonNumber;
  final String name;
  final int? episodeCount;
  final String? airDate;
  final String? posterPath;
}

/// Rotten Tomatoes / IMDb scores from Seerr's ratings endpoints.
class SeerrRatings {
  SeerrRatings({this.rtCritics, this.rtCriticsRating, this.rtAudience, this.rtAudienceRating, this.imdb});
  factory SeerrRatings.fromJson(Map<String, dynamic> j) {
    final rt = _map(j['rt']) ?? (j.containsKey('criticsScore') ? j : null);
    final imdb = _map(j['imdb']);
    return SeerrRatings(
      rtCritics: _int(rt?['criticsScore'])?.clamp(0, 100),
      rtCriticsRating: _str(rt?['criticsRating']),
      rtAudience: _int(rt?['audienceScore'])?.clamp(0, 100),
      rtAudienceRating: _str(rt?['audienceRating']),
      imdb: _dbl(imdb?['criticsScore'])?.clamp(0.0, 10.0),
    );
  }
  final int? rtCritics;

  /// Certified Fresh, Fresh, Rotten
  final String? rtCriticsRating;
  final int? rtAudience;

  /// Upright, Spilled
  final String? rtAudienceRating;
  final double? imdb;
}

class SeerrPerson {
  SeerrPerson({required this.id, required this.name, this.biography, this.birthday, this.deathday, this.placeOfBirth, this.profilePath, this.knownFor});
  factory SeerrPerson.fromJson(Map<String, dynamic> j) => SeerrPerson(
    id: _int(j['id']) ?? 0,
    name: '${j['name'] ?? ''}',
    biography: _str(j['biography']),
    birthday: _str(j['birthday']),
    deathday: _str(j['deathday']),
    placeOfBirth: _str(j['placeOfBirth']),
    profilePath: _str(j['profilePath']),
    knownFor: _str(j['knownForDepartment']),
  );
  final int id;
  final String name;
  final String? biography;
  final String? birthday;
  final String? deathday;
  final String? placeOfBirth;
  final String? profilePath;
  final String? knownFor;
  String? profileUrl({String size = 'h632'}) => _tmdbImage(profilePath, size);
}

class SeerrRequest {
  SeerrRequest({required this.id, required this.status, required this.createdAt, this.media, this.requestedBy, this.seasonCount = 0, this.seasonNumbers = const [], this.type});
  factory SeerrRequest.fromJson(Map<String, dynamic> j) => SeerrRequest(
    id: _int(j['id']) ?? 0,
    status: _int(j['status']) ?? RequestStatus.pending,
    createdAt: _date(j['createdAt']) ?? DateTime.now(),
    media: j['media'] is Map<String, dynamic> ? SeerrMediaInfo.fromJson(j['media'] as Map<String, dynamic>) : null,
    requestedBy: _str(_map(j['requestedBy'])?['displayName']),
    seasonCount: j['seasons'] is List ? (j['seasons'] as List).length : 0,
    seasonNumbers: [for (final s in _list(j['seasons'])) ?_pos(s['seasonNumber'])],
    type: _str(j['type']),
  );
  final int id;
  final int status;
  final DateTime createdAt;
  final SeerrMediaInfo? media;
  final String? requestedBy;
  final int seasonCount;

  /// The seasons asked for, when Seerr says (a series request).
  final List<int> seasonNumbers;
  final String? type;
}

class SeerrResult {
  SeerrResult({
    required this.id,
    required this.mediaType,
    this.title,
    this.name,
    this.releaseDate,
    this.firstAirDate,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.mediaInfo,
    this.seasons = const [],
    this.seasonDetails = const [],
    this.tagline,
    this.runtime,
    this.genres = const [],
    this.voteAverage,
    this.voteCount,
    this.cast = const [],
    this.crew = const [],
    this.createdBy = const [],
    this.videos = const [],
    this.certification,
    this.studios = const [],
    this.networks = const [],
    this.status,
    this.imdbId,
    this.character,
    this.popularity,
    this.collectionId,
    this.collectionName,
    this.releases = const [],
  });
  factory SeerrResult.fromJson(Map<String, dynamic> j) {
    final credits = _map(j['credits']);
    final type = '${j['mediaType'] ?? (j['firstAirDate'] != null || j['name'] != null && j['title'] == null ? 'tv' : 'movie')}';
    return SeerrResult(
      id: _int(j['id']) ?? 0,
      mediaType: type,
      title: _str(j['title']),
      name: _str(j['name']),
      releaseDate: _str(j['releaseDate']),
      firstAirDate: _str(j['firstAirDate']),
      posterPath: _str(j['posterPath']),
      backdropPath: _str(j['backdropPath']),
      overview: _str(j['overview']),
      mediaInfo: j['mediaInfo'] is Map<String, dynamic> ? SeerrMediaInfo.fromJson(j['mediaInfo'] as Map<String, dynamic>) : null,
      seasons: _list(j['seasons']).map((s) => _int(s['seasonNumber']) ?? 0).toList(),
      seasonDetails: _list(j['seasons']).map(SeerrSeason.fromJson).toList(),
      tagline: _str(j['tagline']),
      runtime: _minutes(j['runtime']) ?? (j['episodeRunTime'] is List && (j['episodeRunTime'] as List).isNotEmpty ? _minutes((j['episodeRunTime'] as List).first) : null),
      genres: _list(j['genres']).map((g) => '${g['name']}').toList(),
      voteAverage: _dbl(j['voteAverage'])?.clamp(0.0, 10.0),
      voteCount: _pos(j['voteCount']),
      cast: _list(credits?['cast']).map(SeerrCredit.fromJson).toList(),
      crew: _list(credits?['crew']).map(SeerrCredit.fromJson).toList(),
      createdBy: _list(j['createdBy']).map(SeerrCredit.fromJson).toList(),
      videos: _list(j['relatedVideos']).map(SeerrVideo.fromJson).toList(),
      certification: _certification(j),
      studios: _list(j['productionCompanies']).map((g) => '${g['name']}').toList(),
      networks: _list(j['networks']).map((g) => '${g['name']}').toList(),
      status: _str(j['status']),
      imdbId: [_str(_map(j['externalIds'])?['imdbId']), _str(j['imdbId'])].where(_isImdbId).firstOrNull,
      character: _str(j['character']),
      popularity: _posDbl(j['popularity']),
      collectionId: _int(_collection(j)?['id']),
      collectionName: _str(_collection(j)?['name']),
      releases: [
        for (final r in _list(_map(j['releases'])?['results']))
          for (final d in _list(r['release_dates']))
            if ((_date(d['release_date']), _int(d['type'])) case (final DateTime date, final int type)) SeerrRelease(country: '${r['iso_3166_1'] ?? ''}', type: type, date: date),
      ],
    );
  }

  static Map<dynamic, dynamic>? _collection(Map<String, dynamic> j) {
    final c = j['collection'] ?? j['belongsToCollection'];
    return c is Map ? c : null;
  }

  /// US rating first ("PG-13", "TV-MA"), else the first one listed.
  static String? _certification(Map<String, dynamic> j) {
    final out = <String, String>{};
    for (final r in _list(_map(j['releases'])?['results'])) {
      final c = _list(r['release_dates']).map((d) => '${d['certification'] ?? ''}').where((c) => c.isNotEmpty).firstOrNull;
      if (c != null) out['${r['iso_3166_1']}'] = c;
    }
    for (final r in _list(_map(j['contentRatings'])?['results'])) {
      final c = '${r['rating'] ?? ''}';
      if (c.isNotEmpty) out['${r['iso_3166_1']}'] = c;
    }
    return out['US'] ?? out.values.firstOrNull;
  }

  final int id;

  /// movie, tv, person
  final String mediaType;
  final String? title;
  final String? name;
  final String? releaseDate;
  final String? firstAirDate;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final SeerrMediaInfo? mediaInfo;
  final List<int> seasons;
  final List<SeerrSeason> seasonDetails;
  final String? tagline;

  /// Minutes (episode run time for series).
  final int? runtime;
  final List<String> genres;

  /// TMDB score 0..10
  final double? voteAverage;
  final int? voteCount;
  final List<SeerrCredit> cast;
  final List<SeerrCredit> crew;
  final List<SeerrCredit> createdBy;
  final List<SeerrVideo> videos;
  final String? certification;
  final List<String> studios;
  final List<String> networks;

  /// Released, Returning Series, Ended…
  final String? status;
  final String? imdbId;

  /// Set on a person's credits: who they played.
  final String? character;
  final double? popularity;

  /// The film series a movie belongs to (TMDB collection), from its details.
  final int? collectionId;
  final String? collectionName;

  /// A movie's release dates by country and kind (theatrical, digital…), from its details.
  final List<SeerrRelease> releases;

  String get displayTitle => title ?? name ?? 'Untitled';
  String? get date => releaseDate ?? firstAirDate;
  bool get isTv => mediaType == 'tv';

  String? posterUrl({String size = 'w342'}) => _tmdbImage(posterPath, size);
  String? backdropUrl({String size = 'w1280'}) => _tmdbImage(backdropPath, size);
}

/// One of a movie's release dates from TMDB.
class SeerrRelease {
  const SeerrRelease({required this.country, required this.type, required this.date});

  /// TMDB release types.
  static const premiere = 1, theatricalLimited = 2, theatrical = 3, digital = 4, physical = 5, tv = 6;

  /// ISO 3166-1 code: US, GB…
  final String country;
  final int type;
  final DateTime date;
}

/// A film series from TMDB (Star Wars, The Lord of the Rings…) with every film in it.
class SeerrCollection {
  SeerrCollection({required this.id, required this.name, this.overview, this.posterPath, this.backdropPath, this.parts = const [], this.json = const {}});
  factory SeerrCollection.fromJson(Map<String, dynamic> j) => SeerrCollection(
    json: j,
    id: _int(j['id']) ?? 0,
    name: '${j['name'] ?? ''}',
    overview: _str(j['overview']),
    posterPath: _str(j['posterPath']),
    backdropPath: _str(j['backdropPath']),
    parts: _list(j['parts']).map((p) => SeerrResult.fromJson({'mediaType': 'movie', ...p})).toList(),
  );
  final int id;
  final String name;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final List<SeerrResult> parts;

  /// What Seerr sent, so the series can be kept on disk and read back as it was.
  final Map<String, dynamic> json;

  String? posterUrl({String size = 'w500'}) => _tmdbImage(posterPath, size);
  String? backdropUrl({String size = 'w1280'}) => _tmdbImage(backdropPath, size);
}
