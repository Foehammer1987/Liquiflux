#!/usr/bin/env bash
# Sets up a CI job container for Liquiflux (used by .forgejo/workflows, which run in plain
# Ubuntu/Debian containers on a self-hosted runner, so little is preinstalled).
#
#   tools/ci/setup-flutter.sh            Flutter only (tests)
#   tools/ci/setup-flutter.sh android    Flutter, JDK 17 and the Android SDK command-line tools
#
# Pinned by version and checksum: FLUTTER_VERSION / FLUTTER_SHA256 and, for Android,
# ANDROID_CMDLINE_TOOLS / ANDROID_CMDLINE_TOOLS_SHA256 (set in the workflow's env).
# Installs into /opt (cached between runs by the workflow when the runner has a cache).
# Adds the tools to PATH for later steps through $GITHUB_PATH, which Forgejo Actions and
# GitHub Actions both read.
set -euo pipefail

want_android=false
[ "${1:-}" = android ] && want_android=true

: "${FLUTTER_VERSION:?set FLUTTER_VERSION}"
: "${FLUTTER_SHA256:?set FLUTTER_SHA256}"

export DEBIAN_FRONTEND=noninteractive
pkgs=(curl git unzip xz-utils zip ca-certificates)
$want_android && pkgs+=(openjdk-17-jdk-headless)
missing=()
for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${missing[@]}"
fi

# Jobs run as root, and the checkout and the Flutter SDK are owned by someone else.
git config --global --add safe.directory '*'

flutter_dir=/opt/flutter
if [ "$(cat "$flutter_dir/version" 2>/dev/null || true)" != "$FLUTTER_VERSION" ] \
  && [ "$("$flutter_dir/bin/flutter" --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')" != "$FLUTTER_VERSION" ]; then
  rm -rf "$flutter_dir"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  echo "Downloading Flutter $FLUTTER_VERSION"
  curl -fsSL "$url" -o /tmp/flutter.tar.xz
  echo "$FLUTTER_SHA256  /tmp/flutter.tar.xz" | sha256sum -c -
  tar -xJf /tmp/flutter.tar.xz -C /opt
  rm /tmp/flutter.tar.xz
fi
echo "$flutter_dir/bin" >> "$GITHUB_PATH"
export PATH="$flutter_dir/bin:$PATH"
flutter config --no-analytics >/dev/null
dart --disable-analytics >/dev/null 2>&1 || true

if $want_android; then
  : "${ANDROID_CMDLINE_TOOLS:?set ANDROID_CMDLINE_TOOLS}"
  sdk=/opt/android-sdk
  tools="$sdk/cmdline-tools/latest"
  if [ ! -x "$tools/bin/sdkmanager" ]; then
    url="https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip"
    echo "Downloading Android command-line tools $ANDROID_CMDLINE_TOOLS"
    curl -fsSL "$url" -o /tmp/cmdline-tools.zip
    sha="$(sha256sum /tmp/cmdline-tools.zip | cut -d' ' -f1)"
    echo "Android command-line tools sha256: $sha"
    if [ -n "${ANDROID_CMDLINE_TOOLS_SHA256:-}" ] && [ "$sha" != "$ANDROID_CMDLINE_TOOLS_SHA256" ]; then
      echo "::error::The Android command-line tools download changed (expected $ANDROID_CMDLINE_TOOLS_SHA256)."
      exit 1
    fi
    rm -rf "$sdk/cmdline-tools"
    mkdir -p "$sdk/cmdline-tools"
    unzip -q /tmp/cmdline-tools.zip -d "$sdk/cmdline-tools"
    mv "$sdk/cmdline-tools/cmdline-tools" "$tools"
    rm /tmp/cmdline-tools.zip
  fi
  java_home="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
  {
    echo "ANDROID_HOME=$sdk"
    echo "ANDROID_SDK_ROOT=$sdk"
    echo "JAVA_HOME=$java_home"
  } >> "$GITHUB_ENV"
  echo "$tools/bin" >> "$GITHUB_PATH"
  export ANDROID_HOME="$sdk" JAVA_HOME="$java_home"
  # Gradle fetches the platform, build tools and NDK the app asks for, once the licenses
  # are accepted.
  yes | "$tools/bin/sdkmanager" --sdk_root="$sdk" --licenses >/dev/null || true
  "$tools/bin/sdkmanager" --sdk_root="$sdk" "platform-tools" >/dev/null
  flutter config --android-sdk "$sdk" >/dev/null
fi

flutter --version
