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
- `build.yml` also has a `windows` job: the Windows zip and installer
  (`Liquiflux-<version>-windows-x64.zip`, `Liquiflux-<version>-Setup-x64.exe`), built on a
  Windows runner (see below).
- `tizen.yml`: on pull requests that touch the app, pushes to `main` and Run workflow. Three
  TPKs, one per Tizen version group (see `TIZEN.md`).

The Linux jobs run on the self-hosted runner (label `docker`) inside two local images, built
once on the runner's Docker host so jobs don't install the same tools every run:

| Image | Built from | Used by | Has |
| --- | --- | --- | --- |
| `liquiflux-flutter-ci:1` | `tools/ci/flutter-image/Dockerfile` (on `ghcr.io/catthehacker/ubuntu:act-24.04`) | `build.yml` test and android | Pinned Flutter, JDK 17, Android SDK, NDK and Gradle downloads |
| `liquiflux-tizen-ci:1` | `tools/ci/tizen-image/Dockerfile` (on `ghcr.io/catthehacker/ubuntu:act-22.04`) | `tizen.yml` | Tizen SDK and packages for all three version groups, flutter-tizen at the pinned commit |

Build them with `docker build -t <image> <folder with the Dockerfile>`. They aren't pushed to a
registry; the runner uses the local copy. Rebuild with a new tag, and bump `image:` in the
workflow, when `FLUTTER_VERSION`, `ANDROID_CMDLINE_TOOLS`, `FLUTTER_TIZEN_COMMIT` or the Tizen
SDK change. A build needs about 15 GB free on the Docker host.

`tools/ci/setup-flutter.sh` and `tools/ci/tizen-build.sh` only install what the image lacks, so
pointing `image:` back at the catthehacker images still works (slower). Between runs the jobs
cache only the pub packages and media_kit's libmpv jars.

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

## The Windows runner

Windows jobs (`runs-on: windows`) need a runner on a Windows PC: Forgejo's Docker runner only
runs Linux. Forgejo's own runner has no Windows build, so it's Gitea's runner
(`gitea-runner`, formerly `act_runner`) in host mode, registered for the forgeadmin user (all of
its repositories) with the single label `windows:host`, capacity 1, started at logon by a
scheduled task ("Forgejo runner") as the PC's user. It needs Git, Node.js, Flutter, Visual
Studio's C++ tools, Inno Setup 6 (found on PATH or in its default install folders) and, for
X-Ray Desktop, 64-bit Python 3.12. While the PC is off, Windows jobs wait in the queue.

Host mode has no container: a workflow runs as that user, with everything that user can reach.
Keep it to private repositories that only trusted people push to.

Without a Windows runner, `tools/build-windows.ps1` builds Windows locally.
