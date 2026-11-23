#!/bin/sh
# Screenshots of every iPhone/iPad screen from a simulator, through
# app/integration_test/touch_tour_test.dart. Start the fake servers first
# (node tools/mock-servers.mjs) for the signed-in tour, which signs in to them as Enter Address
# Manually would.
#
#   tools/ios-tour.sh <simulator name or udid> <out folder> [app|welcome|polish|signin|real] [prefix]
#
# signin and real keep the app installed between runs: signin prints a plex.tv/link code
# ("CODE ABCD") and waits for it (SERVER=<name> picks the server), then real plays from it.
#
# Each "SHOT name" the tour prints becomes <out folder>/<prefix>-<name>.png.
set -eu
sim=$1; out=$2; tour=${3:-app}; prefix=${4:-$(echo "$sim" | tr ' ()' '-__' | tr -s '-_')}
mkdir -p "$out"
cd "$(dirname "$0")/../app"
udid=$(xcrun simctl list devices available | grep -F "$sim (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$udid" ] || udid=$sim
xcrun simctl boot "$udid" 2>/dev/null || true
# A fresh start: no sign-in or settings from an earlier run (but a real sign-in is kept).
case "$tour" in signin|real) ;; *) xcrun simctl uninstall "$udid" com.foehammer.liquiflux 2>/dev/null || true ;; esac
flutter test integration_test/touch_tour_test.dart -d "$udid" --no-uninstall --dart-define=TOUR="$tour" --dart-define=SERVER="${SERVER:-}" --dart-define=SKIP="${SKIP:-}" --dart-define=LIQUIFLUX_STORE=apple 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *"SHOT "*) name=${line##*SHOT }; xcrun simctl io "$udid" screenshot "$out/$prefix-$name.png" >/dev/null 2>&1 && echo "  -> $out/$prefix-$name.png" ;;
      # Leave the app (Settings comes to the front) and come back to it.
      # (iOS suspends the app in the background, tour and all, so this side brings it back.)
      *"HOST bg"*) xcrun simctl launch "$udid" com.apple.Preferences >/dev/null 2>&1; sleep 8; xcrun simctl launch "$udid" com.foehammer.liquiflux >/dev/null 2>&1 ;;
    esac
  done
