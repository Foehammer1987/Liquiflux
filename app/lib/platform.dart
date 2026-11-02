import 'dart:ffi' show Abi;
import 'dart:io';

/// A desktop window (Windows, Linux, macOS): window_manager, the mouse, a title bar.
final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// The 10-foot TV layout and remote-control behaviour: every Android build (Shield, Google
/// TV, Fire TV), or a desktop dev build started with CONSOLE_TV=1 to try it out with the
/// arrow keys, Enter and Esc.
final bool isTv = Platform.isAndroid || Platform.environment['CONSOLE_TV'] == '1';

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
final bool isLowMemoryTv = Platform.isAndroid && (forceLowMemory || is32BitAndroid || lowMemoryRam(deviceRamMb));

/// Whether a 64-bit device with [ramMb] of RAM counts as low on memory.
bool lowMemoryRam(int? ramMb) => ramMb != null && ramMb < lowMemoryRamMb;

/// Whether muted trailer clips may play behind the Home spotlight on this device.
final bool homeTrailersSupported = !isLowMemoryTv;
