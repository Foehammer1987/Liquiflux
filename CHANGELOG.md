# Changelog

## 1.1.7

Liquiflux on the Mac, ready for the App Store, and server conversion that works there.

- **Mac app.** The first macOS build: a sandboxed, signed app with its own icon (the Windows and Android icon on Apple's grid), Entertainment category, a privacy manifest and the App Store's Info.plist keys. Sign-ins are kept in the Mac's keychain. Server discovery goes through plex.tv, so no Bonjour or multicast permission is needed.
- **App Store build** (`--dart-define=LIQUIFLUX_STORE=apple`): no TV Networks page, and no rows named after streaming services on Trending (Netflix's Top 10, "Popular on ..."), since Apple doesn't want other companies' brands in an app without their permission. Samsung's build keeps those rows.
- The in-app updater is off on every Apple platform: the App Store doesn't allow an app to fetch new code.
- **Settings > Advanced > About**: Open-Source Licenses (every package, plus the player's mpv and FFmpeg with their LGPL texts and where to get their source to rebuild Liquiflux with your own) and a Privacy Policy link. A TV shows the address and a QR code instead of opening a browser.
- **Sign in with a link code on a computer** too: *Use a Link Code* next to Sign In with Plex shows the plex.tv/link code a TV uses, for when the browser is on another device. A passing plex.tv error while waiting for the code no longer ends the sign-in, and a code that ran out shows as expired instead of "Not found (404)".
- **Server conversion on macOS and Linux.** A Plex server picks its client profile from the platform name, and for "macOS" and "Linux" that's Plex's own desktop apps' profile, so every conversion from Liquiflux failed (400 Bad Request, or a closed connection). There Liquiflux now asks for Plex's Generic profile and says what it plays (HLS with H.264, and EAC3, AC3 or AAC sound). Windows, Android and iOS keep the server's own profiles.
- Before converting, the player asks the server's decision and, when the server refuses, says so with its reason instead of "Failed to open". Going back to Original after a conversion waits for the server to end it first: Plex refuses the file itself (503) while the same client's conversion still runs.
- Playback Info no longer shows "((null))" after the codec or the decoder's name ("videotoolbox") as the colour format.
- Mac: leaving full screen puts the window back where it was. The Welcome page has no focus ring on a computer until a key is pressed.
- Home on an empty library says so instead of "Picking something good..." for ever.
- The keyring warning gives Linux advice only on Linux.
- For the Apple targets to come (iPhone, iPad, Apple TV): one `isApple` and `isTvOS` in platform.dart (an Apple TV is a TV, not touch), one `playerIsMpv` flag for the settings only mpv has, and an icon script that also makes separate back and front layers.
- Version 1.1.7+84 (Samsung packages 1.1.700, 1.1.701, 1.1.702).

## 1.1.6

Riptide shows who's in the scene, not just who's on camera that second.

- Riptide's *In This Scene* list and the pause screen now name everyone in the scene around the moment you paused: the people on screen right then come first, then the others in the same scene, nearest first. Before, it named only faces within a few seconds of the pause, so a pause on a cutaway, a reaction shot or an empty corridor often showed the whole cast instead. Someone stays listed between their shots (the back and forth of a conversation) and for about 15 seconds after they were last seen, and never past one of the title's chapter marks, which usually start a new scene.
- On the server's newly rescanned films someone is named at about 9 pauses in 10 (8 in 10 before); on films scanned by older versions of the scanner, 7 in 10 (4 in 10 before). 99% of the names shown are of people seen within 20 seconds of the pause.
- When the Riptide server can't be reached as a title starts (a restart, a moment of Wi-Fi trouble), Liquiflux tries again twice in the next few seconds, and after that again whenever you open Riptide, at most once a minute. Before, one failed try left the title with the cast list only until it was played again. A server that turns the account away isn't asked again.
- Works with every Riptide and X-Ray server and every timeline they have made, old and new. Nothing changes where there's no timeline: the cast list shows as before.
- Version 1.1.6+83 (Samsung packages 1.1.600, 1.1.601, 1.1.602).

## 1.1.5

TV: the remote moves row by row everywhere, and Settings is one column.

- Up and Down go to the nearest line of controls and never pass one over. They used to prefer a control straight above or below however far away it was, so Down from Settings' tabs jumped six settings to Skip Intro, and some controls (Theme, Clear Image Cache, a title's Play row once you had left it) couldn't be reached with Up and Down at all. This fixes Home's Top 10 rows, the Play and Request buttons on title pages, a show's season buttons and TV Networks' See All as well. A run of Up or Down moves keeps the column it started in.
- Settings on a TV: the categories are a column on the left (the one in focus opens; Right or Select enters it, Left comes back, Left again opens the rail) in place of tabs that wrapped onto two lines. Each setting is one full-width row that lights up edge to edge. Select flips a switch, presses a button, or opens the list of choices for a dropdown or a three-way choice such as Skip Intro. Buttons such as Save and Test and Sign Out are rows in the same column.
- The Settings page stays still until focus nears its top or bottom edge, instead of re-centring on every press.
- The player's Audio, Subtitles and Watch Together panels keep the remote's focus until Back closes them. Down used to walk out onto the seek bar with the panel still open.
- The focus ring is white on the dark theme (the text colour on the light one), so it shows on blue buttons, switches that are on and the chosen option of a segmented control.
- Home's spotlight page marks are no longer a stop for a remote.
- Desktop, phone and tablet layouts are unchanged apart from the focus ring's colour when moving by keyboard.
- Version 1.1.5+82 (Samsung packages 1.1.500, 1.1.501, 1.1.502). 1.1.4 is skipped; the Riptide gap-smoothing work will be 1.1.6.

## 1.1.3

Skipping forward while Plex converts a title no longer sends it back to the start.

- Player: when a title that Plex was transcoding had been resumed partway in, skipping or scrubbing to a part the player hadn't loaded (ahead past the few seconds read so far, or back) showed the wrong part of the film (the skip counted from the film's start, so 9:40 resumed and skipped to 11:06 showed 1:26) and the clock stopped. It then looked as if the film had started again, and the picture and the timeline no longer agreed. Plex restarts its transcoder for such a skip and loses the place the stream began. Liquiflux now starts a new transcode at the place you skipped to, with a short wait, and holds repeated presses for a moment so a held key makes one jump. A transcode that began at the film's start seeks as before. Seen on an older Fire TV, where more files need converting; reproduced on a Shield with Direct Play off. Titles that play directly were never affected.
- Version 1.1.3+80 (Samsung packages 1.1.300, 1.1.301, 1.1.302).

## 1.1.2

X-Ray is now **Riptide**: the same "who's on screen" panel, under a new name.

- The player button is *Riptide (R)*. X still opens it too. The pause screen hint and the panel say Riptide.
- Settings > Servers > **Riptide Server**, with *Use a Riptide Server* and *Riptide Server Address*.
- Existing settings carry over: the address and the switch saved by earlier versions (`xrayUrl`, `xrayEnabled` in settings.json) are read and saved again as `riptideUrl` and `riptideEnabled`.
- Works with X-Ray servers and Riptide servers alike. The sign-in and timeline API are unchanged.
- The server and desktop scanner are now [liquiflux-riptide-server](https://github.com/Foehammer1987/liquiflux-riptide-server) and [Liquiflux-riptide-ML-PC](https://github.com/Foehammer1987/Liquiflux-riptide-ML-PC).
- Version 1.1.2+79 (Samsung packages 1.1.200, 1.1.201, 1.1.202).

## 1.1.0

Liquiflux 1.1: phones and tablets. This release adds an Android build for phones and tablets with a touch layout, and rounds up everything since 1.0.14:

- Seerr and the X-Ray server became opt-in add-ons, so a Plex-only setup looks finished on its own (1.0.15).
- A Samsung TV build for the Samsung store, which leaves out TV Networks (1.0.16).
- On Fire TV and Android TV, the remote no longer gets stuck on the first-run sign-in page (1.0.18).
- Generic example addresses in Settings (1.0.19).

What's new in 1.1.0 (the Android TV build is unchanged):

- New phone/tablet build: `tools\build-android.ps1 -Mobile` (or `flutter build apk --dart-define=LIQUIFLUX_FORM=mobile --android-project-arg=liquiflux.form=mobile`). Same app id; its own manifest (`android/app/src/mobile/AndroidManifest.xml`): any orientation and resizable, picture-in-picture, Impeller, no leanback launcher, banner, sleep-timer accessibility service or 256 MB heap cap. Without the switch the build is the TV one, exactly as before. Forgejo CI builds both (`liquiflux-android-mobile` artifact, arm64).
- Phones (screen's short side under 600 dp): a bottom bar (Home, Search, Library, Collections, More) replaces the side rail; the More sheet holds Trending, TV Networks, Moods, Shuffle Play, Channels, Requests, Switch Profile and Settings. Home opens on a poster-sized spotlight you swipe through, with Play and More Info; rows, Top 10 numbers and page margins shrink to fit; libraries show three posters across; page headings stack. No Home trailer clips on phones (mobile data).
- Tablets: the desktop layout with the same bottom bar, edge to edge.
- Player on phones and tablets: turns landscape and full screen; tap shows or hides the controls; double-tap left or right to skip back or forward, the middle to pause; a picture-in-picture button, and going Home mid-video floats it (Android 8+). The volume slider is left to the device's buttons.
- The logo intro fits any screen: on portrait phones it sizes itself by the screen's width, so the logo and name stay whole and centred. Landscape screens and TVs look as before.
- README: a "Where it runs" section lists every platform (available now, in store review, coming soon) with the Roku Channel Store link and liquiflux.app.
- Releases (Forgejo and GitHub) now carry `Liquiflux-android-mobile-arm64-v8a.apk` next to the TV APKs, and the README and download guide list it. The phone/tablet build's updater takes that APK only, so it never turns itself into the TV build.
- `isTouch` in `platform.dart` (also true on iOS, for the coming iPhone/iPad build) decides the touch layout; `CONSOLE_TOUCH=1` tries it on a desktop. `isAndroidTv` now gates the sleep service, display mode switching and refresh-rate matching.
- Version 1.1.0+78 (Samsung packages 1.1.0, 1.1.1, 1.1.2).

## 1.0.19

Settings: example addresses in the Seerr/X-Ray fields now use generic hostnames (seerr.local, xray.local) instead of private-network IPs.

- Version 1.0.19+77.

## 1.0.18

Fire TV / Android TV: the remote no longer gets stuck on the search bar on the first-run sign-in page; search is hidden until Plex is set up, and the sign-in page always gets focus.

- Version 1.0.18+76.

## 1.0.16

The Samsung TV build leaves out TV Networks, for the Samsung store review: that page shows real network and block names and posters of shows you may not own. Every other platform is unchanged.

- Samsung TVs (`LIQUIFLUX_STORE=samsung`): no TV Networks item in the sidebar and no TV Networks page, no Networks & Blocks tab in Channels > Choose What Plays, and the collection pack is never read or fetched. `tools/build-tizen.sh` packs an empty collection pack into the TPKs, so no network or block names ship inside them.
- `AppState.tvNetworks` says whether TV Networks exist in a build (`tvNetworksInBuild` in `app_info.dart`, and never on Tizen).
- Version 1.0.16+74 (Samsung packages 1.0.1600, 1.0.1601, 1.0.1602).

## 1.0.15

Seerr and the X-Ray server are now add-ons you switch on, since they need a server of your own. Off (the default for a new install), Liquiflux is Plex alone and looks finished that way.

- Settings > Servers: a **Use Seerr** switch and a new **X-Ray Server** panel with a **Use an X-Ray Server** switch. The address, sign-in and Save and Test show once a switch is on. Off keeps what was entered, so switching back on picks up where it was.
- Updating from 1.0.14: an add-on with an address saved stays on, so nothing changes for anyone already using it.
- With Seerr off: no Trending or Requests in the sidebar, no Seerr rows on Home (Top 10 Not in Your Library, Because You Watched, Trending), no Notifications tab or Discovery panel in Settings, no "Seerr isn't set up" panel in search or "Connect Seerr" line on actor pages, no download badge or Seerr page on missing shows and films in collections, and no connection to Seerr at all.
- With the X-Ray server off: the player never contacts it and X-Ray shows the cast from Plex, without the note about the scanner.
- The first-run Welcome page is Plex sign-in only; add-ons are in Settings afterwards.
- Version 1.0.15+73 (Samsung packages 1.0.1500, 1.0.1501, 1.0.1502).

## 1.0.14

Builds on a self-hosted Forgejo, so day-to-day work doesn't depend on GitHub. No change to the app itself.

- `.forgejo/workflows/build.yml`: every pull request, push to `main` and Run workflow runs the tests (also as a TV) and builds the Android TV APKs for armeabi-v7a and arm64-v8a, with their SHA-256 sums, as the run's artifacts. Nothing is published.
- `.forgejo/workflows/tizen.yml`: the three Samsung TPKs, as on GitHub, with the Tizen 10.0 package name fixed (`TIZEN-10.0-NativeAppDevelopment-CLI`).
- A `windows` job builds the Windows zip and installer on a Windows runner (a PC in host mode; see `docs/CI.md`).
- The Tizen build runs as a normal user in CI (`tools/ci/tizen-build.sh`): Tizen's SDK installer refuses root.
- `tools/ci/setup-flutter.sh` sets up the pinned Flutter (checked against its SHA-256), JDK 17 and the Android SDK in an Ubuntu 24.04 container.
- `docs/CI.md` explains the two homes: Forgejo for development, GitHub for public releases (its workflows are unchanged), and the signing secrets for each.
- Version 1.0.14+72 (Samsung packages 1.0.1400, 1.0.1401, 1.0.1402).

## 1.0.13

Samsung TVs: fixes for what a store reviewer would trip over, from the App Description review of 1.0.12. Most of it helps every TV.

- Player keys: only the arrows, OK, the media keys and 0-9 bring the controls up (or end the pause screen). Colour keys, Channel Up/Down, Info and Guide now do nothing at all, as Samsung's rule asks for keys an app doesn't list.
- Exit: the remote's Exit key now closes the app during the launch animation and while the sleep timer's warning is up (both used to swallow the first press). flutter-tizen gives Exit no logical key, so it's told apart by its physical key.
- Playback Info on Samsung TVs is no longer an empty box: it shows Direct Play or Transcode, the file, the video and audio tracks from Plex, the subtitles (and when Plex burns them in), the picture size Samsung's player reports, and the speed.
- Speed on Samsung TVs: a speed the TV's player turns down now says "This TV can't play at N× speed" and the speed badge and chips keep showing the speed that's really playing.
- Samsung remotes: a long press of Rewind or Fast Forward (which the remote sends as Previous / Next track) now seeks back or forward instead of changing episode.
- Ready to Watch, Watch Together invitations and the update card: on a TV the card takes the remote's focus on its main button as it comes in (the arrows couldn't reach the corner from a page), Back closes it, and focus goes back where it was. Not while the player, a popup or a text field is in use. Ready to Watch stays 20 s on a TV.
- "Ask Who's Watching" now works at launch (it was checked before the settings had loaded).
- Trending and Requests are left out of the sidebar until Seerr is set up (they only said to connect Seerr).
- On a TV, Back from search results goes back to the page the search started on, not Home.
- Deleting a channel asks first (Cancel focused). The Request All popups on collection and TV network pages start with Cancel focused and scroll when the list is long.
- Wording: the Watch Together invitation for another server no longer says "Join from Plex Web"; the Watch Together sign-in error points to Plex Media Server's Sign In Again (not Seerr's My Plex Account); the secure-storage warning and the Flat surfaces hint have TV wording; the online subtitle note leaves out Subtitle Delay where it's hidden; the picture-subtitle "size and height still apply" note no longer shows when Plex burns them in.
- Checked in flutter-tizen's embedder: one Return press can't act twice there (it skips the route pop when the key-down was handled), so Android's BackKeyGuard isn't needed on Samsung TVs.
- Tests: `app/test/notice_toast_test.dart`, and new cases in `intro_test.dart` (Exit isn't swallowed), `player_remote_test.dart` (unused keys, Exit, long-press track keys) and `tizen_test.dart` (the confirm popup).
- Version 1.0.13+71 (Android versionCode 1071 for armeabi-v7a, 2071 for arm64-v8a; Samsung packages 1.0.1300, 1.0.1301, 1.0.1302).

## 1.0.12

Samsung TVs: a first Tizen build of Liquiflux, for Samsung TVs from 2021 on. Not yet tried on a Samsung TV (see TIZEN.md, Testing).

- Built with Samsung's flutter-tizen (3.47.5-tizen.1.0.1) as a TV app (`app/tizen/`, package `com.foehammer.liquiflux`, label "Liquiflux", internet privilege only). The new `tizen` workflow builds three signed TPKs per run, one per Tizen version group (6.0 for 2021, 6.5 for 2022-2025, 10.0 for 2026), with `tools/build-tizen.sh`; package versions are x.y.(z*100 + n), so 1.0.12 is 1.0.1200, 1.0.1201 and 1.0.1202.
- Video plays through Samsung's own player (AVPlay, `video_player_avplay`) on the TV's video plane. `services/avplay_player.dart` puts it behind media_kit's player API, so the player page and everything on it (resume, tracks, Skip Intro, Up Next, sleep timer, Watch Together, X-Ray, Plex progress) is shared with the other platforms. Plex's headers go in the stream address (AVPlay sends only Cookie and User-Agent). Text subtitles are drawn by the app; sidecar SRT and WebVTT files are read by the app.
- What Samsung TVs can't play goes through Plex: DTS and TrueHD sound (converted, picture untouched), picture-based subtitles (burned in), and VC-1. AV1 plays on the TV.
- Samsung's Return and Exit rules: Return on Home goes to the top of Home, then asks "Exit Liquiflux?" (No focused, only Yes exits); Return closes popups; Exit closes the app from anywhere. Media keys work in the player as on Android TV; colour, channel, Info and Guide keys do nothing.
- A "No network connection" popup when the TV loses its network (checked every 3 s from the TV's own interfaces): playback stops and the player closes first, and the popup closes itself when the network is back, when Plex and Seerr are asked again at once.
- No screensaver while a video plays (wakelock_plus_tizen).
- Hidden on Samsung TVs: mpv-only settings (Passthrough, Speakers, Night Mode, Volume Boost, Hardware Decoding, Deinterlace, High Quality Scaling, Debanding, mpv Options, audio and subtitle delay, Restyle Styled Subtitles), Home trailers, and buttons that only open a web page. Samsung TVs count as low-memory TVs.
- Store builds (`LIQUIFLUX_STORE`, now also Samsung) no longer check GitHub for updates or show the Updates panel.
- Plex trademark line ("Works with Plex. Plex is a trademark of Plex, Inc. ...") in Settings > Advanced and the README.
- Tests: `app/test/tizen_test.dart` (package manifest, AVPlay address, what goes through Plex, network watch, exit and network popups).
- Version 1.0.12+70 (Android versionCode 1070 for armeabi-v7a, 2070 for arm64-v8a).

## 1.0.11

TV Networks: shows by the channel or programming block they aired on, with the ones you're missing to request.

- A new TV Networks page in the sidebar (the satellite dish, under Collections), with a row for each programming block (Toonami, Adult Swim Originals, Adult Swim Anime, Nick at Nite, SNICK, Cartoon Cartoons, Fox Kids, Kids' WB, 4Kids TV, Jetix, Miguzi, The Disney Afternoon, One Saturday Morning, Animation Domination, Nicktoons) and, under Networks, for networks and streaming services (Adult Swim, Cartoon Network, Nickelodeon, Disney, HBO, FX, AMC, the broadcast networks, Netflix, Prime Video, Crunchyroll, TV Tokyo and more).
- What a row shows: every show of it in your library, best-rated first. While you have fewer than ten, the best-rated shows you're missing fill it up to ten; with ten or more, it's just yours. Missing shows are dimmed and open their Seerr page.
- See All opens the block's own page: what you have, the top-rated missing shows, Show All N Missing for the full list, and Request N Missing to ask Seerr for them in one go.
- Built for every library, not one server: the collections are lists of show ids (TMDB, TVDB, IMDb) that every install matches against its own Plex library, through the new Plex agents' ids, the legacy TheTVDB and TheMovieDB agents and HAMA's tvdb ids, and last by title and year.
- The lists come from Wikipedia's programme lists (blocks) and TVmaze (networks), with ids from Wikidata, built by `tools/collection-pack/build_pack.py` in the new Collection pack workflow (no API keys). It runs when its source list changes and on the 1st of each month; Liquiflux ships the latest pack and fetches a newer one from this repository at most once a day. `tools/collection-pack/sources.json` says which blocks and networks are in it; `report.md` lists what didn't match.
- Channels: a TV network or block can be a channel's source (the Networks & Blocks tab in the picker). The channel plays the shows of it you have, and picks up new ones as you add them.
- Tests: `packages/console_core/test/tv_collections_test.dart` (pack reading, matching, the ten-show rule, pack sources in channels) and `app/test/tv_networks_test.dart` (rows, the block page, Request Missing, with the remote under CONSOLE_TV=1); the D-pad walk covers both pages.
- Version 1.0.11+69 (Android versionCode 1069 for armeabi-v7a, 2069 for arm64-v8a).

## 1.0.10

Channels can mix several shows, collections, labels and libraries.

- A channel now draws from as many sources as you like, played as one pool: tick shows, collections, labels or whole libraries in the new picker (Add Shows and Collections in the channel editor). A show that's in two of them counts once. Each source has its own Remove button in the editor.
- The picker is made for the remote: tabs for Shows, Collections, Labels and Libraries (with counts), a Search box that narrows the list as you type, and a list where Select ticks or unticks a line. Done keeps the choice, Cancel leaves it as it was. Choosing bumpers uses the same picker, picking one.
- D-pad fix for every screen: Left or Right from a button under a scrolling list no longer jumps into a list row that's mostly hidden behind it (only the part of a row that shows counts as beside the button).
- Channels saved by 1.0.9 open with their one source; a channel saved by 1.0.10 still opens in 1.0.9 with its first source.
- `app/test/channels_tv_test.dart` (CONSOLE_TV=1) now builds a channel with key presses only: ticking four shows, scrolling far down the list, removing one, choosing bumpers, raising a show's share, saving, and editing it again with Search.
- Version 1.0.10+68 (Android versionCode 1068 for armeabi-v7a, 2068 for arm64-v8a).

## 1.0.9

Channels: shuffle rules that play like your own TV channel, bumpers and all.

- A new Channels page in the sidebar (the radio tower, under Shuffle Play). A channel plays random episodes from a Plex collection, a label, one show or a whole library, and keeps going like TV.
- Every show gets a fair turn by default: a channel picks a show, then one of its episodes, so The Simpsons' 800 episodes don't drown out a show with 50. Turn that off for a classic shuffle where every episode is equally likely. Each show can also be set higher or lower (from off to 12 times as often), and the editor shows each show's share as a percentage, so "Simpsons at 60%" is a few presses of +.
- Nothing repeats until that show has played every episode, and the same show never plays twice running while there's another to pick. Continue picks up on the episode you left, mid-episode; Start Fresh deals a new line-up but still remembers what's played.
- Bumpers: pick a show, collection or label of short clips (Adult Swim bumpers, say) and the channel plays one before the first episode and after every episode (or every 2, 3 or 4). Bumpers always play from the start, never show Skip Intro or Up Next, aren't counted by the sleep timer's "after N episodes", and are never reported to Plex (no watched marks, no Continue Watching), Trakt or AniList. An episode followed by a bumper plays out into it with no Up Next card. Clips filed as specials (season 0) are included for bumpers; a channel's own shows leave their specials out.
- Channels are kept per Plex server on this device (channels.json in the app's data folder), with what each has played.
- Everything works with the remote: the editor opens on its first choice and every control is reachable with the D-pad (`app/test/channels_tv_test.dart`, run with CONSOLE_TV=1).
- How: the shuffle is in `packages/console_core/lib/src/channels.dart` (rules, picker, progress, reading collections, labels, shows and libraries from Plex); the player gets the channel's line-up as its queue, which grows a few episodes ahead as it plays, and knows which places in it are bumpers (`app/lib/services/channels.dart`).
- Version 1.0.9+67 (Android versionCode 1067 for armeabi-v7a, 2067 for arm64-v8a).

## 1.0.8

A new, original Liquiflux logo, ready for app stores.

- The old mark looked like the Starfleet insignia, a trademark that would get Liquiflux turned away from the Amazon Appstore and other stores. The new one is an LF made of two ribbons of liquid: the L flows up into the F's top arm, and an outer layer peels off into the middle arm, in the app's blue.
- It's everywhere the old one was: the sidebar, Home's spotlight, the Settings welcome, the Android TV banner and launcher icons, the Windows icon (taskbar, Start, installer) and the README.
- A new startup animation, "flow": the two ribbons fly in twisting from opposite edges of the screen and lay themselves down into the LF, a shine runs across it, then the name surfaces as before. 3.6 s; any key or click still skips it.
- The Android launch screen is now plain dark grey (no faint logo), and the intro starts from that same empty screen.
- How: the logo is drawn from one vector source; `packages/console_ui/assets/logos/` holds mark-blue/white/navy and the two ribbons the intro uses (ribbon-1/2.png). The intro's flying ribbons are short lines along a precomputed route; the landed part is the ribbon image seen through a stroke along its centre line, in a layer only as big as the logo.
- Version 1.0.8+66 (Android versionCode 1066 for armeabi-v7a, 2066 for arm64-v8a).

## 1.0.7

A mini player on Windows: keep watching while you browse.

- The Mini Player button at the top of the player (or B) shrinks the title into a corner of the window, 16:9 and a quarter of the window wide (300 to 480 px). It keeps playing while you scroll the library, search and open pages behind it; nothing restarts, so audio, subtitles and position carry on.
- Hover it for Play / Pause, Expand and Close, with the title and time; a thin progress line runs along its bottom. Paused, the controls stay up. Drag it anywhere and it glides into the nearest corner (a flick carries it). Click the picture, or Expand, to go back to full window, with the keyboard shortcuts back on the player.
- Picking another title while it plays replaces it (its place is saved as when closing). Up Next carries on in the corner. An actor picked in X-Ray opens their page with the title still playing in the corner, instead of closing it. Switching profile closes it. Home's spotlight and its trailers hold still while a title plays.
- How: on desktop the player now opens on a layer of its own over the app, with its own navigator (`app/lib/ui/player/player_dock.dart`), instead of on the app's navigator. The app under a full-window player is kept but not drawn (Offstage, tickers off, no keyboard focus), as a covered page was before; the keyboard goes back to where it was when the player shrinks or closes. Android and Fire TV are unchanged: the player still opens on the app's navigator there.
- Also in this release: the 1.0.6 fix below (Watch Together lists Plex friends again), which wasn't released on its own.
- Version 1.0.7+65 (Android versionCode 1065 for armeabi-v7a, 2065 for arm64-v8a).

## 1.0.6

Watch Together with Plex friends works again.

- Inviting Plex friends failed with "Request failed (410)": plex.tv retired the friends list Liquiflux read (`/api/v2/friends` now answers 410 Gone for everyone). The list now comes from plex.tv's `/api/users` (XML, the same one python-plexapi and other Plex tools read), with the old one tried only if that fails. Only the `<User>` attributes (id, name, username, picture) are read, at most 500 people.
- If Plex ever answers 410 again, the panel says Plex has switched that part off and that room codes still work, instead of a bare status code.
- Version 1.0.6+64 (Android versionCode 1064 for armeabi-v7a, 2064 for arm64-v8a).

## 1.0.5

Plex Home profiles: a household can share the TV, each person with their own Plex.

- Who's watching: the people in your Plex Home (listed from plex.tv, `/api/v2/home/users`), each with their plex.tv picture or initials and a lock when they have a PIN. Open it from the avatar above Settings in the sidebar (shown once the Home has two or more people), from Settings > General > Plex Home, or as Liquiflux opens with Ask Who's Watching turned on (off by default; it closes itself when there's no Home or plex.tv can't be reached).
- A PIN pad for protected profiles, made for the remote (the digits are buttons; on a PC the number keys and Backspace work too). A wrong PIN shakes the dots and clears them; Back leaves the pad for the profiles.
- Switching asks plex.tv for that user's token (`/home/users/{uuid}/switch`), then for the server's token for them from plex.tv's resources, matched by the server's machine id. The server address stays; a user the server isn't shared with gets a clear message and nothing changes. Every page starts again from Home, so Continue Watching, Recently Added and watched marks are that person's.
- Per-person things: thumbs up/down (Because You Watched), spoiler settings, the Watch Together name and remembered audio/subtitle choices per show are put away when someone else takes over and come back when they return (settings.json, `profiles`). Trakt and AniList sign-ins are per person too (credential store, `scrobble_accounts_<uuid>`); the account that signed in to Plex keeps the existing ones. Seerr's Plex sign-in, Watch Together and the X-Ray server all sign in as the person watching.
- The signed-in account's plex.tv token is kept in the credential store (`plex_home_token`) while someone else is watching, so the Home can be listed and switched again; switching back to it asks for its PIN when it has one, as Plex's own apps do. Signing out or signing in again goes back to that account's own settings.
- Version 1.0.5+63 (Android versionCode 1063 for armeabi-v7a, 2063 for arm64-v8a).

## 1.0.4

Fire TV fixes from a cloud Fire TV test (Fire OS 14, 64-bit): less memory while a video plays, and three remote and player bugs.

- Low-memory mode now goes by RAM as well as by 32-bit Android: a 64-bit TV with less than 3.3 GB (MemTotal in /proc/meminfo; a "2 GB" Fire TV stick reports about 1.9 GB) gets everything the 2019 Shield gets. Before, the 64-bit Fire TV got none of it: Flutter's full 100 MB image cache, full-size artwork, Skia's uncapped GPU cache, 64 MB of read-ahead plus 64 MB of played video kept by mpv, and mpv copying every frame. It went from 450 MB browsing to 798 MB playing a 1080p film. Now it gets a 48 MB image cache, artwork decoded at most 1280 wide, Skia capped (64 MB browsing, 8 MB playing), 32 MB read-ahead and 8 MB kept behind, Video Plane output (the decoder draws on the TV's own surface), and no Home trailers. The log says at launch: "memory: N MB RAM, 64-bit, low-memory mode on". The probe switch `lowmem` turns it on for testing on a bigger device.
- The pages behind the player put their artwork away for every video on a low-memory TV, not only for a 4K file at Original quality (the 0.9.13 fix). Going back to them loads it again.
- Player timeline: after a pause and resume a transcode could show nonsense times (26:30:43 elapsed, 23:18:09 left in a 3-hour film) until the next seek. Plex sends transcodes as MPEG-TS, whose clock wraps after 2^33 ticks of 90 kHz (26 h 30 min 44 s); mpv's clock had wrapped below zero. A wrapped clock is now unwrapped, and any other position past the end is ignored (the last good one stays), so it never reaches Plex's progress or Trakt either.
- Paused, the controls put the focus on Play, so Left and Right move between the buttons. Before, the picture kept the focus while the big Play button looked selected, and Right seeked. Left or Right on the pause screen only brings the controls back.
- Movies (and every library page): Down from the sort buttons goes to the first poster. They sit at the right end of the header, so Down landed on the last poster of the first row.
- "Pick up where you left off?" focuses Resume when it appears. The player already held the focus, so the button's autofocus did nothing: on a TV neither button was focused and Select did nothing until an arrow was pressed (seen on the Shield).
- Version 1.0.4+62 (Android versionCode 1062 for armeabi-v7a, 2062 for arm64-v8a).

## 1.0.3

Trakt and AniList: what you watch is tracked as you watch it.

- Settings > Tracking (new tab). Trakt signs in with its device code: a code to type at trakt.tv/activate and a QR code with the code filled in, the same way Plex's link code works on a TV. Tokens are refreshed before they run out and once more on a 401. Disconnect revokes them.
- AniList has no code sign-in, so it uses AniList's own token page (implicit grant with the redirect `https://anilist.co/api/v2/oauth/pin`). On a TV, a QR code opens a page the TV serves on the home network (services/phone_link.dart: random 128-bit path, 15 minutes at most, closes after 20 wrong addresses, form posts only, a strict CSP, no caching); the phone signs in to AniList there and pastes the token. On Windows the token is pasted in Settings. The same phone page takes a Trakt app's Client ID and Secret, which are miserable to type with a remote.
- Playing, pausing and leaving the player send Trakt's scrobble start, pause and stop with the progress; past 80% counts as watched (Trakt's rule). Movies go by their IMDb/TMDB ids, episodes by the show's ids and season/episode number, falling back to the episode's own ids. Calls go one at a time per play and the newest state wins. Marking a title watched by hand adds it to the Trakt history.
- Anime (Plex genre "Anime", or a library named for it) also moves AniList forward when an episode or film passes 80% or is marked watched. The show is found by title (and year), and its AniList seasons are walked through prequels and sequels (films in between skipped). The episode's air date then picks the AniList entry, so split cours, TVDB seasons and absolute numbering all land on the right entry and number; without air dates, Plex season N is the Nth entry. Progress only goes up, finished entries are left alone, and an entry reaching its episode count becomes COMPLETED. Matches are cached a week (misses a day) in anilist-map.json; Match Shows Again forgets them.
- Keys: Trakt's sign-in and refresh need the app's Client Secret, which can't stay secret in an open-source app, so none is in the repo or the release builds: each user makes a free Trakt app and an AniList API client and enters them once in Settings > Tracking (the phone page on a TV). Source builds can still bake keys in with `--dart-define` (`LIQUIFLUX_TRAKT_CLIENT_ID`, `LIQUIFLUX_TRAKT_CLIENT_SECRET`, `LIQUIFLUX_ANILIST_CLIENT_ID`). The Trakt secret and the sign-ins (Trakt tokens, AniList token) are kept in the OS credential store, never in settings.json, and are scrubbed from logs.
- New dependency: `qr` 4.0.0 (pure Dart, pinned) for the QR codes.
- Version 1.0.3+61 (Android versionCode 1061 for armeabi-v7a, 2061 for arm64-v8a).

## 1.0.2

Match Frame Rate: the display follows the video's frame rate while it plays.

- Settings > Video > Match Frame Rate: Off, Frame Rate, or (Android TV) Rate and Resolution. On by default (Frame Rate) on Android TV, off by default on Windows.
- Which mode: the frame rate comes from Plex's video stream (`frameRate`, e.g. 23.976), or from mpv's container-fps once the file opens if Plex didn't say. The display goes to the exact rate when it has it, else an even multiple (47.952, 50 for 25, 119.88), else 24 Hz for 23.976; 60 Hz is never picked for film. A display that already shows the rate evenly (59.94 for 29.97) isn't switched. With resolution, the picture's size picks the smallest mode that holds it, never below 1080p (packages/console_core/lib/src/display_match.dart, with tests).
- Android TV: the window asks for the mode with preferredDisplayModeId (DisplayModes.kt, channel liquiflux/display), as Kodi and Plex's app do. Android puts the TV's own mode back when another app comes to the front or Liquiflux closes.
- Windows: the monitor the window is on switches refresh rate only, never resolution, with CDS_FULLSCREEN, so nothing is saved and Windows restores it if the app closes or crashes (windows/runner/display_mode.cpp).
- The first play of a title waits, paused, until the switch is done and the TV has had 2 seconds to show a picture again (0.8 s on Windows), so the opening isn't lost to the blank screen. If the rate only comes from mpv, the player pauses through the switch. Closing the player goes back to the display's own mode 3 seconds later, unless the next episode asks for the same mode first, which then plays with no second blank.
- Version 1.0.2+60 (Android versionCode 1060 for armeabi-v7a, 2060 for arm64-v8a).

## 1.0.1

Liquiflux updates itself, and the release workflow can publish it to WinGet.

- Update check: about 20 seconds after launch (at most every 12 hours) Liquiflux asks GitHub for the latest release, with no sign-in and no token, and shows a card when there's a newer one. Settings > Advanced > Updates has the version, Check Now, Update and a Check at Launch switch. "Not Now" on the card hides it for that version only.
- Windows: Update downloads `Liquiflux-Setup-x64.exe`, checks its SHA-256 against both GitHub's record of the upload and the release's SHA256SUMS.txt, closes the players, and runs the installer silently with `/RELAUNCH=1`, which starts the new Liquiflux when it's done (tools/installer/liquiflux.iss). The portable zip (no `unins000.exe` beside the exe) only links to the release.
- Android TV: Update downloads the APK for this system's ABI (armeabi-v7a on a 32-bit system such as the 2019 Shield), checks the SHA-256 the same way, then AppUpdater.kt checks it's Liquiflux, newer, and signed with the same key before handing it to Android's installer through a PackageInstaller session. Android asks once to allow installs from Liquiflux and then to confirm each update. New permission: REQUEST_INSTALL_PACKAGES.
- An app store build: `tools/build-android.ps1 -Store amazon` (or `--dart-define=LIQUIFLUX_STORE=amazon` with `--android-project-arg=liquiflux.store=amazon`) leaves out the updater's permission and the sleep timer's accessibility service, and hides both features. A copy that Google Play or the Amazon Appstore installed never updates itself either.
- WinGet: tools/winget/make-manifests.sh writes the manifests for `Liquiflux.Liquiflux`, and with a `WINGET_TOKEN` secret the release workflow sends each new version to microsoft/winget-pkgs with wingetcreate (pinned by checksum). Run workflow with "Submit this version to WinGet" sends a version that's already released.
- Android closes an app when you allow it to install apps, so the first update on a TV takes a second Update after reopening Liquiflux (the panel says so). Android also switches the sleep timer's "turn the TV off" accessibility permission off whenever it updates the app (tested on the Shield), so switch it on again from the sleep timer after an update.
- Tested on the PC (a 0.9.0 test build updated itself to the real 1.0.0 installer; the 1.0.1 installer with /RELAUNCH=1 restarted the app, without it didn't; `winget validate` passed) and on the 2019 Shield (a 0.9.0 test build updated itself to the real 1.0.0 APK through Android's installer, versionCode 1050 to 1058; the store build has neither the permission nor SleepService).
- Version 1.0.1+59 (Android versionCode 1059 for armeabi-v7a, 2059 for arm64-v8a).

## 1.0.0

The first public release. Liquiflux now lives on GitHub, and every version is built and published there, so nobody has to compile it to use it.

- Releases come with a Windows installer (per-user, no admin rights), a portable Windows zip, and Android TV APKs for 32-bit (armeabi-v7a: 2019 Shield, Fire TV) and 64-bit (arm64-v8a: Google TV) devices, built by GitHub Actions from this repository.
- The Windows builds carry the Visual C++ runtime, so they run on PCs without the redistributable.
- tools/setup-dev.ps1 installs everything needed to build it yourself (Git, Flutter, the Visual Studio C++ build tools, Developer Mode and Java) with winget, in one command.
- A new README with screenshots; the detailed guide moved to docs/GUIDE.md.
- The X-Ray scanner and server are no longer copied into this repository: they have their own (liquiflux-xray-server and Liquiflux-xray-ML-PC).
- No changes to the app itself since 0.9.49. Version 1.0.0+58 (Android versionCode 1058 for armeabi-v7a, 2058 for arm64-v8a).

## 0.9.49

Security fixes 1-5 from the review of 0.9.47 (security/liquiflux-0.9.47-app-review.md). Sign in to Plex once more in Settings after installing, on every device, to get the https address and the server check.

- The player checks https certificates. mpv's `tls-verify` is off by default and direct-play and transcode addresses carry the Plex token, so an https stream went to whoever answered. Both players (the movie player and Home's trailers) now set `tls-verify=yes` and `tls-ca-file`. media_kit's libmpv does TLS with mbedtls on Windows and Android alike, which can't read the system's certificate store, so the app ships Mozilla's root list (app/assets/tls/cacert.pem, from certifi 2026.10.23, see below) and copies it to its own folder for mpv. A certificate that isn't signed by those roots or doesn't match the address now fails to open. http on the LAN is unchanged.
- The player refuses an https address that is a bare IP (https://192.168.x.x). mpv's TLS skips the name check for those, so any trusted certificate would pass; tested on the PC. The app's own requests do check it, so a sign-in never lands on one; this is the backstop. plex.direct names are checked in full.
- One list of trusted roots for everything. The app's own https requests (Plex, plex.tv, Seerr, X-Ray, Trakt, TMDB, artwork) now trust the same bundled list as mpv instead of the system store (lib/services/trusted_roots.dart, through HttpOverrides), so an old TV's store can't keep a root the browsers dropped. eMudhra (October 2026: eight intermediate CA keys computable from their certificates, CVE-2026-111943; Mozilla removed emSign ECC Root CA - G3 in NSS 3.131.1): the bundle is certifi 2026.10.23, which no longer has G3, and Liquiflux also removes emSign Root CA - G1, since a fixed file can't carry the browsers' revocation blocks and nothing Liquiflux uses needs it. Sectigo's cross-signed copies chain to AAA Certificate Services, which isn't in the list either. app/test/trusted_roots_test.dart keeps both out.
- Plex sign-in prefers https. Among addresses of the same kind (local, remote, relay), the https plex.direct one now comes before plain http, so on the LAN the token travels inside TLS with the server's own certificate. A router with DNS rebind protection that can't resolve plex.direct falls back to http, as before.
- The saved Plex address is checked before the token goes to it. Sign-in keeps the server's machine id (settings.json `plexMachineId`); every launch asks the address's /identity, without the token, whether it's still that server, and if it isn't, nothing carrying the token is sent and Settings says to sign in again. A sign-in from before 0.9.49 learns the id on its next successful launch. A new address or pasted token learns it afresh.
- Seerr's "sign in with Plex" and Plex Watch Together use the plex.tv account token (kept since 0.9.39) instead of the server token. For the server's owner they're the same; for a friend on a shared server only the account token works with plex.tv, so both failed for them before. Settings.plexTvToken picks it, falling back to the server token.
- "4K in Another App" is gone (Settings, PlaybackPrefs, the Android method channel and external_player.dart). It handed a URL with the Plex token to whatever video app the TV picked. 4K has played inside Liquiflux on the Shield since 0.9.13. An old saved switch is ignored and dropped on the next save.
- The measuring probe can't be set by other apps. A release build takes `--es probe ...` only through a new activity alias, `com.foehammer.console_app.Probe`, which needs the DUMP permission that adb's shell has and ordinary apps can't get. Switches sent to MainActivity are ignored (a debug build still takes them). Test scripts start `com.foehammer.liquiflux/com.foehammer.console_app.Probe`.
- Version 0.9.49+57 (Shield versionCode 1057).

## 0.9.47

Checked against every handoff (v1.1 to v1.28) and built for Windows. No feature or fix from 0.9.1 to 0.9.40 is missing; nothing in the app's own code changed.

- tools/xray-server is now the published server (github.com/Foehammer1987/liquiflux-xray-server, 0.9.46, commit 5111773) instead of the 0.9.40 copy. Its sign-in and timeline API is the one Liquiflux has used since 0.9.37.
- console_core/tool/xray_check.dart (new): signs in to an X-Ray server and reads one timeline with Liquiflux's own client code, reading the Plex token from a file and never printing it.

## 0.9.40

- xray-api: a sign-in now lasts 2 hours instead of 12 (`XRAY_SESSION_HOURS`). Liquiflux signs in again by itself, so nobody notices, and someone whose Plex share is removed is out within 2 hours instead of 12. Access is hands-off, the way Seerr does it: every sign-in is checked live with plex.tv against who currently has access to this Plex server; `XRAY_ALLOWED_USERS` stays optional and empty by default.

## 0.9.39

Allow lists on the X-Ray server, from the Fable review of 0.9.38.

- xray-api: `XRAY_ALLOWED_USERS` no longer matches a Plex account's display name, which anyone can change to a listed one; it matches the account id or username, and the name only for Plex Home members (no username, names set by the owner).
- Liquiflux keeps the plex.tv account token from the Plex sign-in (in the credential store, next to the server token) and signs in to the X-Ray server with it. The server can then check with plex.tv who a shared user is, so allow lists work for them too; before, a shared user only had a server token, which no allow list could name. Signing out forgets it; a pasted token replaces it. People who signed in before 0.9.39 keep working as before and get the account token the next time they sign in to Plex in Settings.

## 0.9.38

Security fix for the X-Ray server, from a security review of 0.9.37.

- xray-api: the check that catches Plex letting the container in without a token ("allowed without auth") failed open. If Plex was down when the API started (an Unraid reboot), or a network covering the container was added to that list later, then for up to 10 minutes anyone could sign in with a made-up token and read timelines. Now it assumes the worst until Plex has answered, and every sign-in that Plex accepts asks Plex again, with a made-up token, before it's trusted. While Plex can't be asked, shared users' server tokens get "try again shortly" instead of a session. plex.tv sign-ins (the owner, and friends signed in with their Plex account) are unaffected.
- SECURITY.md: notes on setting XRAY_TRUSTED_PROXIES to cloudflared's address, and that Liquiflux hands its Plex token to the X-Ray server it's pointed at.

## 0.9.37

The X-Ray server for Unraid, and Liquiflux signing in to it.

- tools/xray-server (new): two containers for Unraid. xray-api shares the X-Ray timelines at home and through Cloudflare Tunnel to anyone who signs in with a Plex account that can use this Plex server (the way Seerr's Plex sign-in works); xray-scanner scans movies Plex adds from now on, on the NVIDIA GPU, and imports packs from X-Ray Desktop. README.md has the install, SECURITY.md the design and the checks to run.
- X-Ray Server setting: Liquiflux now signs in to the X-Ray server with its Plex sign-in by itself (nothing to set up but the address), shares one session between titles, and signs in again when the server restarts. Save checks it and says "Saved, signed in to X-Ray" or the server's reason. The Plex token is only sent over https, or plain http on your own network. A plain web server over the timeline files still works as before.

## 0.9.36

Two fixes found while testing X-Ray on the Shield.

- Leaving Liquiflux with Back from Home sometimes crashed it (2 of 4 times on the Shield; Home never did). A video player that was still open, such as a Spotlight trailer or the movie player still closing, outlived the app's code and crashed inside the video library. Every player is now closed before the app leaves (3 seconds at most).
- Back couldn't leave a paused movie: it only switched between the pause screen and the controls. Paused, Back now leaves the player straight away, from the pause screen or the controls (an open panel or the info still closes first). Playing, it hides the controls first as before.
- tools/xray: the scanner as used for the full library scan (round 7, fills chapter gaps), the README, the overrides from the scan, and xray_throttle.py (caps the scanner's Plex bandwidth while people are watching).

## 0.9.35

Every feature from the parallel builds in one app. 0.9.29 to 0.9.34 were each made from 0.9.28, so each one had only its own change; this build has all of them, with every fix, and later work builds on it.

- X-Ray (0.9.29), Watch Together by room code (0.9.30), audio and subtitles per show with the English dub for anime (0.9.31), the sleep timer that turns the TV off (0.9.32), Top 10 on your server (0.9.33), and the mood rows and Moods page (0.9.34), as described below.
- Sleep timer, Allow Turning the TV Off: on the Shield it opened nothing (Android's generic Accessibility link only says "You don't have an app that can do this" there). It now opens the TV's own Accessibility settings, or the main Settings screen if that isn't found; the button names the path, Settings > Device Preferences > Accessibility.
- Home's mood rows also leave out the titles in Top 10 on your server (0.9.34 knew only the older Top in Your Library row).

## 0.9.34

Mood rows, Netflix style. (Built on 0.9.28; 0.9.29 to 0.9.33 are other threads' builds.)

- Home's three plain genre rows ("Drama", "Action"...) are now four mood rows drawn from your whole library, such as Feel-Good Comedies, Dark Sci-Fi, Edge-of-Your-Seat Thrillers, Binge-Worthy Series or Waiting on Your Shelf. Each visit to Home picks four different ones where the library has enough, and keeps a title from turning up in more than one of them (or repeating the spotlight and Top in Your Library). They sit after Recently Added.
- A new Moods page in the sidebar (under Collections) with every mood that has at least 8 titles, then every Plex genre, with All / Movies / Series. Rows load as you scroll to them.
- Plex has no moods for movies and shows, so each mood is a recipe over what it does know: genres, year, running time, rating, when it was added and whether you've watched it. 26 in all, e.g. Feel-Good Comedies is comedy with no horror, thriller, crime or war; Waiting on Your Shelf is unwatched, well rated and added over a year ago; Worth a Rewatch is favourites you've already seen; In 90 Minutes or Less, Timeless Classics, Totally '80s. Magical Worlds needs fantasy plus adventure or family, since plenty of comedies are tagged fantasy too (Ted 2, Liar Liar). Genre names from the movie and TV agents count the same ("Science Fiction", "Sci-Fi & Fantasy").
- Rows lean toward titles you haven't watched and better-rated ones, at random, so a big library shows a different slice each time.

## 0.9.33

- Home: a "Top 10 on <your server>" row (named after your Plex server) of the titles watched most on the server this week, by everyone who uses it, with the big rank numbers. A title scores once for each person and day it was watched, so binging six episodes of a show in one night counts once, and two people watching the same movie counts twice. When fewer than five titles were watched this week it ranks the last 30 days instead. It reads the server's watch history, which only the server owner's account can see.
- It takes the place of "Top in Your Library" (best-rated titles), so Home doesn't show two ranked rows and has no more posters than before (memory on the Shield). "Top in Your Library" comes back whenever there isn't enough watching to rank, or the account can't read the history.

## 0.9.32

Sleep timer, after "a sleep timer would be cool". There already was one (Playback Settings, Playback tab), so this makes it work for a night of episodes.

- A timed sleep keeps running when Up Next starts the next episode. Each episode opened a fresh player, so a 1-hour timer started during an episode was quietly lost when it ended.
- New choices: stop after 2 or 3 episodes (shown for episodes and queues), beside 15 min to 90 min and End of This. Going on to the next episode, by Up Next or Next, counts one off.
- The last minute: a card at the top says "Sleep timer: stopping in 0:42" and the volume fades out. Any button on the remote (or any key, or a click on the card) keeps you watching, turns the timer off and brings the volume back. The button does nothing else.
- When time's up (or the last episode you picked ends) the player closes, saving where you were, and the TV goes to sleep. On a Shield that also turns the TV off when HDMI-CEC is on. Android TV only lets an app do this through an accessibility service (there's no device admin on a TV), so the first time the Sleep Timer panel has an Allow Turning the TV Off button that opens Settings > Accessibility, where you switch on "Liquiflux sleep timer". It only puts the TV to sleep and reads nothing on screen. Without it the player just closes and the TV's own sleep setting takes over. It used to pause and sit on the pause screen.
- A moon button in the player controls opens the sleep timer directly, and stays lit while a timer runs. The bottom bar shows what's left beside "Ends at" ("Sleep in 42:10", "Sleep after this").
- Leaving the player yourself turns a running timer off.

## 0.9.31

Audio and subtitles per show, after "per-show audio and subtitle language would be nice, especially for anime: I only watch English dubbed anime".

- Pick an audio track or subtitles while watching an episode and the rest of that show starts the same way: the same audio language, and subtitles off, signs only, or every line in the same language. It's per show, so a dubbed anime and a subtitled one can sit side by side. An episode without that track (no dub yet) falls back to the usual settings. Settings > Audio & Subtitles > Remember Per Show shows how many shows are saved and can forget them all.
- New setting Anime Audio, English to start with: shows and films tagged Anime by Plex, or in a library with Anime in its name, start on the English dub when there is one, before you've picked anything for that show. Set it to "Same as Audio Language" to treat anime like anything else.
- Subtitle tracks named "Signs & Songs" (how anime releases label the subtitles meant for the dub) count as forced subtitles, even when the file doesn't flag them forced. With Subtitles on Plex Default, Plex's choice of full subtitles drops to signs only once the audio moves to the subtitles' language (the dub), instead of showing every line over English dialogue.
- A setting changed in the player in the last half second before leaving it (volume, subtitle style, a track) is saved; it could be lost.

## 0.9.30

Watch Together by room code.

- **Watch Together with a room code**, through Open Watch Party, the rooms Plezy uses. Start a Room (from the people button in the player, or Watch Together on a movie or episode page) gives you a six-character code such as K7M-Q2X. Friends type it into Join with a Code in Liquiflux, or join from Plezy. Each person plays their own copy from their own Plex server: Liquiflux finds it by IMDb, TMDB, TVDB or Plex ids, then by title and year, and an episode by its series, season and number. Someone on the same server gets the exact file. Play, pause, jumps and speed changes happen for everyone, with a note saying who did it. The room waits while someone buffers.
- In a code room, the host decides. Up Next and choosing another episode move the whole room on; the others' players follow on their own. A guest who picks something else leaves the room. Closing the player leaves the room a few seconds later (Up Next swapping the player doesn't).
- The panel shows the code, who's in the room and whether they're watching, buffering or reconnecting, and offers Leave Room. The host can also End Room for Everyone. When your copy is a different length from the host's, it says so and offers Play Mine Anyway.
- The Plex rooms are still there, under With Plex Friends. Plex has dropped Watch Together from its own apps except Plex Web, so those rooms may stop working; the log now says what Plex answered, to check them against the real service.
- New dependency: openwatchparty 1.1.0 (Apache 2.0), pinned to that exact version. The rooms use the public relays at openwatch.party; CONSOLE_OWP_RELAY points Liquiflux at your own relay instead.

## 0.9.29

X-Ray, after Prime's: who's in what you're watching.

- An X-Ray button in the player's bar (X on a keyboard), and Down on the pause screen, open a panel with the whole cast: photo, name and character. Picking someone closes the player (your place is saved as usual) and opens their page, with their other titles on the server. Their page waits until the player has gone, so its artwork never loads over a 4K picture.
- With an X-Ray server set (Settings > Discovery), the pause screen shows who's in the scene you paused on ("In this scene") instead of top billing, and the panel lists them first. The scanner that makes those files is new in tools/xray: it runs on a PC, matches faces in sampled frames against the cast's photos with a confidence weight for each, scans unsure chapters again at double the resolution, and leaves animated films out (it tells them apart from the frames, not from Plex's genres). See tools/xray/README.md.
- The pause screen says how to reach X-Ray.
- Never an empty "nobody here": whenever the scene data can't be trusted (no file, server down, an unsure chapter, a poor or out-of-date scan, nobody named surely enough), the pause screen and panel show top billing instead.
- An actor playing several parts shows once, with every character ("Reggie Kray / Ronnie Kray"). Lookalikes the scanner can't tell apart, such as twins, are shown together rather than guessed.
- Cast photos in the player are always fetched small, through Plex's resizer. Web-hosted headshots came in full size, and opening X-Ray over a paused film got the app killed for memory on the 2 GB Shield (found in testing, never released).

## 0.9.28

Android TV remote navigation, after "Left shifts the rows and needs a second press".

- Left along a Home row moves one card per press again. Each "Because You Watched" card has a thumbs-up button in its corner that only shows under a mouse pointer, but it still took focus from the remote: Left from the next card landed on that invisible button, Home jumped to centre it, nothing looked focused, and only a second Left reached the card. Down from the row above could land on it too. On a TV those buttons are no longer stops, and nothing hidden is: the remote skips any control that's faded out, offstage or has no size, and any small control tucked inside another card.
- Home's spotlight: Right from More Info went to an invisible Mute button (it only shows while a trailer plays) before reaching Re-roll.
- Up straight after Down goes back to the card you came from, between any two rows. Before, it went to whichever card above was nearest, often a different one.
- Up from a Continue Watching card lands on Play, not More Info.
- On an episode list, Left from an episode reaches its play thumbnail (it went straight to the sidebar).
- Scrolling to the focused card is one smooth glide to the middle of the screen. It used to snap the row just into view and then slide it to the middle.
- The focus ring shows from the moment the app opens, on Play. Android starts apps in touch mode, where Flutter hides the focus ring until the first button press, so the first press moved a focus you couldn't see.
- Up from the rows into the spotlight scrolls Home to the top in one move (it slid to the middle first, then to the top).
- Back while browsing Home's rows goes to the top of Home, on Play, as TV apps do. It left the app straight away. Back from there still leaves.

## 0.9.27

- Windows: no more tearing in the picture, and smoother motion. mpv copied each frame across to Flutter's renderer without waiting for the copy to finish, so a frame on screen could be half the old picture and half the new one. Flutter's drawing also waited on mpv while it rendered the next frame, which cost it display refreshes. Frames now go into a ring of three, and Flutter is only handed one that's completely copied. (Our own copy of media_kit_video, in packages/; Android TV isn't touched.)
- Windows probe switches for measuring playback, from the environment (LIQUIFLUX_PROBE), logging to a file, plus mpv's dropped and late frame counts every second while a title plays.

## 0.9.26

- A new, grander startup animation, "liquid" (picked from three previews). A drop of blue falls onto a faint outline of the logo, which fills from the bottom with rippling liquid. Once it's full the logo glows and rises, ripples roll out across a waterline, and the letters of LIQUIFLUX surface one by one beneath it. Then it fades into Home. About 3.4 seconds; Home still loads underneath meanwhile. Any button (or a click) skips to the fade-out, as in 0.9.25.
- No more black flash between the launch screen and the animation. Flutter switched the window to plain black as soon as the app started, half a second before its first frame on the Shield. The window now keeps the launch screen until the animation is over, then goes back to black (which video needs).
- The launch screen shows the same faint logo outline the animation starts from.
- The logo images are let go once the animation is over.

## 0.9.25

The logo animation (planned as 0.9.23), on top of 0.9.24.

- A startup animation built on the logo (Android TV and Windows). The logo gets a glint, the name "Liquiflux" slides out beside it, and then the pair lifts away and fades into Home, about 2.3 seconds in all. Home loads underneath meanwhile, so it doesn't add to the wait. Any button on the remote (or a click) skips to the fade-out, and that press doesn't also act on Home. Plays once per launch; skipped when the system asks for reduced motion.
- Android's launch screen is the logo on the app's dark background instead of a plain white screen, at the same size and place the animation starts from, so the hand-over doesn't jump.
- Kept light for 2 GB TVs: one small image (decoded at 440 px), no blur, and the fade-out doesn't put a layer over the whole screen.
- Probe switch `nointro` leaves the animation out. The app logs "intro: done after N ms".

## 0.9.24

Fixes from testing 0.9.22 on the Shield. (0.9.23 is the logo startup animation, made in parallel from 0.9.22; this build doesn't include it.)

- On Requests, each whole row takes focus, not just its title. Down from the In Progress / Available / All filter jumped straight to the last row; it now lands on the first.
- A focused request row shows the focus ring and a light background. Before, nothing on screen showed which row had focus.
- The "In theaters since…" line is read out with the rest of a Not on Streaming Yet row.

## 0.9.22

- Home no longer has a "Requests in Progress" row (Windows and TV). Requests live under Requests in the sidebar.
- Requests has a separate "Not on Streaming Yet" panel for requested titles that aren't out on streaming or digital yet. Each shows its date at a glance (for example "Nov 18, 2026", "Digital release · in 25 days", "In theaters since Oct 3, 2026"), with no progress bar, soonest first. Dates come from Seerr's TMDB data: a movie's US digital release (else the earliest digital release anywhere); a series' premiere, or the first requested season's air date. A film in theaters with no digital date yet says "Date not announced".
- Such a title leaves the panel by itself once its date passes or a download starts. Seerr's details for each request are looked up again every six hours, so a newly announced date shows up without restarting.
- A title's page shows the same "Not on Streaming Yet" state with the date instead of the "Searching for a release" bar.
- The sidebar's Requests count leaves out titles waiting for a streaming release.

## 0.9.21

- With Home trailers on (including Spotlight Only), the spotlight keeps rotating while one of its buttons has focus. A trailer plays for 20 seconds (was 40), then the spotlight moves to its next title, and that title's trailer starts if focus is still on the spotlight. A title without a trailer moves on after the usual 9 seconds. The rotation waits while a trailer is opening, so a slow start doesn't skip it.
- When the spotlight moves on under focus, focus goes to the same button (Play or More Info) of the next title instead of falling into the rows. With trailers off the title still holds while a button has focus, as in 0.9.17.
- Logs "spotlight: next" on each rotation and "trailer: playing" when a clip starts.
- Probe switch `playat=T` starts `play` T seconds after launch instead of 30, to test 4K after several spotlight trailers.

## 0.9.20

- Focus "at a page's first control" means the topmost control on screen (on Home, the spotlight's Play). It used Flutter's first focus, which returns whatever the page last had focused. After Back to Home that was sometimes a card far down the page, so 0.9.19's claim put focus straight back there, out of sight. A fresh launch now also starts on Play rather than the first Continue Watching card.
- The "focus after back" log line now gives the control's label, position and size.

## 0.9.19

- Back from search results to Home: Home takes focus at its first control, wherever focus was left. 0.9.18 still left nothing visibly focused after 6 of 9 searches on the Shield, with Down jumping far down the page. The app logs where focus had gone ("focus after back"), to find the cause.

## 0.9.18

- Back from search results to Home leaves focus on Home again. 0.9.17's fix only acted on an arrow press, and after Back nothing had focus, so nothing showed it and Down still jumped far down the page. On a TV, whenever the focused control disappears with its page, the page on top now takes focus at its first control.

## 0.9.17

Fixes from testing 0.9.16 on the Shield.

- The spotlight holds its title while one of its buttons has focus. It kept rotating, and each new title replaced the buttons, so focus fell into the rows after a few seconds and the next Up couldn't reach search.
- Space while typing a search is a space again. On a TV the search pill took it as a press and searched for the first word.
- After Back from search results, Home had nothing focused, and Down jumped far down the page. Any arrow now picks the page's first control when nothing has focus.

## 0.9.16

Fixes from testing 0.9.15 on the Shield.

- Enter or Select while typing in the search pill now searches. The Shield's phone-remote keyboard sends a plain Enter, which only reopened the keyboard, so a search couldn't be submitted from the remote.
- Moving Up from the rows onto the spotlight's buttons scrolls Home back to the top. Before, the page stayed scrolled with the buttons at the top edge, Home counted the spotlight as off screen, and its rotation and trailers stopped.
- The sidebar rings the focused button (and the logo at its top). Focus there was invisible on the Shield.

## 0.9.15

Remote fixes for the sidebar, Home and search, and an experimental trailer mode for 32-bit TVs.

- Down from Settings at the bottom of the sidebar now stays on Settings. Before, it closed the sidebar and dropped into the page's rows, because the sidebar and the page share one focus area and the nearest thing below Settings was on the page. The sidebar keeps the D-pad to itself now; Up from its top still goes to search, and Right or Back still return to the page.
- Up from the top of Home (the spotlight's buttons), or of any page, now goes to the search pill at the top right. On a TV the pill takes focus as a button first, so passing through it doesn't open the keyboard: Select starts typing, Down or Back returns to the page, and Back while typing returns to the pill.
- Search lists movies and series, not episodes. Episodes that match are folded into their series, shown once with the series' own poster and details. A series found only through an episode is kept when its name matches what you searched for, so "avatar" shows Avatar: The Last Airbender once instead of every episode, and an unrelated show with an episode called "Avatar" doesn't appear.
- Home trailers on 32-bit Android (Settings > Appearance > Home Trailers: Spotlight Only, off by default). A muted trailer plays only while focus is on the spotlight's buttons. Moving down into the rows, opening a title or playing one stops it and frees its player entirely, rather than keeping it paused, so its memory is back before any 4K video opens. The probe's new `trailers` switch turns it on for one launch.

## 0.9.14

4K on the 2019 Nvidia Shield: no white flash before a video starts.

- 0.9.13, tested on the Shield: with the pages behind redrawn without their artwork, Liquiflux held about 200 MB less graphics memory as Avatar: The Way of Water started (about 400 MB in use for the whole TV against about 590 MB without the redraw, peaking near 680 MB instead of 870 MB). It played every time, with about 350 MB still free during a normal 4-minute watch, and Android closed far fewer other apps to make room.
- A screen recording showed the area behind the player's controls white for about a second before a 4K video started: on 32-bit TVs the app is drawn transparently over the window, and until the video's surface is up that window showed through, white in Android's light theme. The window is black now.

## 0.9.13

4K on the 2019 Nvidia Shield: the pages hidden behind the player let go of their artwork's graphics memory.

- 0.9.12, tested on the Shield: freeing the image-loading thread's textures made no difference to graphics memory (about 240 MB still held with the player covering Home, the same with or without it). With Avatar: The Way of Water opened from its title page, the pages behind held only 6 images by then, yet graphics memory hadn't moved. Avatar kept playing in all three runs with 0.9.12 and was closed in the one run without its freeing, but with memory the same either way, that says this TV is right at the edge rather than that the freeing worked.
- The likely reason, from Flutter's source: Flutter doesn't draw a page another page hides, and a hidden page keeps the last drawing it made, which holds on to every picture in it. Letting go of the pictures, emptying the cache and freeing textures can't free what that drawing still holds. Before a 4K video opens on a 32-bit TV, the player now draws itself black for a moment while the pages hidden behind it (the title page, Home under it, the whole app) are drawn once more without their artwork, then hides them again.
- For that, the player on a 32-bit TV now fades in over the app, which stays where it is behind it. Before, the app slid aside and faded out as the player came in, and a page faded out isn't drawn at all.
- When a 4K video ends, only the page it was started from loads its artwork again; the pages still hidden behind that one (Home, under a title page) wait until you go back to them. In a test on the Shield, Android closed Liquiflux in the background when Home was pressed straight after leaving the player, while all of that artwork was loading again.
- The player logs memory once those pages are drawn again, and the probe's new `noredraw` switch measures without it.

## 0.9.12

4K on the 2019 Nvidia Shield: the artwork put away for 4K is now actually freed.

- 0.9.11's measurements on the Shield: Flutter itself, the transparent TextureView, the glass and blur effects and Skia's cache each cost next to nothing (within 15 MB). Artwork was the whole gap: Liquiflux held about 290 MB of graphics memory on Home against 100 MB with no artwork and 65 MB for Plezy, and with the player covering Home it still held about 235 MB against 60 MB with no artwork, though the pictures had been let go of.
- The likely reason, from Flutter's and Skia's source: a picture uploaded on Flutter's image-loading thread is handed back there to be freed, and that thread only tidies up the next time it loads or drops an image. While a video plays nothing loads, so the artwork let go of for 4K stays in graphics memory. Before a video opens on a 32-bit TV, the player now loads and drops a 1-pixel image so that thread frees it.
- The player also logs memory once the artwork behind it is put away, and the probe's new `nofree` switch measures without the freeing.

## 0.9.11

A measuring build for 4K on the 2019 Nvidia Shield. Nothing changes in normal use.

- 0.9.10 showed a few frames of 4K before Android closed it. Android's exit records confirm a memory kill, not a crash. Releasing the artwork behind the player freed only about 45 MB, while Liquiflux still holds about 200 MB more graphics memory than Plezy on the same TV, and the TV's own tools can't say what it is.
- Launched from adb with switches (see ANDROID-TV.md, Measuring memory), the app logs its memory every second and turns one suspect off at a time: the blur effects, glass panels, artwork, the transparent TextureView Flutter draws into (0.9.9), or everything but a black screen. It can also cover itself the way the player does, or start a 4K title by itself, so each setting can be tried against the 4K decoder without anyone at the TV.

## 0.9.10

4K on the 2019 Nvidia Shield: less graphics memory in use when the decoder starts.

- 0.9.9's video surface works (the decoder draws straight to it), but Android still closed Liquiflux as a 4K decoder took its 400 to 450 MB. Logs showed the TV's graphics memory at 550 to 670 MB just before a 4K file opened in Liquiflux, against 364 MB in Plezy for the same file, and that extra went away whenever Android closed Liquiflux.
- The pages kept behind the player (Home, the title page) held on to all their decoded artwork, and 0.9.7's cache clearing can't free a picture a page is still showing. On 32-bit Android TVs, those pages now let go of their artwork while a 4K file plays, once the player covers them, and get it back as you return. The decoder opens only after that memory is freed.
- Artwork decodes no wider than 1280 pixels on those TVs (Home's backdrop was 1920x1080, 8 MB), as Plezy does there. The resume screen's blurred art decodes at 480 pixels wide, and a 4K file opens only after the resume screen has faded out.
- The player logs the TV's free memory and graphics memory before and as a video starts, so the next log shows how much the decoder had to work with.

## 0.9.9

4K on the 2019 Nvidia Shield, played inside Liquiflux, the way Plex's app and Plezy do it.

- Logs taken while Plex's app and Plezy (another Flutter and mpv Plex client) played the same 4K files on the Shield showed the same hardware decoder with the same memory as Liquiflux, and less free memory than Liquiflux had when Android closed it. That points at how the picture reaches the screen, not at how much memory there is.
- On 32-bit Android TVs the picture now goes on its own surface behind the app, which the TV's display shows directly (Settings > Video > Video Output: Video Plane, the new Auto there). Liquiflux draws its controls and subtitles over it in a transparent window. Before, the picture went through a Flutter texture inside the app, and media_kit's player starts decoding before that texture exists, without the hardware decoder.
- mpv decodes no video until the surface is there, so a 4K file never starts in software.
- Flutter's Dart memory is capped at 256 MB on Android (it could grow to half the RAM), as Plezy does on 2 GB TVs.
- 4K in Another App (0.9.8) is now off unless you turn it on in Settings > Video.

## 0.9.8

4K on the 2019 Nvidia Shield: handed to another app.

- 0.9.7's graphics-memory cap freed 135–170 MB as a video opened, but the Shield still closed Liquiflux 2–4 seconds into every 4K HDR file, while the decoder was still setting up. A 4K HEVC decoder doesn't fit beside Liquiflux on this TV.
- On 32-bit Android TVs, 4K files now open in a video app installed on the TV (Android's "open with"; VLC on the test Shield), from the same place and with the resume point. Liquiflux's player closes behind it. If no app can play it, the player says so instead of closing the app.
- Settings > Video > 4K in Another App turns this off.
- The graphics-memory cap from 0.9.7 stays.

## 0.9.7

4K on the 2019 Nvidia Shield, third try. (0.9.6 was a test build: playing 4K through the Plex server at 1080p timed out, and drawing the picture on an Android video surface didn't save any memory, so both are gone again.)

- Logs showed Liquiflux holding 300–400 MB of graphics memory while browsing, mostly Flutter's GPU texture cache, which Flutter sizes at 12 full screens. On the Shield that comes out of the same RAM a 4K decoder needs (about 500 MB), so Android closed the app as soon as a 4K file started.
- On 32-bit Android TVs the cache is now capped at 64 MB, and when a video starts the app drops its decoded artwork and shrinks the cache to 8 MB until the player closes. Pages behind the player reload their pictures when you come back.

## 0.9.5

4K and high-bitrate playback on the 2019 Nvidia Shield.

- On 32-bit Android TVs the hardware decoder now draws the picture straight onto the screen. Before, every decoded frame was copied out of the decoder and rendered again by mpv at full 4K size, and Android closed the app for memory within about two seconds of a 4K or high-bitrate file starting.
- With this direct output, Liquiflux draws text subtitles itself, using the same size, height, colour and background settings. Picture-based subtitles (PGS, VobSub) and video the TV can't decode in hardware (such as AV1) are handed to the Plex server, which converts them.
- New Settings > Video > Video Output on Android: Auto, Direct or Enhanced. Enhanced is the old mpv rendering (HDR tone mapping, deband, scaling options) and is still the default on 64-bit TVs.
- On 32-bit TVs mpv keeps 8 MB of already-played video instead of 32 MB.

## 0.9.4

D-pad navigation on the TV.

- Left and Right only move along the row you're in. At the start of a row, Left now opens the side menu instead of jumping to a card in the row above; at the end of a row, Right stays put. This applies on every page (Home, Trending, Collections, libraries, title pages, search, settings) and with arrow keys on Windows. Up and Down work as before.
- In the player, Right from the volume button goes on to Subtitles, Audio and Playback Settings. It used to land on the picture behind the controls, which looked like the seek bar had taken over and made Right skip forward. The hidden volume slider no longer takes focus either.
- On a Settings text field, Left from the edge opens the side menu like everywhere else.

## 0.9.3

The two causes of Liquiflux closing on the 2019 Nvidia Shield, both found with logs from the TV.

- Android builds draw with Skia instead of Impeller. On the Shield, Impeller's Vulkan renderer grew the app to 400–600 MB within seconds of launch and Android closed it for memory. With Skia it holds at about 260 MB on Home, playback included. Windows already draws with Skia, so nothing looks different.
- One press of Back on the remote does one thing. Android was also turning each press into a second, system Back, so Back on a title page or in the player went back and then straight out of the app. Back from Home still leaves the app, as before.
- The Android build script copes with a `JAVA_HOME` that ends in a backslash.

## 0.9.2

Android TV stability, from the first run on a 2019 Nvidia Shield (Tube).

Logs from the Shield showed no crash at all: Android's low-memory killer was closing the app (up to 420 MB) while it was on screen, as soon as 11 seconds after launch.

- Home trailers on Android no longer stop or close their player while a clip is still opening. Moving onto a title and pressing Select straight away did exactly that, and could crash the app.
- On 32-bit Android (the 2019 Shield Tube, Fire TV sticks, budget boxes) Home trailers are off and the artwork cache is capped at 48 MB, since the app gets much less memory there. Settings says so in place of the Home Trailers switch.
- The blurred art behind every page is decoded at 480 pixels wide instead of full size; blurred that much it looks the same.
- On 32-bit Android the player reads ahead 32 MB instead of 64 MB.
- ANDROID-TV.md and the build script now say the 2019 Shield Tube needs the armeabi-v7a APK; `-Install` already picked it by asking the TV.

## 0.9.1

Security fixes from the 0.9.0 review.

- Custom mpv options (Settings > Advanced) now work from a list of allowed options instead of a list of blocked ones. Picture, scaling, HDR, cache, audio and subtitle-style options still work; anything else is skipped and listed in Settings. This closes options the old block list missed, such as ones that write files (`ao-pcm-file`, `vo-image-outdir`), load local files (`external-files`, `sub-files`, filter graphs with `movie=`) or change the network path (`http-proxy`, `tls-verify`).
- Error messages on the library, title, Seerr title, person and search pages, and every list that loads with a spinner, now go through the same secret scrubbing as the rest of the app, so a failed request can't show a token or key on screen. The error box itself scrubs its text too, as a backstop.

## 0.9.0

Three player additions from the to-do list: a resume question, hidden spoilers and subtitles from the internet.

**Resume or start again**
- Playing something you stopped part-way through now asks first, over the title's softened artwork: Resume from 42:10, or Start from the Beginning. It shows how far in you were and how long is left.
- Settings > Playback > Partly Watched picks Ask, Resume or Start Over. A title page's Resume and Play from Start buttons still do just that, and Up Next and Watch Together rooms never ask.
- Places under 10 seconds in, or past the end, count as not started.

**Spoilers** (Settings > Appearance, all off to start)
- Blur Episode Pictures: stills of episodes you haven't watched are blurred in episode lists, an episode's page, Continue Watching and Up Next.
- Hide Episode Stories: the synopsis is held back with "Story hidden until you've watched it". Select it to read it anyway.
- Hide Episode Names: "Episode 4" instead of a name that gives the twist away.

**Find subtitles online**
- The player's Subtitles panel has Find Online: pick a language (your subtitle language, English and the title's audio languages are offered) and your Plex server searches OpenSubtitles. Results made for your exact file come first, with Plex's match score.
- Pick one and Plex adds it to the title, then Liquiflux turns it on. It stays on the server, so other Plex apps see it too.
- Uses Plex's own subtitle search, so the server needs internet access. Results are treated as untrusted: names are cleaned up and anything malformed is dropped.

## 0.8.0

Liquiflux on Android TV: Nvidia Shield, Google TV, stock Android TV and Fire TV (Fire OS 6 and later). See ANDROID-TV.md.

**Building and installing**
- `tools\build-android.ps1` builds two APKs on your PC: arm64-v8a (Shield, Google TV) and armeabi-v7a (Fire TV sticks, older boxes). The first run sets up Java and the Android SDK if needed and makes a signing key in `%USERPROFILE%\.liquiflux` that every later build reuses, so updates install over the top.
- `-Install <TV IP>` installs over the network and picks the right APK by asking the TV.
- Shows on the Android TV / Google TV home screen with its own banner, and in Fire TV's app list.

**10-foot layout and the remote**
- The app is laid out at desktop size and scaled to fill the TV, so posters and text are readable from the sofa.
- Every page focuses its first control when it opens. Left at the edge opens the menu, Right or Back closes it, and Back steps back through pages, then to Home, then leaves the app.
- Player: Left/Right seek (faster when held), Up/Down bring up the controls, Select plays/pauses (or presses Skip Intro / Up Next when showing), Back closes one layer at a time. Media keys work too. Focused controls get a bold white ring.
- Sign in with Plex using a code at plex.tv/link (with a QR code) instead of a browser.
- Text fields in Settings don't pop up the on-screen keyboard while you move past them; Select opens it.
- Desktop-only things are hidden on TV: window buttons, full screen, keyboard shortcuts, system notifications (the in-app cards stay). Spotlight trailers need yt-dlp, so TVs show artwork.

A desktop build started with `CONSOLE_TV=1` uses the TV layout, for trying it with the arrow keys.

## 0.7.4

A security pass: how sign-ins are kept and sent, and what happens when files or servers send something they shouldn't.

**Sign-ins and keys**
- Your Plex token, Seerr API key and Trakt client ID are kept only in the system's secure storage (encrypted with your Windows account on Windows; the keyring on Linux). Older settings files that still held one are cleaned up on first launch. If there's no keyring (some Linux setups), nothing is written in plain text: you stay signed in until Liquiflux closes, and Settings explains how to fix it.
- Tokens and keys never go to other sites: not when a server redirects elsewhere, not to YouTube or other trailer hosts, and the Plex sign-in no longer sends your token to every address while finding the server.
- Tokens, keys and cookies are blanked out of logs, crash output and error messages on screen.
- Settings warns when Plex or Seerr is reached over plain http across the internet, and rejects addresses that aren't http/https or contain a password.

**Tampering and hostile input**
- A damaged or edited settings, cache or preferences file is ignored or repaired instead of crashing or being trusted; out-of-range playback values fall back to defaults.
- Odd data from Plex, Seerr, Trakt or TMDB (wrong types, huge or negative numbers, strange ids and paths) can no longer crash a page or build a bad link.
- Watch Together treats the room as untrusted: malformed messages are ignored, jumps to impossible positions are dropped, rapid jumps are slowed down, names are cleaned up and shortened, and invite floods are capped.
- Links from servers only open if they're ordinary web links. Notification buttons only accept the actions Liquiflux created.
- The player only opens web streams (no local files from a playlist), YouTube's downloader only runs for real YouTube trailers, and custom mpv options that could run scripts or touch files are skipped (Settings lists any it skipped).

## 0.7.3

A clean-up pass over the whole app: bug fixes, speed-ups and small touches.

**Fixes**
- You can type "/" in text boxes again (server addresses, searches like "AC/DC"). It only jumps to search when you're not typing.
- Settings no longer undoes your edits every few seconds: the Seerr sign-in choice stays put, and a cleared field stays cleared.
- Retry works on a title page that failed to load, and one hiccup no longer hides Search's request results for good.
- Double-clicking Play opens one player, not two. Request buttons can't be pressed twice while a request is going, and a series page stops offering films you've just requested.
- Coming back from the player keeps the season you were looking at and refreshes the series page's watch state.
- A person's "In Your Library" panel no longer spins forever when they aren't in Plex.
- Trending and Collections say when Seerr or Plex can't be reached instead of loading forever, and Liquiflux now keeps trying to reconnect in the background.
- Switching server can't mix the old server's library, collections or requests into the new one.
- Home's trailer pauses whenever the player opens, however it was started (Shuffle, a Ready card, a Watch Together invite), and a stopped trailer can't start playing out of sight.
- Toasts no longer restart their timer when another arrives.
- Player: the pause screen no longer flickers away; the controls hide again after closing a side panel; "End of This" isn't overridden by Up Next; a failed direct play resumes where you were; mute doesn't carry over as volume 0; finished titles don't reappear in Continue Watching; closing the window while watching still saves your place and stops the server's transcode; leaving the player only exits full screen if the player entered it.
- Settings are saved safely one at a time, so a quick run of changes can't corrupt the settings file.
- A slow or dropped connection mid-download now times out with a clear message instead of hanging, and a Seerr sign-in that expires is renewed once for everything waiting on it.

**Faster**
- The app no longer redraws everything every 10 seconds while requests are unchanged.
- Library and Trending only build and load the posters on screen. Library loads more as you scroll.
- The player's control bar redraws only the times, not every button, as it plays, and the pause screen's animation only runs while it shows.
- Collections only re-reads Plex collections that changed. Netflix's Top 10 is fetched once every few hours. Plex sign-in tries all of a server's addresses at once.

## 0.7.2

- Collections opens straight away: the series it found last time are kept on disk and shown at once, then brought up to date in the background. Plex collections are fetched side by side instead of one at a time, and TMDB's series are refetched weekly rather than on every visit.
- Smoother hover on collection cards: cards load smaller art sized to the card, only the cards on screen are built, and each card repaints on its own.
- Every series page has a Collections button at the top left to go back.
- A series needs two or more films to show, counting announced ones, so single-film collections are gone. Announced films count in the totals ("1 of 2") and get an outlined light on the bar.

## 0.7.1

- Collection cards: the bar under each series has one light per film, lit for every film you have and dim for each one you're missing, so a complete series is fully lit. (It used to light only the films you'd watched.) The bar no longer runs under the posters.
- Pointing at a collection card brings in the series' story: the poster fan steps back and the description fades in across the card.

## 0.7.0

- **Collections** in the sidebar: every film series you own at least one part of, found automatically from TMDB (Star Wars, The Lord of the Rings, Harry Potter, Pirates of the Caribbean, Unbreakable/Split/Glass and so on) plus your Plex collections. Each series gets its own showcase page: a slow cross-fade of its films' art, the series story, total running time and average score, a numbered timeline of the films in release order with the years between them, a ratings chart and the faces who appear across the films. Start the Saga, Continue, or Marathon plays them in order. Films you don't have show in place, ready to request one at a time or all at once.
- **Shuffle Play** button in the sidebar: picks something from your library with a spinning reel, filtered by movies or shows, how long you've got, genre and whether you've finished it. Play, shuffle again or open its page.
- **Pause screen**: after five seconds paused, the title (its logo when Plex has one), the story, the main cast and the director fade in over a softened picture in the title's colours. Settings > Playback > While Paused turns it off.
- **Because You Watched** rows on Home, from what you've played lately. Point at a card for thumbs up (more like this, and a "Because You Liked" row of its own) or thumbs down (never show it again).
- **Ready to watch**: when a request lands in Plex, a card slides in with Play. With Liquiflux in the background it's a Windows notification with a Play button instead. Settings > Notifications picks your requests, everyone's, or off.
- **Watch Together** through Plex's own rooms, so friends on Plex Web can join: start a room from the player or a title's page, invite Plex friends, and play, pause and jumps stay in step for everyone, with a note saying who did what. Invitations from friends pop up with Join. Closing the player leaves the room.

## 0.6.2

- The time and chapter tip over the scrubber now floats above everything else instead of being cut off by the frosted control bar.

## 0.6.1

- Ranked rows (Netflix Top 10s on Trending, Top in Your Library and Top 10 Not in Your Library on Home) now give every number a clearly different colour. Each still comes from its poster, picking another of the poster's colours or turning round the colour wheel when it would look too close to its neighbours.
- The whole player now takes its colours from the title you're watching: a main colour and a second accent from the artwork tint the panels, fades, scrubber, buttons, volume, Up Next, Playback Info and the settings panel, with a soft glow behind the controls. Subtitles set to "Artwork" use the same colour.

## 0.6.0

- New player controls: a floating frosted bar tinted from each title's artwork, a scrubber with chapters and intro/credits spans and a time tip, remaining time and "Ends at", skip back/forward, previous/next episode, volume to 200%, full screen. Controls and the pointer hide while playing.
- Skip Intro and Skip Credits from Plex's markers (button or automatic), and Up Next with a countdown at an episode's final credits.
- A playback panel: audio track, audio delay, night mode, output device; subtitle track (including sidecar files), delay, size, height, colour, background with a live preview; quality from Original down to 0.7 Mbps, file version, fit/fill/stretch, deinterlace; speed 0.5–2×; sleep timer; chapters with thumbnails.
- Playback Info overlay with live mpv numbers (decoder, bitrate, dropped frames, buffer, HDR).
- Track choices are saved to the Plex server the way Plex's apps do. Subtitles move up while the controls show.
- Settings split into Servers, Playback, Audio & Subtitles, Video, Appearance and Advanced: home and away quality, direct play/stream, skip steps and behaviour, autoplay next and countdown, preferred audio and subtitle languages and subtitle mode, subtitle style, passthrough, speaker layout, hardware decoding, picture size, scaling, debanding, custom mpv options, clear image cache, reset, sign out and a keyboard shortcut list.
- More keys: K/J/L, M, C, A, S, N, P, [ ], 0–9, I.

## 0.5.0

- No top bar: the spotlight runs to the top of the window. Search is a frosted pill floating at the top right (Ctrl+F or / still jump to it), next to the window buttons.
- The sidebar hides until you move to the left edge (or move focus into it), slides in over the page and is more see-through. Requests shows its count there; Settings shows a red mark if Plex can't be reached.
- Top 10 numbers sit fully beside their posters, their foot on the poster's bottom edge.
- Bigger posters and more room between cards and rows.
- New Trending page in the sidebar: Netflix's official Top 10 (movies and series), Popular on Netflix, Prime Video, Max, Disney+, Apple TV+ and Hulu, then trending by genre. Titles you have open in your library; the rest can be requested.
- Settings > Discovery: an optional Trakt Client ID switches the genre rows to Trakt's live charts, and a streaming region for the "Popular on" rows.

## 0.4.0

- Named the app Liquiflux and started version numbers (shown in Settings and in the build).
- Spotlight: a re-roll button picks a fresh set of titles without restarting.
- Home: "Top 10 in Your Library" is now "Top in Your Library", re-picked with every spotlight re-roll and never repeating a spotlight title.
- Home: a "Top 10 Not in Your Library" row from Seerr, checked against your library so nothing you own shows there.
- Top 10 numbers take their colour from each poster.
- Left rail: bigger, centred icons, Settings on its own at the bottom, no separate search button.

## 0.3.0

- Netflix-style Home: a rotating spotlight of well-rated titles with muted trailer clips, hover previews, Top 10, Trending and genre rows.

## 0.2.0

- Frosted-glass surfaces and full title pages (cast and crew, ratings, file info, extras, reviews, episodes), the same for Plex and Seerr titles. Person pages and per-season requests.

## 0.1.0

- First Windows build: Plex sign-in, browsing, playback, search across Plex and Seerr, requests with progress and ETA.
