# Liquiflux on Android TV

One app for the Nvidia Shield, Google TV and stock Android TV devices, and Amazon Fire TV. It
needs Android 7.0 or later: every Shield, every Google TV, and Fire TV devices on Fire OS 6 or
later (Fire TV Stick 2nd gen and newer, Cube, 4K, 4K Max, Lite). The 2015/2016 Fire TV boxes on
Fire OS 5 are too old.

## Download

The easiest way: get the APK from the [latest release](https://github.com/Foehammer1987/Liquiflux/releases/latest).
`Liquiflux-android-tv-armeabi-v7a.apk` runs on every device; `Liquiflux-android-tv-arm64-v8a.apk` is a little
faster on 64-bit Google TV devices. Then install it with one of the ways under
[Install on the TV](#install-on-the-tv). With **Downloader** on the TV you can type the release link straight in.
Release APKs are signed with the same key every time, so each one installs as an update.

## Or build the APKs yourself

On your Windows PC, from the source folder:

```powershell
tools\build-android.ps1
```

The first run takes a while. It:

1. uses Android Studio's Java and Android SDK if you have it; if not, it installs Microsoft
   OpenJDK 17 with winget and the Android SDK into `%LOCALAPPDATA%\Android\Sdk`, and accepts
   the SDK licences;
2. makes a signing key in `%USERPROFILE%\.liquiflux`. **Back this folder up.** Every update
   must be signed with the same key, or you'll have to uninstall the app on each TV first;
3. builds two APKs into `dist\`:

| File | For |
| --- | --- |
| `Liquiflux-<version>-arm64-v8a.apk` | Chromecast with Google TV, most Google TV boxes and TVs, older Shields that accept it |
| `Liquiflux-<version>-armeabi-v7a.apk` | 2019 Nvidia Shield (Tube), Fire TV sticks and Cube, older or budget Android TV boxes, and any device where the arm64 one won't install |

If you're not sure, the `-Install` option below asks the TV and picks the right one. The 2019 Shield
Tube has a 64-bit chip but runs 32-bit Android, so the arm64 APK won't install on it.
On 32-bit Android, and on 64-bit TVs with less than about 3.3 GB of RAM (most Fire TV sticks), the
app runs in low-memory mode: it turns Home trailers off (Spotlight Only, an experimental mode in
Settings, plays one only while focus is on the spotlight's buttons), keeps a smaller artwork cache,
decodes artwork at no more than 1280 pixels wide, reads less video ahead, and shows video through the
TV's own video plane. While a video plays, the pages behind the player also put their artwork away
until you go back to them. The log says at launch whether the mode is on.

## Install on the TV

### Easiest: over the network from your PC

Turn on network debugging on the TV once (see your device below), then:

```powershell
tools\build-android.ps1 -Install 192.168.1.50
```

using your TV's IP address (Settings > Network on the TV). The first time, the TV asks to allow
debugging from your PC: tick **Always allow** and choose **Allow**. Updates install the same way
and keep your sign-in and settings.

To install an APK you already built without rebuilding, use adb directly:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb connect 192.168.1.50:5555
& $adb install -r dist\Liquiflux-<version>-armeabi-v7a.apk
```

### Nvidia Shield (2019 Tube or Pro)

1. Settings > Device Preferences > About: select **Build** seven times to unlock Developer options.
2. Settings > Device Preferences > Developer options: turn on **Network debugging**
   (on older firmware, **USB debugging** plus **Network debugging**).
3. Install from your PC as above. The Shield's IP is under Settings > Device Preferences > About > Status.

Without a PC: install **Downloader** (by AFTVnews) from the Play Store, allow it under Settings >
Device Preferences > Security & restrictions > Unknown sources, and open the APK from a link or
your network share. Or use **Send Files to TV** from a phone.

### Google TV (Chromecast with Google TV, Google TV sets)

1. Settings > System > About: select **Android TV OS build** seven times.
2. Settings > System > Developer options: turn on **USB debugging** (on Google TV this also
   allows network debugging).
3. Install from your PC as above.

Without a PC: install **Downloader** from the Play Store, then Settings > Apps > Security &
restrictions > Unknown sources > turn Downloader on.

### Stock Android TV boxes

Same as Google TV: Settings > Device Preferences > About > **Build** seven times, then Developer
options > **USB debugging**. Then install from your PC, or use Downloader as above.

### Fire TV (Stick, Stick 4K / 4K Max, Cube, Lite)

1. Settings > My Fire TV > About: select your device name seven times to show Developer options.
2. Settings > My Fire TV > Developer options: turn on **ADB debugging**, and set
   **Apps from Unknown Sources** (or **Install unknown apps** > Downloader) to on.
3. Install from your PC as above, using the IP from Settings > My Fire TV > About > Network.

Without a PC: install **Downloader** from the Amazon Appstore and open the armeabi-v7a APK in it.

Fire TV doesn't show sideloaded apps on the home row straight away: find Liquiflux under
**Your Apps & Channels** (hold the Home button > Apps) and move it to the front.

## Updates

From 1.0.1 Liquiflux checks GitHub for a new release when it starts and shows a card when there
is one; Settings > Advanced > Updates has the same. Choose **Update**: it downloads the APK for
your TV, checks its SHA-256 against the release, and checks it is signed with the same key as the
Liquiflux you have. The first time, Android opens the setting to allow installs from Liquiflux
(on the Shield: Settings > Apps > Security & restrictions > Unknown sources > Liquiflux); turn
it on, go back, and choose Update again. Android then asks you to confirm the update.

A copy installed from an app store is updated by that store, so it doesn't offer this.

## Measuring memory

For finding what takes the 2019 Shield's memory, the app takes switches from adb for one launch
and then logs its memory every second (lines starting `probe` in `adb logcat`):

```
adb shell am force-stop com.foehammer.liquiflux
adb shell am start -n com.foehammer.liquiflux/com.foehammer.console_app.Probe --es probe noglass,noblur,cover=25
```

Since 0.9.49 a release build only takes the switches through the `Probe` alias, which needs
the DUMP permission adb's shell has and other apps on the TV can't get, so no app can make
Liquiflux play a title or join a room by itself. Switches sent to `MainActivity` are ignored
(a debug build still takes them there).

| Switch | Effect |
| --- | --- |
| `on` | Logging only |
| `surface` | Flutter draws on its own surface instead of a transparent TextureView (the video picture is hidden then) |
| `blank` | A black screen and nothing else: the engine's own cost |
| `noart` | No artwork |
| `noglass` | Flat panels, as with Surfaces: Flat in Settings |
| `noblur` | No blurred art behind pages, no faded spotlight edge |
| `cache=N` | Skia's GPU cache capped at N MB while browsing (normally 64) |
| `nofree` | The player doesn't make Flutter free the artwork it put away (as in 0.9.11) |
| `noredraw` | The player doesn't draw the pages hidden behind it again without their artwork (as in 0.9.12) |
| `trailers` | Home trailers in Spotlight Only mode for this launch, whatever Settings says |
| `cover=T` | T seconds in, an empty page covers the app for 15 s, as the player does for 4K |
| `play=KEY` | 30 s in, opens Plex item KEY's title page, then 12 s later plays it from the start, muted; `play=4k` picks the first 4K movie, `play=way_of_water` the first 4K movie with those words in its title |

Each line has the TV's available memory, its graphics memory in use (`NvMapMemUsed`, for the
whole TV), Flutter's decoded images, and every few seconds the GPU buffers the app has mapped.
Graphics memory the app held shows as the drop when it is force-stopped.

## Match Frame Rate

Settings > Video > Match Frame Rate switches the TV to the video's frame rate while it plays
(23.976 Hz for most films, 25 or 50 for PAL, 29.97 or 59.94 for TV) and back when you leave the
player. It's on by default. Rate and Resolution also plays 1080p titles at 1080p, for TVs that
upscale better than the box does; SD and 720p still go to 1080p. Most TVs show a black screen for
a second or two as they switch; Liquiflux holds the start of the title until the picture is back.
The TV must offer the mode: on the Shield, the modes it lists depend on what the TV reports over
HDMI. The Shield's own "match frame rate" options don't need to be on for this.

## Trakt and AniList

Settings > Tracking connects them.

- **Trakt:** Connect Trakt shows a code and a QR code. Open trakt.tv/activate on your phone (or scan
  the code), enter it, and approve. The first time, Add Keys from My Phone: scan the QR code, and the page that opens on your phone takes your Trakt app's Client ID
  and Secret.
- **AniList:** Connect AniList shows a QR code. On the page it opens, tap Sign in to AniList,
  approve, copy the long token AniList shows, go back to the page and paste it. The phone must be
  on the same Wi-Fi as the TV. The page is served by the TV itself, at a random address, only while
  the QR code is on screen (15 minutes at most).

Movies and episodes scrobble to Trakt as you play, pause and stop them, and count as watched past
80%. Anime (Plex's "Anime" genre, or a library with anime in its name) also moves the AniList entry
forward when you finish an episode, never backwards, and leaves finished shows alone. Titles you
mark watched in Liquiflux go to both too.

## Using it with a remote

- **D-pad** moves between buttons and posters; **Select/OK** opens or plays. Left and Right stay
  in their row; Up straight after Down goes back to the card you came from. Controls you can't
  see (the thumbs on "Because You Watched" cards, which show for a mouse only) are skipped.
- **Left** at the edge of a page opens the menu; **Right** or **Back** closes it. Up and Down stay
  inside the menu.
- **Up** at the top of a page goes to search; **Select** there starts typing, **Down** or **Back**
  returns to the page.
- **Back** steps back through pages, then to Home, then to the top of Home, then leaves the app.
- In the player: **Left/Right** seek (hold to go faster), **Up/Down** show the controls,
  **Select** plays/pauses or presses Skip Intro / Up Next when they're showing, **Back** closes
  one thing at a time and then leaves the player. Media keys on the remote work too.
- **Sign In with Plex** shows a code: enter it at plex.tv/link on your phone or computer, or
  scan the QR code.
- In Settings, move onto a text field and press Select to type.

YouTube trailers need yt-dlp, which Android doesn't have, so only Plex's own trailers play there.
