import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';

/// Artwork and labels shared by the Collections pages.
abstract final class SeriesArt {
  /// [small] art is for cards: a fraction of the pixels to fetch and decode.
  static String? poster(FranchisePart p, PlexClient? plex, {bool small = false}) =>
      p.tmdb?.posterUrl(size: small ? 'w185' : 'w342') ?? plex?.imageUrl(p.plex?.thumb, width: small ? 200 : 300, height: small ? 300 : 450);

  static String? backdrop(FranchisePart p, PlexClient? plex, {bool small = false}) =>
      p.tmdb?.backdropUrl(size: small ? 'w780' : 'w1280') ?? plex?.imageUrl(p.plex?.art, width: small ? 780 : 1280, height: small ? 440 : 720);

  /// The series' own poster, else its first film's.
  static String? seriesPoster(Franchise f, PlexClient? plex, {bool small = false}) =>
      f.tmdb?.posterUrl(size: small ? 'w185' : 'w500') ??
      plex?.imageUrl(f.plexCollection?.thumb, width: small ? 200 : 300, height: small ? 300 : 450) ??
      f.parts.map((p) => poster(p, plex, small: small)).whereType<String>().firstOrNull;

  static String? seriesBackdrop(Franchise f, PlexClient? plex, {bool small = false}) =>
      f.tmdb?.backdropUrl(size: small ? 'w780' : 'w1280') ??
      plex?.imageUrl(f.plexCollection?.art, width: small ? 780 : 1280, height: small ? 440 : 720) ??
      f.parts.map((p) => backdrop(p, plex, small: small)).whereType<String>().firstOrNull;

  /// Every film's backdrop in order, then the series' own, for the moving montage.
  static List<String> montage(Franchise f, PlexClient? plex) {
    final seen = <String>{};
    return [
      for (final u in [...f.released.map((p) => backdrop(p, plex)), seriesBackdrop(f, plex)])
        if (u != null && seen.add(u)) u,
    ];
  }

  /// "The Lord of the Rings: The Two Towers" → "The Two Towers" inside its own series.
  static String shortTitle(String title, Franchise f) {
    for (final sep in [': ', ' - ', ' – ']) {
      final head = '${f.name}$sep';
      if (title.toLowerCase().startsWith(head.toLowerCase()) && title.length > head.length) return title.substring(head.length);
    }
    return title;
  }

  static String roman(int n) {
    const table = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
    var out = '';
    var left = n;
    for (final (v, s) in table) {
      while (left >= v) {
        out += s;
        left -= v;
      }
    }
    return out;
  }

  /// 1290 → "21h 30m".
  static String hours(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
  }

  static String clockAt(DateTime t, BuildContext context) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t));
}
