import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:console_ui/console_ui.dart';
import 'package:console_core/console_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart' show customTitleBar;
import '../platform.dart';
import '../app_info.dart';
import '../services/links.dart';
import '../services/live_players.dart';
import '../services/network_watch.dart';
import '../services/notifier.dart';
import '../services/probe.dart';
import '../services/updater.dart';
import '../state/app_state.dart';
import '../state/scope.dart';
import 'nav.dart';
import 'profiles.dart';
import 'play.dart';
import 'player/player_dock.dart';
import 'notice_toast.dart';
import 'shuffle/shuffle_dialog.dart';
import 'tv_focus.dart';
import 'tv_popups.dart';
import 'window_buttons.dart';
import 'channels/channels_page.dart';
import 'collections/collection_page.dart';
import 'collections/collections_page.dart';
import 'collections/tv_collections_page.dart';
import 'pages/home_page.dart';
import 'pages/item_page.dart';
import 'pages/library_page.dart';
import 'pages/moods_page.dart';
import 'pages/person_page.dart';
import 'pages/player_page.dart';
import 'pages/requests_page.dart';
import 'pages/search_page.dart';
import 'pages/seerr_title_page.dart';
import 'pages/settings_page.dart';
import 'pages/trending_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _nav = GlobalKey<NavigatorState>();
  final _rail = GlobalKey<_RailState>();
  final _pages = _PageFocus();
  // On a TV the D-pad lands on the search pill as a button; Select starts typing.
  final _searchFocus = FocusNode(debugLabel: 'search field', skipTraversal: isTv);
  final _searchButton = FocusNode(debugLabel: 'search');
  // The sign-in page shown before Plex is set up. It isn't a route, so the page-focus helpers
  // (which look at the Navigator's top route) can't find it on their own.
  final _welcome = FocusScopeNode(debugLabel: 'welcome');
  final _search = TextEditingController();
  final _backdrop = BackdropController();
  Dest _top = const HomeDest();
  StreamSubscription<RequestRow>? _readySub;
  StreamSubscription<TogetherRoom>? _inviteSub;
  StreamSubscription<PlexItem>? _roomSub;
  StreamSubscription<UpdateInfo>? _updateSub;
  Timer? _updateCheck;

  /// Cards at the bottom right: requests that are ready ([RequestRow]) and invitations ([_Invite]).
  final _toasts = <Object>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = AppScope.read(context);
      _readySub = app.readyEvents.stream.listen(_ready);
      _inviteSub = app.watchTogether.invites.stream.listen(_invited);
      _roomSub = app.openParty.opens.stream.listen(_roomTitle);
      _updateSub = app.updater.found.stream.listen(_updateFound);
      // Once things have settled after launch: is there a newer Liquiflux on GitHub? Not in a
      // store build: the store updates the app, and Samsung's TVs install nothing else.
      if (storeBuild.isEmpty) _updateCheck = Timer(const Duration(seconds: 20), () => unawaited(app.updater.checkInBackground()));
      Notifier.instance.onAction = _onNotification;
      unawaited(Probe.atHome(context, openTitle: (key) => push(ItemDest(key))));
      // "Who's watching?" as Liquiflux opens, when asked for (it closes itself without a Home).
      // Settings are still loading on the first frame, so this waits for them.
      _whenLoaded(app, () {
        if (mounted && app.settings.plexReady && app.settings.askProfile) unawaited(_profiles(atStart: true));
      });
    });
    if (isTv) FocusManager.instance.addListener(_focusMoved);
    playerHandoff.addListener(_fromPlayer);
    if (isTizen) {
      NetworkWatch.instance.online.addListener(_networkChanged);
      NetworkWatch.instance.start();
    }
  }

  /// Runs [then] once the saved settings have loaded (straight away if they have).
  void _whenLoaded(AppState app, VoidCallback then) {
    if (app.loaded) return then();
    void check() {
      if (!app.loaded) return;
      app.removeListener(check);
      then();
    }

    app.addListener(check);
  }

  bool _networkPopup = false;

  /// Samsung TVs: the network went or came back. While it's gone a popup says so (the player
  /// closes itself first, see PlayerPage); once it's back the popup closes and Plex and Seerr
  /// are asked again straight away instead of at their next retry.
  void _networkChanged() {
    if (!mounted) return;
    final app = AppScope.read(context);
    if (NetworkWatch.instance.online.value) {
      app.networkBack();
      return;
    }
    if (_networkPopup) return;
    _networkPopup = true;
    // After the player's own route has gone, so the popup isn't what it pops.
    Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || NetworkWatch.instance.online.value) {
        _networkPopup = false;
        return;
      }
      await showNetworkLost(context);
      _networkPopup = false;
    });
  }

  void _fromPlayer() {
    final d = playerHandoff.value;
    if (d == null) return;
    playerHandoff.value = null;
    push(d);
  }

  Timer? _refocus;

  /// On a TV something must always have focus. When the focused control goes away with its
  /// page (Back from search results to Home), Flutter leaves focus on a scope with nothing in
  /// it, where the D-pad either does nothing or jumps far down the page. Then the page on top
  /// takes focus again, at its first control.
  void _focusMoved() {
    _refocus?.cancel();
    if (!_lost) return;
    _refocus = Timer(const Duration(milliseconds: 400), () {
      // Not while the player or a dialog covers the shell.
      if (mounted && _lost && (ModalRoute.of(context)?.isCurrent ?? true)) _toPage();
    });
  }

  bool get _lost {
    final p = FocusManager.instance.primaryFocus;
    return p == null || (p is FocusScopeNode && p.focusedChild == null);
  }

  @override
  void dispose() {
    if (isTv) FocusManager.instance.removeListener(_focusMoved);
    playerHandoff.removeListener(_fromPlayer);
    NetworkWatch.instance.online.removeListener(_networkChanged);
    _refocus?.cancel();
    _readySub?.cancel();
    _inviteSub?.cancel();
    _roomSub?.cancel();
    _updateSub?.cancel();
    _updateCheck?.cancel();
    Notifier.instance.onAction = null;
    _searchFocus.dispose();
    _searchButton.dispose();
    _welcome.dispose();
    super.dispose();
  }

  /// A request just landed: a card in the app, and a system toast too when Liquiflux
  /// isn't the window you're looking at.
  Future<void> _ready(RequestRow r) async {
    setState(
      () => _toasts
        ..removeWhere((t) => t is RequestRow && t.request.id == r.request.id)
        ..add(r),
    );
    final focused = !isDesktop || await windowManager.isFocused();
    if (focused || !mounted) return;
    final key = await AppScope.read(context).ratingKeyFor(r);
    final m = r.request.media;
    final kind = r.details?.isTv == true ? 'series' : 'movie';
    await Notifier.instance.ready(
      title: '${r.title} is ready to watch',
      body: 'The $kind you asked for is in your Plex library now.',
      payload: key != null ? 'play:$key' : 'open:${m?.mediaType ?? 'movie'}:${m?.tmdbId ?? 0}',
      posterUrl: r.details?.posterUrl(size: 'w185'),
    );
  }

  void _dismiss(Object t) => setState(() => _toasts.remove(t));

  /// The launch check found a newer Liquiflux.
  void _updateFound(UpdateInfo info) {
    if (!mounted) return;
    setState(
      () => _toasts
        ..removeWhere((t) => t is UpdateInfo)
        ..add(info),
    );
  }

  /// A friend asked us into a Watch Together room.
  Future<void> _invited(TogetherRoom room) async {
    final app = AppScope.read(context);
    final wt = app.watchTogether;
    final here = wt.playableHere(room);
    final item = here && room.ratingKey != null ? await app.plex?.metadata(room.ratingKey!).catchError((Object _) => null) : null;
    if (!mounted) return;
    final invite = _Invite(room, item);
    setState(
      () => _toasts
        ..removeWhere((t) => t is _Invite && t.room.id == room.id)
        ..add(invite),
    );
    final focused = !isDesktop || await windowManager.isFocused();
    if (focused || !mounted) return;
    final thumb = item?.thumb;
    await Notifier.instance.ready(
      title: '${room.createdBy?.title ?? 'A friend'} invited you to Watch Together',
      body: here ? room.title : '${room.title}. It’s on a Plex server Liquiflux isn’t connected to.',
      payload: 'join:${room.id}',
      posterUrl: thumb == null ? null : app.plex?.imageUrl(thumb, width: 200, height: 300),
      action: here ? 'Join' : 'Open',
    );
  }

  /// A Watch Together room (by code) is playing [item]: swap the player over to it, or open
  /// one. The room says where everyone is, so nothing asks about resuming.
  void _roomTitle(PlexItem item) {
    if (!mounted) return;
    final playing = AppScope.read(context).openParty.session;
    if (playing != null) return playing.onPlay(item);
    unawaited(openPlayer(context, (_) => PlayerPage(item: item, resume: false, choose: false)));
  }

  Future<void> _join(_Invite invite) async {
    _dismiss(invite);
    final wt = AppScope.read(context).watchTogether;
    final item = invite.item;
    if (item == null) return;
    if (await wt.join(invite.room)) {
      if (mounted) await playTitle(context, item);
    } else if (mounted && wt.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wt.error!)));
    }
  }

  Future<void> _playReady(RequestRow r) async {
    _dismiss(r);
    final key = await AppScope.read(context).ratingKeyFor(r);
    if (!mounted) return;
    if (key == null) return _openReady(r);
    await _playKey(key);
  }

  void _openReady(RequestRow r) {
    _dismiss(r);
    final m = r.request.media;
    if (m != null) push(SeerrDest(m.mediaType, m.tmdbId));
  }

  Future<void> _playKey(String key) async {
    final plex = AppScope.read(context).plex;
    if (plex == null) return;
    try {
      final item = await plex.metadata(key);
      if (item != null && mounted) await playTitle(context, item);
    } catch (e) {
      debugPrint('ready play: $e');
      if (mounted) push(ItemDest(key));
    }
  }

  /// Play (or a click) on a system toast: bring the window forward and do it.
  Future<void> _onNotification(String payload) async {
    if (isDesktop) {
      await windowManager.show();
      await windowManager.focus();
    }
    final action = parseToastPayload(payload);
    if (!mounted || action == null) return;
    switch (action.kind) {
      case 'play':
        _toasts.removeWhere((t) => t is RequestRow && t.request.media?.ratingKey == action.id);
        setState(() {});
        await _playKey(action.id);
      case 'join':
        // Only a room we were actually invited to (and still show) can be joined this way.
        final invite = _toasts.whereType<_Invite>().where((t) => t.room.id == action.id).firstOrNull;
        if (invite != null) await _join(invite);
      case 'open':
        push(SeerrDest(action.mediaType!, int.parse(action.id)));
    }
  }

  /// On a TV a card takes the remote's focus as it comes in (the arrows can't reach the corner
  /// from a page), unless the player or a popup is over the pages or a text field is in use.
  bool get _cardTakesFocus {
    if (!isTv || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final p = FocusManager.instance.primaryFocus?.context;
    return p == null || p.widget is! EditableText;
  }

  Widget _toast(Object t) {
    final takeFocus = _cardTakesFocus;
    if (t is UpdateInfo) {
      final updater = AppScope.read(context).updater;
      return NoticeToast(
        eyebrow: 'UPDATE',
        icon: LucideIcons.download,
        title: '$appName ${t.version} is out',
        body: updater.canInstall ? 'Update now, or any time from Settings > Advanced.' : 'See what’s new and download it from GitHub.',
        primary: updater.canInstall ? 'Update' : 'What’s New',
        primaryIcon: updater.canInstall ? LucideIcons.download : LucideIcons.externalLink,
        onPrimary: () {
          _dismiss(t);
          if (updater.canInstall) {
            go(const SettingsDest(update: true));
          } else {
            unawaited(openExternal(t.pageUrl));
          }
        },
        secondary: 'Not Now',
        onSecondary: () {
          _dismiss(t);
          unawaited(updater.skip(t.version));
        },
        onDismiss: () => _dismiss(t),
        takeFocus: takeFocus,
        // Longer on a TV, where the remote has further to go to reach it.
        lifetime: Duration(seconds: isTv ? 40 : 20),
      );
    }
    if (t is RequestRow) {
      final d = t.details;
      return NoticeToast(
        eyebrow: 'READY TO WATCH',
        icon: LucideIcons.circleCheck,
        title: t.title,
        body: 'The ${d?.isTv == true ? 'series' : 'movie'} you asked for is in your library now.',
        poster: d?.posterUrl(size: 'w185'),
        art: d?.backdropUrl(size: 'w300'),
        primary: 'Play',
        onPrimary: () => _playReady(t),
        secondary: 'Details',
        onSecondary: () => _openReady(t),
        onDismiss: () => _dismiss(t),
        takeFocus: takeFocus,
        // Longer on a TV, where it's read from across the room.
        lifetime: Duration(seconds: isTv ? 20 : 12),
      );
    }
    final invite = t as _Invite;
    final plex = AppScope.read(context).plex;
    final item = invite.item;
    final who = invite.room.createdBy?.title ?? 'A friend';
    return NoticeToast(
      eyebrow: 'WATCH TOGETHER',
      icon: LucideIcons.usersRound,
      title: invite.room.title,
      body: item != null ? '$who wants to watch this with you, in step.' : '$who invited you, but it’s on a Plex server Liquiflux isn’t connected to. Join from an app signed in to that server.',
      poster: item == null ? null : plex?.imageUrl(item.thumb, width: 200, height: 300),
      art: item == null ? null : plex?.imageUrl(item.art ?? item.thumb, width: 400, height: 225),
      primary: 'Join',
      primaryIcon: LucideIcons.logIn,
      onPrimary: item == null ? null : () => _join(invite),
      secondary: item == null ? null : 'Details',
      onSecondary: item == null
          ? null
          : () {
              _dismiss(invite);
              push(ItemDest(item.ratingKey));
            },
      onDismiss: () => _dismiss(invite),
        takeFocus: takeFocus,
      lifetime: const Duration(seconds: 45),
    );
  }

  /// Home runs to the top edge; other pages leave room for the floating search and window buttons.
  Widget _pageFor(Dest d) => d is HomeDest || d is CollectionDest
      ? _page(d)
      : Padding(
          padding: EdgeInsets.only(top: _chromeHeight + Space.space2, left: d is TrendingDest || d is MoodsDest || d is CollectionsDest || d is TvCollectionsDest || d is ChannelsDest ? 0 : Space.space4),
          child: _page(d),
        );

  Widget _page(Dest d) => switch (d) {
    HomeDest() => const HomePage(),
    TrendingDest() => const TrendingPage(),
    MoodsDest() => const MoodsPage(),
    ChannelsDest() => const ChannelsPage(),
    CollectionsDest() => const CollectionsPage(),
    // The Samsung store build has no TV Networks page (AppState.tvNetworks).
    TvCollectionsDest() || TvCollectionDest() when !AppScope.read(context).tvNetworks => const HomePage(),
    TvCollectionsDest() => const TvCollectionsPage(),
    TvCollectionDest(:final id) => TvCollectionPage(key: ValueKey('tv:$id'), id: id),
    CollectionDest(:final franchise) => CollectionPage(key: ValueKey(franchise.key), franchise: franchise),
    LibraryDest(:final sectionKey) => LibraryPage(key: ValueKey(sectionKey), sectionKey: sectionKey),
    SearchDest(:final query) => SearchPage(key: ValueKey(query), query: query),
    RequestsDest() => const RequestsPage(),
    SettingsDest(:final update) => SettingsPage(key: ValueKey('settings:$update'), update: update),
    ItemDest(:final ratingKey) => ItemPage(key: ValueKey(ratingKey), ratingKey: ratingKey),
    SeerrDest(:final mediaType, :final tmdbId) => SeerrTitlePage(key: ValueKey('$mediaType:$tmdbId'), mediaType: mediaType, tmdbId: tmdbId),
    PersonDest() => PersonPage(key: ValueKey('person:${d.name}'), person: d),
  };

  Route<void> _route(Dest d) => PageRouteBuilder(
    settings: RouteSettings(arguments: d),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) => _pageFor(d),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
  );

  /// The page search results were opened from, for Back to return to on a TV.
  Dest? _fromSearch;

  void go(Dest d) {
    if (d is SearchDest && _top is! SearchDest) _fromSearch = _top;
    if (d is! SearchDest) _fromSearch = null;
    setState(() => _top = d);
    if (d is! SearchDest) _search.clear();
    _nav.currentState?.pushAndRemoveUntil(_route(d), (_) => false);
  }

  void push(Dest d) => _nav.currentState?.push(_route(d));

  /// The Plex Home's profiles; after a switch every page starts again from Home, as the new
  /// user's Continue Watching, watched marks and recommendations differ.
  Future<void> _profiles({bool atStart = false}) async {
    final switched = await showProfiles(context, atStart: atStart);
    if (!mounted || !switched) return;
    // A mini player was the last user's: it stops, saving their place.
    PlayerDock.instance.close();
    go(const HomeDest());
    if (isTv) _claimFocus();
  }

  void back() => _nav.currentState?.maybePop();

  /// Esc, the remote's Back button and Android's system back: leave search, then step back
  /// through pages, then (on a TV) return Home, then to the top of Home. False when there's
  /// nothing left to go back to.
  bool _backPressed() {
    if (_rail.currentState?.hasFocus ?? false) {
      _toPage();
      return true;
    }
    if (_searchFocus.hasFocus) {
      // On a TV, back to the search button rather than to nothing.
      isTv ? _searchButton.requestFocus() : _searchFocus.unfocus();
      return true;
    }
    if (_searchButton.hasFocus) {
      _toPage();
      return true;
    }
    final nav = _nav.currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
      return true;
    }
    // Back from search results returns to the page the search started on.
    if (isTv && _top is SearchDest && _fromSearch != null && _fromSearch is! HomeDest) {
      go(_fromSearch!);
      _claimFocus();
      return true;
    }
    if (isTv && _top is! HomeDest) {
      go(const HomeDest());
      _claimFocus();
      return true;
    }
    if (isTv && _backToTop()) return true;
    return false;
  }

  /// Back while browsing Home's rows on a TV: up to the top of Home, on its first control, as
  /// TV apps do. It used to leave the app straight away. Back again from there leaves.
  bool _backToTop() {
    final ctx = _pages.current?.subtreeContext;
    final p = FocusManager.instance.primaryFocus;
    if (ctx == null || !ctx.mounted || p == null || p.context == null) return false;
    final scope = FocusScope.of(ctx);
    if (!p.ancestors.contains(scope)) return false;
    final list = Scrollable.maybeOf(p.context!, axis: Axis.vertical);
    if (list == null || list.position.pixels <= 0) {
      final first = _firstIn(scope);
      if (first == null || first == p) return false;
      first.requestFocus();
      return true;
    }
    list.position.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic).then((_) {
      if (mounted && scope.hasFocus) _firstIn(scope)?.requestFocus();
    });
    return true;
  }

  /// After Back to Home on a TV: the new page takes focus at its first control, wherever focus
  /// was left. On the Shield, Back from some search results left focus on something unseen
  /// below the spotlight (Down then jumped far down the page), which neither the page's own
  /// first-focus pass nor [_focusMoved] caught. Logs where focus was, to find out what it was.
  void _claimFocus() {
    for (final ms in const [350, 1000, 2000]) {
      Timer(Duration(milliseconds: ms), () {
        final ctx = _pages.current?.subtreeContext;
        if (!mounted || ctx == null || !ctx.mounted) return;
        // Someone already went to the rail or search.
        if ((_rail.currentState?.hasFocus ?? false) || _searchFocus.hasFocus || _searchButton.hasFocus) return;
        final scope = FocusScope.of(ctx);
        final p = FocusManager.instance.primaryFocus;
        final mine = p != null && p != scope && p.context?.mounted == true && p.ancestors.contains(scope) && p.rect.top >= 0 && p.rect.bottom <= MediaQuery.sizeOf(context).height;
        String where(FocusNode? n) {
          if (n == null) return 'none';
          final r = n.rect;
          final label = n.context?.mounted == true ? n.context!.findAncestorWidgetOfExactType<Semantics>()?.properties.label : 'unmounted';
          return '${n.runtimeType} "$label" (${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()}) in page: ${n.ancestors.contains(scope)}';
        }
        final first = mine ? null : _firstIn(scope);
        debugPrint('focus after back ${ms}ms: ${where(p)}${mine ? ', on page' : ', claimed for ${where(first)}'}');
        first?.requestFocus();
      });
    }
  }

  /// From the rail back to the page, where focus was before.
  void _toPage() {
    // Before sign-in there is no Navigator, only the welcome page: focus its first control.
    // Without this, focus that reached the search pill (or got lost) on a TV had nowhere to go,
    // and the remote was stuck there (seen on Fire TV, 1.0.17).
    if (_welcome.context?.mounted == true) {
      (_firstIn(_welcome) ?? _welcome).requestFocus();
      return;
    }
    final ctx = _pages.current?.subtreeContext;
    if (ctx == null) return;
    final scope = FocusScope.of(ctx);
    scope.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst(scope));
  }

  /// Up from the top of a page or the rail: the search pill.
  void _toSearch() => (isTv ? _searchButton : _searchFocus).requestFocus();

  /// Back from the top of Home leaves the app on Android, like any TV app. A Samsung TV asks
  /// first (Samsung's Return key policy): only Yes closes the app.
  void _back() {
    if (_backPressed()) return;
    if (Platform.isAndroid) unawaited(_leaveApp());
    if (isTizen) unawaited(_askToLeave());
  }

  bool _leaving = false;
  bool _asking = false;

  Future<void> _askToLeave() async {
    if (_asking || _leaving) return;
    _asking = true;
    final yes = await confirmExit(context);
    _asking = false;
    if (yes && mounted) await _leaveApp();
  }

  /// Lets go of every mpv player (a Spotlight trailer, a player still closing) before the
  /// activity finishes: one left open crashed natively in libmpv once Dart was gone. On a
  /// Samsung TV, SystemNavigator.pop is the app's exit() (ui_app_exit in flutter-tizen).
  Future<void> _leaveApp() async {
    if (_leaving) return;
    _leaving = true;
    await LivePlayers.releaseAll();
    debugPrint('leaving the app');
    await SystemNavigator.pop();
    _leaving = false;
  }

  void _submitSearch(String q) {
    if (q.trim().isEmpty) return;
    // On a TV the results take focus once they load.
    if (isTv) _searchFocus.unfocus();
    go(SearchDest(q.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final needsSetup = app.loaded && !app.settings.plexReady;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyF, control: true): _FocusSearchIntent(),
          SingleActivator(LogicalKeyboardKey.slash): _SlashSearchIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _BackIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonB): _BackIntent(),
        },
        child: Actions(
          actions: {
            _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(onInvoke: (_) => _searchFocus.requestFocus()),
            _SlashSearchIntent: _SlashSearchAction(_searchFocus),
            _BackIntent: CallbackAction<_BackIntent>(
              onInvoke: (_) {
                _back();
                return null;
              },
            ),
          },
          child: ShellNav(
            go: go,
            push: push,
            back: back,
            child: BackdropScope(
              controller: _backdrop,
              child: Scaffold(
                body: BackdropGroup(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ListenableBuilder(
                        listenable: _backdrop,
                        builder: (_, _) => AmbientBackdrop(imageUrl: _backdrop.url),
                      ),
                      !app.loaded
                          ? const SizedBox()
                          : needsSetup
                          ? Padding(
                              padding: const EdgeInsets.only(top: _chromeHeight),
                              child: _WelcomeFocus(scope: _welcome, child: const SettingsPage(welcome: true)),
                            )
                          : Actions(
                              // Left from the edge of a page opens the rail; Up from its top goes to search.
                              actions: {DirectionalFocusIntent: _EdgeAction(left: () => _rail.currentState?.enter(), up: _toSearch, empty: _toPage)},
                              child: FocusTraversalGroup(
                                policy: TvTraversalPolicy(),
                                child: Navigator(
                                  key: _nav,
                                  routeDirectionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop,
                                  onGenerateInitialRoutes: (_, _) => [_route(_top)],
                                  observers: [
                                    pageRoutes,
                                    pageStack,
                                    _TopTracker((d) {
                                      if (d.railId.isNotEmpty && d.railId != _top.railId) setState(() => _top = d);
                                    }),
                                    _pages,
                                  ],
                                ),
                              ),
                            ),
                      // No bar: search and the window buttons float over the page.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        // No search before sign-in: there's nothing to search yet, and on a TV the pill was a
                        // focus trap above the welcome page.
                        child: _TopChrome(search: _search, searchFocus: _searchFocus, searchButton: _searchButton, onSearch: _submitSearch, toPage: _toPage, showSearch: !needsSetup),
                      ),
                      if (_toasts.isNotEmpty)
                        Positioned(
                          right: Space.space6,
                          bottom: Space.space6,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Keyed on the row itself, so a newcomer doesn't restart the others.
                              for (final t in _toasts.reversed.take(3))
                                Padding(
                                  key: ValueKey(switch (t) {
                                    RequestRow r => 'ready:${r.request.id}',
                                    UpdateInfo u => 'update:${u.version}',
                                    _ => 'invite:${(t as _Invite).room.id}',
                                  }),
                                  padding: const EdgeInsets.only(top: Space.space3),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: 1),
                                    duration: const Duration(milliseconds: 420),
                                    curve: Curves.easeOutCubic,
                                    builder: (_, v, child) => Opacity(
                                      opacity: v,
                                      child: Transform.translate(offset: Offset(60 * (1 - v), 0), child: child),
                                    ),
                                    child: _toast(t),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (!needsSetup)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: _Rail(key: _rail, app: app, current: _top.railId, go: go, leave: _toPage, toSearch: _toSearch, profiles: _profiles),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The welcome (sign-in) page's focus scope. On a TV it makes sure one of its controls has
/// focus once it is on screen, as [_PageFocus] does for routed pages: the Sign In button's
/// autofocus alone wasn't always enough (Fire TV).
class _WelcomeFocus extends StatefulWidget {
  const _WelcomeFocus({required this.scope, required this.child});
  final FocusScopeNode scope;
  final Widget child;

  @override
  State<_WelcomeFocus> createState() => _WelcomeFocusState();
}

class _WelcomeFocusState extends State<_WelcomeFocus> {
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    if (!isTv) return;
    for (final ms in const [200, 700, 1500, 3000]) {
      _timers.add(Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        final p = FocusManager.instance.primaryFocus;
        // Something on the page already has focus (the user may have moved): leave it.
        if (p != null && p != widget.scope && p.ancestors.contains(widget.scope)) return;
        // A dialog or another route has focus: leave it too.
        if (p != null && !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        (_firstIn(widget.scope) ?? widget.scope).requestFocus();
      }));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(node: widget.scope, child: widget.child);
}

/// "/" jumps to search, except while typing, when it's just a slash (a server address, "AC/DC").
class _SlashSearchIntent extends Intent {
  const _SlashSearchIntent();
}

class _SlashSearchAction extends Action<_SlashSearchIntent> {
  _SlashSearchAction(this.node);
  final FocusNode node;

  @override
  bool isEnabled(_SlashSearchIntent intent) => FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() == null;

  @override
  Object? invoke(_SlashSearchIntent intent) {
    node.requestFocus();
    return null;
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _LeaveRailIntent extends Intent {
  const _LeaveRailIntent();
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// Keeps the rail highlight right when the user goes back.
/// The first control on a page, in reading order.
///
/// The topmost control on screen (leftmost of a row), not Flutter's first focus: that returns
/// whatever the page last had focused, which after Back to Home on the Shield was sometimes a
/// card far down the page, so claiming focus "at the first control" landed it there again.
FocusNode? _firstIn(FocusScopeNode scope) {
  final ctx = scope.context;
  if (ctx == null) return null;
  final height = MediaQuery.maybeSizeOf(ctx)?.height ?? double.infinity;
  FocusNode? best;
  for (final n in scope.traversalDescendants) {
    if (n is FocusScopeNode || n.context?.mounted != true) continue;
    final r = n.rect;
    if (r.isEmpty || r.bottom <= 0 || r.right <= 0 || r.top >= height) continue;
    if (best == null || _above(r, best.rect)) best = n;
  }
  if (best != null) return best;
  final policy = FocusTraversalGroup.maybeOf(ctx) ?? ReadingOrderTraversalPolicy();
  final first = policy.findFirstFocus(scope);
  return first == scope ? null : first;
}

/// [a] comes before [b] reading down the screen: higher up, or level with it and further left.
bool _above(Rect a, Rect b) => (a.top - b.top).abs() > 16 ? a.top < b.top : a.left < b.left;

/// Focuses the first control in [scope] when nothing in it has focus yet.
void _focusFirst(FocusScopeNode scope) {
  if (scope.focusedChild == null) _firstIn(scope)?.requestFocus();
}

/// Keeps track of the page on top. On a TV something must always have focus, or the remote
/// does nothing visible, so each new page focuses its first control once it has loaded (pages
/// that load data get a few tries).
class _PageFocus extends NavigatorObserver {
  ModalRoute<dynamic>? current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) current = route;
    _settle(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute is ModalRoute) current = previousRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == current && previousRoute is ModalRoute) current = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is ModalRoute && oldRoute == current) current = newRoute;
    if (newRoute != null) _settle(newRoute);
  }

  void _settle(Route<dynamic> route) {
    if (!isTv || route is! ModalRoute) return;
    FocusNode? picked;
    for (final ms in const [200, 700, 1500, 3000, 5000]) {
      Timer(Duration(milliseconds: ms), () {
        final ctx = route.subtreeContext;
        if (!route.isCurrent || ctx == null || !ctx.mounted) return;
        final scope = FocusScope.of(ctx);
        final primary = FocusManager.instance.primaryFocus;
        // Still on the control we picked (nobody has pressed anything): pick again, as the
        // page may have loaded something better placed since.
        if (picked != null && primary == picked) {
          picked = _firstIn(scope) ?? picked;
          picked!.requestFocus();
          return;
        }
        // Leave the rail and search alone if the user has gone there meanwhile.
        if (primary != null && primary is! FocusScopeNode && !primary.ancestors.contains(scope)) return;
        if (scope.focusedChild != null && scope.focusedChild!.context?.mounted == true) return;
        picked = _firstIn(scope);
        picked?.requestFocus();
      });
    }
  }
}

/// Arrow keys and the D-pad as usual, but Left with nothing further left opens the rail, and
/// Up with nothing further up goes to search.
class _EdgeAction extends DirectionalFocusAction {
  _EdgeAction({required this.left, required this.up, required this.empty});
  final VoidCallback left;
  final VoidCallback up;
  final VoidCallback empty;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return;
    if (intent.ignoreTextFields && node.context?.widget is EditableText) return;
    // Nothing on the page has focus (it went with a page that closed): any arrow picks its
    // first control, rather than whatever lies furthest that way.
    if (node is FocusScopeNode && node.focusedChild == null) {
      empty();
      return;
    }
    final moved = node.focusInDirection(intent.direction);
    if (!moved && intent.direction == TraversalDirection.left) left();
    if (!moved && intent.direction == TraversalDirection.up) up();
  }
}

class _TopTracker extends NavigatorObserver {
  _TopTracker(this.onTop);
  final void Function(Dest) onTop;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final d = previousRoute?.settings.arguments;
    if (d is Dest) WidgetsBinding.instance.addPostFrameCallback((_) => onTop(d));
  }
}

/// Height of the floating strip at the top: drag area, search and window buttons.
const _chromeHeight = 44.0;

class _TopChrome extends StatelessWidget {
  const _TopChrome({required this.search, required this.searchFocus, required this.searchButton, required this.onSearch, required this.toPage, this.showSearch = true});
  final bool showSearch;
  final TextEditingController search;
  final FocusNode searchFocus;
  final FocusNode searchButton;
  final ValueChanged<String> onSearch;
  final VoidCallback toPage;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _chromeHeight + 28,
    child: Stack(
      children: [
        // A soft shade keeps the buttons readable over bright art without drawing a bar.
        if (Theme.of(context).brightness == Brightness.dark)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Color(0x00000000)]),
              ),
              child: SizedBox.expand(),
            ),
          ),
        SizedBox(
          height: _chromeHeight,
          child: Row(
            children: [
              Expanded(child: customTitleBar ? const DragToMoveArea(child: SizedBox.expand()) : const SizedBox()),
              if (showSearch) _SearchBox(controller: search, focus: searchFocus, button: searchButton, onSubmit: onSearch, toPage: toPage),
              const SizedBox(width: Space.space3),
              if (customTitleBar) const WindowButtons(height: _chromeHeight) else const SizedBox(width: Space.space3),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Frosted, see-through search pill; it widens while you type. On a TV it is a button first:
/// the D-pad stops on it (outlined, not typing yet), Select opens the keyboard, Down goes back
/// to the page.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.focus, required this.button, required this.onSubmit, required this.toPage});
  final TextEditingController controller;
  final FocusNode focus;
  final FocusNode button;
  final ValueChanged<String> onSubmit;
  final VoidCallback toPage;

  @override
  Widget build(BuildContext context) {
    final box = _pill(context);
    if (!isTv) return box;
    return FocusPanel(
      onEdge: (d) {
        if (d == TraversalDirection.down) toPage();
      },
      child: Focusable(
        focusNode: button,
        semanticLabel: 'Search',
        onTap: focus.requestFocus,
        builder: (_, _, _) => box,
      ),
    );
  }

  Widget _pill(BuildContext context) {
    final c = context.c;
    final fx = context.fx;
    return ListenableBuilder(
      listenable: Listenable.merge([focus, button]),
      builder: (context, _) {
        final on = focus.hasFocus || button.hasPrimaryFocus;
        final pill = AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: on ? 360 : 260,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Space.space3),
          decoration: BoxDecoration(
            color: on ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(Radii.radiusFull),
            border: Border.all(color: on ? c.primary : Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: Colors.white.withValues(alpha: on ? 0.9 : 0.7)),
              const SizedBox(width: Space.space2),
              Expanded(
                child: _tvKeys(
                  TextField(
                  controller: controller,
                  focusNode: focus,
                  onSubmitted: onSubmit,
                  textInputAction: TextInputAction.search,
                  style: ConsoleText.body.copyWith(color: Colors.white),
                  cursorColor: c.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search movies and shows',
                    hintStyle: ConsoleText.body.copyWith(color: Colors.white.withValues(alpha: 0.6)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
                ),
              ),
            ],
          ),
        );
        if (!fx.glass) return pill;
        return ClipRRect(
          borderRadius: BorderRadius.circular(Radii.radiusFull),
          child: BackdropFilter.grouped(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: pill),
        );
      },
    );
  }

  /// On a TV, Enter or Select while typing searches: the keyboard (or the phone-remote bridge)
  /// may send a plain Enter rather than its Search action. Space stays a space: the search
  /// pill's button would take it as a press otherwise, and the keyboard never saw it.
  Widget _tvKeys(Widget field) {
    if (!isTv) return field;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): DoNothingAndStopPropagationTextIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _SubmitSearchIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _SubmitSearchIntent(),
        SingleActivator(LogicalKeyboardKey.select): _SubmitSearchIntent(),
      },
      child: Actions(
        actions: {
          _SubmitSearchIntent: CallbackAction<_SubmitSearchIntent>(
            onInvoke: (_) {
              if (controller.text.trim().isNotEmpty) onSubmit(controller.text);
              return null;
            },
          ),
        },
        child: field,
      ),
    );
  }
}

class _SubmitSearchIntent extends Intent {
  const _SubmitSearchIntent();
}

/// Minimise / maximise / close for the custom Windows title bar.
/// Wider than the design system's 44px rail so the icons read at a glance.
const _railWidth = 64.0;

/// The sidebar hides off the left edge and slides in when the pointer reaches the edge
/// (or keyboard / remote focus moves into it), over the page rather than beside it.
class _Rail extends StatefulWidget {
  const _Rail({super.key, required this.app, required this.current, required this.go, required this.leave, required this.toSearch, required this.profiles});
  final AppState app;

  /// Opens "Who's watching?".
  final VoidCallback profiles;
  final String current;
  final void Function(Dest) go;

  /// Back to the page (Right or Back from the rail).
  final VoidCallback leave;

  /// Up from the top of the rail.
  final VoidCallback toSearch;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  bool _open = false;
  bool _focused = false;
  Timer? _close;
  final _nodes = <String, FocusNode>{};
  FocusNode _node(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'rail:$id'));

  bool get hasFocus => _focused;

  /// Opens the rail with the current page's button focused (from the D-pad).
  void enter() {
    _show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = _nodes[widget.current] ?? _node('home');
      if (mounted) n.requestFocus();
    });
  }

  void _show() {
    _close?.cancel();
    if (!_open) setState(() => _open = true);
  }

  void _hideSoon() {
    _close?.cancel();
    _close = Timer(const Duration(milliseconds: 450), () {
      if (mounted && !_focused) setState(() => _open = false);
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _go(Dest d) {
    widget.go(d);
    _hideSoon();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = widget.app;
    Widget item(String id, IconData icon, String label, Dest d, {int badge = 0, bool alert = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.space1),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Focusable(
          onTap: () => _go(d),
          focusNode: _node(id),
          semanticLabel: label,
          // Ringed whenever it has focus: Flutter's focus highlight didn't show in the rail on the Shield.
          builder: (context, hover, focus) => ListenableBuilder(
            listenable: _node(id),
            builder: (context, _) => _RailIcon(icon: icon, on: widget.current == id, hover: hover, focus: focus || _node(id).hasPrimaryFocus, badge: badge, alert: alert),
          ),
        ),
      ),
    );
    // A button that does something rather than going somewhere.
    Widget action(String id, IconData icon, String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.space1),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Focusable(
          onTap: () {
            onTap();
            _hideSoon();
          },
          focusNode: _node(id),
          semanticLabel: label,
          builder: (context, hover, focus) => ListenableBuilder(
            listenable: _node(id),
            builder: (context, _) => _RailIcon(icon: icon, on: false, hover: hover, focus: focus || _node(id).hasPrimaryFocus),
          ),
        ),
      ),
    );
    // Who's watching: their avatar, which opens the Plex Home's profiles.
    Widget profile() {
      final who = app.profile;
      final label = who == null ? 'Switch Profile' : 'Watching as ${who.name}. Switch Profile';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.space1),
        child: Tooltip(
          message: label,
          preferBelow: false,
          child: Focusable(
            onTap: () {
              _hideSoon();
              widget.profiles();
            },
            focusNode: _node('profile'),
            semanticLabel: label,
            builder: (context, hover, focus) => ListenableBuilder(
              listenable: _node('profile'),
              builder: (context, _) {
                final ring = focus || _node('profile').hasPrimaryFocus;
                return SizedBox(
                  width: _railWidth,
                  height: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ring ? c.primary : (hover ? c.border300 : Colors.transparent), width: 2),
                      ),
                      child: who == null ? const Icon(LucideIcons.usersRound, size: 24) : ProfileAvatar(user: who, size: 34),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    Widget rule() => Container(
      width: 24,
      height: 1,
      color: c.border200,
      margin: const EdgeInsets.symmetric(vertical: Space.space2),
    );
    final fx = context.fx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The main group sits in the middle of the rail; Settings is on its own at the bottom.
    final main = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        item('home', LucideIcons.house, 'Home', const HomeDest()),
        // Trending and Requests come from Seerr: without one set up they'd only say so.
        if (app.settings.seerrReady) item('trending', LucideIcons.flame, 'Trending', const TrendingDest()),
        item('collections', LucideIcons.layers, 'Collections', const CollectionsDest()),
        // Not in the Samsung store build (AppState.tvNetworks).
        if (app.tvNetworks) item('tv-networks', LucideIcons.satelliteDish, 'TV Networks', const TvCollectionsDest()),
        item('moods', LucideIcons.sparkles, 'Moods', const MoodsDest()),
        action('shuffle', LucideIcons.shuffle, 'Shuffle Play', () => showShuffle(context)),
        item('channels', LucideIcons.radioTower, 'Channels', const ChannelsDest()),
        if (app.sections.isNotEmpty) rule(),
        for (final s in app.sections) item('library:${s.key}', s.type == 'show' ? LucideIcons.tv : LucideIcons.clapperboard, s.title, LibraryDest(s.key)),
        if (app.settings.seerrReady) ...[
          rule(),
          item('requests', LucideIcons.download, 'Requests', const RequestsDest(), badge: app.activeRequestCount),
        ],
      ],
    );
    final panel = Container(
      width: _railWidth,
      decoration: BoxDecoration(
        color: fx.glass ? (dark ? Colors.black.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.35)) : c.surface050.withValues(alpha: 0.92),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      padding: const EdgeInsets.only(top: Space.space3, bottom: Space.space3),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Center(
              child: Focusable(
                onTap: () => _go(const HomeDest()),
                focusNode: _node('logo'),
                semanticLabel: 'Home',
                builder: (_, _, focus) => ListenableBuilder(
                  listenable: _node('logo'),
                  builder: (_, _) => Container(
                    padding: const EdgeInsets.all(Space.space1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.radiusLg),
                      border: Border.all(color: focus || _node('logo').hasPrimaryFocus ? c.primary : Colors.transparent, width: 2),
                    ),
                    child: const ConsoleLogo(height: 26),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(child: SingleChildScrollView(child: main)),
          ),
          if ((app.homeList?.length ?? 0) > 1) profile(),
          item('settings', LucideIcons.settings, 'Settings', const SettingsDest(), alert: app.plexConn == Conn.failed),
        ],
      ),
    );
    return Focus(
      skipTraversal: true,
      onFocusChange: (f) {
        _focused = f;
        f ? _show() : _hideSoon();
      },
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _hideSoon(),
        hitTestBehavior: HitTestBehavior.translucent,
        // While hidden, only a thin strip at the edge listens for the pointer.
        child: SizedBox(
          width: _open ? _railWidth : 14,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // A faint handle hints that the rail is there.
              Positioned(
                left: 3,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _open ? 0 : 1,
                    child: Container(
                      width: 3,
                      height: 44,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: _open ? 0 : -_railWidth - 8,
                top: 0,
                bottom: 0,
                width: _railWidth,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _open ? 1 : 0,
                  // On a TV the hidden rail stays out of the D-pad's way until Left opens it.
                  child: ExcludeFocus(
                    excluding: isTv && !_open,
                    child: Shortcuts(
                      shortcuts: const {SingleActivator(LogicalKeyboardKey.arrowRight): _LeaveRailIntent()},
                      child: Actions(
                        actions: {_LeaveRailIntent: CallbackAction<_LeaveRailIntent>(onInvoke: (_) => widget.leave())},
                        // Down from Settings stays on Settings, rather than leaving for the page below.
                        child: FocusPanel(
                          onEdge: (d) {
                            if (d == TraversalDirection.up) widget.toSearch();
                          },
                          child: FocusTraversalGroup(policy: TvTraversalPolicy(), child: _frost(context, panel)),
                        ),
                      ),
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
}

/// A rail button: a soft glow and an accent bar mark where you are.
class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.icon, required this.on, required this.hover, required this.focus, this.badge = 0, this.alert = false});
  final int badge;

  /// A red dot, e.g. Settings when Plex can't be reached.
  final bool alert;
  final IconData icon;
  final bool on;
  final bool hover;
  final bool focus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ink = Theme.of(context).brightness == Brightness.dark ? Colors.white : c.text100;
    return SizedBox(
      width: _railWidth,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 3,
              height: on ? 24 : 0,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                boxShadow: [if (on) BoxShadow(color: c.primary.withValues(alpha: 0.7), blurRadius: 10)],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.radiusLg),
              color: on ? c.primaryTint : (hover ? c.surface200 : Colors.transparent),
              border: focus ? Border.all(color: c.primary, width: 2) : null,
              boxShadow: [if (on) BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 16)],
            ),
            child: AnimatedScale(
              scale: hover && !on ? 1.08 : 1,
              duration: const Duration(milliseconds: 150),
              child: Icon(icon, size: 24, color: on ? c.primary : (hover ? ink : ink.withValues(alpha: 0.75))),
            ),
          ),
          if (badge > 0 || alert)
            Positioned(
              right: 10,
              top: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: alert ? c.dangerFill : c.primaryFill, borderRadius: BorderRadius.circular(Radii.radiusFull)),
                child: Center(
                  child: Text(
                    alert ? '!' : '$badge',
                    style: ConsoleText.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: c.onPrimary, height: 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Blurs the backdrop behind window chrome when glass is on.
Widget _frost(BuildContext context, Widget child) {
  final fx = context.fx;
  if (!fx.glass) return child;
  return ClipRect(
    child: BackdropFilter.grouped(
      filter: ImageFilter.blur(sigmaX: fx.blur, sigmaY: fx.blur),
      child: child,
    ),
  );
}

/// Used by pages that need the platform for copy.
bool get isWindows => Platform.isWindows;

/// A Watch Together invitation, with the title when it's on our server.
class _Invite {
  _Invite(this.room, this.item);
  final TogetherRoom room;
  final PlexItem? item;
}
