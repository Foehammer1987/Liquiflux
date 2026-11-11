<#
.SYNOPSIS
  Pushes the newest green commit of Forgejo's main to GitHub's main, at most once a day.

.DESCRIPTION
  Forgejo is where day-to-day work happens; GitHub gets code that has built cleanly there.
  This script, run once a day (see docs/CI.md):
    1. fetches Forgejo's main (the `origin` remote of this clone);
    2. picks the newest of its last 20 commits whose Forgejo checks all passed, including the
       build and tizen workflows;
    3. fetches GitHub's main (read only) and stops if there is nothing new, or if GitHub's main
       is not an ancestor of that commit (the histories have split: sort that out by hand);
    4. stops if the last promotion was less than -MinHours ago;
    5. checks the new commits before they go public: every author and committer email must be
       on the allow list, and no added line may contain a LAN address, a local path, this PC's
       name or user name, or anything listed in %LOCALAPPDATA%\Liquiflux\promote-blocklist.txt
       (one word or email per line: other machine names, real email addresses and so on);
    6. pushes that commit to GitHub's main. Never forced, no tags, nothing else.
  A push to GitHub's main with a new app version makes GitHub publish its release.

  Needs: env FORGEJO_URL and FORGEJO_TOKEN (to read the Forgejo checks) and env
  GITHUB_PROMOTE_TOKEN (a fine-grained GitHub token; see docs/CI.md). The tokens are only
  passed to git and the API in memory: never written to disk, remotes or the log.

  Exit codes: 0 pushed or nothing to do, 1 setup or git error, 2 not yet (no green commit or
  too soon since the last promotion), 3 GitHub's main isn't an ancestor, 4 the scrub check
  found something, 5 the push failed.

.PARAMETER DryRun
  Do every check but don't push or log.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\promote-to-github.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$GitHubRepo = 'Foehammer1987/Liquiflux',
  # owner/name on Forgejo; empty = read it from the `origin` remote.
  [string]$ForgejoRepo = '',
  [string]$Branch = 'main',
  [double]$MinHours = 24,
  [int]$Depth = 20,
  [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Emails that may appear as a commit's author or committer on GitHub.
$AllowedEmails = @(
  '342276654+Foehammer1987@users.noreply.github.com',
  'noreply@anthropic.com',
  'noreply@github.com',
  '41898282+github-actions[bot]@users.noreply.github.com'
)

$stateDir = Join-Path $env:LOCALAPPDATA 'Liquiflux'
$logFile = Join-Path $stateDir 'promote.log'
$blocklistFile = Join-Path $stateDir 'promote-blocklist.txt'

function Say([string]$text) { Write-Host $text }
function Stop-With([int]$code, [string]$text) {
  if ($code -eq 0) { Write-Host $text } else { Write-Host "STOP ($code): $text" -ForegroundColor Yellow }
  exit $code
}

# Runs git; returns its output lines, throws on a non-zero exit unless -AllowFail.
# (A simple function, so git's own -x options pass through untouched in $args.)
function Git {
  $GitArgs = @($args | ForEach-Object { "$_" })
  $allowFail = $false
  if ($GitArgs.Count -gt 0 -and $GitArgs[0] -eq '-AllowFail') { $allowFail = $true; $GitArgs = @($GitArgs | Select-Object -Skip 1) }
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & git.exe @GitArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $old }
  $script:GitExit = $code
  if ($code -ne 0 -and -not $allowFail) {
    throw "git $($GitArgs[0]) failed ($code): $(($out | Select-Object -Last 5) -join ' | ')"
  }
  return $out
}

# Passes config to git through the environment (not the command line, not a file).
function Set-GitEnvConfig([hashtable]$pairs) {
  $i = 0
  foreach ($k in $pairs.Keys) {
    Set-Item "env:GIT_CONFIG_KEY_$i" $k
    Set-Item "env:GIT_CONFIG_VALUE_$i" $pairs[$k]
    $i++
  }
  $env:GIT_CONFIG_COUNT = "$i"
}
function Clear-GitEnvConfig {
  $n = 0; [int]::TryParse("$env:GIT_CONFIG_COUNT", [ref]$n) | Out-Null
  for ($i = 0; $i -lt $n; $i++) {
    Remove-Item "env:GIT_CONFIG_KEY_$i" -ErrorAction SilentlyContinue
    Remove-Item "env:GIT_CONFIG_VALUE_$i" -ErrorAction SilentlyContinue
  }
  Remove-Item env:GIT_CONFIG_COUNT -ErrorAction SilentlyContinue
}

try {
  $root = Split-Path -Parent $PSScriptRoot
  Set-Location $root
  $env:GIT_TERMINAL_PROMPT = '0'
  $ghToken = $env:GITHUB_PROMOTE_TOKEN
  if (-not $env:FORGEJO_URL -or -not $env:FORGEJO_TOKEN) {
    Stop-With 1 'FORGEJO_URL and FORGEJO_TOKEN must be set (to read the Forgejo checks).'
  }
  if (-not $ghToken -and -not $DryRun) {
    Stop-With 1 @'
GITHUB_PROMOTE_TOKEN is not set. To make one:
  1. GitHub > Settings > Developer settings > Fine-grained tokens > Generate new token.
  2. Repository access: only this repository. Permissions: Contents and Workflows, read and write.
     Expiry: 90 days.
  3. Save it as a user environment variable named GITHUB_PROMOTE_TOKEN
     (Windows: Edit environment variables for your account), then open a new terminal.
'@
  }
  if (-not $ForgejoRepo) {
    $url = (Git remote get-url origin | Select-Object -First 1)
    if ($url -match '[:/]([^/:]+/[^/]+?)(\.git)?$') { $ForgejoRepo = $Matches[1] } else { Stop-With 1 "Can't read owner/name from origin ($url); pass -ForgejoRepo." }
  }
  $ghUrl = "https://github.com/$GitHubRepo.git"
  $ghAuth = $null
  if ($ghToken) {
    $ghAuth = 'Authorization: Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$ghToken"))
  }
  if ($DryRun) { Say 'Dry run: nothing will be pushed or logged.' }

  # 1. Forgejo's main.
  Say "Fetching $Branch from Forgejo (origin, $ForgejoRepo)..."
  Git fetch --quiet --no-tags origin "+refs/heads/${Branch}:refs/remotes/origin/$Branch" | Out-Null
  $commits = @(Git rev-list --first-parent -n $Depth "origin/$Branch")

  # 2. The newest green commit.
  $api = $env:FORGEJO_URL.TrimEnd('/') + "/api/v1/repos/$ForgejoRepo"
  $headers = @{ Authorization = "token $env:FORGEJO_TOKEN" }
  $candidate = $null
  foreach ($sha in $commits) {
    try { $st = Invoke-RestMethod -Headers $headers -Uri "$api/commits/$sha/status" } catch { Stop-With 1 "Forgejo API: $($_.Exception.Message)" }
    $contexts = @($st.statuses | Where-Object { $_ } | ForEach-Object { $_.context })
    $hasBuild = @($contexts | Where-Object { $_ -match '^build\b' }).Count -gt 0
    $hasTizen = @($contexts | Where-Object { $_ -match '^tizen\b' }).Count -gt 0
    $short = $sha.Substring(0, 8)
    if ($st.state -eq 'success' -and $hasBuild -and $hasTizen) { $candidate = $sha; Say "Newest green commit: $short"; break }
    Say ("  {0}: {1}{2}{3}" -f $short, $(if ($st.state) { $st.state } else { 'no checks' }),
      $(if (-not $hasBuild) { ', no build' } else { '' }), $(if (-not $hasTizen) { ', no tizen' } else { '' }))
  }
  if (-not $candidate) { Stop-With 2 "None of the last $Depth commits on Forgejo's $Branch has passing build and tizen checks." }
  $version = (Git show "${candidate}:app/pubspec.yaml" | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1) -replace '^version:\s*', ''

  # 3. GitHub's main, read only.
  Say "Fetching $Branch from GitHub ($GitHubRepo)..."
  if ($ghAuth) { Set-GitEnvConfig @{ 'http.https://github.com/.extraheader' = $ghAuth; 'credential.helper' = '' } }
  try { Git fetch --quiet --no-tags $ghUrl "refs/heads/$Branch" | Out-Null } finally { Clear-GitEnvConfig }
  $ghSha = (Git rev-parse FETCH_HEAD | Select-Object -First 1)
  Say "GitHub's ${Branch}: $($ghSha.Substring(0, 8))"
  Git -AllowFail merge-base --is-ancestor $candidate $ghSha | Out-Null
  if ($script:GitExit -eq 0) { Stop-With 0 "Nothing new: GitHub already has $($candidate.Substring(0, 8))." }
  Git -AllowFail merge-base --is-ancestor $ghSha $candidate | Out-Null
  if ($script:GitExit -ne 0) { Stop-With 3 "GitHub's $Branch ($($ghSha.Substring(0, 8))) is not an ancestor of $($candidate.Substring(0, 8)): the histories have split. Sort it out by hand; this script never forces." }
  $new = @(Git rev-list "$ghSha..$candidate")
  Say "$($new.Count) new commit(s), app version $version."

  # 4. Once a day.
  if (Test-Path $logFile) {
    $last = Get-Content $logFile | Where-Object { $_ -match "`tpushed$" } | Select-Object -Last 1
    if ($last) {
      $when = [DateTime]::Parse(($last -split "`t")[0], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]'AdjustToUniversal,AssumeUniversal')
      $hours = ([DateTime]::UtcNow - $when).TotalHours
      if ($hours -lt $MinHours) { Stop-With 2 ("Last promotion was {0:N1} h ago (minimum {1} h)." -f $hours, $MinHours) }
    }
  }

  # 5. Scrub check over the new commits.
  $problems = New-Object System.Collections.Generic.List[string]
  foreach ($line in (Git log --format='%h%x09%ae%x09%ce' "$ghSha..$candidate")) {
    $parts = $line -split "`t"
    foreach ($email in $parts[1], $parts[2]) {
      if ($AllowedEmails -notcontains $email) { $problems.Add("commit $($parts[0]): email $email is not on the allow list") }
    }
  }
  $patterns = New-Object System.Collections.Generic.List[string]
  $patterns.Add('\b192\.168\.\d{1,3}\.\d{1,3}\b')
  $patterns.Add('\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')
  $patterns.Add('\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b')
  $patterns.Add('(?i)\b[A-Z]:[\\/]src\b')
  $patterns.Add('(?i)[\\/]Users[\\/](?!<|\$|%|Public\b|Default\b)[A-Za-z0-9._-]+')
  $words = @($env:COMPUTERNAME, $env:USERNAME)
  $globalEmail = (Git -AllowFail config --global user.email | Select-Object -First 1)
  if ($script:GitExit -eq 0 -and $globalEmail -and $AllowedEmails -notcontains $globalEmail) { $words += $globalEmail }
  if (Test-Path $blocklistFile) {
    $words += @(Get-Content $blocklistFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
  }
  foreach ($w in ($words | Where-Object { $_ } | Sort-Object -Unique)) { $patterns.Add('(?i)' + [regex]::Escape($w)) }

  $file = ''
  $diff = Git -c core.quotepath=off diff --no-color --no-ext-diff -U0 $ghSha $candidate -- . ':(exclude)tools/promote-to-github.ps1'
  foreach ($line in $diff) {
    if ($line.StartsWith('+++ ')) { $file = $line.Substring(4) -replace '^b/', ''; continue }
    if (-not $line.StartsWith('+')) { continue }
    $text = $line.Substring(1)
    foreach ($p in $patterns) {
      if ($text -match $p) {
        $shown = if ($text.Length -gt 120) { $text.Substring(0, 120) + '...' } else { $text }
        $problems.Add("${file}: matches /$p/: $($shown.Trim())")
        break
      }
    }
  }
  if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "  $_" }
    Stop-With 4 "$($problems.Count) problem(s) in the new commits. Fix them on Forgejo (or extend the allow list), then run again."
  }
  Say 'Scrub check: clean.'

  # 6. Push.
  if ($DryRun) { Stop-With 0 "Dry run: would push $($candidate.Substring(0, 8)) (version $version) to GitHub's $Branch." }
  Say "Pushing $($candidate.Substring(0, 8)) to GitHub's $Branch..."
  Set-GitEnvConfig @{ 'http.https://github.com/.extraheader' = $ghAuth; 'credential.helper' = '' }
  try { $out = Git -AllowFail push --no-tags $ghUrl "${candidate}:refs/heads/$Branch" } finally { Clear-GitEnvConfig }
  if ($script:GitExit -ne 0) {
    $out | ForEach-Object { Write-Host "  $_" }
    Stop-With 5 'git push to GitHub failed (token expired or missing permissions? see docs/CI.md).'
  }
  New-Item -ItemType Directory -Force $stateDir | Out-Null
  Add-Content -Path $logFile -Encoding UTF8 -Value ("{0}`t{1}`t{2}`tpushed" -f [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'), $candidate, $version)
  Stop-With 0 "Pushed $($candidate.Substring(0, 8)) (version $version) to GitHub's $Branch."
} catch {
  Clear-GitEnvConfig
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
