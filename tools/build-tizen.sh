#!/usr/bin/env bash
# Builds Liquiflux for Samsung TVs: one signed TPK per Tizen version group (see TIZEN.md).
#
#   tools/build-tizen.sh [6.0|6.5|10.0 ...]      (all three when none are given)
#
# Needs flutter-tizen on PATH and the Tizen SDK (CLI) with the matching native packages, and
# an active certificate profile (Tizen's Certificate Manager, or `tizen security-profiles`).
# Set TIZEN_SECURITY_PROFILE to pick a profile by name. Output: dist/Liquiflux-<version>-tizen-<api>.tpk
#
# Why three packages: Samsung's player plugin (video_player_avplay) ships a native library
# per Tizen version, and a package only runs on the versions its api-version covers:
#   6.0  -> 2021 TVs (Tizen 6.0)
#   6.5  -> 2022-2025 TVs (Tizen 6.5 to 9.0)
#   10.0 -> 2026 TVs (Tizen 10.0)
# Seller Office takes each as the package for those model groups. Each gets its own version,
# as Samsung's plugin notes ask: the app's x.y.z becomes x.y.(z*100 + n), n = 0, 1, 2 for the
# three groups, so 1.0.12 ships as 1.0.1200, 1.0.1201 and 1.0.1202, and every later release
# is still higher than every earlier one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/app"
manifest="$app/tizen/tizen-manifest.xml"
groups=("$@")
[ ${#groups[@]} -eq 0 ] && groups=(6.0 6.5 10.0)

version="$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$app/pubspec.yaml")"
[ -n "$version" ] || { echo "No version in app/pubspec.yaml" >&2; exit 1; }
IFS=. read -r major minor patch <<<"$version"

group_index() {
  case "$1" in
    6.0) echo 0 ;;
    6.5) echo 1 ;;
    10.0) echo 2 ;;
    *) echo "Unknown Tizen group $1 (use 6.0, 6.5 or 10.0)" >&2; exit 1 ;;
  esac
}

mkdir -p "$root/dist"
original="$(cat "$manifest")"
trap 'printf "%s\n" "$original" > "$manifest"' EXIT

for api in "${groups[@]}"; do
  n="$(group_index "$api")"
  tpk_version="$major.$minor.$((patch * 100 + n))"
  echo "== Tizen $api: Liquiflux $version as package version $tpk_version"
  printf "%s\n" "$original" \
    | sed -E "/<manifest /{s/ version=\"[^\"]*\"/ version=\"$tpk_version\"/; s/ api-version=\"[^\"]*\"/ api-version=\"$api\"/}" \
    > "$manifest"
  grep -q " version=\"$tpk_version\" api-version=\"$api\"" "$manifest" || { echo "Couldn't set the version in tizen-manifest.xml" >&2; exit 1; }
  rm -rf "$app/build/tizen/tpk"
  (
    cd "$app"
    # A store build: no update check or self-updater (the store updates the app).
    flutter-tizen build tpk --release --device-profile tv \
      --dart-define=LIQUIFLUX_STORE=samsung \
      ${TIZEN_SECURITY_PROFILE:+--security-profile "$TIZEN_SECURITY_PROFILE"}
  )
  tpk="$(ls "$app"/build/tizen/tpk/*.tpk | head -n 1)"
  cp "$tpk" "$root/dist/Liquiflux-$version-tizen-$api.tpk"
  echo "   -> dist/Liquiflux-$version-tizen-$api.tpk"
done
