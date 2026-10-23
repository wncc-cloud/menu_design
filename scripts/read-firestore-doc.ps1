<#
.SYNOPSIS
  READ-ONLY: print one Firestore document (or list one collection) as JSON, to see
  the data behind a bug log (e.g. menu/current or menuDraft/data).

.DESCRIPTION
  Same read-only service account as fetch-bug-logs.ps1 (Cloud Datastore Viewer
  only). Paths are relative to the database root. Prints to the console; nothing
  is saved. Admin emails may appear - do not paste output publicly.
  -Emulator reads the local Firestore emulator instead (tests only).

.EXAMPLE
  .\scripts\read-firestore-doc.ps1 -Path menu/current
.EXAMPLE
  .\scripts\read-firestore-doc.ps1 -Path businesses -PageSize 5
.EXAMPLE
  .\scripts\read-firestore-doc.ps1 -Path menu/current -Emulator -Port 8080
#>
param(
  # Document path (even number of segments) or collection path (odd number).
  [Parameter(Mandatory = $true)] [string]$Path,
  # Collection listing only: how many documents to return.
  [int]$PageSize = 10,
  [switch]$Emulator,
  [int]$Port = 8080
)

. (Join-Path $PSScriptRoot 'lib\firestore-readonly.ps1')

if ($Emulator) {
  $project = $FsEmulatorProject
  $token = 'owner'
  $root = Get-FsDocsRoot $project $Port
} else {
  $project = $FsProjects['prod']
  $token = Get-FsReadOnlyToken $project
  $root = Get-FsDocsRoot $project
}
$clean = $Path.Trim('/')
$base = "$root/$clean"

function ConvertFrom-FsDoc($d) {
  $entry = [ordered]@{ path = ($d.name -split '/documents/')[-1] }
  foreach ($kv in (ConvertFrom-FsFields $d.fields).GetEnumerator()) { $entry[$kv.Key] = $kv.Value }
  return $entry
}

if ((($clean -split '/').Count % 2) -eq 0) {
  $doc = Invoke-FsRead $project $token 'GET' $base
  ConvertFrom-FsDoc $doc | ConvertTo-Json -Depth 12
} else {
  $list = Invoke-FsRead $project $token 'GET' "${base}?pageSize=$PageSize"
  @(@($list.documents) | Where-Object { $_ } | ForEach-Object { ConvertFrom-FsDoc $_ }) | ConvertTo-Json -Depth 12
}
