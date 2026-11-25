import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart';
import 'platform.dart';
import 'services/channels.dart';
import 'services/doc_store.dart';
import 'services/gpu_memory.dart';
import 'services/native_licenses.dart';
import 'services/notifier.dart';
import 'services/probe.dart';
import 'services/safe_file.dart';
import 'services/settings_store.dart';
import 'services/trusted_roots.dart';
import 'state/app_state.dart';
import 'ui/nav.dart' show rootRoutes, rootStack, showHidden;
import 'ui/player/player_dock.dart';
import 'state/scope.dart';
import 'ui/back_key.dart';
import 'ui/intro.dart';
import 'ui/tv_focus.dart';
import 'ui/shell.dart';
import 'ui/touch.dart';

/// The status and navigation bars on a phone or tablet: see-through, with white text.
const touchOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  systemNavigationBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);

/// Windows draws its own charcoal title bar (the app bar doubles as one).
final bool customTitleBar = Platform.isWindows;

/// Everything the app (and Flutter, and media_kit) logs passes through [redactSecrets], so a
/// failed image or stream address never puts the Plex token or a key in the log.
void _redactLogs() {
  final plain = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => plain(message == null ? null : redactSecrets(message), wrapWidth: wrapWidth);
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
}

/// The logo animation at launch; the `nointro` probe switch leaves it out.
bool get _intro => !Probe.has('nointro');

Future<void> main() => runZoned(
  _main,
  // Packages' plain print() calls too.
  zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => parent.print(zone, redactSecrets(line))),
);

Future<void> _main() async {
  _redactLogs();
  // An Apple TV lays the app out on the TV canvas at the root instead of scaling it there.
  if (isTvOS) TvCanvasBinding();
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything goes out over https: trust only the app's own root list.
  await TrustedRoots.install();
  await Probe.init();
  // Before anything asks whether this is a low-memory TV.
  if (Probe.has('lowmem')) forceLowMemory = true;
  if (isTizen) debugPrint('Samsung TV, Tizen ${Platform.environment['TIZEN_API_VERSION']}, ${deviceRamMb ?? '?'} MB RAM');
  if (Platform.isAndroid) debugPrint('memory: ${deviceRamMb ?? '?'} MB RAM, ${is32BitAndroid ? '32' : '64'}-bit, low-memory mode ${isLowMemoryTv ? 'on' : 'off'}');
  if (Probe.has('blank')) {
    // The engine alone, for measuring what it costs.
    runApp(const ColoredBox(color: Color(0xFF000000)));
    return;
  }
  // mpv: there's none on a Samsung TV or an Apple TV, where the system player is used instead.
  if (playerIsMpv) MediaKit.ensureInitialized();
  registerNativeLicenses();
  // Android starts in touch mode, where Flutter hides the focus highlight until the first key
  // press (and hides it again after any touch): on a TV the first press moved focus you
  // couldn't see yet. A remote always shows where focus is.
  if (isTv) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  // Flutter keeps up to 100 MB of decoded artwork by default; a low-memory TV can't spare that.
  if (isLowMemoryTv) {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 48 << 20
      ..maximumSize = 300;
  }
  // Phones and tablets draw behind the status and navigation bars (Android 15 and later
  // insist on it); pages keep clear of them with the screen's padding. The status bar's
  // text is white in either theme, over the dark shade at the top of every page
  // (statusBarIconBrightness on Android, statusBarBrightness on iOS).
  if (isTouch) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    SystemChrome.setSystemUIOverlayStyle(touchOverlayStyle);
  }
  await GpuMemory.init();
  GpuMemory.showHidden = showHidden;
  if (isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1440, 900),
        minimumSize: const Size(960, 600),
        center: true,
        title: appName,
        backgroundColor: ConsoleColors.dark.surface000,
        titleBarStyle: customTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  // Lets a dev build load TMDB art from the mock server.
  final tmdbImages = Platform.environment['CONSOLE_TMDB_IMAGES'];
  if (tmdbImages != null) SeerrImages.base = tmdbImages;
  // An Apple TV may purge the app's files, so settings and channels go in user defaults there.
  final docs = isTvOS ? DefaultsDocStore(values: const TvosDefaults(), legacy: appDataDirectory) : null;
  final state = AppState(SettingsStore(forgetOnFreshInstall: isApple, docs: docs), channels: ChannelStore(docs: docs));
  if (_intro) await Intro.preload();
  runApp(ConsoleApp(state: state));
  await state.init();
  await Notifier.instance.init();
}

class ConsoleApp extends StatelessWidget {
  const ConsoleApp({super.key, required this.state});
  final AppState state;

  bool get _glass => state.settings.glass && !Probe.has('noglass');

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: ConsoleTheme.light(glass: _glass),
        darkTheme: ConsoleTheme.dark(glass: _glass),
        themeMode: state.settings.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
        navigatorObservers: [rootRoutes, rootStack],
        builder: (context, child) {
          // Left / Right stay in their row (see [TvTraversalPolicy]), on every platform.
          // On a desktop the player has a layer of its own over the app, to shrink into a
          // corner of (see [PlayerDock]).
          // On a phone the design system lays out compactly (see [TouchDensity]).
          final page = FocusTraversalGroup(policy: TvTraversalPolicy(), child: isTv ? TvCanvas(child: child!) : (PlayerDock.enabled ? PlayerDockHost(child: child!) : TouchDensity(child: child!)));
          return IntroGate(enabled: _intro, child: Platform.isAndroid ? BackKeyGuard(child: page) : page);
        },
        home: const Shell(),
      ),
    ),
  );
}

/// Apple TV: the root of the app is laid out at [TvCanvas.width] logical pixels and drawn at
/// the screen's full resolution, rather than at 1920 and scaled by [TvCanvas]'s FittedBox.
/// A scale transform there put the frosted-glass panels' blur (BackdropFilter) in the wrong
/// place under Impeller: the player's glass bars sat offset from their controls. With the
/// canvas set here, TvCanvas finds its box already 1440 wide and scales by 1. An Apple TV has
/// no pointer, so nothing reads touch positions against the platform's own pixel ratio.
class TvCanvasBinding extends WidgetsFlutterBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = ViewConfiguration.fromView(renderView.flutterView);
    final physical = view.physicalConstraints;
    if (!physical.hasBoundedWidth || physical.maxWidth <= 0) return view;
    final ratio = physical.maxWidth / TvCanvas.width;
    return ViewConfiguration(physicalConstraints: physical, logicalConstraints: physical / ratio, devicePixelRatio: ratio);
  }
}

/// Android TVs report 1920×1080 at a pixel ratio of 2, which leaves a 960-wide logical screen:
/// too cramped for the desktop layout (an Apple TV's is 1920 wide, which is too sparse). The app is laid out on a 1440-wide canvas instead and scaled
/// to fill the screen, so it looks the same from the sofa as on a desktop at 1440.
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});
  final Widget child;
  static const double width = 1440;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (!box.hasBoundedWidth || !box.hasBoundedHeight || box.maxWidth <= 0) return child;
      final scale = box.maxWidth / width;
      final size = Size(width, box.maxHeight / scale);
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          size: size,
          // Physical pixels per canvas pixel, however the scaling is done (here, or by
          // TvCanvasBinding before layout, where scale is 1).
          devicePixelRatio: View.of(context).physicalSize.width / width,
          // tvOS reports a TV-safe area (90 x 60 points at 1080p) as padding, and the pages
          // that keep clear of it (the player) then drew their scrims and glass in an inset
          // box over the full-screen video. The TV layout keeps its own margins, as on
          // Android TV, whose padding is zero.
          padding: isTvOS ? EdgeInsets.zero : mq.padding / scale,
          viewPadding: isTvOS ? EdgeInsets.zero : mq.viewPadding / scale,
          viewInsets: mq.viewInsets / scale,
          navigationMode: NavigationMode.directional,
        ),
        // Tight to the screen: FittedBox under loose constraints keeps the canvas's own size
        // when the screen is bigger than it (an Apple TV's 1920-wide logical screen, a large
        // CONSOLE_TV window), which left the app in the top-left three quarters.
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: size, child: child),
          ),
        ),
      );
    },
  );
}
