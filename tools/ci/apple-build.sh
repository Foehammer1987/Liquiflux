#!/bin/bash
# Debug build of one Apple target for .forgejo/workflows/apple.yml, on the Mac runner.
#
#   tools/ci/apple-build.sh macos|ios|tvos
#
# The runner (host mode) checks each job out into a new random folder, and Xcode keys its
# DerivedData (intermediate builds, the Swift packages such as AetherEngine and FFmpeg) on the
# project's path. Built there, every job would start cold, copy the Swift packages again and
# leave another DerivedData folder behind. So this copies the checkout into one fixed folder
# per target, ~/forgejo-runner/apple-build/<target> (APPLE_BUILD_DIR overrides the parent), and
# builds there: DerivedData, Pods and .dart_tool carry over from the last run, while the
# downloads stay in their usual shared caches (~/.pub-cache, ~/Library/Caches/org.swift.swiftpm,
# ~/.cocoapods, the Flutter and flutter-tvos bin/cache folders). Afterwards it deletes only that
# run's build output (app/build), never the caches.
set -euo pipefail

target=${1:?usage: apple-build.sh macos|ios|tvos}
case $target in
  macos) cmd=(flutter build macos --debug) ;;
  ios) cmd=(flutter build ios --simulator --debug) ;;
  tvos) cmd=(flutter-tvos build tvos --simulator --debug) ;;
  *) echo "unknown target: $target" >&2; exit 2 ;;
esac
flutter=${cmd[0]}

src=$(git rev-parse --show-toplevel)
dir="${APPLE_BUILD_DIR:-$HOME/forgejo-runner/apple-build}/$target"
mkdir -p "$dir"

# Mirror the checkout. The excluded folders are generated, never tracked, and are what make
# the next build warm; --delete still drops files the commit no longer has.
rsync -a --delete \
  --exclude=/.git/ --exclude=/app/build/ --exclude=.dart_tool/ --exclude=Pods/ \
  --exclude=.symlinks/ --exclude=ephemeral/ \
  "$src/" "$dir/"

trap 'rm -rf "$dir/app/build"' EXIT
cd "$dir/app"
"$flutter" --version
"$flutter" pub get
"${cmd[@]}"
