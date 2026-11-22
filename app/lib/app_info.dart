/// The app's name and version, in one place. The version must match `version:` in
/// pubspec.yaml (a test checks), which also stamps the Windows .exe.
const appName = 'Liquiflux';
const appVersion = '1.1.5';

/// Works with Plex, but isn't Plex's: the line Plex's trademark guidelines ask for (shown in
/// Settings > Advanced, the README and the store listings).
const plexAttribution = 'Works with Plex. Plex is a trademark of Plex, Inc. $appName is not affiliated with or endorsed by Plex, Inc.';

/// The name the first builds used; settings saved under it are carried over once.
const previousAppNames = ['Console'];

/// Set for an app-store build (`--dart-define=LIQUIFLUX_STORE=amazon`): the store updates the
/// app, so the in-app updater is off, and the sleep timer can't turn the TV off (no
/// accessibility service). Empty for the GitHub builds.
const storeBuild = String.fromEnvironment('LIQUIFLUX_STORE');

/// Whether this build has the TV Networks page and the Networks & Blocks channel sources
/// (the bundled collection pack of real network and block names, with posters of shows you
/// may not own). The Samsung store build leaves all of it out, for the store review.
const tvNetworksInBuild = storeBuild != 'samsung';
