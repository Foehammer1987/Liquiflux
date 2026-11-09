# Builds and CI

Liquiflux has two git homes, and each has its own workflows folder:

| | Forgejo (self-hosted) | GitHub |
| --- | --- | --- |
| Used for | Day-to-day work: branches, pull requests, test builds | Public releases, once code with working builds is pushed there |
| Workflows | `.forgejo/workflows/` | `.github/workflows/` |
| Builds | Tests, Android TV APKs, Samsung TPKs, as run artifacts | Tests, Windows installer and zip, Android TV APKs, Samsung TPKs |
| Publishes | Nothing | GitHub releases (which the in-app updater reads) and WinGet |

Forgejo only reads `.forgejo/workflows` once that folder exists, and GitHub never reads it, so
the same repository works on both without either running the other's workflows. Keep both
sets building the same way: a change to how the app is built goes into both files.

## Forgejo workflows

- `build.yml`: on every pull request, push to `main`, and Run workflow. Runs the
  `console_core`, `console_ui` and app tests (also as a TV), then builds the release APKs for
  `armeabi-v7a` (32-bit TVs such as the Shield) and `arm64-v8a`, named
  `Liquiflux-<version>-android-tv-<abi>.apk`, with a `SHA256SUMS.txt`. Download them from the
  run's page (Artifacts).
- `tizen.yml`: on pull requests that touch the app, pushes to `main` and Run workflow. Three
  TPKs, one per Tizen version group (see `TIZEN.md`).

Both run on the self-hosted runner (label `docker`) inside containers: `node:22-bookworm` for
Flutter and Android, `ghcr.io/catthehacker/ubuntu:act-22.04` for Tizen.
`tools/ci/setup-flutter.sh` installs the pinned Flutter (checked against its SHA-256), JDK 17
and the Android SDK command-line tools; Gradle then fetches the rest. Flutter, the Android SDK,
pub and Gradle are cached between runs when the runner has a cache.

Artifacts use `https://code.forgejo.org/forgejo/upload-artifact`, Forgejo's build of the upload
action (GitHub's newer upload-artifact versions don't work with Forgejo).

### Secrets

Add them in Forgejo under the repository's Settings > Actions > Secrets. Without them every
build still runs, signed with a throwaway key.

| Secret | What |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The APK signing key (`.jks`), base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Its store password |
| `ANDROID_KEY_ALIAS` | Its key alias |
| `ANDROID_KEY_PASSWORD` | Its key password |
| `TIZEN_AUTHOR_P12_BASE64` | Samsung author certificate, base64-encoded |
| `TIZEN_AUTHOR_PASSWORD` | Its password |
| `TIZEN_DISTRIBUTOR_P12_BASE64` | Samsung distributor certificate, base64-encoded |
| `TIZEN_DISTRIBUTOR_PASSWORD` | Its password |

`tools/export-signing-key.ps1` prints the four Android values from the key that
`tools/build-android.ps1` made in `%USERPROFILE%\.liquiflux`, so CI APKs install as updates
over PC builds. Use the same names on GitHub.

## Moving builds to GitHub

When a version builds cleanly on Forgejo, push `main` (and its tags) to GitHub, either by hand
(`git push github main`) or with a push mirror (Forgejo: Settings > Repository > Mirror
settings, with a GitHub token that can push). A push to GitHub's `main` with a new `version:` in
`app/pubspec.yaml` makes `.github/workflows/release.yml` publish the release there.

Windows builds only run on GitHub (Windows runners) or on a PC: the Forgejo runner is Linux.
`tools/build-windows.ps1` builds Windows locally.
