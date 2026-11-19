import 'dart:ui' show ImageFilter;

import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import '../state/app_state.dart';
import 'nav.dart';
import 'shuffle/shuffle_dialog.dart';

/// Phones and tablets ([isTouch]): the phone layout ([ConsoleDensity.compact]) when the
/// screen's short side is under [compactWidth], so a phone keeps it on its side too and a
/// tablet never gets it. Elsewhere [child] as it is.
class TouchDensity extends StatelessWidget {
  const TouchDensity({super.key, required this.child, this.touch});
  final Widget child;

  /// [isTouch] when not given (tests set it).
  final bool? touch;

  @override
  Widget build(BuildContext context) {
    if (!(touch ?? isTouch)) return child;
    return ConsoleDensity(compact: MediaQuery.sizeOf(context).shortestSide < compactWidth, child: child);
  }
}

/// Height of the bottom bar, above the system's gesture area.
const touchBarHeight = 58.0;

/// The bottom bar of the phone and tablet layout, in place of the TV/desktop side rail
/// (which opens on hover or the D-pad, neither of which a touch screen has): Home, Search,
/// your libraries, Collections, and More for the rest of the rail.
class TouchBar extends StatelessWidget {
  const TouchBar({super.key, required this.app, required this.current, required this.go, required this.search, required this.profiles});
  final AppState app;

  /// The page shown, by its [Dest.railId].
  final String current;
  final void Function(Dest) go;

  /// Puts the cursor in the search field (the keyboard comes up).
  final VoidCallback search;

  /// Opens "Who's watching?".
  final VoidCallback profiles;

  String get _tab {
    if (current == 'home') return 'home';
    if (current == 'search') return 'search';
    if (current.startsWith('library:')) return 'library';
    if (current == 'collections') return 'collections';
    return current.isEmpty ? '' : 'more';
  }

  void _library(BuildContext context) {
    final sections = app.sections;
    if (sections.length == 1) return go(LibraryDest(sections.first.key));
    _sheet(context, 'Your Library', [
      for (final s in sections)
        _SheetItem(s.type == 'show' ? LucideIcons.tv : LucideIcons.clapperboard, s.title, () => go(LibraryDest(s.key)), on: current == 'library:${s.key}'),
    ]);
  }

  void _more(BuildContext context) {
    final who = app.profile;
    _sheet(context, 'More', [
      if (app.settings.seerrReady) _SheetItem(LucideIcons.flame, 'Trending', () => go(const TrendingDest()), on: current == 'trending'),
      // Not in the Samsung store build (AppState.tvNetworks); kept here for the same rule.
      if (app.tvNetworks) _SheetItem(LucideIcons.satelliteDish, 'TV Networks', () => go(const TvCollectionsDest()), on: current == 'tv-networks'),
      _SheetItem(LucideIcons.sparkles, 'Moods', () => go(const MoodsDest()), on: current == 'moods'),
      _SheetItem(LucideIcons.shuffle, 'Shuffle Play', () => showShuffle(context)),
      _SheetItem(LucideIcons.radioTower, 'Channels', () => go(const ChannelsDest()), on: current == 'channels'),
      if (app.settings.seerrReady) _SheetItem(LucideIcons.download, 'Requests', () => go(const RequestsDest()), on: current == 'requests', badge: app.activeRequestCount),
      if ((app.homeList?.length ?? 0) > 1) _SheetItem(LucideIcons.usersRound, who == null ? 'Switch Profile' : 'Switch Profile (${who.name})', profiles),
      _SheetItem(LucideIcons.settings, 'Settings', () => go(const SettingsDest()), on: current == 'settings', alert: app.plexConn == Conn.failed),
    ]);
  }

  void _sheet(BuildContext context, String title, List<_SheetItem> items) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.c.surface100,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Space.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.space5, 0, Space.space5, Space.space2),
                child: Text(title, style: ConsoleText.titleLg.copyWith(color: sheet.c.text100)),
              ),
              for (final i in items)
                InkWell(
                  onTap: () {
                    Navigator.pop(sheet);
                    i.onTap();
                  },
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.space5),
                      child: Row(
                        children: [
                          Icon(i.icon, size: 22, color: i.on ? sheet.c.primary : sheet.c.text200),
                          const SizedBox(width: Space.space4),
                          Expanded(child: Text(i.label, style: ConsoleText.body.copyWith(fontSize: 16, color: i.on ? sheet.c.primary : sheet.c.text100))),
                          if (i.badge > 0 || i.alert) _Badge(text: i.alert ? '!' : '${i.badge}', alert: i.alert),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final tab = _tab;
    final moreAlert = app.plexConn == Conn.failed;
    final moreBadge = app.settings.seerrReady ? app.activeRequestCount : 0;
    Widget item(String id, IconData icon, String label, VoidCallback onTap, {int badge = 0, bool alert = false}) {
      final on = tab == id;
      final ink = on ? c.primary : (dark ? Colors.white : c.text100).withValues(alpha: 0.7);
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            radius: 36,
            child: SizedBox(
              height: touchBarHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 24, color: ink),
                      if (badge > 0 || alert) Positioned(right: -10, top: -6, child: _Badge(text: alert ? '!' : '$badge', alert: alert)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(label, maxLines: 1, style: ConsoleText.caption.copyWith(fontSize: 11, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: ink)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bar = Container(
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: fx.glass ? (dark ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.7)) : c.surface050.withValues(alpha: 0.97),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          item('home', LucideIcons.house, 'Home', () => go(const HomeDest())),
          item('search', LucideIcons.search, 'Search', search),
          if (app.sections.isNotEmpty) item('library', LucideIcons.clapperboard, 'Library', () => _library(context)),
          item('collections', LucideIcons.layers, 'Collections', () => go(const CollectionsDest())),
          item('more', LucideIcons.menu, 'More', () => _more(context), badge: moreBadge, alert: moreAlert),
        ],
      ),
    );
    if (!fx.glass) return Material(type: MaterialType.transparency, child: bar);
    return Material(
      type: MaterialType.transparency,
      child: ClipRect(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: fx.blur, sigmaY: fx.blur), child: bar),
      ),
    );
  }
}

class _SheetItem {
  const _SheetItem(this.icon, this.label, this.onTap, {this.on = false, this.badge = 0, this.alert = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;
  final int badge;
  final bool alert;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.alert});
  final String text;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: alert ? c.dangerFill : c.primaryFill, borderRadius: BorderRadius.circular(Radii.radiusFull)),
      child: Center(
        child: Text(text, style: ConsoleText.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: c.onPrimary, height: 1)),
      ),
    );
  }
}
