# Builds and CI

Liquiflux has two git homes, and each has its own workflows folder:

| | Forgejo (self-hosted) | GitHub |
| --- | --- | --- |
| Used for | Day-to-day work: branches, pull requests, test builds | Public releases, once code with working builds is pushed there |
| Workflows | `.forgejo/workflows/` | `.github/workflows/` |
| Builds | Tests, Android TV APKs, Samsung TPKs, as run artifacts | Tests, Windows installer and zip, Android TV APKs, Samsung TPKs |
| Publishes | Forgejo releases and pre-releases from `v*` tags | GitHub releases (which the in-app updater reads) and WinGet |

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
- `release.yml`: on a pushed tag `v<version>` (it must match `version:` in `app/pubspec.yaml`).
  Builds the APKs, the Windows zip and installer and the three TPKs, all signed with the real
  keys (it fails rather than ship throwaway-signed files), and publishes them with one
  `SHA256SUMS.txt` as a Forgejo release. `v1.0.15-rc1`, `-rc2`... make pre-releases (test
  builds); `v1.0.15` makes a normal release with that version's `CHANGELOG.md` section. It never
  touches GitHub, and the rc tags stay on Forgejo.
- `collection-pack.yml`: on the 1st of each month (and Run workflow) rebuilds the TV collection
  pack and opens a pull request with it on a `collection-pack/<date>` branch, instead of
  committing to `main`. On GitHub the same workflow now only runs by hand or when its builder
  changes on a branch.

The Linux jobs run on the self-hosted runner (label `docker`) inside two local images, built
once on the runner's Docker host so jobs don't install the same tools every run:

| Image | Built from | Used by | Has |
| --- | --- | --- | --- |
| `liquiflux-flutter-ci:1` | `tools/ci/flutter-image/Dockerfile` (on `ghcr.io/catthehacker/ubuntu:act-24.04`) | `build.yml` test and android, `release.yml` android | Pinned Flutter, JDK 17, Android SDK, NDK and Gradle downloads |
| `liquiflux-tizen-ci:1` | `tools/ci/tizen-image/Dockerfile` (on `ghcr.io/catthehacker/ubuntu:act-22.04`) | `tizen.yml`, `release.yml` tizen | Tizen SDK and packages for all three version groups, flutter-tizen at the pinned commit |

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

## Promoting to GitHub

`tools/promote-to-github.ps1` moves code from Forgejo to GitHub, once a day, run on a PC with a
clone of the Forgejo repository (its `origin`). It:

1. fetches Forgejo's `main` and picks the newest of its last 20 commits whose Forgejo checks all
   passed, including the `build` and `tizen` workflows;
2. fetches GitHub's `main` (read only). If the app version differs from GitHub's, that version
   has to be released on Forgejo first: it promotes the commit tagged `v<version>` (the final
   tag, not an rc), exactly that commit, which must be green and have that version. Without the
   tag it stops and says which tag to make. Then it stops if GitHub already has that commit,
   and if GitHub's `main` isn't an ancestor of it (it never forces);
3. stops if the last promotion was less than 24 hours ago (`-MinHours`);
4. checks the new commits: author and committer emails must be GitHub noreply addresses (or
   Claude's / the Actions bot's), and no added line may hold a LAN address, a local path, the
   PC's name or user name, or a word from `%LOCALAPPDATA%\Liquiflux\promote-blocklist.txt` (one
   per line: other machine names, private email addresses; this file stays on the PC);
5. pushes that commit to GitHub's `main`, no tags, and logs it in
   `%LOCALAPPDATA%\Liquiflux\promote.log`.

GitHub's `release.yml` then publishes a release when the app version is new: plain `v1.0.15`,
never the Forgejo rc tags.

WinGet: after a GitHub release, Sync fork on Foehammer1987/winget-pkgs, then Actions > WinGet >
Run workflow with the version.

So a new version reaches GitHub like this: bump the version on Forgejo, test it with
`v1.0.15-rc1`, `-rc2`... (pre-releases on Forgejo only), then tag `v1.0.15` on the commit you
want released. The next run pushes that commit, and GitHub makes its v1.0.15 release from it.
Until then, nothing after the bump goes to GitHub. Commits that don't change the version flow
every day as usual.

`-DryRun` does every check without pushing. Exit codes: 0 pushed or nothing to do, 1 setup
error, 2 not yet (including a new version without its release tag), 3 histories split, 4 scrub
check failed, 5 push failed, 6 the release tag is wrong (another version, or not on `main`).

To run it daily, add a Task Scheduler task running
`powershell -ExecutionPolicy Bypass -File <clone>\tools\promote-to-github.ps1`.

Token setup: GitHub > Settings > Developer settings > Fine-grained tokens > Generate new token.
Repository access: only this repository. Permissions: Contents and Workflows, read and write.
Expiry: 90 days (renew it when the push starts failing with exit code 5). Save it as a user
environment variable `GITHUB_PROMOTE_TOKEN`. The script also needs `FORGEJO_URL` and
`FORGEJO_TOKEN` to read the Forgejo checks. Tokens are only handed to git and the API in memory,
never written to disk, remotes or the log.

## The Windows runner

Windows jobs (`runs-on: windows`) need a runner on a Windows PC: Forgejo's Docker runner only
runs Linux. Forgejo's own runner has no Windows build, so it's Gitea's runner
(`gitea-runner`, formerly `act_runner`) in host mode, registered for your Forgejo user (all of
its repositories) with the single label `windows:host`, capacity 1, started at logon by a
scheduled task ("Forgejo runner") as the PC's user. It needs Git, Node.js, Flutter, Visual
Studio's C++ tools, Inno Setup 6 (found on PATH or in its default install folders) and, for
X-Ray Desktop, 64-bit Python 3.12. While the PC is off, Windows jobs wait in the queue.

Host mode has no container: a workflow runs as that user, with everything that user can reach.
Keep it to private repositories that only trusted people push to.

Without a Windows runner, `tools/build-windows.ps1` builds Windows locally.
