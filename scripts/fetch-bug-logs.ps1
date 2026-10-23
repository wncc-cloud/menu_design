<#
.SYNOPSIS
  READ-ONLY export of the app's Bug Logs (top-level Firestore collection clientLogs)
  so they can be analysed by Claude (/check-bug-logs) without copy-paste.

.DESCRIPTION
  Uses the read-only service account bug-log-reader@cafe-countryside-menu (Cloud
  Datastore Viewer only - see scripts/lib/firestore-readonly.ps1). Only runs a query
  (runQuery); Google rejects any write with this token. Costs one Firestore read
  per log returned (free plan: 50,000 reads/day).

  Output: <repo>/client-logs/prod-<yyyyMMdd-HHmmss>.json  (+ prod-latest.json copy)
  The folder is git-ignored: logs contain admin emails, page paths and user agents.

  -Emulator reads the LOCAL Firestore emulator instead (tests only; no gcloud, no PROD).

  One-time setup (asks the owner first - it changes IAM): .\scripts\setup-bug-log-reader.ps1

.EXAMPLE
  .\scripts\fetch-bug-logs.ps1                       # everything still stored (~7 days)
.EXAMPLE
  .\scripts\fetch-bug-logs.ps1 -Hours 24 -Type ERROR # last 24 h, errors only
.EXAMPLE
  .\scripts\fetch-bug-logs.ps1 -Emulator -Port 8080  # local test data
#>
param(
  # 0 = everything still stored (logs expire after 7 days / Admin cleanup)
  [int]$Hours = 0,
  # Filter by type after fetching: ERROR, WARN
  [string[]]$Type = @(),
  # Filter: source contains this text (case-insensitive), e.g. Checkout, Draft
  [string]$Source = '',
  # Max logs read from Firestore (newest first), before the Type/Source filters
  [int]$Limit = 2000,
  # Test only: read the local Firestore emulator on this port instead of PROD
  [switch]$Emulator,
  [int]$Port = 8080,
  [string]$OutDir = '',
  # Test only: output file prefix (default prod, or emu with -Emulator)
  [string]$Prefix = ''
)

. (Join-Path $PSScriptRoot 'lib\firestore-readonly.ps1')

if ($Emulator) {
  $project = $FsEmulatorProject
  $token = 'owner'   # emulator-only "admin" bearer; rules are bypassed locally
  $docsRoot = Get-FsDocsRoot $project $Port
  if (-not $Prefix) { $Prefix = 'emu' }
} else {
  $project = $FsProjects['prod']
  $token = Get-FsReadOnlyToken $project
  $docsRoot = Get-FsDocsRoot $project
  if (-not $Prefix) { $Prefix = 'prod' }
}

$query = [ordered]@{
  from    = @(@{ collectionId = 'clientLogs' })
  orderBy = @(@{ field = @{ fieldPath = 'createdAt' }; direction = 'DESCENDING' })
  limit   = $Limit
}
if ($Hours -gt 0) {
  $since = (Get-Date).ToUniversalTime().AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ')
  $query.where = @{ fieldFilter = @{
      field = @{ fieldPath = 'createdAt' }; op = 'GREATER_THAN_OR_EQUAL'; value = @{ timestampValue = $since }
    } }
}
$body = @{ structuredQuery = $query } | ConvertTo-Json -Depth 12 -Compress
$rows = Invoke-FsRead $project $token 'POST' "${docsRoot}:runQuery" $body

$logs = New-Object System.Collections.ArrayList
foreach ($row in @($rows)) {
  if ($null -eq $row.document) { continue }
  $doc = ConvertFrom-FsFields $row.document.fields
  $entry = [ordered]@{ id = ($row.document.name -split '/')[-1] }
  if ($doc.Contains('createdAt') -and $doc['createdAt']) { $entry.createdAtIst = ConvertTo-FsIst $doc['createdAt'] }
  foreach ($k in $doc.Keys) { $entry[$k] = $doc[$k] }
  [void]$logs.Add($entry)
}
$fetched = $logs.Count

if ($Type.Count -gt 0) {
  $wanted = $Type | ForEach-Object { $_.ToUpperInvariant() }
  $logs = @($logs | Where-Object { $wanted -contains "$($_['type'])".ToUpperInvariant() })
}
if ($Source) {
  $logs = @($logs | Where-Object { "$($_['source'])" -like "*$Source*" })
}

if (-not $OutDir) { $OutDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')) 'client-logs' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $OutDir "$Prefix-$stamp.json"
$latest = Join-Path $OutDir "$Prefix-latest.json"
$meta = [ordered]@{
  project   = $project
  emulator  = [bool]$Emulator
  fetchedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
  filters   = [ordered]@{ hours = $Hours; type = $Type; source = $Source; limit = $Limit }
  readFromDb = $fetched
  count     = @($logs).Count
  logs      = @($logs)
}
Write-FsJson $meta $outFile
Write-FsJson $meta $latest

$where = if ($Emulator) { "LOCAL emulator :$Port" } else { 'PROD (read-only)' }
Write-Output "Project $project, $where - read $fetched log(s), kept $(@($logs).Count) after filters."
Write-Output "Saved: $outFile"
Write-Output "       $latest"
if (@($logs).Count -gt 0) {
  Write-Output ''
  Write-Output 'By type / source:'
  @($logs) | Group-Object { "$($_['type']) | $($_['source'])" } | Sort-Object Count -Descending |
    ForEach-Object { Write-Output ('  {0,4}  {1}' -f $_.Count, $_.Name) }
  if ($fetched -ge $Limit) { Write-Output "NOTE: hit -Limit $Limit; older logs were not read." }
}
