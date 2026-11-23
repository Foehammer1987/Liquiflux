import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../platform.dart';

/// A native library the player is built from, and the license files that cover it
/// (assets/licenses, see docs/native-licenses.md).
typedef NativeLicense = ({String name, String note, List<String> files});

/// The native libraries in this build, for the Open-Source Licenses page. Flutter lists the
/// Dart packages and its own engine itself; these are the player's. None on a Samsung TV,
/// which plays through the TV's own player instead of mpv.
List<NativeLicense> nativeLicenses({bool? apple, bool? tizen}) {
  if (tizen ?? isTizen) return const [];
  // The Mac and iPhone builds carry media_kit's libmpv frameworks: FFmpeg there is
  // configured with --enable-version3 (for mbedTLS), so it is LGPL 3.
  final darwin = apple ?? (Platform.isMacOS || Platform.isIOS);
  return [
    (
      name: 'mpv',
      note: 'The video player. Built without its GPL parts, so it is under the GNU Lesser General Public License, version 2.1 or later. Source: https://github.com/mpv-player/mpv',
      files: const ['mpv.txt', 'LGPL-2.1.txt'],
    ),
    (
      name: 'FFmpeg',
      note: darwin
          ? 'Decodes audio and video. This build is under the GNU Lesser General Public License, version 3 or later (with mbedTLS), which is read together with the GNU General Public License, version 3. Source: https://ffmpeg.org'
          : 'Decodes audio and video. Under the GNU Lesser General Public License, version 2.1 or later. Source: https://ffmpeg.org',
      files: darwin ? const ['ffmpeg.txt', 'LGPL-3.0.txt', 'GPL-3.0.txt'] : const ['ffmpeg.txt', 'LGPL-2.1.txt'],
    ),
    if (darwin) ...[
      (name: 'Mbed TLS', note: 'Secure connections for the player. Apache License 2.0 (or GPL 2.0 or later).', files: const ['mbedtls.txt']),
      (name: 'dav1d', note: 'AV1 video decoding. BSD 2-clause license.', files: const ['dav1d.txt']),
      (name: 'libass', note: 'Styled subtitles. ISC license.', files: const ['libass.txt']),
      (name: 'HarfBuzz', note: 'Text shaping for subtitles. "Old MIT" license.', files: const ['harfbuzz.txt']),
      (name: 'FreeType', note: 'Fonts for subtitles. The FreeType License.', files: const ['FTL.txt']),
      (name: 'FriBidi', note: 'Right-to-left subtitle text. GNU Lesser General Public License, version 2.1 or later.', files: const ['LGPL-2.1.txt']),
      (name: 'uchardet', note: 'Finds the character set of subtitle files. Mozilla Public License 1.1.', files: const ['MPL-1.1.txt']),
      (name: 'libpng', note: 'PNG images. The libpng license.', files: const ['libpng.txt']),
      (name: 'libxml2', note: 'Reads XML (streaming manifests). MIT license.', files: const ['libxml2.txt']),
    ],
  ];
}

/// Adds [nativeLicenses] to Flutter's LicenseRegistry, read from the assets only when the
/// licenses page asks.
void registerNativeLicenses() {
  final libs = nativeLicenses();
  if (libs.isEmpty) return;
  LicenseRegistry.addLicense(() async* {
    for (final lib in libs) {
      final texts = [lib.note, for (final f in lib.files) await rootBundle.loadString('assets/licenses/$f')];
      yield LicenseEntryWithLineBreaks([lib.name], texts.join('\n\n'));
    }
  });
}
