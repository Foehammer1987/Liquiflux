import 'platform.dart' show isApple;

/// The app's name and version, in one place. The version must match `version:` in
/// pubspec.yaml (a test checks), which also stamps the Windows .exe.
const appName = 'Liquiflux';
const appVersion = '1.1.11';

/// Works with Plex, but isn't Plex's: the line Plex's trademark guidelines ask for (shown in
/// Settings > Advanced, the README and the store listings).
const plexAttribution = 'Works with Plex. Plex is a trademark of Plex, Inc. $appName is not affiliated with or endorsed by Plex, Inc.';

/// Liquiflux's source code (MIT). Its README says how to build it, including with your own
/// mpv or FFmpeg (the LGPL lets you; docs/native-licenses.md).
const sourceCodeUrl = 'https://github.com/Foehammer1987/Liquiflux';

/// Liquiflux's privacy policy, linked from Settings > Advanced > About (and the store listings).
const privacyPolicyUrl = 'https://liquiflux.app/privacy';

/// The name the first builds used; settings saved under it are carried over once.
const previousAppNames = ['Console'];

/// Set for an app-store build (`--dart-define=LIQUIFLUX_STORE=amazon`): the store updates the
/// app, so the in-app updater is off, and the sleep timer can't turn the TV off (no
/// accessibility service). Empty for the GitHub builds.
const storeBuild = String.fromEnvironment('LIQUIFLUX_STORE');

/// Whether the app looks for and installs its own updates (Settings > Advanced > Updates).
/// Not in a store build, and never on Apple's platforms (Mac, iPhone, iPad, Apple TV): the
/// App Store doesn't allow an app to fetch new code (guideline 2.5.2), and there's no
/// installer for them outside it either.
final bool selfUpdates = storeBuild.isEmpty && !isApple;

/// Whether this build has the TV Networks page and the Networks & Blocks channel sources
/// (the bundled collection pack of real network and block names, with posters of shows you
/// may not own).
/// The Samsung and Apple store builds leave all of it out, for the store review.
const tvNetworksInBuild = storeBuild != 'samsung' && storeBuild != 'apple';

/// Whether Trending has the rows named after streaming services ("Top 10 Movies on Netflix",
/// "Popular on Prime Video"). The App Store build (LIQUIFLUX_STORE=apple) leaves them out:
/// Apple doesn't want other companies' brands in an app without their permission
/// (guideline 4.1(c)/5.2.1). Samsung's build keeps them.
const brandRowsInBuild = storeBuild != 'apple';
