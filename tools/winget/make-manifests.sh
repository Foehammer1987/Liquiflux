#!/usr/bin/env bash
# Writes the WinGet manifests for one Liquiflux release, in winget-pkgs' layout:
#   tools/winget/make-manifests.sh <version> <installer sha256> <release date YYYY-MM-DD> <out dir>
# makes <out dir>/manifests/l/Liquiflux/Liquiflux/<version>/Liquiflux.Liquiflux{,.installer,.locale.en-US}.yaml
# The release workflow submits them to microsoft/winget-pkgs with wingetcreate; to try them on a
# PC first: winget validate --manifest <that folder>
set -euo pipefail
version=$1
sha=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
date=$3
out=$4
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad version: $version" >&2; exit 1; }
[[ $sha =~ ^[0-9A-F]{64}$ ]] || { echo "bad sha256: $2" >&2; exit 1; }
[[ $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad date: $date" >&2; exit 1; }

id=Liquiflux.Liquiflux
schema=1.10.0
repo=https://github.com/Foehammer1987/Liquiflux
dir="$out/manifests/l/Liquiflux/Liquiflux/$version"
mkdir -p "$dir"
header() { echo "# yaml-language-server: \$schema=https://aka.ms/winget-manifest.$1.$schema.schema.json"; echo; }

{
  header version
  cat <<YAML
PackageIdentifier: $id
PackageVersion: $version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $schema
YAML
} > "$dir/$id.yaml"

# The Inno Setup installer (tools/installer/liquiflux.iss) installs per user with no admin
# rights; its AppId is the ProductCode Windows lists it under.
{
  header installer
  cat <<YAML
PackageIdentifier: $id
PackageVersion: $version
MinimumOSVersion: 10.0.17763.0
InstallerType: inno
Scope: user
InstallModes:
- interactive
- silent
- silentWithProgress
InstallerSwitches:
  Custom: /CURRENTUSER
UpgradeBehavior: install
ReleaseDate: $date
AppsAndFeaturesEntries:
- DisplayName: Liquiflux
  Publisher: Liquiflux
  ProductCode: '{F88427EC-1DFB-4761-8BBF-05C8FA253AB7}_is1'
Installers:
- Architecture: x64
  InstallerUrl: $repo/releases/download/v$version/Liquiflux-Setup-x64.exe
  InstallerSha256: $sha
ManifestType: installer
ManifestVersion: $schema
YAML
} > "$dir/$id.installer.yaml"

{
  header defaultLocale
  cat <<YAML
PackageIdentifier: $id
PackageVersion: $version
PackageLocale: en-US
Publisher: Liquiflux
PublisherUrl: https://github.com/Foehammer1987
PublisherSupportUrl: $repo/issues
PackageName: Liquiflux
PackageUrl: $repo
License: MIT
LicenseUrl: $repo/blob/main/LICENSE
ShortDescription: A Plex client with a clean, Netflix-like interface and Seerr requests built in.
Description: |-
  Liquiflux is a Plex client for Windows and Android TV that feels like the big streaming apps:
  a full-width spotlight with trailers, rows that change with your mood, and a player that gets
  out of the way. It plays your files directly through mpv, so almost anything in your library
  plays without the server converting it. Seerr (or Overseerr / Jellyseerr) is built in, so what
  you don't have yet gets a Request button. Also Riptide on pause, Watch Together, per-show audio
  and subtitles, and a sleep timer.
Moniker: liquiflux
Tags:
- media-player
- mpv
- plex
- seerr
- streaming
- video
ReleaseNotesUrl: $repo/releases/tag/v$version
ManifestType: defaultLocale
ManifestVersion: $schema
YAML
} > "$dir/$id.locale.en-US.yaml"

echo "$dir"
