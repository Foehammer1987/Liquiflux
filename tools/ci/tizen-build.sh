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

echo "== Tizen SDK"
curl -fsSL "$TIZEN_SDK_URL" -o "$work/install.bin"
sha="$(sha256sum "$work/install.bin" | cut -d' ' -f1)"
echo "Tizen SDK installer sha256: $sha"
if [ -n "${TIZEN_SDK_SHA256:-}" ] && [ "$sha" != "$TIZEN_SDK_SHA256" ]; then
  echo "::error::The Tizen SDK installer changed (expected $TIZEN_SDK_SHA256)."
  exit 1
fi
chmod +x "$work/install.bin"
"$work/install.bin" --accept-license "$HOME/tizen-studio"
rm "$work/install.bin"
# shellcheck disable=SC2086
"$HOME/tizen-studio/package-manager/package-manager-cli.bin" install $TIZEN_PACKAGES
export PATH="$HOME/tizen-studio/tools/ide/bin:$HOME/tizen-studio/tools:$PATH"

echo "== flutter-tizen"
git clone -q https://github.com/flutter-tizen/flutter-tizen.git "$HOME/flutter-tizen"
git -C "$HOME/flutter-tizen" checkout -q --detach "$FLUTTER_TIZEN_COMMIT"
export PATH="$HOME/flutter-tizen/bin:$PATH"

# Tizen's CLI keeps certificate passwords in the keyring, so everything runs in one D-Bus
# session with an unlocked gnome-keyring.
dbus-run-session -- bash -euo pipefail -c '
  echo tizen | gnome-keyring-daemon --unlock >/dev/null
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
