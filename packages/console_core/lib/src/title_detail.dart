import 'format.dart';
import 'plex/plex_models.dart';
import 'seerr/seerr_models.dart';

/// Resolves a Plex image path (or absolute URL) to a sized image URL.
typedef ImageResolver = String? Function(String? path, int width, int height);

enum ScoreSource { imdb, rtCritic, rtAudience, tmdb, critic, audience }

/// One rating as shown on the detail page: "IMDb 7.5", "Rotten Tomatoes 81%".
class Score {
  const Score(this.source, this.value, {this.positive});
  final ScoreSource source;

  /// Already formatted: "7.5" or "81%".
  final String value;

  /// Fresh / upright (true) or rotten / spilled (false), when the source says.
  final bool? positive;

  String get label => switch (source) {
    ScoreSource.imdb => 'IMDb',
    ScoreSource.rtCritic => 'Critics',
    ScoreSource.rtAudience => 'Audience',
    ScoreSource.tmdb => 'TMDB',
    ScoreSource.critic => 'Critics',
    ScoreSource.audience => 'Audience',
  };
}

/// Someone in Cast & Crew.
class Credit {
  const Credit({required this.name, this.role, this.photoUrl, this.plexTagId, this.tmdbId, this.crew = false});
  final String name;

  /// Character for cast, job for crew.
  final String? role;
  final String? photoUrl;
  final int? plexTagId;
  final int? tmdbId;
  final bool crew;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

/// A trailer or bonus clip: a Plex extra to play in the app, or a web video to open.
class Extra {
  const Extra({required this.title, required this.kind, this.imageUrl, this.durationMs, this.plexItem, this.url});
  final String title;

  /// Trailer, Behind the Scenes, Featurette…
  final String kind;
  final String? imageUrl;
  final int? durationMs;
  final PlexItem? plexItem;
  final String? url;
}

/// What the file is: "1080p (HEVC Main 10)", "English (AAC 5.1)"…
class TrackInfo {
  const TrackInfo({this.video, this.audio, this.audioTracks = 0, this.subtitles = const [], this.file});
  final String? video;
  final String? audio;
  final int audioTracks;
  final List<String> subtitles;
  final String? file;
  bool get isEmpty => video == null && audio == null && subtitles.isEmpty && file == null;
}

enum TitleKind { movie, show, season, episode }

/// Everything the detail page shows, from Plex or from Seerr, so both look the same.
class TitleDetail {
  const TitleDetail({
    required this.kind,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.tagline,
    this.summary,
    this.year,
    this.released,
    this.contentRating,
    this.runtimeMs,
    this.genres = const [],
    this.scores = const [],
    this.posterUrl,
    this.landscape = false,
    this.backdropUrl,
    this.cast = const [],
    this.crew = const [],
    this.facts = const [],
    this.tracks,
    this.extras = const [],
    this.seasonCount,
    this.episodeCount,
    this.plexRatingKey,
    this.tmdbId,
    this.imdbId,
  });

  final TitleKind kind;

  /// Movie or show name.
  final String title;

  /// Episode or season name.
  final String? subtitle;

  /// "Season 5 · Episode 1"
  final String? eyebrow;
  final String? tagline;
  final String? summary;
  final int? year;
  final DateTime? released;
  final String? contentRating;
  final int? runtimeMs;
  final List<String> genres;
  final List<Score> scores;
  final String? posterUrl;

  /// The art is a 16:9 still (episodes) rather than a 2:3 poster.
  final bool landscape;
  final String? backdropUrl;
  final List<Credit> cast;
  final List<Credit> crew;

  /// Label → value rows: Directed by, Written by, Studio, Released…
  final List<(String, String)> facts;
  final TrackInfo? tracks;
  final List<Extra> extras;
  final int? seasonCount;
  final int? episodeCount;
  final String? plexRatingKey;
  final int? tmdbId;
  final String? imdbId;

  TitleDetail copyWith({List<Extra>? extras, String? tagline, List<Score>? scores, String? subtitle}) => TitleDetail(
    kind: kind,
    title: title,
    subtitle: subtitle ?? this.subtitle,
    eyebrow: eyebrow,
    tagline: tagline ?? this.tagline,
    summary: summary,
    year: year,
    released: released,
    contentRating: contentRating,
    runtimeMs: runtimeMs,
    genres: genres,
    scores: scores ?? this.scores,
    posterUrl: posterUrl,
    landscape: landscape,
    backdropUrl: backdropUrl,
    cast: cast,
    crew: crew,
    facts: facts,
    tracks: tracks,
    extras: extras ?? this.extras,
    seasonCount: seasonCount,
    episodeCount: episodeCount,
    plexRatingKey: plexRatingKey,
    tmdbId: tmdbId,
    imdbId: imdbId,
  );

  bool get isSeries => kind == TitleKind.show || kind == TitleKind.season;
  String get mediaType => isSeries || kind == TitleKind.episode ? 'tv' : 'movie';

  /// Plex item (with its show, for episodes and seasons) → detail.
  factory TitleDetail.fromPlex(PlexItem item, {PlexItem? show, required ImageResolver image}) {
    final kind = switch (item.type) {
      'show' => TitleKind.show,
      'season' => TitleKind.season,
      'episode' => TitleKind.episode,
      _ => TitleKind.movie,
    };
    final roles = item.roles.isNotEmpty ? item.roles : (show?.roles ?? const <PlexTag>[]);
    String? photo(PlexTag t) => image(t.thumb, 240, 240);
    final cast = [for (final r in roles) Credit(name: r.tag, role: r.role, photoUrl: photo(r), plexTagId: r.id)];
    final directors = item.directors.isNotEmpty ? item.directors : (show?.directors ?? const <PlexTag>[]);
    final writers = item.writers.isNotEmpty ? item.writers : (show?.writers ?? const <PlexTag>[]);
    final crew = [
      for (final d in directors) Credit(name: d.tag, role: 'Director', photoUrl: photo(d), plexTagId: d.id, crew: true),
      for (final w in writers.take(4)) Credit(name: w.tag, role: 'Writer', photoUrl: photo(w), plexTagId: w.id, crew: true),
      for (final p in item.producers.take(3)) Credit(name: p.tag, role: 'Producer', photoUrl: photo(p), plexTagId: p.id, crew: true),
    ];
    final released = DateTime.tryParse(item.originallyAvailableAt ?? '');
    final studio = item.studio ?? show?.studio;
    final facts = <(String, String)>[
      if (directors.isNotEmpty) ('Directed by', _names(directors.map((t) => t.tag))),
      if (writers.isNotEmpty) ('Written by', _names(writers.map((t) => t.tag))),
      if (studio != null && studio.isNotEmpty) (kind == TitleKind.movie ? 'Studio' : 'Network', studio),
      if (item.countries.isNotEmpty) ('Country', item.countries.take(2).join(', ')),
    ];
    final epLine = switch (kind) {
      TitleKind.episode => 'Season ${item.parentIndex ?? 0} · Episode ${item.index ?? 0}',
      TitleKind.season => item.leafCount != null ? '${item.leafCount} Episodes' : null,
      _ => null,
    };
    final isShowLevel = kind == TitleKind.show || kind == TitleKind.season;
    return TitleDetail(
      kind: kind,
      title: switch (kind) {
        TitleKind.episode => item.grandparentTitle ?? item.title,
        TitleKind.season => item.parentTitle ?? item.title,
        _ => item.title,
      },
      subtitle: kind == TitleKind.episode || kind == TitleKind.season ? item.title : null,
      eyebrow: epLine,
      tagline: item.tagline,
      summary: (item.summary?.isNotEmpty ?? false) ? item.summary : show?.summary,
      year: item.year ?? released?.year,
      released: released,
      contentRating: item.contentRating ?? show?.contentRating,
      runtimeMs: isShowLevel ? null : item.duration,
      genres: item.genres.isNotEmpty ? item.genres : (show?.genres ?? const []),
      scores: plexScores(item).isNotEmpty ? plexScores(item) : (show != null ? plexScores(show) : const []),
      posterUrl: kind == TitleKind.episode ? image(item.thumb, 640, 360) : image(item.posterPath, 400, 600),
      landscape: kind == TitleKind.episode,
      backdropUrl: image(item.art ?? show?.art, 1280, 720),
      cast: cast,
      crew: crew,
      facts: facts,
      tracks: plexTracks(item),
      seasonCount: item.childCount,
      episodeCount: item.leafCount,
      plexRatingKey: item.ratingKey,
      tmdbId: item.tmdbId ?? show?.tmdbId,
      imdbId: item.imdbId ?? show?.imdbId,
    );
  }

  /// Seerr (TMDB) title → detail, for things that aren't in Plex yet.
  factory TitleDetail.fromSeerr(SeerrResult d, {SeerrRatings? ratings}) {
    final directors = d.crew.where((c) => c.job == 'Director').toList();
    final writers = d.crew.where((c) => c.department == 'Writing').toList();
    final seenWriters = <String>{};
    final uniqueWriters = [
      for (final w in writers)
        if (seenWriters.add(w.name)) w,
    ];
    final released = DateTime.tryParse(d.date ?? '');
    final realSeasons = d.seasonDetails.where((s) => s.seasonNumber > 0).toList();
    final facts = <(String, String)>[
      if (d.createdBy.isNotEmpty) ('Created by', _names(d.createdBy.map((c) => c.name))),
      if (directors.isNotEmpty) ('Directed by', _names(directors.map((c) => c.name))),
      if (uniqueWriters.isNotEmpty) ('Written by', _names(uniqueWriters.map((c) => c.name))),
      if (d.isTv && d.networks.isNotEmpty) ('Network', d.networks.take(2).join(', ')),
      if (!d.isTv && d.studios.isNotEmpty) ('Studio', d.studios.take(2).join(', ')),
      if (d.status != null && d.status!.isNotEmpty) ('Status', d.status!),
    ];
    return TitleDetail(
      kind: d.isTv ? TitleKind.show : TitleKind.movie,
      title: d.displayTitle,
      tagline: (d.tagline?.isNotEmpty ?? false) ? d.tagline : null,
      summary: d.overview,
      year: released?.year,
      released: released,
      contentRating: d.certification,
      runtimeMs: d.runtime != null && d.runtime! > 0 ? d.runtime! * 60000 : null,
      genres: d.genres,
      scores: seerrScores(d, ratings),
      posterUrl: d.posterUrl(size: 'w500'),
      backdropUrl: d.backdropUrl(),
      cast: [for (final c in d.cast.take(30)) Credit(name: c.name, role: c.character, photoUrl: c.profileUrl(), tmdbId: c.id)],
      crew: [
        for (final c in d.createdBy) Credit(name: c.name, role: 'Creator', photoUrl: c.profileUrl(), tmdbId: c.id, crew: true),
        for (final c in directors) Credit(name: c.name, role: 'Director', photoUrl: c.profileUrl(), tmdbId: c.id, crew: true),
        for (final c in uniqueWriters.take(4)) Credit(name: c.name, role: 'Writer', photoUrl: c.profileUrl(), tmdbId: c.id, crew: true),
      ],
      facts: facts,
      extras: seerrExtras(d),
      seasonCount: realSeasons.isEmpty ? null : realSeasons.length,
      episodeCount: realSeasons.isEmpty ? null : realSeasons.fold<int>(0, (a, s) => a + (s.episodeCount ?? 0)),
      plexRatingKey: d.mediaInfo?.status == MediaStatus.available || d.mediaInfo?.status == MediaStatus.partiallyAvailable ? d.mediaInfo?.ratingKey : null,
      tmdbId: d.id,
      imdbId: d.imdbId,
    );
  }

  /// One line under the title: 2011 · 21m · 5 Seasons.
  List<String> get metaLine => [
    if (released != null && kind != TitleKind.show) formatDate(released!) else if (year != null) '$year',
    if (runtimeMs != null) formatDuration(runtimeMs),
    if (kind == TitleKind.show && (seasonCount ?? 0) > 0) '$seasonCount Season${seasonCount == 1 ? '' : 's'}',
    if (kind == TitleKind.show && (episodeCount ?? 0) > 0) '$episodeCount Episodes',
  ].where((s) => s.isNotEmpty).toList();
}

String _names(Iterable<String> names) {
  final l = names.toList();
  if (l.length <= 2) return l.join(', ');
  return '${l.take(2).join(', ')} and ${l.length - 2} more';
}

/// Plex's Rating array (or the older rating/audienceRating pair) as scores.
List<Score> plexScores(PlexItem item) {
  Score? fromImage(String image, double v, String type) {
    if (image.startsWith('imdb://')) return Score(ScoreSource.imdb, v.toStringAsFixed(1));
    if (image.startsWith('rottentomatoes://')) {
      final pct = '${(v * 10).round()}%';
      final kind = image.split('.').last; // ripe, rotten, upright, spilled
      if (kind == 'ripe' || kind == 'rotten') return Score(ScoreSource.rtCritic, pct, positive: kind == 'ripe');
      if (kind == 'upright' || kind == 'spilled') return Score(ScoreSource.rtAudience, pct, positive: kind == 'upright');
      return Score(type == 'critic' ? ScoreSource.rtCritic : ScoreSource.rtAudience, pct);
    }
    if (image.startsWith('themoviedb://')) return Score(ScoreSource.tmdb, '${(v * 10).round()}%');
    if (v <= 0) return null;
    return Score(type == 'critic' ? ScoreSource.critic : ScoreSource.audience, v.toStringAsFixed(1));
  }

  final out = <Score>[];
  final seen = <ScoreSource>{};
  void add(Score? s) {
    if (s != null && seen.add(s.source)) out.add(s);
  }

  for (final r in item.ratings) {
    add(fromImage(r.image, r.value, r.type));
  }
  // Older servers only send the pair; newer ones repeat it inside the Rating array.
  if (item.ratings.isEmpty) {
    if (item.rating != null) add(fromImage(item.ratingImage ?? '', item.rating!, 'critic'));
    if (item.audienceRating != null) add(fromImage(item.audienceRatingImage ?? '', item.audienceRating!, 'audience'));
  }
  return out;
}

List<Score> seerrScores(SeerrResult d, SeerrRatings? r) => [
  if (r?.imdb != null) Score(ScoreSource.imdb, r!.imdb!.toStringAsFixed(1)),
  if (r?.rtCritics != null) Score(ScoreSource.rtCritic, '${r!.rtCritics}%', positive: r.rtCriticsRating == null ? null : !r.rtCriticsRating!.contains('Rotten')),
  if (r?.rtAudience != null) Score(ScoreSource.rtAudience, '${r!.rtAudience}%', positive: r.rtAudienceRating == null ? null : r.rtAudienceRating == 'Upright'),
  if ((d.voteAverage ?? 0) > 0) Score(ScoreSource.tmdb, '${(d.voteAverage! * 10).round()}%'),
];

List<Extra> seerrExtras(SeerrResult d) {
  final vids = d.videos.where((v) => v.url.isNotEmpty).toList()..sort((a, b) => (a.type == 'Trailer' ? 0 : 1).compareTo(b.type == 'Trailer' ? 0 : 1));
  return [for (final v in vids.take(12)) Extra(title: v.name, kind: v.type ?? 'Video', imageUrl: v.thumbUrl, url: v.url)];
}

/// Video / audio / subtitle / file summary of an item's first file.
TrackInfo? plexTracks(PlexItem item) {
  final m = item.media.firstOrNull;
  if (m == null) return null;
  final streams = m.streams;
  final video = streams.where((s) => s.streamType == 1).firstOrNull;
  final audios = streams.where((s) => s.streamType == 2).toList();
  final audio = audios.where((s) => s.selected).firstOrNull ?? audios.where((s) => s.isDefault).firstOrNull ?? audios.firstOrNull;
  final subs = <String>{for (final s in streams.where((s) => s.streamType == 3)) s.displayTitle ?? s.language ?? 'Unknown'}.toList();
  final part = m.parts.firstOrNull;
  final codec = (m.videoCodec ?? '').toUpperCase();
  final file = [
    if (m.container != null) m.container!.toUpperCase(),
    if (part?.size != null) formatBytes(part!.size!),
    if (m.bitrate != null && m.bitrate! > 0) '${(m.bitrate! / 1000).toStringAsFixed(1)} Mbps',
  ];
  return TrackInfo(
    video: video?.displayTitle ?? [?m.resolutionLabel, if (codec.isNotEmpty) '($codec)'].join(' ').trim().emptyAsNull,
    audio: audio?.displayTitle ?? (m.audioCodec != null ? '${m.audioCodec!.toUpperCase()}${m.audioChannels != null ? ' ${_channels(m.audioChannels!)}' : ''}' : null),
    audioTracks: audios.length,
    subtitles: subs,
    file: file.isEmpty ? null : file.join(' · '),
  );
}

String _channels(int n) => switch (n) {
  1 => 'Mono',
  2 => 'Stereo',
  6 => '5.1',
  8 => '7.1',
  _ => '${n}ch',
};

/// Plex extra subtype → label.
String extraKind(String? subtype) => switch (subtype) {
  'trailer' => 'Trailer',
  'behindTheScenes' => 'Behind the Scenes',
  'deletedScene' => 'Deleted Scene',
  'featurette' => 'Featurette',
  'interview' => 'Interview',
  'sceneOrSample' => 'Scene',
  'short' => 'Short',
  _ => 'Extra',
};

extension on String {
  String? get emptyAsNull => isEmpty ? null : this;
}
