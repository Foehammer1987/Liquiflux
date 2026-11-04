import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform.dart';

/// Where the player lives on a desktop: on its own layer over the whole app, so it can shrink
/// into a corner (the mini player) and keep playing while the library is browsed behind it.
///
/// The layer has a navigator of its own. The player pages go there instead of on the app's
/// navigator, so the app under them stays mounted as it was: a full-window player just hides
/// it, the mini player shows it again. On a TV the player still opens on the app's navigator
/// (see [playerRoute]); nothing here runs there.
class PlayerDock extends ChangeNotifier {
  PlayerDock._();
  static final instance = PlayerDock._();

  /// Desktops only: a TV has no pointer to browse with while a corner of the screen plays.
  static bool get enabled => isDesktop;

  final navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'player dock');
  late final observer = _DockObserver(this);

  /// The pages over the dock's empty first one: the player, and anything it opened.
  final _routes = <Route<dynamic>>[];

  /// A player is open, full window or mini.
  bool get active => _routes.isNotEmpty;

  /// The player is in its corner.
  bool get mini => _mini && active;
  bool _mini = false;

  /// Which corner the mini player sits in; dragging it moves it to the nearest one.
  Alignment corner = Alignment.bottomRight;

  /// The page on top has finished coming in, so the app under it can stop being drawn.
  bool get settled => _settled;
  bool _settled = false;

  /// Plays in the dock: the player [builder] makes replaces any player already open there,
  /// which saves its place and stops as if it had been closed. Completes when it closes.
  Future<void> open(WidgetBuilder builder) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _setMini(false);
    await nav.pushAndRemoveUntil<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
      ),
      (r) => r.isFirst,
    );
  }

  /// Shrinks the player into its corner.
  void minimize() {
    if (active) _setMini(true);
  }

  /// Puts the mini player in [to], one of the four corners.
  void moveTo(Alignment to) {
    corner = to;
    notifyListeners();
  }

  /// Back to full window.
  void expand() => _setMini(false);

  /// Closes the player (and anything it opened), saving its place as Back would.
  void close() => navigatorKey.currentState?.popUntil((r) => r.isFirst);

  void _setMini(bool on) {
    if (_mini == on) return;
    _mini = on;
    notifyListeners();
  }

  void _changed() {
    if (!active) _mini = false;
    final top = _routes.lastOrNull;
    final animation = top is ModalRoute ? top.animation : null;
    _settled = active && (animation == null || animation.isCompleted);
    if (!_settled && animation != null) {
      void onStatus(AnimationStatus s) {
        if (s.isAnimating) return;
        animation.removeStatusListener(onStatus);
        if (_routes.lastOrNull == top) _changed();
      }

      animation.addStatusListener(onStatus);
    }
    notifyListeners();
  }
}

class _DockObserver extends NavigatorObserver {
  _DockObserver(this.dock);
  final PlayerDock dock;

  // The dock's own empty page is the only one pushed with nothing under it.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    dock._routes.add(route);
    dock._changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (dock._routes.remove(route)) dock._changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (dock._routes.remove(route)) dock._changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = dock._routes.indexOf(oldRoute!);
    if (i < 0) return;
    dock._routes[i] = newRoute!;
    dock._changed();
  }
}

/// The app with the player's layer over it (see [PlayerDock]).
class PlayerDockHost extends StatefulWidget {
  const PlayerDockHost({super.key, required this.child});

  /// The app: its navigator and everything on it.
  final Widget child;

  @override
  State<PlayerDockHost> createState() => _PlayerDockHostState();

  /// The mini player's size in a window [area] big: a quarter of the width, within reason, 16:9.
  static Size miniSize(Size area) {
    final w = (area.width * 0.26).clamp(300.0, 480.0).clamp(0.0, area.width - 2 * margin);
    return Size(w, w * 9 / 16);
  }

  /// Space between the mini player and the window's edges; more at the top, clear of the
  /// title bar, the search box and a title page's Back link.
  static const margin = 24.0;
  static const topMargin = 96.0;

  /// The mini player's place in [corner] of a window [area] big.
  static Rect miniRect(Size area, Alignment corner) {
    final s = miniSize(area);
    final left = corner.x < 0 ? margin : area.width - margin - s.width;
    final top = corner.y < 0 ? topMargin : area.height - margin - s.height;
    return Offset(left, top) & s;
  }

  /// The corner nearest to where a mini player at [rect], thrown at [velocity], comes to rest.
  static Alignment nearestCorner(Size area, Rect rect, Offset velocity) {
    // A flick carries it a little further, so a quick throw towards a corner gets there.
    final c = rect.center + velocity * 0.12;
    return Alignment(c.dx < area.width / 2 ? -1 : 1, c.dy < area.height / 2 ? -1 : 1);
  }
}

class _PlayerDockHostState extends State<PlayerDockHost> {
  final _dock = PlayerDock.instance;
  final _appScope = FocusScopeNode(debugLabel: 'app under the player');

  /// What had the keyboard in the app as the player opened, for it to have it back.
  FocusNode? _appFocus;
  bool _wasActive = false;
  bool _wasMini = false;

  /// The mini player is being dragged this far from its corner.
  Offset? _drag;

  /// The player's frame is moving between full window and its corner.
  bool _moving = false;

  /// The mini player is gliding into a corner after a drag.
  bool _glide = false;

  /// The player closed from its corner: the frame stays there while it fades out.
  bool _restInCorner = false;

  @override
  void initState() {
    super.initState();
    _dock.addListener(_changed);
  }

  @override
  void dispose() {
    _dock.removeListener(_changed);
    _appScope.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final active = _dock.active, mini = _dock.mini;
    // The player opened over the app: remember where the keyboard was.
    if (active && !_wasActive) {
      final f = FocusManager.instance.primaryFocus;
      _appFocus = f != null && f.ancestors.contains(_appScope) ? f : null;
    }
    // Going to or from the corner moves the frame; the app shows meanwhile.
    if (active && _wasActive && mini != _wasMini) _moving = true;
    // The app has the keyboard back once the player is in its corner or gone.
    final appKeys = (_wasActive && !_wasMini) && (!active || mini);
    final wasMini = _wasMini;
    _wasActive = active;
    _wasMini = mini;
    if (!active) {
      _drag = null;
      _glide = false;
      _moving = false;
    }
    setState(() {
      if (!active && wasMini) _restInCorner = true;
      if (active) _restInCorner = false;
    });
    if (appKeys) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (_dock.active && !_dock.mini)) return;
        final f = _appFocus;
        if (f != null && f.context?.mounted == true) {
          f.requestFocus();
        } else {
          _appScope.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final area = box.biggest;
      final active = _dock.active, mini = _dock.mini;
      // The app isn't drawn under a full-window player once it has come in, as it wouldn't
      // be on a navigator either; it keeps its state.
      final hideApp = active && !mini && _dock.settled && !_moving;
      final corner = PlayerDockHost.miniRect(area, _dock.corner);
      final inCorner = mini || (!active && _restInCorner);
      final rect = !inCorner ? Offset.zero & area : (_drag == null ? corner : corner.shift(_drag!));
      return Stack(
        children: [
          Positioned.fill(
            child: Offstage(
              offstage: hideApp,
              child: TickerMode(
                enabled: !hideApp,
                child: ExcludeFocus(
                  excluding: active && !mini,
                  child: FocusScope(node: _appScope, child: widget.child),
                ),
              ),
            ),
          ),
          AnimatedPositioned.fromRect(
            rect: rect,
            // Only between full window and the corner, and into a corner after a drag; a resized
            // window or a player opening puts it straight in place.
            duration: _moving || _glide ? const Duration(milliseconds: 320) : Duration.zero,
            curve: Curves.easeOutCubic,
            onEnd: () {
              if ((_moving || _glide) && mounted) {
                setState(() {
                  _moving = false;
                  _glide = false;
                });
              }
            },
            child: IgnorePointer(
              ignoring: !active,
              child: ExcludeFocus(
                excluding: !active || mini,
                child: GestureDetector(
                  onPanStart: mini ? (_) => setState(() => _drag = Offset.zero) : null,
                  onPanUpdate: mini ? (d) => setState(() => _drag = (_drag ?? Offset.zero) + d.delta) : null,
                  onPanEnd: mini
                      ? (d) {
                          final at = corner.shift(_drag ?? Offset.zero);
                          setState(() {
                            _drag = null;
                            _glide = true;
                            _dock.corner = PlayerDockHost.nearestCorner(area, at, d.velocity.pixelsPerSecond);
                          });
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(inCorner ? 14 : 0),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: inCorner ? 0.55 : 0), blurRadius: 40, offset: const Offset(0, 16))],
                    ),
                    // A hairline edge, over the picture so it doesn't inset it.
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(inCorner ? 14 : 0),
                      border: Border.all(color: Colors.white.withValues(alpha: inCorner ? 0.14 : 0)),
                    ),
                    child: HeroControllerScope.none(
                      child: Navigator(
                        key: _dock.navigatorKey,
                        observers: [_dock.observer],
                        onGenerateRoute: (_) => PageRouteBuilder<void>(
                          opaque: false,
                          pageBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
