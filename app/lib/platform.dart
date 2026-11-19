import 'dart:ffi' show Abi;
import 'dart:io';

/// A Samsung TV (Tizen 6.0 and later, built with flutter-tizen). Dart sees Tizen as Linux, so
/// this is told apart by the variable flutter-tizen's own `isTizen` checks. The build differs
/// there: Samsung's player (AVPlay) instead of mpv, Samsung's Return and Exit key rules, no
/// self-updater. See TIZEN.md.
final bool isTizen = tizenEnvironment(Platform.environment);

/// Whether [env] is a Tizen app's environment.
bool tizenEnvironment(Map<String, String> env) => env.containsKey('TIZEN_API_VERSION');

/// Which Android build this is: 'mobile' for the phone and tablet one (built with
/// `--dart-define=LIQUIFLUX_FORM=mobile -P liquiflux.form=mobile`, see tools/build-android.ps1
/// -Mobile), empty for the TV one.
const formBuild = String.fromEnvironment('LIQUIFLUX_FORM');

/// A phone or tablet: touch first, no window, no remote. The Android phone/tablet build
/// ([formBuild] 'mobile'), an iPhone or iPad, or a desktop dev build started with
/// CONSOLE_TOUCH=1 to try the touch layout in a window.
///
/// Everything touch-specific asks this, never Platform.isAndroid, so the same layout serves
/// iOS. Phone or tablet is then a matter of screen size (see [compactWidth]).
final bool isTouch = touchBuild(android: Platform.isAndroid, ios: Platform.isIOS, flavor: formBuild, env: Platform.environment);

/// Whether a build with these traits is a phone/tablet one.
bool touchBuild({required bool android, required bool ios, required String? flavor, required Map<String, String> env}) =>
    ios || (android && flavor == 'mobile') || env['CONSOLE_TOUCH'] == '1';

/// Below this many logical pixels on the screen's short side a touch device gets the phone
/// layout (bottom bar, compact rows); from it up, the tablet one. Android's own phone/tablet
/// line (600 dp).
const compactWidth = 600.0;

/// A desktop window (Windows, Linux, macOS): window_manager, the mouse, a title bar.
final bool isDesktop = (Platform.isWindows || Platform.isLinux || Platform.isMacOS) && !isTizen && !isTouch;

/// The 10-foot TV layout and remote-control behaviour: every Android TV build (Shield, Google
/// TV, Fire TV), every Samsung TV, or a desktop dev build started with CONSOLE_TV=1 to try it
/// out with the arrow keys, Enter and Esc. Not the Android phone/tablet build ([isTouch]).
final bool isTv = (Platform.isAndroid || isTizen || Platform.environment['CONSOLE_TV'] == '1') && !isTouch;

/// The Android TV build (Shield, Google TV, Fire TV): the Android features only a TV has,
/// such as the accessibility sleep service, refresh-rate and resolution switching, leaving
/// with Back from Home.
final bool isAndroidTv = Platform.isAndroid && isTv;

/// A 32-bit Android system: Fire TV sticks on Fire OS 8, budget boxes, and the 2019 Nvidia
/// Shield Tube (32-bit Android on a 64-bit chip).
final bool is32BitAndroid = Platform.isAndroid && Abi.current() == Abi.androidArm;

/// The device's RAM in MB (MemTotal from /proc/meminfo), or null where it can't be read.
final int? deviceRamMb = _ramMb();

int? _ramMb() {
  if (!Platform.isAndroid && !Platform.isLinux) return null;
  try {
    return memTotalMb(File('/proc/meminfo').readAsStringSync());
  } catch (_) {
    return null;
  }
}

/// MemTotal from the text of /proc/meminfo, in MB.
int? memTotalMb(String meminfo) {
  final m = RegExp(r'^MemTotal:\s+(\d+) kB', multiLine: true).firstMatch(meminfo);
  return m == null ? null : int.parse(m.group(1)!) >> 10;
}

/// Below this much RAM a 64-bit Android TV is treated as low on memory too. A "2 GB" Fire TV
/// stick reports about 1.9 GB, a 3 GB box about 2.8 GB; 4 GB boxes report 3.6 GB or more.
const lowMemoryRamMb = 3300;

/// Set by the `lowmem` probe switch before anything reads [isLowMemoryTv], to try the
/// low-memory behaviour on a bigger device.
bool forceLowMemory = false;

/// A TV that gets far less memory than a desktop: every 32-bit Android system, and 64-bit
/// ones with under [lowMemoryRamMb] of RAM (most Fire TV sticks on Fire OS 14). There Home
/// trailers (a second video player) stay off, the image and graphics caches are kept small,
/// mpv reads ahead less, and the pages behind the player let go of their artwork while a
/// video plays. A cloud Fire TV on Fire OS 14 (64-bit, not counted before 1.0.4) grew from
/// 450 MB browsing to 798 MB playing a 1080p film.
/// Every Samsung TV counts too: Samsung warns that TVs run short of graphics memory quickly
/// and close apps in the background when memory runs low.
final bool isLowMemoryTv = (Platform.isAndroid && (forceLowMemory || is32BitAndroid || lowMemoryRam(deviceRamMb))) || isTizen;

/// Whether a 64-bit device with [ramMb] of RAM counts as low on memory.
bool lowMemoryRam(int? ramMb) => ramMb != null && ramMb < lowMemoryRamMb;

/// Whether muted trailer clips may play behind the Home spotlight on this device.
final bool homeTrailersSupported = !isLowMemoryTv;

/// Whether trailers can play at all: they need mpv (and its YouTube support), which Samsung
/// TVs don't have.
final bool trailersSupported = !isTizen;
