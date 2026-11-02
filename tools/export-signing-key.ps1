# Prints the four GitHub secrets the release workflow needs to sign the Android TV APKs, using
# the key tools\build-android.ps1 made in %USERPROFILE%\.liquiflux. Releases signed with that key
# install as updates over APKs you built yourself (and the other way round).
#
#   tools\export-signing-key.ps1                       writes signing-secrets.txt in your temp folder
#   tools\export-signing-key.ps1 -Repo owner/name      sets the secrets with the GitHub CLI (gh) instead
#
# The values are passwords: paste them into GitHub (Settings > Secrets and variables > Actions >
# New repository secret), then delete the text file.
param([string]$Repo)
$ErrorActionPreference = 'Stop'
$props = if ($env:LIQUIFLUX_KEY_PROPERTIES) { $env:LIQUIFLUX_KEY_PROPERTIES } else { Join-Path $env:USERPROFILE '.liquiflux\key.properties' }
if (-not (Test-Path $props)) { throw "No signing key at $props. Run tools\build-android.ps1 once to make one." }
$kv = @{}
foreach ($line in Get-Content $props) {
  if ($line -match '^\s*([^=#]+?)\s*=\s*(.*)$') { $kv[$Matches[1]] = $Matches[2] }
}
$store = $kv['storeFile'] -replace '/', '\'
$secrets = [ordered]@{
  ANDROID_KEYSTORE_BASE64   = [Convert]::ToBase64String([IO.File]::ReadAllBytes($store))
  ANDROID_KEYSTORE_PASSWORD = $kv['storePassword']
  ANDROID_KEY_ALIAS         = $kv['keyAlias']
  ANDROID_KEY_PASSWORD      = $kv['keyPassword']
}
if ($Repo) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'The GitHub CLI (gh) is not installed: winget install GitHub.cli, then gh auth login.' }
  foreach ($name in $secrets.Keys) {
    $secrets[$name] | gh secret set $name --repo $Repo
    if ($LASTEXITCODE -ne 0) { throw "gh could not set $name" }
  }
  Write-Host "Set the four signing secrets on $Repo."
} else {
  $out = Join-Path $env:TEMP 'signing-secrets.txt'
  $secrets.GetEnumerator() | ForEach-Object { "$($_.Key)`r`n$($_.Value)`r`n" } | Set-Content -Encoding ascii $out
  Write-Host "Wrote $out. Add each name and value as a repository secret on GitHub, then delete the file."
}
