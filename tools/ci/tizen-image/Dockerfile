# Prebuilt image for the Forgejo Tizen workflow (.forgejo/workflows/tizen.yml).
#
# Everything a tpk job used to install from scratch on every run lives here instead: the apt
# packages (python3.8, the KDE/keyring libraries and dotnet-sdk-8.0), the `builder` user, the Tizen
# SDK with the packages for all three Tizen version groups, and flutter-tizen at the pinned commit
# with its Flutter checkout, Dart SDK and Tizen engine artifacts. A job then only builds the TPK.
#
# tools/ci/tizen-build.sh skips each step that this image has already done, so the script still
# works on a plain runner image (and the GitHub workflow, which does not use this image, is
# unaffected).
#
# Build it on the runner's Docker host (Unraid), from this directory:
#   docker build -t liquiflux-tizen-ci:1 .
# Rebuild with a new tag, and update `image:` in .forgejo/workflows/tizen.yml, whenever
# FLUTTER_TIZEN_COMMIT, TIZEN_SDK_URL or TIZEN_PACKAGES change there. The build args below must
# match the workflow's env, or the job falls back to installing the difference itself.

FROM ghcr.io/catthehacker/ubuntu:act-22.04

ARG FLUTTER_TIZEN_COMMIT=cd5ad06b3e7ba93a392a3636a3b896aee5483eed
ARG TIZEN_SDK_URL=https://download.tizen.org/sdk/Installer/tizen-sdk_10.0/web-cli_Tizen_SDK_10.0_ubuntu-64.bin
ARG TIZEN_SDK_SHA256=""
# The union of the matrix's package lists in .forgejo/workflows/tizen.yml.
ARG TIZEN_PACKAGES="NativeToolchain-Gcc-9.2 IOT-Headed-6.0-NativeAppDevelopment-CLI IOT-Headed-6.5-NativeAppDevelopment-CLI TIZEN-10.0-NativeAppDevelopment-CLI"
ARG IMAGE_VERSION=1

USER root
RUN add-apt-repository -y ppa:deadsnakes/ppa \
 && apt-get update \
 && apt-get install -y --no-install-recommends libncurses5 python3.8 libpython3.8 gettext \
      libkf5itemmodels5 libkf5kiowidgets5 libkchart2 dbus-x11 gnome-keyring dotnet-sdk-8.0 \
 && rm -rf /var/lib/apt/lists/* \
 && (id builder >/dev/null 2>&1 || useradd -m -s /bin/bash builder)

# The Tizen SDK refuses to install as root.
USER builder
WORKDIR /home/builder
RUN set -eu; \
    curl -fsSL "$TIZEN_SDK_URL" -o /tmp/install.bin; \
    sha="$(sha256sum /tmp/install.bin | cut -d' ' -f1)"; \
    echo "Tizen SDK installer sha256: $sha"; \
    if [ -n "$TIZEN_SDK_SHA256" ] && [ "$sha" != "$TIZEN_SDK_SHA256" ]; then \
      echo "The Tizen SDK installer changed (expected $TIZEN_SDK_SHA256)."; exit 1; \
    fi; \
    chmod +x /tmp/install.bin; \
    /tmp/install.bin --accept-license "$HOME/tizen-studio"; \
    rm /tmp/install.bin; \
    "$HOME/tizen-studio/package-manager/package-manager-cli.bin" install $TIZEN_PACKAGES; \
    printf '%s\n' $TIZEN_PACKAGES > "$HOME/tizen-studio/.liquiflux-ci-packages"

ENV PATH=/home/builder/flutter-tizen/bin:/home/builder/tizen-studio/tools/ide/bin:/home/builder/tizen-studio/tools:$PATH
RUN set -eu; \
    git clone -q https://github.com/flutter-tizen/flutter-tizen.git "$HOME/flutter-tizen"; \
    git -C "$HOME/flutter-tizen" checkout -q --detach "$FLUTTER_TIZEN_COMMIT"; \
    flutter-tizen config --no-analytics >/dev/null 2>&1 || true; \
    flutter-tizen doctor -v || true; \
    flutter-tizen precache --tizen || true

USER root
WORKDIR /
RUN echo "liquiflux-tizen-ci:${IMAGE_VERSION} flutter-tizen ${FLUTTER_TIZEN_COMMIT}" > /etc/liquiflux-tizen-ci
