# Prebuilt image for the Linux jobs in .forgejo/workflows/build.yml (test and android).
#
# The jobs used to restore a multi-GB cache bundle (Flutter, the Android SDK, Gradle) into every
# job container, or download it all when the cache missed. This image has that already:
# Flutter at the pinned version with its Android and Linux artifacts precached, JDK 17, the
# Android command-line tools, and the SDK platform, build tools, NDK and Gradle downloads that a
# release APK build of the Flutter template asks for (the app uses Flutter's default compileSdk,
# targetSdk and ndkVersion, so they are the same ones). The image writes /etc/liquiflux-flutter-ci
# as a marker.
#
# tools/ci/setup-flutter.sh skips whatever is already here, so the jobs still work on a plain
# image (and the GitHub workflows, which don't use this image, are unaffected).
#
# Build it on the runner's Docker host (Unraid), from this directory:
#   docker build -t liquiflux-flutter-ci:1 .
# Rebuild with a new tag, and update `image:` in .forgejo/workflows/build.yml, whenever
# FLUTTER_VERSION or ANDROID_CMDLINE_TOOLS change there. The build args below must match the
# workflow's env, or the jobs fall back to downloading the difference themselves.

FROM ghcr.io/catthehacker/ubuntu:act-24.04

ARG FLUTTER_VERSION=3.47.7
ARG FLUTTER_SHA256=af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230
ARG ANDROID_CMDLINE_TOOLS=13114758
ARG ANDROID_CMDLINE_TOOLS_SHA256=7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee
ARG IMAGE_VERSION=1

USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl git unzip xz-utils zip ca-certificates \
      openjdk-17-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && git config --global --add safe.directory '*'

# Flutter, checked against the same SHA-256 as tools/ci/setup-flutter.sh.
RUN set -eu; \
    url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"; \
    curl -fsSL "$url" -o /tmp/flutter.tar.xz; \
    echo "$FLUTTER_SHA256  /tmp/flutter.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/flutter.tar.xz -C /opt; \
    rm /tmp/flutter.tar.xz
ENV PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:$PATH
RUN flutter config --no-analytics >/dev/null \
 && (dart --disable-analytics >/dev/null 2>&1 || true) \
 && flutter precache --universal --android --linux

# Android command-line tools, same pin and SHA-256 as the workflow.
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
RUN set -eu; \
    url="https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip"; \
    curl -fsSL "$url" -o /tmp/cmdline-tools.zip; \
    echo "$ANDROID_CMDLINE_TOOLS_SHA256  /tmp/cmdline-tools.zip" | sha256sum -c -; \
    mkdir -p "$ANDROID_HOME/cmdline-tools"; \
    unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"; \
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"; \
    rm /tmp/cmdline-tools.zip; \
    (yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true); \
    sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" >/dev/null; \
    flutter config --android-sdk "$ANDROID_HOME" >/dev/null

# Warm everything a release APK build downloads (SDK platform, build tools, NDK, CMake, the Gradle
# distribution, the Android Gradle plugin and Kotlin) by building the Flutter template once, then
# throw the project away. Only the downloads stay, in /opt/android-sdk and /root/.gradle.
RUN set -eu; \
    cd /tmp; \
    flutter create -q --platforms android --org dev.liquiflux warmup; \
    cd warmup; \
    flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64; \
    (cd android && ./gradlew --stop >/dev/null 2>&1 || true); \
    cd /; rm -rf /tmp/warmup /root/.gradle/daemon /root/.gradle/caches/*/fileHashes 2>/dev/null || true

RUN echo "liquiflux-flutter-ci:${IMAGE_VERSION} flutter ${FLUTTER_VERSION} cmdline-tools ${ANDROID_CMDLINE_TOOLS}" > /etc/liquiflux-flutter-ci
