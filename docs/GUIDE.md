# Liquiflux user guide

Liquiflux is a Plex client in the Console (UniFi-style) design, with Seerr built in. You search once: Plex titles play, and anything Plex doesn't have gets a **Request** button with a live progress bar, time left and finish time.

It runs on Windows and on Android TV (Nvidia Shield, Google TV, Fire TV) from the same code.

## Layout

| Path | What it is |
| --- | --- |
| `packages/console_core` | Pure Dart. Plex and Seerr clients, Plex sign-in, models, the request/progress state, formatters. Shared by every app. |
| `packages/console_ui` | Flutter. The Console design system: tokens (generated from the design system's `tokens.json`), theme, panels, buttons, badges, posters, progress bar. Works with mouse, keyboard and a TV remote's D-pad. |
| `app` | The app: Windows, Android TV (`app/android`), and Linux builds for testing. Screens, settings, mpv player. On Android it uses a 10-foot layout and the remote (`lib/platform.dart`). |
| `tools/mock-servers.mjs` | Fake Plex and Seerr for trying the app without real servers. |


## Install or build

Ready-made builds for Windows and Android TV are on the [Releases page](https://github.com/Foehammer1987/Liquiflux/releases/latest). To build it yourself, see [Build it yourself](../README.md#build-it-yourself) in the README; [ANDROID-TV.md](../ANDROID-TV.md) covers installing on each TV.

To try the TV layout on a PC, start a desktop build with `CONSOLE_TV=1` and use the arrow keys, Enter and Esc.

## Using it

1. **Sign In with Plex** opens your browser to approve the app, then finds your server and the fastest way to reach it. You can also enter an address and X-Plex-Token by hand.
2. **Seerr**: enter its address. By default it signs in with your Plex account, so requests are filed under your own Seerr user. You can use an API key instead, in which case requests go in as the key's owner (usually the admin) and are approved automatically.
3. Search with the box at the top (Ctrl+F or /). Esc goes back.

## Home

Home opens on a full-width spotlight that rotates through well-rated titles from your libraries (audience score 7 and up, unwatched titles more often, movies and shows alternating). A couple of seconds in, a muted clip of the title's trailer fades in behind it; the button by the rating unmutes it. Point at any title in the rows below and the spotlight switches to it and plays its trailer, then goes back to rotating when you move away.

The dice button next to the rating re-rolls the spotlight: a new set of titles, none from the set you just saw. **Top in Your Library** re-rolls with it, ranked by score, and never repeats a title the spotlight is showing.

Below the spotlight: Continue Watching, Requests in Progress, Top in Your Library, **Top 10 Not in Your Library** (TMDB's best-rated movies and series, checked against your Plex libraries by TMDB id and by title and year, and against Seerr, so nothing you own shows up there), **Because You Watched** rows built from what you've played lately (point at a card for thumbs up, which adds a "Because You Liked" row, or thumbs down, which hides the title for good), Recently Added, Trending titles you don't have (with Request), and a few genre rows. The big rank numbers take their colour from each poster.

Trailers come from Plex's own trailer extras (Plex Pass "Cinema Trailers" or local `-trailer` files). If a title has none and [yt-dlp](https://github.com/yt-dlp/yt-dlp) is on your PATH (`winget install yt-dlp`), the app plays the TMDB trailer from YouTube instead. Settings > Appearance > Home Trailers turns them off.

## Trending

The flame in the sidebar opens **Trending**, a mix of titles you have and titles you can request:

- **Top 10 Movies / Series on Netflix**: Netflix's own weekly chart (netflix.com/tudum/top10), matched to titles by name.
- **Popular on Netflix, Prime Video, Max, Disney+, Apple TV+, Hulu**: TMDB's daily popularity for what each service carries in your region (streaming data from JustWatch via TMDB). Set the region in Settings > Discovery.
- **By genre**: what's trending in each genre. With a Trakt Client ID in Settings > Discovery these are Trakt's live "watching now" charts; without one, TMDB's daily popularity. A Client ID is free and needs no sign-in from anyone using the app: make an app at trakt.tv/oauth/applications/new (any name, redirect `urn:ietf:wg:oauth:2.0:oob`) and copy its Client ID.

## Collections

The layers icon in the sidebar opens **Collections**: every film series you own at least one part of. Series come from TMDB's collections (looked up once per movie and cached on disk, so only the first visit takes a moment; after that the page opens at once and catches up in the background) and from your Plex collections, so trilogies like Unbreakable, Split and Glass show up without any setup. A series needs at least two films, announced ones included, so a collection of one is left out. Series you're partway through come first. The bar on each card has a light per film, lit for the ones you have, dim for the ones you're missing and outlined for ones not out yet; point at a card to read the series' story.

Each series has its own page: a cross-fade of its films' art, the series overview, how many films, the years, the total running time and the average score, and how much of it you have and have left to watch. **Start the Saga** (or **Continue**) plays the next film; **Marathon** plays everything you have from there in order, with Up Next between films. Below that: the films as a numbered timeline in release order with the years between them (point at one to bring its art into the header), a ratings chart, and the actors who appear in more than one film. Films you don't have are shown in place with Request, and **Request N Missing** asks for all of them.

## Moods

The sparkles icon in the sidebar opens **Moods**: your library as Netflix-style themed rows, such as Feel-Good Comedies, Dark Sci-Fi, Mind-Bending Mysteries, Binge-Worthy Series, Waiting on Your Shelf (unwatched, well rated, added over a year ago) and Worth a Rewatch, then every Plex genre. All / Movies / Series at the top. Plex has no moods for movies and shows, so each is a recipe over genres, year, running time, rating and what you've watched (packages/console_core/lib/src/moods.dart). A mood needs at least 8 titles to show. Home shows four of them, different ones each visit.

## Shuffle Play

The shuffle button in the sidebar picks something to watch from your libraries, better-rated titles more often. Filter by movies or shows, how long you've got, genre, and whether to skip things you've finished. Play starts it (a show starts at its next episode).

## Watch Together

There are two kinds of room.

**With a room code** (Open Watch Party, the rooms Plezy uses): Start a Room from the people button at the top of the player, or from Watch Together on a movie or episode page, and share the six-character code. Friends join with Join with a Code in Liquiflux, or from Plezy. Everyone plays their own copy from their own Plex server, found by catalogue ids and then by title; play, pause, jumps and speed stay in step, and the room waits for anyone buffering. The host's Up Next moves everyone on. Rooms run on the public relays at openwatch.party (`CONSOLE_OWP_RELAY=https://your.relay` uses your own).

**With Plex friends**: Watch Together uses Plex's own rooms (the ones Plex Web offers), so friends can join from Liquiflux or Plex Web. Start a room from the people button at the top of the player or on a title's page, pick from your Plex friends, and everyone's play, pause and jumps stay in step, with a note saying who did what. When a friend invites you, a card offers Join. Closing the player leaves the room; rooms close three hours after they open.

It needs Liquiflux signed in with your own Plex account (Settings > Servers > My Plex Account), and invites go to Plex friends and Home users only. Plex doesn't publish this service, so Liquiflux follows what Plex Web does; it may need updating if Plex changes it.

## Layout

There's no top bar: pages run to the top of the window, with search floating at the top right (Ctrl+F or /). The sidebar hides off the left edge; move the pointer to the edge (or move keyboard or remote focus left) to bring it in.

## Title pages

Every movie, show, season and episode opens a full page: art, ratings (IMDb, Rotten Tomatoes critics and audience, TMDB), content rating, runtime, genres, tagline and summary, who directed and wrote it, the studio or network, and what the file is (video, audio tracks, subtitles, size and bitrate). Below that are Cast & Crew, Extras (trailers and featurettes from Plex play in the app; TMDB trailers open on YouTube), Episodes with stills, critic reviews, More Like This, and similar titles you don't have yet with a Request button.

Titles that aren't in Plex use the same page, filled from Seerr, with Request where Play would be. Series can be requested whole or one season at a time.

Click anyone in Cast & Crew to see what they're in: their titles in your library first, then the rest of their work, ready to request.

Settings > Appearance switches between frosted-glass and flat surfaces (flat is lighter on old graphics cards) and between dark and light.

The Plex token, Seerr API key and Trakt client ID are kept only in the system's credential store: on Windows a file encrypted with DPAPI that only your Windows account can read (`flutter_secure_storage.dat`), on Linux the Secret Service keyring (GNOME Keyring or KWallet, through libsecret). They never go in `settings.json`, the caches or the logs (anything logged has tokens and keys scrubbed out), and a `settings.json` from an older build that still holds one is moved into the credential store and rewritten without it. On a Linux desktop with no keyring, sign-ins last until Liquiflux closes rather than being saved in plain text, and Settings says so. Addresses and preferences are in `%APPDATA%\com.foehammer\Liquiflux\settings.json` (settings from builds named Console are copied over on first launch).

The token only goes to your Plex server and plex.tv, and the Seerr key only to Seerr: a redirect to another host drops them, online trailers get no token, and Settings warns when a server is reached over plain http across the internet. Links from servers only open if they're http or https, yt-dlp only ever gets a YouTube link, and Advanced's custom mpv options are limited to a list of known-safe picture, audio, subtitle and cache settings, so nothing there can run programs, open control sockets, read or write files, or change how the player reaches the network.

## Playback

Video plays through mpv (media_kit). It direct plays the original file, so MKV, HEVC, AV1, DTS, TrueHD, styled (ASS) and picture (PGS) subtitles work without Plex converting them. If a file won't open, or you pick a lower quality, Plex's transcoder takes over. Watch progress goes back to Plex every 10 seconds, so Continue Watching stays current on all your devices.

The controls float on a frosted bar tinted from the title's own artwork, and hide after 3 seconds of playing (click toggles play, double click goes full screen):

- Scrubber with chapter breaks, intro and credits spans, and a time and chapter tip under the pointer. Remaining or total time, and when it ends.
- Skip back / forward (steps set in Settings), previous / next episode, volume up to 200% with Volume Boost.
- **Skip Intro / Skip Credits** from the markers Plex finds, as a button or automatically.
- **Up Next** at an episode's final credits (or 20 s before the end without markers), with a countdown that starts the next episode.
- A side panel with **Audio** (track, delay, night mode, volume boost, output device), **Subtitles** (track including sidecar files, **Find Online** to search OpenSubtitles through your Plex server and add one to the title, delay, size, height, colour including the title's own colour, outline / shadow / box, live preview), **Video** (quality ladder from Original down to 0.7 Mbps, file version, fit / fill / stretch, deinterlace), **Playback** (speed 0.5 to 2 with natural pitch, sleep timer) and **Chapters** (with thumbnails).
- **Mini Player** (B, or the button at the top of the player, on Windows): the title shrinks into a corner of the window and keeps playing while you browse, search and open pages behind it. Hover it for Play / Pause, Expand and Close; drag it to any corner; click the picture (or press B in the player) to go back to full window. Picking another title replaces it, and an actor picked in X-Ray opens their page with the title still playing in the corner. Home's spotlight holds still while it plays.
- Playback Info (I): direct play or transcode, codecs, resolution, HDR, hardware or software decoding, bitrate, dropped frames and buffer, live from mpv.

Track choices are saved to your Plex server like Plex's own apps do, so they carry over to the next episode and other devices. Subtitle style changes made while watching become your defaults.

Playing something you stopped part-way through asks whether to **resume or start again** (Settings can make it always do one). The Resume and Play from Start buttons on a title's page, Up Next and Watch Together don't ask.

After five seconds paused, a pause screen fades in with the title or its logo, the story, the main cast and the director. Click or press Space to carry on.

Player keys: Space or K play/pause, ←/→ (or J/L) skip, ↑/↓ volume, M mute, F full screen, C next subtitle, A next audio, S skip intro or credits (or play Up Next), N/P next or previous episode, [ / ] speed, 0 to 9 jump to that tenth, I info, B mini player (Windows), Esc closes the panel, then full screen, then the player.

## Settings

- **Servers**: Plex sign-in, then the add-ons, each off until you switch it on: Seerr (address and sign-in), Discovery (Trakt, streaming region; shown with Seerr on) and the X-Ray server. Sign out.
- **Playback**: streaming quality at home and away (picked by whether the server address is on your network), allow direct play and direct stream, skip steps, skip intro and credits (button, automatic or off), Up Next autoplay and countdown, what happens with a partly watched title (ask, resume or start over), the pause screen.
- **Audio & Subtitles**: preferred audio language (commentary is passed over), subtitle mode (Plex default, off, forced only, foreign audio, always) and language, subtitle style, passthrough to an AV receiver, speaker layout, night mode, volume boost.
- **Video**: hardware decoding, picture size, deinterlace, high quality scaling, debanding.
- **Appearance**: theme, frosted or flat surfaces, Home trailers, and **Spoilers**: blur the stills, hide the stories and hide the names of episodes you haven't watched (each on its own, all off to start).
- **Notifications**: when a request becomes available (yours, everyone's or off). Liquiflux shows a card with Play, or a Windows notification when it's in the background.
- **Advanced**: extra mpv options (one name=value per line), clear the image cache, reset playback settings, keyboard shortcuts, version.

## Request progress

Seerr reports request status (Pending Approval, Requested, Downloading, Available) and live download stats from Radarr and Sonarr: size, size left and estimated completion time. The app shows percent done, time left, the finish time and the size, refreshing every 10 seconds.

## Develop

```sh
cd packages/console_core && dart test
cd packages/console_ui && flutter test
node tools/mock-servers.mjs              # fake Plex :9001, Seerr :9002 and Watch Together :9003
cd app && CONSOLE_PLEX_URL=http://localhost:9001 CONSOLE_PLEX_TOKEN=x \
  CONSOLE_SEERR_URL=http://localhost:9002 CONSOLE_SEERR_KEY=x \
  CONSOLE_TMDB_IMAGES=http://localhost:9002/tmdb CONSOLE_NETFLIX_TOP10=http://localhost:9002/netflix/top10.tsv \
  CONSOLE_TRAKT_URL=http://localhost:9002/trakt CONSOLE_TRAKT_ID=dev \
  CONSOLE_TOGETHER_URL=http://localhost:9003 CONSOLE_PLEXTV_URL=http://localhost:9003 flutter run -d linux --no-tree-shake-icons
```

Release builds need `--no-tree-shake-icons`: trimming unused icons corrupts the Lucide icon font (some icons show as boxes). The build script and workflow already pass it.

Set `MOCK_VIDEO=/path/to/file.mkv` before starting the mock servers to test direct play. The mock lists 3 audio tracks, 4 embedded subtitles, a sidecar subtitle, chapters and intro / credits markers sized for a 75 second clip; a file with matching tracks can be made from any short video:

```sh
ffmpeg -i clip.mkv -i en.srt -i sdh.srt -i es.srt -i fr.srt -map 0:v -map 0:a -map 0:a -map 0:a -map 1 -map 2 -map 3 -map 4 -c copy -c:s srt multi.mkv
```

The mock Watch Together service has three friends; "Alex" joins every room and, a few seconds in, pauses, plays and jumps back so you can watch the sync. An invitation from Alex arrives `MOCK_INVITE_AT` seconds after start (240 by default), and a request turns available about 3.5 minutes in.

## Versions

Versions follow `major.minor.patch` (semantic versioning), starting at 0.x while things settle: a new feature bumps the minor number, a fix bumps the patch. The version lives in `app/pubspec.yaml` and `app/lib/app_info.dart` (a test keeps them in step), shows at the bottom of Settings, and is stamped into `Liquiflux.exe`; a push of a new version to `main` publishes a GitHub release. `CHANGELOG.md` lists what changed in each one.

## Notes

- The logo and design are for personal, non-commercial use. Inter and JetBrains Mono are under the SIL Open Font License.
