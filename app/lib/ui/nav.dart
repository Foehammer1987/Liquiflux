import 'package:console_core/console_core.dart' show Franchise;
import 'package:flutter/widgets.dart';

/// Where the content area is. Top-level destinations reset the stack; others push.
sealed class Dest {
  const Dest();
  String get railId;
}

class HomeDest extends Dest {
  const HomeDest();
  @override
  String get railId => 'home';
}

class LibraryDest extends Dest {
  const LibraryDest(this.sectionKey);
  final String sectionKey;
  @override
  String get railId => 'library:$sectionKey';
}

class SearchDest extends Dest {
  const SearchDest(this.query);
  final String query;
  @override
  String get railId => 'search';
}

class TrendingDest extends Dest {
  const TrendingDest();
  @override
  String get railId => 'trending';
}

/// Your library by mood and genre.
class MoodsDest extends Dest {
  const MoodsDest();
  @override
  String get railId => 'moods';
}

class RequestsDest extends Dest {
  const RequestsDest();
  @override
  String get railId => 'requests';
}

class SettingsDest extends Dest {
  const SettingsDest();
  @override
  String get railId => 'settings';
}

/// Film series: your Plex collections and well-known series.
class CollectionsDest extends Dest {
  const CollectionsDest();
  @override
  String get railId => 'collections';
}

/// One series' showcase page.
class CollectionDest extends Dest {
  const CollectionDest(this.franchise);
  final Franchise franchise;
  @override
  String get railId => '';
}

class ItemDest extends Dest {
  const ItemDest(this.ratingKey);
  final String ratingKey;
  @override
  String get railId => '';
}

/// A title that isn't in Plex (or is being requested), shown from Seerr.
class SeerrDest extends Dest {
  const SeerrDest(this.mediaType, this.tmdbId);
  final String mediaType;
  final int tmdbId;
  @override
  String get railId => '';
}

/// An actor or crew member: what's in the library and what can be requested.
class PersonDest extends Dest {
  const PersonDest({required this.name, this.plexTagId, this.tmdbId, this.photoUrl});
  final String name;
  final int? plexTagId;
  final int? tmdbId;
  final String? photoUrl;
  @override
  String get railId => '';
}

/// A page the player asked for on its way out (an actor picked in X-Ray). The shell opens it
/// once the player has gone, so its artwork never loads under a playing 4K title.
final playerHandoff = ValueNotifier<Dest?>(null);

/// Tells pages when another page covers them (Home pauses its trailers).
final pageRoutes = RouteObserver<ModalRoute<void>>();

/// The same for the app's top level, where the player opens over the whole shell.
final rootRoutes = RouteObserver<ModalRoute<dynamic>>();

/// The pages on the app's navigator and on the shell's, so the player can have the hidden
/// ones drawn ([showHidden]).
final rootStack = RouteStack();
final pageStack = RouteStack();

/// The routes on one navigator.
class RouteStack extends NavigatorObserver {
  final routes = <ModalRoute<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    routes.remove(oldRoute);
    if (newRoute is ModalRoute) routes.add(newRoute);
  }
}

/// While [on], every page is drawn, the ones other pages hide too. Flutter doesn't draw a page
/// another page hides, so a hidden page keeps what it last drew, and with it the artwork it
/// showed, until it is uncovered. The player draws itself black meanwhile.
void showHidden(bool on) {
  for (final stack in [rootStack, pageStack]) {
    stack.routes.removeWhere((r) => !r.isActive || r.overlayEntries.isEmpty);
    for (final r in stack.routes) {
      // A page coming in or going out sets this itself once it has.
      if (!r.opaque || !(r.animation?.isCompleted ?? true)) continue;
      r.overlayEntries.first.opaque = !on;
    }
  }
}

/// A [RouteAware] that just reports covered / uncovered.
class RouteCover with RouteAware {
  RouteCover(this.onChange);
  final ValueChanged<bool> onChange;
  @override
  void didPushNext() => onChange(true);
  @override
  void didPopNext() => onChange(false);
}

/// Lets any page navigate the shell's content area.
class ShellNav extends InheritedWidget {
  const ShellNav({super.key, required this.go, required this.push, required this.back, required super.child});
  final void Function(Dest) go;
  final void Function(Dest) push;
  final VoidCallback back;

  static ShellNav of(BuildContext context) => context.getInheritedWidgetOfExactType<ShellNav>()!;

  @override
  bool updateShouldNotify(ShellNav oldWidget) => false;
}
