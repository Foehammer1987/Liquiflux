# Builds the Android TV app (Nvidia Shield, Google TV, Android TV, Fire TV) on this PC.
# Needs: Flutter (stable). The first run sets up Java and the Android SDK if they're missing
# (or uses Android Studio's, if it's installed) and makes a signing key in ~\.liquiflux.
#
#   tools\build-android.ps1                     build both APKs into dist\
#   tools\build-android.ps1 -Install 192.168.1.50   ...then install on the TV at that address
#   tools\build-android.ps1 -Store amazon       the app-store build: no in-app updater and no
#                                               sleep-timer accessibility service
#   tools\build-android.ps1 -Mobile             the phone and tablet build (touch layout,
#                                               rotation, picture-in-picture, Impeller)
param(
  # IP address of the TV to install on over the network (ADB debugging must be on).
  [string]$Install,
  # An app store to build for (amazon). Leave out for the GitHub build.
  [ValidateSet('amazon')]
  [string]$Store = '',
  # The phone and tablet build instead of the TV one.
  [switch]$Mobile
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location (Join-Path $root 'app')
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
Write-Host ("Building Liquiflux $version for " + $(if ($Mobile) { "Android phones and tablets" } else { "Android TV" }))

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter is not on PATH.' }

# --- Java (the Android build needs JDK 17 or later) -----------------------------------------
function Find-Jdk {
  $candidates = @(
    $env:JAVA_HOME,
    "$env:ProgramFiles\Android\Android Studio\jbr",
    "$env:LOCALAPPDATA\Programs\Android Studio\jbr"
  ) + (Get-ChildItem "$env:ProgramFiles\Microsoft\jdk-*", "$env:ProgramFiles\Eclipse Adoptium\jdk-*", "$env:ProgramFiles\Java\jdk-*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object FullName)
  foreach ($c in $candidates) {
    # A trailing backslash ("C:\jdk\") would escape the closing quote when passed to flutter config.
    if ($c -and (Test-Path (Join-Path $c 'bin\keytool.exe'))) { return $c.TrimEnd('\') }
  }
  return $null
}
$jdk = Find-Jdk
if (-not $jdk) {
  Write-Host 'No Java found: installing Microsoft OpenJDK 17 with winget.'
  winget install --id Microsoft.OpenJDK.17 -e --accept-source-agreements --accept-package-agreements
  $jdk = Find-Jdk
  if (-not $jdk) { throw 'Java did not install. Install Android Studio (or JDK 17) and run this again.' }
}
$env:JAVA_HOME = $jdk
$keytool = Join-Path $jdk 'bin\keytool.exe'
Write-Host "Java: $jdk"

# --- Android SDK ------------------------------------------------------------------------------
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sdk) { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
$sdkmanager = Get-ChildItem (Join-Path $sdk 'cmdline-tools\*\bin\sdkmanager.bat') -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sdkmanager) {
  Write-Host "Setting up the Android SDK in $sdk"
  New-Item -ItemType Directory -Force -Path $sdk | Out-Null
  $zip = Join-Path $env:TEMP 'android-cmdline-tools.zip'
  try {
    Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' -OutFile $zip -UseBasicParsing
  } catch {
    throw "Couldn't download the Android command-line tools ($_). Install Android Studio, open it once to finish its setup, then run this again."
  }
  $tmp = Join-Path $env:TEMP 'android-cmdline-tools'
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive $zip $tmp
  $dest = Join-Path $sdk 'cmdline-tools\latest'
  Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Move-Item (Join-Path $tmp 'cmdline-tools') $dest
  Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
  $sdkmanager = Get-Item (Join-Path $dest 'bin\sdkmanager.bat')
}
$env:ANDROID_HOME = $sdk
if (-not (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) {
  Write-Host 'Installing platform tools and accepting the SDK licences.'
  # The Android build fetches the platform, build tools and NDK it needs by itself once the
  # licences are accepted.
  1..20 | ForEach-Object { 'y' } | & $sdkmanager.FullName --sdk_root="$sdk" --licenses | Out-Null
  & $sdkmanager.FullName --sdk_root="$sdk" 'platform-tools'
}
flutter config --android-sdk "$sdk" --jdk-dir "$jdk" | Out-Null
Write-Host "Android SDK: $sdk"

# --- Signing key: made once, kept outside the source folder -----------------------------------
# Every build must be signed with the same key to install as an update. Back this folder up:
# without it, the next build has to replace (uninstall) the app on each TV.
$keyDir = Join-Path $env:USERPROFILE '.liquiflux'
$keyProps = Join-Path $keyDir 'key.properties'
if (-not (Test-Path $keyProps)) {
  New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
  $store = Join-Path $keyDir 'liquiflux-release.jks'
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $pass = [Convert]::ToBase64String($bytes) -replace '[+/=]', 'x'
  & $keytool -genkeypair -keystore $store -alias liquiflux -keyalg RSA -keysize 2048 -validity 10000 -storepass $pass -keypass $pass -dname 'CN=Liquiflux' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'keytool could not make the signing key.' }
  @(
    "storeFile=$($store -replace '\\', '/')",
    "storePassword=$pass",
    "keyAlias=liquiflux",
    "keyPassword=$pass"
  ) | Set-Content -Encoding ascii $keyProps
  # Only this Windows account can read the key and its password.
  icacls $keyDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
  Write-Host "Made a signing key in $keyDir (back this folder up)."
}
$env:LIQUIFLUX_KEY_PROPERTIES = $keyProps

# --- Build ---------------------------------------------------------------------------------------
flutter pub get
# One APK per CPU type keeps each one small. Trimming unused icons corrupts the Lucide icon
# font, so keep it whole.
$storeArgs = if ($Store) { @("--dart-define=LIQUIFLUX_STORE=$Store", "--android-project-arg=liquiflux.store=$Store") } else { @() }
$formArgs = if ($Mobile) { @('--dart-define=LIQUIFLUX_FORM=mobile', '--android-project-arg=liquiflux.form=mobile') } else { @() }
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --no-tree-shake-icons @storeArgs @formArgs
if ($LASTEXITCODE -ne 0) { throw 'The Android build failed.' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$apks = @{}
foreach ($abi in 'arm64-v8a', 'armeabi-v7a') {
  $suffix = ''
  if ($Mobile) { $suffix += '-mobile' }
  if ($Store) { $suffix += "-$Store" }
  $to = Join-Path $dist "Liquiflux-$version-$abi$suffix.apk"
  Copy-Item "build\app\outputs\flutter-apk\app-$abi-release.apk" $to -Force
  $apks[$abi] = $to
  Write-Host ("Built {0} ({1:N0} MB)" -f $to, ((Get-Item $to).Length / 1MB))
}
Write-Host 'Most Google TV devices: arm64-v8a. 2019 Shield Tube, Fire TV sticks and older boxes: armeabi-v7a.'

# --- Optional: install over the network --------------------------------------------------------
if ($Install) {
  $adb = Join-Path $sdk 'platform-tools\adb.exe'
  $target = if ($Install -match ':') { $Install } else { "${Install}:5555" }
  & $adb connect $target
  Write-Host 'If the TV asks to allow USB debugging from this computer, choose Allow (and Always allow).'
  & $adb -s $target wait-for-device
  # Fire TV and many Google TV devices run a 32-bit system even on 64-bit chips; ask the TV.
  $abis = (& $adb -s $target shell getprop ro.product.cpu.abilist).Trim()
  $pick = if ($abis -match 'arm64-v8a') { 'arm64-v8a' } else { 'armeabi-v7a' }
  Write-Host "Installing the $pick build on $target"
  & $adb -s $target install -r $apks[$pick]
  if ($LASTEXITCODE -ne 0) { throw 'Install failed. If it mentions a signature, uninstall Liquiflux on the TV first.' }
  Write-Host 'Installed. Liquiflux is in the TV''s app list.'
}
