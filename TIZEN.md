# Liquiflux on Samsung TVs (Tizen)

Liquiflux runs on Samsung smart TVs from 2021 on (Tizen 6.0 and later), built with Samsung's
[flutter-tizen](https://github.com/flutter-tizen/flutter-tizen). Samsung TVs from 2020 and
earlier can't run Flutter apps. The Samsung build is the same app as on Windows and Android TV:
the same Home, title pages, Seerr requests, Channels, X-Ray, Watch Together, Trakt and AniList.
What's different is below.

Status: first build (1.0.12). It compiles and its tests pass, but it has **not run on a Samsung
TV yet**. See [Testing](#testing) for what needs a real TV.

## What's different on a Samsung TV

- **Samsung's player.** There is no mpv on Tizen. Videos play through Samsung's own hardware
  player (AVPlay, via the [`video_player_avplay`](https://pub.dev/packages/video_player_avplay)
  plugin), drawn on the TV's video plane behind the app. `app/lib/services/avplay_player.dart`
  puts it behind media_kit's player API, so the player page, Skip Intro, Up Next, the sleep timer,
  Watch Together, X-Ray and Plex progress reports work as they do elsewhere.
- **What Plex converts.** Samsung TVs don't play DTS (2025 and 2026 sets say so outright) or
  TrueHD sound, or Dolby Vision. With a DTS or TrueHD track picked, Plex converts the sound and
  sends the picture as it is. Picture-based subtitles (PGS, VobSub) are burned in by Plex, as on
  the Android TV video plane. Text subtitles are drawn by the app, in the style set in Settings.
- **Settings that are mpv's** are hidden: Passthrough, Speakers, Night Mode, Volume Boost,
  Hardware Decoding, Deinterlace, High Quality Scaling, Debanding, mpv Options, Audio and
  Subtitle Delay, and Restyle Styled Subtitles. Picture Size (Fit, Fill, Stretch) stays.
- **No trailers on Home.** Trailers need mpv (and its YouTube support). Plex's own trailers on a
  title page still play.
- **No web links.** Buttons that only open a web page (Open in Plex, Open on IMDb, Open in Seerr,
  YouTube trailers and extras, the Trakt and AniList developer pages) are left out.
- **No updater.** Samsung's store updates the app. The Samsung build is a store build
  (`LIQUIFLUX_STORE=samsung`): no update check, no Updates panel.
- **Samsung's key rules.**
  - Return goes back a page. On Home it first goes to the top of Home, and from there it asks
    "Exit Liquiflux?" (No is focused; only Yes closes the app). Return on a popup closes it.
  - Exit closes the app from anywhere, including during playback. The app never handles it, so
    flutter-tizen closes the app.
  - Long-pressing Return isn't registered (the TV turns it into Exit).
  - Play, Pause, Play/Pause, Stop, Rewind, Fast Forward and the track keys work in the player as on
    Android TV. Number keys 0-9 in the player jump to 0-90% of the title. Colour keys, Channel
    Up/Down, Info and Guide aren't used and do nothing.
- **Network lost.** When the TV loses its network, playback stops (the place is saved, like Back),
  the player closes and a "No network connection" popup shows. It closes by itself once the
  connection is back, and Plex and Seerr are asked again straight away.
- **No screensaver while a video plays.** It may come on while paused.
- **Hidden and shown again** (another app, the Home button): Samsung's player pauses and picks up
  where it was.
- **Memory.** Samsung TVs are treated as low-memory TVs, like a Fire TV stick: smaller image
  caches, smaller artwork, and the pages behind the player let go of their pictures while a video
  plays.

## Build

The TPKs are built by GitHub Actions (`.github/workflows/tizen.yml`) on every pull request that
touches the app and on main. Each run uploads three packages as its artifacts:

| Package | TVs |
| --- | --- |
| `Liquiflux-<version>-tizen-6.0.tpk` | 2021 (Tizen 6.0) |
| `Liquiflux-<version>-tizen-6.5.tpk` | 2022 to 2025 (Tizen 6.5 to 9.0) |
| `Liquiflux-<version>-tizen-10.0.tpk` | 2026 (Tizen 10.0) |

There are three because Samsung's player plugin ships a native library per Tizen version. Each
gets its own package version: 1.0.12 ships as 1.0.1200, 1.0.1201 and 1.0.1202 (x.y.z becomes
x.y.(z×100 + n)), so every later release is still higher than every earlier one.

Without signing secrets, a run signs with a throwaway certificate: the build is checked, but those
TPKs install on no TV. See the top of `tizen.yml` for the four secrets that add your Samsung
certificate.

To build on a PC instead, install the [Tizen SDK](https://samsungtizenos.com/tools-download/) and
flutter-tizen (`git clone https://github.com/flutter-tizen/flutter-tizen`, add its `bin` to PATH),
the native packages for the groups you want (`IOT-Headed-6.0-NativeAppDevelopment-CLI`,
`IOT-Headed-6.5-NativeAppDevelopment-CLI`, `Tizen-10.0-NativeAppDevelopment-CLI`, and
`NativeToolchain-Gcc-9.2`), then run `tools/build-tizen.sh` (Git Bash or WSL on Windows). The
packages land in `dist/`.

## Certificates

Samsung TVs only install apps signed with a **Samsung** certificate. Make one in the Tizen SDK's
Certificate Manager: Create Samsung Certificate, TV, sign in with your Samsung account.

- **Author certificate**: identifies you as the app's author. **Back it up.** Every update must
  be signed with the same one, or the TV and the store treat it as another app.
- **Distributor certificate**: for installing on your own TV in developer mode, add the TV's
  DUID (it shows once the TV is connected). For the store, Seller Office takes a package signed
  with your author certificate and Samsung's public distributor certificate.

## Install on a Samsung TV (developer mode)

1. On the TV: open Apps, then App Settings (or the Apps panel's settings), and type `12345` on
   the remote. Turn Developer mode on, enter your PC's IP address, and restart the TV.
2. On the PC: `sdb connect <TV IP>` (the Tizen SDK's `sdb`, like `adb` for the Shield), then
   `sdb devices` shows the TV and its DUID.
3. Make the Samsung certificate with that DUID (above) and build, or have the workflow build with
   it.
4. `sdb install Liquiflux-1.0.12-tizen-6.5.tpk` (pick the package for the TV's year), or
   `flutter-tizen install` from `app/`.
5. Logs: `sdb dlog -v time ConsoleMessage` or `flutter-tizen logs`.

## Testing

What runs without a TV:

- `flutter test` covers the Samsung parts that are plain Dart: the package's id and privileges,
  the AVPlay address, what goes through Plex, the network watch, and the exit and network popups
  (`app/test/tizen_test.dart`).
- The Tizen TV emulator (Tizen SDK, TV 9.0 image) runs the app's screens, the remote and the
  popups, but **not video**: Samsung's player plugin isn't supported on the emulator.

What needs a real Samsung TV, or Samsung's [Remote Test Lab](https://developer.samsung.com/remote-test-lab)
if it lets you install your own TPK:

1. A film plays (direct play, MKV with HEVC and AC3/EAC3), with the token in the address.
2. Every audio track and every embedded subtitle track can be picked, and the right one plays.
   (The app matches Plex's track order to AVPlay's; this is the main thing to check.)
3. A DTS or TrueHD track plays through Plex with sound; a PGS subtitle burns in.
4. A transcode (a lower quality picked in the player) plays and seeks.
5. 4K HDR10 plays; memory holds up browsing Home after a film.
6. Back, Exit, the media keys and number keys during playback, while loading, and while paused.
7. Pulling the network cable: playback stops, the popup shows, and goes when it's back.
8. The Home button during a film, then back to Liquiflux: it picks up where it was.
9. No screensaver during a long film.
10. Launch time from the icon to Home (Samsung's limit is 10 seconds) on the oldest TV you can.

## Store (Seller Office)

The app is registered in Samsung TV Seller Office as "Liquiflux" (app ID 3202611050786, type
Tizen .NET Application, TPK). For a release, upload the three packages for their model groups
(2021 and later only), with the App Description file, a reviewer Plex account with a reachable
library, and a privacy policy URL. The store text should say "Works with Plex", carry the line
"Plex is a trademark of Plex, Inc. Liquiflux is not affiliated with or endorsed by Plex, Inc.",
and use no Plex logo or play-symbol icon.
