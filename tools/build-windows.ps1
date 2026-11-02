# Builds the Windows app on this PC.
# Needs: Flutter (stable) and Visual Studio 2022 with "Desktop development with C++".
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\app')
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
Write-Host "Building Liquiflux $version"
flutter pub get
# Trimming unused icons corrupts the Lucide icon font, so keep it whole.
flutter build windows --release --no-tree-shake-icons
$out = Resolve-Path 'build\windows\x64\runner\Release'
Write-Host "Built Liquiflux ${version}: $out\Liquiflux.exe"
