import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../platform.dart';

/// A native library the player is built from, and the license files that cover it
/// (assets/licenses, see docs/native-licenses.md).
typedef NativeLicense = ({String name, String note, List<String> files});

/// The native libraries in this build, for the Open-Source Licenses page. Flutter lists the
/// Dart packages and its own engine itself; these are the player's. None on a Samsung TV,
/// which plays through Samsung's own player; AetherEngine and its libraries on an Apple TV.
List<NativeLicense> nativeLicenses({bool? apple, bool? tizen, bool? tvos}) {
  if (tizen ?? isTizen) return const [];
  if (tvos ?? isTvOS) return appleTvLicenses;
  // The Mac and iPhone builds carry media_kit's libmpv frameworks: FFmpeg there is
  // configured with --enable-version3 (for mbedTLS), so it is LGPL 3.
  final darwin = apple ?? isApple;
  return [
    (
      name: 'mpv',
      note: 'The video player. Built without its GPL parts, so it is under the GNU Lesser General Public License, version 2.1 or later. Source: https://github.com/mpv-player/mpv. To run Liquiflux with your own build, see docs/native-licenses.md in Liquiflux\'s source.',
      files: const ['mpv.txt', 'LGPL-2.1.txt'],
    ),
    (
      name: 'FFmpeg',
      note: darwin
          ? 'Decodes audio and video. This build is under the GNU Lesser General Public License, version 3 or later (with mbedTLS), which is read together with the GNU General Public License, version 3. Source: https://ffmpeg.org (this build: https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0). To run Liquiflux with your own build, see docs/native-licenses.md in Liquiflux\'s source.'
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

/// The Apple TV's player: AetherEngine (statically linked, LGPL 3 with an App Store
/// exception) and FFmpegBuild's dynamic frameworks, as FFmpegBuild's LICENSES lists them,
/// plus libdovi (MIT, quietvoid's notice). The optional TrueHD Atmos part (LibTrueHD) isn't
/// built in.
const appleTvLicenses = <NativeLicense>[
  (
    name: 'AetherEngine',
    note: 'The video player (7.73.0). GNU Lesser General Public License, version 3, with an App Store exception. Source: https://github.com/superuser404notfound/AetherEngine/tree/7.73.0',
    files: ['aetherengine.txt'],
  ),
  (
    name: 'FFmpeg',
    note: 'Decodes audio and video, as dynamic frameworks (FFmpegBuild 3.19.0, FFmpeg n8.1.3 with local patches). GNU Lesser General Public License, version 2.1 or later. Source and build: https://github.com/superuser404notfound/FFmpegBuild/tree/3.19.0',
    files: ['LGPL-2.1.txt'],
  ),
  (name: 'dav1d', note: 'AV1 video decoding. BSD 2-clause license.', files: ['dav1d.txt']),
  (name: 'zimg', note: 'Picture scaling and colour conversion. WTFPL.', files: ['zimg.txt']),
  (
    name: 'libzvbi',
    note: 'Teletext subtitles. GNU Lesser General Public License, version 2.0 or later (conveyed under 2.1), its GPL files removed; ure.c under the MIT license. Source and changes: https://github.com/superuser404notfound/FFmpegBuild/tree/3.19.0',
    files: ['LGPL-2.1.txt', 'libzvbi-ure.txt'],
  ),
  (name: 'libdovi', note: 'Reads Dolby Vision metadata. MIT license (dovi_tool by quietvoid and contributors).', files: ['libdovi.txt']),
];

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
