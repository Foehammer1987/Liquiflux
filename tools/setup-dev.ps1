# One-command setup for building Liquiflux yourself on Windows 10 or 11.
#
#   powershell -ExecutionPolicy Bypass -File tools\setup-dev.ps1              Windows and Android TV
#   powershell -ExecutionPolicy Bypass -File tools\setup-dev.ps1 -Windows     Windows app only
#   powershell -ExecutionPolicy Bypass -File tools\setup-dev.ps1 -Android     Android TV APKs only
#
# Installs, with winget, whatever is missing:
#   - Git
#   - Flutter (the version the release builds use), into %LOCALAPPDATA%\flutter, added to your PATH
#   - Windows: Visual Studio 2022 Build Tools with the "Desktop development with C++" workload,
#     and Developer Mode (Flutter needs it to link plugins)
#   - Android TV: Microsoft OpenJDK 17. tools\build-android.ps1 fetches the Android SDK on its first run.
# Safe to run again: anything already installed is skipped. Windows asks for administrator
# approval for the Build Tools and Developer Mode.
param([switch]$Windows, [switch]$Android)
$ErrorActionPreference = 'Stop'
if (-not $Windows -and -not $Android) { $Windows = $true; $Android = $true }

# Keep in step with FLUTTER_VERSION in .github/workflows/release.yml.
$flutterVersion = '3.47.7'
$flutterDir = Join-Path $env:LOCALAPPDATA 'flutter'

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Winget-Install($id, [string[]]$extra = @()) {
  winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements @extra
  # winget returns a non-zero code when the package is already installed; that's fine.
  Refresh-Path
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw 'winget is missing. Install "App Installer" from the Microsoft Store, then run this again.'
}

Step 'Git'
if (Get-Command git -ErrorAction SilentlyContinue) { Write-Host 'Already installed.' } else { Winget-Install 'Git.Git' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $env:Path += ";$env:ProgramFiles\Git\cmd" }

Step "Flutter $flutterVersion"
$flutterBin = Join-Path $flutterDir 'bin'
if (Test-Path (Join-Path $flutterBin 'flutter.bat')) {
  Write-Host "Already in $flutterDir."
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
  $flutterBin = Split-Path (Get-Command flutter).Source
  Write-Host "Using the Flutter already on your PATH ($flutterBin)."
} else {
  git clone --depth 1 --branch $flutterVersion https://github.com/flutter/flutter.git $flutterDir
  if ($LASTEXITCODE -ne 0) { throw 'Could not download Flutter.' }
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $flutterBin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$flutterBin"), 'User')
  Write-Host "Added $flutterBin to your PATH."
}
Refresh-Path
flutter config --no-analytics | Out-Null
flutter --version

if ($Windows) {
  Step 'Visual Studio 2022 Build Tools (Desktop development with C++)'
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $hasCpp = (Test-Path $vswhere) -and (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
  if ($hasCpp) {
    Write-Host 'Already installed.'
  } else {
    Write-Host 'This is a large download (several GB) and takes a while.'
    Winget-Install 'Microsoft.VisualStudio.2022.BuildTools' @('--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
  }

  Step 'Developer Mode'
  $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
  $on = (Get-ItemProperty $key -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1
  if ($on) {
    Write-Host 'Already on.'
  } else {
    Write-Host 'Flutter needs Developer Mode to build apps with plugins. Turning it on (Windows asks for approval).'
    Start-Process reg.exe -Verb RunAs -Wait -ArgumentList 'add', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock', '/t', 'REG_DWORD', '/f', '/v', 'AllowDevelopmentWithoutDevLicense', '/d', '1'
  }
}

if ($Android) {
  Step 'Java 17'
  $jdk = Get-ChildItem "$env:ProgramFiles\Microsoft\jdk-17*", "$env:ProgramFiles\Eclipse Adoptium\jdk-17*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($jdk -or (Test-Path "$env:ProgramFiles\Android\Android Studio\jbr")) { Write-Host 'Already installed.' } else { Winget-Install 'Microsoft.OpenJDK.17' }
  Write-Host 'The Android SDK is set up by tools\build-android.ps1 the first time you run it.'
}

Step 'Done'
flutter doctor
Write-Host ''
if ($Windows) { Write-Host 'Build the Windows app:  powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1' }
if ($Android) { Write-Host 'Build the Android TV APKs:  powershell -ExecutionPolicy Bypass -File tools\build-android.ps1' }
Write-Host 'Open a new terminal first so it picks up the new PATH.'
