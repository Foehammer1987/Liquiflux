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
