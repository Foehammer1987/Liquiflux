import 'dart:ffi' show Abi;
import 'dart:io';

/// A desktop window (Windows, Linux, macOS): window_manager, the mouse, a title bar.
final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// The 10-foot TV layout and remote-control behaviour: every Android build (Shield, Google
/// TV, Fire TV), or a desktop dev build started with CONSOLE_TV=1 to try it out with the
/// arrow keys, Enter and Esc.
final bool isTv = Platform.isAndroid || Platform.environment['CONSOLE_TV'] == '1';

/// A 32-bit Android system: Fire TV sticks, budget boxes, and the 2019 Nvidia Shield Tube
/// (32-bit Android on a 64-bit chip). The app gets far less memory there, so
/// Home trailers (a second video player) stay off and the image cache is kept small.
final bool isLowMemoryTv = Platform.isAndroid && Abi.current() == Abi.androidArm;

/// Whether muted trailer clips may play behind the Home spotlight on this device.
final bool homeTrailersSupported = !isLowMemoryTv;
