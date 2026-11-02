import 'plex/plex_models.dart';
import 'seerr/seerr_models.dart';
import 'format.dart';

String _norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Seerr results worth offering as requests: not already available, and not something
/// Plex just returned (in case Seerr's library sync is behind).
List<SeerrResult> requestableResults(List<SeerrResult> results, List<PlexItem> plexItems) {
  final have = {for (final p in plexItems.where((p) => p.type != 'episode')) '${_norm(p.title)}:${p.year ?? ''}'};
  return results.where((r) {
    if (r.mediaInfo?.status == MediaStatus.available) return false;
    return !have.contains('${_norm(r.displayTitle)}:${yearOf(r.date)}');
  }).toList();
}

/// Search hits as titles: each episode (or season) becomes its series, once, so "avatar" lists
/// the show rather than every episode in it. A series reached only through an episode is kept
/// when its own name matches every word of [query]; one whose episode title merely matched is
/// dropped. Movies and shows Plex returned keep their order; a series from an episode takes the
/// place of its first episode. [shows] lists the series made from episodes, by rating key, whose
/// full details the caller may still fetch (they carry only the episode's show title and poster).
({List<PlexItem> items, Set<String> shows}) searchTitles(List<PlexItem> hits, String query) {
  final words = query.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  bool named(String title) {
    final t = title.toLowerCase();
    return words.every(t.contains);
  }

  final seen = <String>{};
  final items = <PlexItem>[];
  final shows = <String>{};
  // A show Plex returned itself wins over the stand-in an earlier episode would make.
  final returned = {for (final h in hits.where((h) => h.type == 'show')) h.ratingKey};
  for (final h in hits) {
    if (h.type != 'episode' && h.type != 'season') {
      if (seen.add(h.ratingKey)) items.add(h);
      continue;
    }
    final key = h.type == 'episode' ? h.grandparentRatingKey : h.parentRatingKey;
    final title = h.type == 'episode' ? h.grandparentTitle : h.parentTitle;
    if (key == null || title == null || returned.contains(key) || !named(title) || !seen.add(key)) continue;
    items.add(
      PlexItem(
        ratingKey: key,
        key: '/library/metadata/$key/children',
        type: 'show',
        title: title,
        thumb: h.type == 'episode' ? h.grandparentThumb : h.parentThumb,
        librarySectionId: h.librarySectionId,
      ),
    );
    shows.add(key);
  }
  return (items: items, shows: shows);
}
