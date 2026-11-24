# liquiflux_aether

The Apple TV player, a tvOS-only Flutter plugin used through flutter-tvos.

The native side (`tvos/Classes/LiquifluxAetherPlugin.swift`) drives
[AetherEngine](https://github.com/superuser404notfound/AetherEngine) (LGPL-3.0 with an App
Store exception), pinned to one release tag in `tvos/Package.swift`. Its picture is an
`AetherPlayerView` placed behind the Flutter view, which is made transparent, so the app
draws its controls and subtitles over the video where it leaves the screen clear (the same
"hole" the Samsung build uses).

The Dart side (`lib/liquiflux_aether.dart`) is a thin channel API; the app wraps it as a
media_kit `PlatformPlayer` (`app/lib/services/aether_player.dart`).

Other platforms don't build this plugin: only `tvos` is listed in `pubspec.yaml`.
