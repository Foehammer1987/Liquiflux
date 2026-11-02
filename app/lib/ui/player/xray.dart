import 'dart:async';

import 'package:console_core/console_core.dart';
import 'package:flutter/foundation.dart';

/// X-Ray for the title playing: its whole cast (with the show's, for an episode) and, when the
/// scanner has been over it, who's on screen at any moment.
class XRay extends ChangeNotifier {
  /// [token] is what to sign in to the X-Ray server with (the plex.tv account token when the
  /// app has one, so the server can tell who it is); the Plex server's token when not given.
  XRay({required this.plex, required this.server, String? token, JsonHttp? http}) : _xray = XRayServer.shared(server, token ?? plex.token, http: http);
  final PlexClient plex;

  /// The X-Ray server from Settings; empty means the cast list only.
  final String server;

  /// Signs in to the X-Ray server with this Plex account (shared by every title played).
  final XRayServer? _xray;

  PlexItem? _item;
  PlexItem? _show;
  XRayTimeline? _timeline;
  bool _disposed = false;

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

  /// The cast seen around [at], most certain first. Empty without a timeline, or wherever the
  /// scanner wasn't sure: callers then show top billing ([cast]), never an empty list. People
  /// the scanner named but who aren't in Plex's cast list keep the scanner's name and role.
  List<PlexTag> inScene(Duration at) {
    final t = _timeline;
    if (t == null) return const [];
    final cast = this.cast;
    return [
      for (final p in t.at(at))
        cast.where((r) => (p.plexTagId != null && r.id == p.plexTagId) || r.tag == p.name).firstOrNull ?? PlexTag(id: p.plexTagId, tag: p.name, role: p.role),
    ];
  }

  /// Follows the player to [item] (Up Next moves it on), loading what it needs once.
  void follow(PlexItem item) {
    if (_item?.ratingKey == item.ratingKey) return;
    final showChanged = _item?.grandparentRatingKey != item.grandparentRatingKey;
    _item = item;
    _timeline = null;
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
    final xray = _xray;
    if (xray == null) return;
    try {
      final body = await xray.timeline(item.ratingKey);
      if (_disposed || _item?.ratingKey != item.ratingKey || body == null) return;
      final t = XRayTimeline.fromJson(body);
      // A poor or stale scan isn't used at all: the cast list shows instead.
      if (!t.usableFor([for (final r in item.roles) if (r.id != null) r.id!])) return;
      _timeline = t;
      notifyListeners();
    } catch (e) {
      // The server is off, or won't let this account in: the cast list still works.
      debugPrint('xray: ${errorText(e)}');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
