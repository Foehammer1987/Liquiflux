import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';

/// Riptide for the title playing: its whole cast (with the show's, for an episode) and, when the
/// scanner has been over it, who's on screen at any moment.
class Riptide extends ChangeNotifier {
  /// [token] is what to sign in to the Riptide server with (the plex.tv account token when the
  /// app has one, so the server can tell who it is); the Plex server's token when not given.
  ///
  /// [retryDelays] are the waits between tries when the server can't be reached or has a
  /// problem; [now] is the clock (tests set both).
  Riptide({required this.plex, required this.server, String? token, JsonHttp? http, this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5)], DateTime Function()? now})
    : _riptide = RiptideServer.shared(server, token ?? plex.token, http: http),
      _now = now ?? DateTime.now;
  final PlexClient plex;
  final List<Duration> retryDelays;
  final DateTime Function() _now;

  /// After a title's timeline couldn't be fetched, it's asked for again (when someone looks
  /// at who's in the scene) once this has passed, up to [maxRefetches] times.
  static const refetchAfter = Duration(minutes: 1);
  static const maxRefetches = 5;

  /// The Riptide server from Settings; empty means the cast list only.
  final String server;

  /// Signs in to the Riptide server with this Plex account (shared by every title played).
  final RiptideServer? _riptide;

  PlexItem? _item;
  PlexItem? _show;
  RiptideTimeline? _timeline;
  bool _disposed = false;
  bool _loading = false;
  DateTime? _failedAt;
  int _refetches = 0;

  /// The show, for an episode (its cast, logo and directors).
  PlexItem? get show => _show;

  /// Who's in it, top billing first, each actor once. An actor with several roles (twins
  /// played by one person, say) shows them all: "Reggie Kray / Ronnie Kray".
  List<PlexTag> get cast {
    final it = _item;
    if (it == null) return const [];
    final byName = <String, PlexTag>{};
    for (final r in [...it.roles, if (it.type == 'episode') ...?_show?.roles]) {
      if (r.tag.isEmpty) continue;
      final had = byName[r.tag];
      if (had == null) {
        byName[r.tag] = r;
      } else if (r.role != null && r.role!.isNotEmpty && !(had.role ?? '').split(' / ').contains(r.role)) {
        byName[r.tag] = PlexTag(id: had.id, tag: had.tag, thumb: had.thumb, role: (had.role ?? '').isEmpty ? r.role : '${had.role} / ${r.role}');
      }
    }
    return byName.values.toList();
  }

  /// Whether the scanner has a timeline for this title.
  bool get scanned => _timeline != null;

  /// Who's in the scene at [at]: those on screen that moment first, then the rest of the scene
  /// (see [RiptideTimeline.scene]), never reaching past one of the title's chapter marks. Empty
  /// without a timeline, or wherever the scanner wasn't sure: callers then show top billing
  /// ([cast]), never an empty list. People the scanner named but who aren't in Plex's cast
  /// list keep the scanner's name and role.
  List<PlexTag> inScene(Duration at) {
    final t = _timeline;
    if (t == null) {
      _refetchIfDue();
      return const [];
    }
    final cast = this.cast;
    return [
      for (final s in t.scene(at, breaks: [for (final c in _item?.chapters ?? const <PlexChapter>[]) if (c.startMs > 0) Duration(milliseconds: c.startMs)]))
        cast.where((r) => (s.person.plexTagId != null && r.id == s.person.plexTagId) || r.tag == s.person.name).firstOrNull ?? PlexTag(id: s.person.plexTagId, tag: s.person.name, role: s.person.role),
    ];
  }

  /// Asks again for a timeline that couldn't be fetched earlier (the server was restarting,
  /// say), at most every [refetchAfter], so one bad moment doesn't leave the whole title
  /// without Riptide.
  void _refetchIfDue() {
    final item = _item, failed = _failedAt;
    if (item == null || failed == null || _loading || _refetches >= maxRefetches) return;
    if (_now().difference(failed) < refetchAfter) return;
    _refetches++;
    unawaited(_loadTimeline(item));
  }

  /// Follows the player to [item] (Up Next moves it on), loading what it needs once.
  void follow(PlexItem item) {
    if (_item?.ratingKey == item.ratingKey) return;
    final showChanged = _item?.grandparentRatingKey != item.grandparentRatingKey;
    _item = item;
    _timeline = null;
    _failedAt = null;
    _refetches = 0;
    _loading = false;
    if (showChanged) _show = null;
    final showKey = item.grandparentRatingKey;
    if (item.type == 'episode' && showKey != null && _show == null) {
      unawaited(
        plex.metadata(showKey).then((s) {
          if (_disposed || _item?.grandparentRatingKey != showKey) return;
          _show = s;
          notifyListeners();
        }, onError: (Object _) {}),
      );
    }
    unawaited(_loadTimeline(item));
  }

  Future<void> _loadTimeline(PlexItem item) async {
    // Animated titles are never scanned; a show's genres are on the show.
    if (isAnimated(item)) return;
    final riptide = _riptide;
    if (riptide == null) return;
    _loading = true;
    try {
      for (var attempt = 0;; attempt++) {
        try {
          final body = await riptide.timeline(item.ratingKey);
          if (_disposed || _item?.ratingKey != item.ratingKey) return;
          _failedAt = null;
          if (body == null) return; // not scanned
          final t = RiptideTimeline.fromJson(body);
          // A poor or stale scan isn't used at all: the cast list shows instead.
          if (!t.usableFor([for (final r in item.roles) if (r.id != null) r.id!])) return;
          _timeline = t;
          notifyListeners();
          return;
        } catch (e) {
          if (_disposed || _item?.ratingKey != item.ratingKey) return;
          // Unreachable, timed out or a server error: try again shortly. Refused (not
          // allowed, too many sign-ins) isn't tried again: the cast list still works.
          final passing = e is ApiException && (e.status == 0 || e.status >= 500);
          if (passing && attempt < retryDelays.length) {
            await Future<void>.delayed(retryDelays[attempt]);
            if (_disposed || _item?.ratingKey != item.ratingKey) return;
            continue;
          }
          debugPrint('riptide: ${errorText(e)}');
          if (passing) _failedAt = _now();
          return;
        }
      }
    } finally {
      if (_item?.ratingKey == item.ratingKey) _loading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
