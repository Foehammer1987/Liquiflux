import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:console_core/console_core.dart';
import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart';
import 'platform.dart';
import 'services/gpu_memory.dart';
import 'services/notifier.dart';
import 'services/probe.dart';
import 'services/settings_store.dart';
import 'services/trusted_roots.dart';
import 'state/app_state.dart';
import 'ui/nav.dart' show rootRoutes, rootStack, showHidden;
import 'state/scope.dart';
import 'ui/back_key.dart';
import 'ui/intro.dart';
import 'ui/tv_focus.dart';
import 'ui/shell.dart';

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
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything goes out over https: trust only the app's own root list.
  await TrustedRoots.install();
  await Probe.init();
  // Before anything asks whether this is a low-memory TV.
  if (Probe.has('lowmem')) forceLowMemory = true;
  if (Platform.isAndroid) debugPrint('memory: ${deviceRamMb ?? '?'} MB RAM, ${is32BitAndroid ? '32' : '64'}-bit, low-memory mode ${isLowMemoryTv ? 'on' : 'off'}');
  if (Probe.has('blank')) {
    // The engine alone, for measuring what it costs.
    runApp(const ColoredBox(color: Color(0xFF000000)));
    return;
  }
  MediaKit.ensureInitialized();
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
  final state = AppState(SettingsStore());
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
          final page = FocusTraversalGroup(policy: TvTraversalPolicy(), child: isTv ? TvCanvas(child: child!) : child!);
          return IntroGate(enabled: _intro, child: Platform.isAndroid ? BackKeyGuard(child: page) : page);
        },
        home: const Shell(),
      ),
    ),
  );
}

/// TVs report 1920×1080 at a pixel ratio of 2, which leaves a 960-wide logical screen: too
/// cramped for the desktop layout. The app is laid out on a 1440-wide canvas instead and scaled
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
          devicePixelRatio: mq.devicePixelRatio * scale,
          padding: mq.padding / scale,
          viewPadding: mq.viewPadding / scale,
          viewInsets: mq.viewInsets / scale,
          navigationMode: NavigationMode.directional,
        ),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      );
    },
  );
}
