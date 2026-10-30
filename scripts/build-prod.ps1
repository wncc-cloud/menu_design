<#
  Builds the production web bundle with a BUILD_ID baked in, so every Bug Log
  says which build wrote it (Admin > Bug logs > Build, and /check-bug-logs).

  Usage (from anywhere):   pwsh scripts/build-prod.ps1        (or powershell -File scripts\build-prod.ps1)

  BUILD_ID = <short-commit>[+wip]@<UTC time>
    +wip   means the working tree had uncommitted changes when it was built.

  This script ONLY builds. It never deploys: run `firebase deploy --only hosting`
  yourself, from cafe_countryside_menu/ (never a bare `firebase deploy`).

  A line is appended to deploy_backups/builds.log so "which build is live?" can be
  answered later.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'cafe_countryside_menu'

$commit = (git -C $root rev-parse --short HEAD).Trim()
$dirty = (git -C $root status --porcelain -- cafe_countryside_menu) | Where-Object { $_ -and $_ -notmatch '\.firebase/' }
$wip = if ($dirty) { '+wip' } else { '' }
$time = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm')
$buildId = "$commit$wip@$time"

Write-Host "Building BUILD_ID=$buildId"
Push-Location $app
try {
  # --no-wasm-dry-run: its warnings go to stderr, which PowerShell ($ErrorActionPreference='Stop') treats as a failure
  flutter build web --release --no-wasm-dry-run --source-maps "--dart-define=BUILD_ID=$buildId"
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }
} finally { Pop-Location }

# Keep the source map PRIVATE: move it out of build/web so `firebase deploy` never publishes it.
# scripts/decode-stack.mjs uses it to turn a minified Bug Log stack into Dart file:line.
$map = Join-Path $app 'build\web\main.dart.js.map'
if (Test-Path $map) {
  $mapDir = Join-Path $root 'deploy_backups\sourcemaps'
  New-Item -ItemType Directory -Force -Path $mapDir | Out-Null
  $safeId = $buildId -replace '[:@]', '_'
  Move-Item -Force $map (Join-Path $mapDir "$safeId.main.dart.js.map")
  Write-Host "Source map kept at deploy_backups\sourcemaps\$safeId.main.dart.js.map (not in build/web)"
} else { Write-Warning 'No main.dart.js.map was produced.' }

$log = Join-Path $root 'deploy_backups\builds.log'
Add-Content -Path $log -Value "$buildId  built (not necessarily deployed)"
Write-Host "Done. Next (only when you decide): cd cafe_countryside_menu; firebase deploy --only hosting"
