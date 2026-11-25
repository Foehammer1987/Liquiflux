# Native library licenses

Kept in app/assets/licenses and shown on Settings > Advanced > Open-Source Licenses (app/lib/services/native_licenses.dart),
next to the Dart packages Flutter lists itself. Each file is the upstream project's own
license or copyright file, unchanged:

| File | From |
| --- | --- |
| mpv.txt | mpv-player/mpv `Copyright` |
| ffmpeg.txt | FFmpeg `LICENSE.md` |
| LGPL-2.1.txt, LGPL-3.0.txt, GPL-3.0.txt | gnu.org (LGPL 3 is read with GPL 3) |
| mbedtls.txt | Mbed-TLS/mbedtls `LICENSE` (Apache-2.0 or GPL-2.0-or-later) |
| dav1d.txt | videolan/dav1d `COPYING` |
| libass.txt | libass/libass `COPYING` |
| harfbuzz.txt | harfbuzz/harfbuzz `COPYING` |
| FTL.txt | FreeType `docs/FTL.TXT` |
| libpng.txt | pnggroup/libpng `LICENSE` |
| libxml2.txt | GNOME/libxml2 `Copyright` |
| MPL-1.1.txt | mozilla.org (uchardet is MPL 1.1 / GPL / LGPL; MPL 1.1 is used) |

The Mac and iPhone builds bundle media_kit's libmpv "video-default" frameworks
(libmpv-darwin-build v0.6.0): mpv built with -Dgpl=false, FFmpeg configured with
--enable-version3 (for mbedTLS), so FFmpeg is LGPL 3 there.

## LGPL: source and replacing the libraries

The decision (November 2026) is to keep these LGPL 3 builds. What the LGPL asks of us:

- **Source.** The exact sources are those of
  [libmpv-darwin-build v0.6.0](https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0)
  (`libmpv-xcframeworks_v0.6.0_{macos,ios}-universal-video-default.tar.gz`), which lists
  each library's version and download; mpv at https://github.com/mpv-player/mpv and
  FFmpeg at https://ffmpeg.org. The in-app licenses page names each project's home.
- **Replacing them.** The libraries ship as separate dynamic frameworks in
  `Liquiflux.app/Contents/Frameworks` (Mpv, Avcodec, Avformat, Avutil, ...), not linked
  statically. To rebuild with modified copies: build libmpv-darwin-build with your
  changes, point `MPV_XCFRAMEWORKS_VERSION`/the download in
  media_kit_libs_{macos,ios}_video's Makefile (or drop your xcframeworks in its
  `.cache/xcframeworks`) and run `flutter build macos` / `flutter build ios` in `app/`.

## Apple TV

The Apple TV build plays through AetherEngine (LGPL-3.0 with an App Store exception,
statically linked, pinned to one tag in `packages/liquiflux_aether/tvos/Package.swift`) and
FFmpegBuild's dynamic frameworks (FFmpeg under LGPL-2.1-or-later, dav1d, zimg, libzvbi),
with libdovi (MIT). Their texts are in `app/assets/licenses/` (`aetherengine.txt`,
`LGPL-2.1.txt`, `dav1d.txt`, `zimg.txt`, `libzvbi-ure.txt`, `libdovi.txt`) and the app lists
them on its Open-Source Licenses page (`appleTvLicenses` in
`app/lib/services/native_licenses.dart`). The FFmpeg frameworks stay dynamic, as the LGPL
asks. AetherEngine's optional TrueHD and DTS:X height components are not built in; turning
them on adds LibTrueHD (Apache-2.0) and, per AetherEngine's own documentation, possible
third-party patent licensing.
