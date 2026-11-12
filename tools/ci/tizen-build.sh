#!/usr/bin/env bash
# Builds the Samsung TPK for one Tizen version group in CI (.forgejo/workflows/tizen.yml).
# Runs as an ordinary user: Tizen's SDK installer refuses to run as root.
#
# Env: TIZEN_API (6.0, 6.5 or 10.0), TIZEN_PACKAGES (package-manager packages to install),
# TIZEN_SDK_URL, TIZEN_SDK_SHA256 (optional), FLUTTER_TIZEN_COMMIT, and optionally the
# certificate secrets AUTHOR_P12 / AUTHOR_PASSWORD / DISTRIBUTOR_P12 / DISTRIBUTOR_PASSWORD
# (base64 .p12 files). Without them a throwaway certificate signs the TPK.
set -euo pipefail
: "${TIZEN_API:?}" "${TIZEN_PACKAGES:?}" "${TIZEN_SDK_URL:?}" "${FLUTTER_TIZEN_COMMIT:?}"

root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work" "$HOME/tizen-studio-data/keystore"' EXIT

# Retries a network command a few times: one dropped DNS lookup shouldn't fail a 10-minute job.
retry() {
  local n
  for n in 1 2 3; do
    "$@" && return 0
    [ "$n" -lt 3 ] && { echo "Attempt $n failed: $*; retrying in 10 s."; sleep 10; }
  done
  return 1
}

# The prebuilt CI image (tools/ci/tizen-image) already has the SDK, the packages and
# flutter-tizen; each step below only does what is missing, so a plain image still works.
echo "== Tizen SDK"
pm="$HOME/tizen-studio/package-manager/package-manager-cli.bin"
if [ -x "$pm" ]; then
  echo "Tizen SDK already installed."
else
  retry curl -fsSL "$TIZEN_SDK_URL" -o "$work/install.bin"
  sha="$(sha256sum "$work/install.bin" | cut -d' ' -f1)"
  echo "Tizen SDK installer sha256: $sha"
  if [ -n "${TIZEN_SDK_SHA256:-}" ] && [ "$sha" != "$TIZEN_SDK_SHA256" ]; then
    echo "::error::The Tizen SDK installer changed (expected $TIZEN_SDK_SHA256)."
    exit 1
  fi
  chmod +x "$work/install.bin"
  "$work/install.bin" --accept-license "$HOME/tizen-studio"
  rm "$work/install.bin"
fi
installed="$HOME/tizen-studio/.liquiflux-ci-packages"
missing=""
for p in $TIZEN_PACKAGES; do
  grep -qxF "$p" "$installed" 2>/dev/null || missing="$missing $p"
done
if [ -n "$missing" ]; then
  # shellcheck disable=SC2086
  "$pm" install $missing
  printf '%s\n' $missing >> "$installed"
else
  echo "Tizen packages already installed: $TIZEN_PACKAGES"
fi
export PATH="$HOME/tizen-studio/tools/ide/bin:$HOME/tizen-studio/tools:$PATH"

echo "== flutter-tizen"
ft="$HOME/flutter-tizen"
if [ "$(git -C "$ft" rev-parse HEAD 2>/dev/null)" = "$FLUTTER_TIZEN_COMMIT" ]; then
  echo "flutter-tizen already at $FLUTTER_TIZEN_COMMIT."
else
  [ -d "$ft/.git" ] || retry git clone -q https://github.com/flutter-tizen/flutter-tizen.git "$ft"
  git -C "$ft" cat-file -e "$FLUTTER_TIZEN_COMMIT^{commit}" 2>/dev/null \
    || retry git -C "$ft" fetch -q origin
  git -C "$ft" checkout -q --detach "$FLUTTER_TIZEN_COMMIT"
fi
export PATH="$ft/bin:$PATH"
# The first flutter-tizen call clones Flutter and downloads the Dart SDK when the image hasn't.
retry flutter-tizen --version >/dev/null

# Tizen's CLI keeps certificate passwords in the keyring, so everything runs in one D-Bus
# session with an unlocked gnome-keyring. Start from no keyring at all (a leftover login.keyring
# made with another password reads as "invalid format"), and wait until the daemon owns the
# secrets service before the CLI asks for it: on a busy runner the CLI could otherwise
# D-Bus-activate a second daemon, store the passwords there, and the signing step then read
# back a wrong one ("PKCS12 key store MAC invalid").
rm -rf "$HOME/.local/share/keyrings"
dbus-run-session -- bash -euo pipefail -c '
  echo tizen | gnome-keyring-daemon --unlock >/dev/null
  for _ in $(seq 1 50); do
    dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.NameHasOwner string:org.freedesktop.secrets 2>/dev/null \
      | grep -q "boolean true" && break
    sleep 0.2
  done
  keys="$0"
  if [ -n "${AUTHOR_P12:-}" ] && [ -n "${DISTRIBUTOR_P12:-}" ]; then
    echo "Signing with the repository'"'"'s Samsung certificate."
    printf "%s" "$AUTHOR_P12" | base64 -d > "$keys/author.p12"
    printf "%s" "$DISTRIBUTOR_P12" | base64 -d > "$keys/distributor.p12"
    tizen security-profiles add -n liquiflux -a "$keys/author.p12" -p "$AUTHOR_PASSWORD" \
      -d "$keys/distributor.p12" -dp "$DISTRIBUTOR_PASSWORD" -A
  else
    echo "::notice::No Samsung certificate secrets: signing with a throwaway certificate. These TPKs will not install on a TV."
    tizen certificate -a liquiflux -p liquiflux -f throwaway
    tizen security-profiles add -n liquiflux -a "$HOME/tizen-studio-data/keystore/author/throwaway.p12" -p liquiflux -A
  fi
  flutter-tizen doctor -v
  TIZEN_SECURITY_PROFILE=liquiflux "$1/tools/build-tizen.sh" "$2"
' "$work" "$root" "$TIZEN_API"
