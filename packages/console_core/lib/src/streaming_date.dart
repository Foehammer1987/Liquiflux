import 'format.dart';
import 'seerr/seerr_models.dart';

/// A requested title that can't be downloaded yet because it isn't out on streaming
/// (digital) yet, and when it will be, as far as TMDB knows.
class StreamingWait {
  const StreamingWait({this.date, required this.what, this.note});

  /// The day it reaches streaming; null while no date is announced.
  final DateTime? date;

  /// What [date] is: "Digital release", "Premiere", "Season 3 premiere".
  final String what;

  /// Anything else worth a glance: "In theaters since October 3, 2026".
  final String? note;

  /// "Digital release November 18, 2026" or "Digital release date not announced".
  String get headline => date == null ? '$what date not announced' : '$what ${formatDate(date!)}';

  /// "in 25 days", "tomorrow", "today"; null without a date.
  String? until({DateTime? now}) {
    final d = date;
    if (d == null) return null;
    final n = now ?? DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }
}

/// TMDB has no digital or disc date for many older films; a film that opened in theaters
/// longer ago than this is taken to be out, rather than waiting forever.
const _theatricalWindow = Duration(days: 365);

/// When [d] (a requested title's Seerr details) reaches streaming, or null when it already
/// has (or TMDB can't tell). Only the date matters, so a release on [now]'s day counts as out.
///
/// Movies use TMDB's digital release (US first, else the earliest anywhere). Without one, a
/// film still in or not yet in theaters waits with no date, unless it's already on disc or TV.
/// Series wait for their premiere, or for the first requested season to air.
StreamingWait? streamingWaitOf(SeerrResult? d, {List<int> seasons = const [], DateTime? now}) {
  if (d == null) return null;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  bool future(DateTime t) => _day(t).isAfter(today);
  return d.isTv ? _seriesWait(d, seasons, today, future) : _movieWait(d, today, future);
}

DateTime _day(DateTime t) {
  // TMDB dates are midnight UTC for a calendar day; keep that day whatever the time zone.
  return DateTime(t.year, t.month, t.day);
}

/// The US date of a kind, else the earliest of that kind anywhere.
DateTime? _first(List<SeerrRelease> all, Set<int> types) {
  final of = all.where((r) => types.contains(r.type)).toList()..sort((a, b) => a.date.compareTo(b.date));
  return (of.where((r) => r.country == 'US').firstOrNull ?? of.firstOrNull)?.date;
}

StreamingWait? _movieWait(SeerrResult d, DateTime today, bool Function(DateTime) future) {
  final digital = _first(d.releases, {SeerrRelease.digital});
  final theaters = _first(d.releases, {SeerrRelease.premiere, SeerrRelease.theatricalLimited, SeerrRelease.theatrical}) ?? DateTime.tryParse(d.releaseDate ?? '');
  String? theaterNote() {
    if (theaters == null) return null;
    return future(theaters) ? 'In theaters ${formatDate(_day(theaters))}' : 'In theaters since ${formatDate(_day(theaters))}';
  }

  if (digital != null) return future(digital) ? StreamingWait(date: _day(digital), what: 'Digital release', note: theaterNote()) : null;
  // No digital date: out already if it's on disc or TV.
  final elsewhere = _first(d.releases, {SeerrRelease.physical, SeerrRelease.tv});
  if (elsewhere != null && !future(elsewhere)) return null;
  if (theaters == null) {
    // Nothing dated at all: only an announced film that isn't out yet.
    return d.status == null || d.status == 'Released' ? null : const StreamingWait(what: 'Release');
  }
  if (!future(theaters) && today.difference(_day(theaters)) > _theatricalWindow) return null;
  return StreamingWait(what: 'Digital release', note: theaterNote());
}

StreamingWait? _seriesWait(SeerrResult d, List<int> seasons, DateTime today, bool Function(DateTime) future) {
  final premiere = DateTime.tryParse(d.firstAirDate ?? '');
  if (premiere == null) {
    // Announced but undated.
    return const {'Planned', 'In Production', 'Pilot'}.contains(d.status) ? const StreamingWait(what: 'Premiere') : null;
  }
  if (future(premiere)) return StreamingWait(date: _day(premiere), what: 'Premiere');
  // Out already: wait only when every requested season is still to come.
  final asked = d.seasonDetails.where((s) => s.seasonNumber > 0 && seasons.contains(s.seasonNumber)).toList();
  if (asked.isEmpty) return null;
  DateTime? soonest;
  int? which;
  for (final s in asked) {
    final air = DateTime.tryParse(s.airDate ?? '');
    if (air != null && !future(air)) return null;
    if (air != null && (soonest == null || air.isBefore(soonest))) (soonest, which) = (air, s.seasonNumber);
  }
  which ??= asked.map((s) => s.seasonNumber).reduce((a, b) => a < b ? a : b);
  return StreamingWait(date: soonest == null ? null : _day(soonest), what: 'Season $which premiere', note: 'Series is out; this season is still to come');
}
