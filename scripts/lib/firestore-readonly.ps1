<#
  Shared helpers for the READ-ONLY Firestore scripts in scripts/.
  Dot-source it:  . (Join-Path $PSScriptRoot 'lib\firestore-readonly.ps1')

  PROD calls use a short-lived token of the service account
  bug-log-reader@cafe-countryside-menu.iam.gserviceaccount.com, which has ONLY
  the "Cloud Datastore Viewer" role (roles/datastore.viewer). Google refuses any
  write/delete made with that token, so these scripts cannot change data even by
  mistake. The owner's own gcloud login is used only to borrow (impersonate)
  that account, never to call Firestore directly.
  One-time setup: scripts/setup-bug-log-reader.ps1

  EMULATOR calls (-Emulator, for tests only) talk to the local Firestore
  emulator with "Bearer owner"; nothing leaves this computer.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# One app, one project (there is no dev Firebase project: the local emulator is dev).
$FsProjects = @{ prod = 'cafe-countryside-menu' }
$FsEmulatorProject = 'why-not-cafe-menu-dev'
$FsReaderName = 'bug-log-reader'

function Get-FsReaderEmail([string]$project) { "$FsReaderName@$project.iam.gserviceaccount.com" }

# ".../documents" root of the database, real or emulator.
function Get-FsDocsRoot([string]$project, [int]$emulatorPort = 0) {
  if ($emulatorPort -gt 0) { return "http://localhost:$emulatorPort/v1/projects/$project/databases/(default)/documents" }
  return "https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents"
}

function Find-Gcloud {
  $cmd = Get-Command gcloud -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
    "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
    "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  throw 'Google Cloud CLI (gcloud) not found. Install it, then run: gcloud auth login'
}

# Read-only token. Deliberately NO fallback to the owner's own token.
function Get-FsReadOnlyToken([string]$project) {
  $gcloud = Find-Gcloud
  $sa = Get-FsReaderEmail $project
  # gcloud always prints an impersonation WARNING on stderr; under 'Stop' PowerShell 5.1
  # would turn that into a terminating error, so relax it for this one call.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $token = (& $gcloud auth print-access-token "--impersonate-service-account=$sa" 2>$null) }
  finally { $ErrorActionPreference = $prev }
  if (-not $token -or $LASTEXITCODE -ne 0) {
    throw ("Could not get a read-only token for $sa.`n" +
      "Run the one-time setup first: .\scripts\setup-bug-log-reader.ps1`n" +
      "(and make sure 'gcloud auth login' is done). Ask the owner before running it: it changes Google Cloud IAM.")
  }
  return "$token".Trim()
}

# Firestore REST call. Only runQuery (POST) and document GET are allowed here.
function Invoke-FsRead([string]$project, [string]$token, [string]$method, [string]$url, [string]$body = $null) {
  if ($method -eq 'POST' -and $url -notmatch ':runQuery$') { throw "Refusing non-read call: $method $url" }
  if ($method -notin @('GET', 'POST')) { throw "Refusing non-read call: $method $url" }
  try {
    $params = @{ Uri = $url; Method = $method; UseBasicParsing = $true; Headers = @{ Authorization = "Bearer $token" } }
    if ($body) {
      $params.ContentType = 'application/json; charset=utf-8'
      $params.Body = [Text.Encoding]::UTF8.GetBytes($body)
    }
    $resp = Invoke-WebRequest @params
  } catch {
    $detail = $_.ErrorDetails.Message
    if (-not $detail) { $detail = $_.Exception.Message }
    throw "Firestore read failed for project '$project': $detail"
  }
  $reader = New-Object IO.StreamReader($resp.RawContentStream, [Text.Encoding]::UTF8)
  return ($reader.ReadToEnd() | ConvertFrom-Json)
}

# Firestore REST "Value" -> plain PowerShell value.
function ConvertFrom-FsValue($v) {
  if ($null -eq $v) { return $null }
  $names = $v.PSObject.Properties.Name
  if ($names -contains 'stringValue') { return $v.stringValue }
  if ($names -contains 'integerValue') { return [long]$v.integerValue }
  if ($names -contains 'doubleValue') { return [double]$v.doubleValue }
  if ($names -contains 'booleanValue') { return [bool]$v.booleanValue }
  if ($names -contains 'timestampValue') { return $v.timestampValue }
  if ($names -contains 'nullValue') { return $null }
  if ($names -contains 'mapValue') { return ConvertFrom-FsFields $v.mapValue.fields }
  if ($names -contains 'arrayValue') {
    $out = @()
    foreach ($item in @($v.arrayValue.values)) { if ($null -ne $item) { $out += , (ConvertFrom-FsValue $item) } }
    return , $out
  }
  if ($names -contains 'referenceValue') { return $v.referenceValue }
  return ($v | ConvertTo-Json -Compress -Depth 5)
}

function ConvertFrom-FsFields($fields) {
  $map = [ordered]@{}
  if ($null -eq $fields) { return $map }
  foreach ($p in $fields.PSObject.Properties) { $map[$p.Name] = ConvertFrom-FsValue $p.Value }
  return $map
}

$FsIst = [TimeZoneInfo]::CreateCustomTimeZone('IST', [TimeSpan]::FromMinutes(330), 'IST', 'IST')

function ConvertTo-FsIst([string]$utcText) {
  $utc = [DateTime]::Parse($utcText, [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::AdjustToUniversal)
  return [TimeZoneInfo]::ConvertTimeFromUtc($utc, $FsIst).ToString('yyyy-MM-dd HH:mm:ss') + ' IST'
}

function Write-FsJson($obj, [string]$path) {
  $utf8 = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 12), $utf8)
}
