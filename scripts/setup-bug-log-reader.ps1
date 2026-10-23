<#
.SYNOPSIS
  ONE-TIME setup of the read-only identity used by scripts/fetch-bug-logs.ps1
  and scripts/read-firestore-doc.ps1. Run once, as the owner.

.DESCRIPTION
  In the Firebase project cafe-countryside-menu this:
    1. enables the IAM Service Account Credentials API (needed to borrow the account),
    2. creates service account  bug-log-reader@cafe-countryside-menu.iam.gserviceaccount.com
       (no key file is ever created or downloaded),
    3. gives it ONLY roles/datastore.viewer (read Firestore; cannot write/delete),
    4. lets the signed-in owner account borrow it (roles/iam.serviceAccountTokenCreator
       on that one service account only).
  Safe to run again: steps that are already done are skipped.
  This changes Google Cloud permissions (IAM) - nothing in the app, rules or data.

  What "read Firestore" covers here: menu, drafts, admins and Bug Logs of this project.
  There is no customer or order data in it (orders live in the counter app's project).

  To undo:  gcloud iam service-accounts delete bug-log-reader@cafe-countryside-menu.iam.gserviceaccount.com --project cafe-countryside-menu
            gcloud projects remove-iam-policy-binding cafe-countryside-menu --member serviceAccount:bug-log-reader@cafe-countryside-menu.iam.gserviceaccount.com --role roles/datastore.viewer

.EXAMPLE
  .\scripts\setup-bug-log-reader.ps1
#>
. (Join-Path $PSScriptRoot 'lib\firestore-readonly.ps1')
# gcloud writes progress to stderr; only exit codes decide success here.
$ErrorActionPreference = 'Continue'

$project = $FsProjects['prod']
$sa = Get-FsReaderEmail $project
$gcloud = Find-Gcloud

function Invoke-Gcloud([string[]]$gcloudArgs, [string]$what) {
  Write-Output "-> $what"
  & $gcloud @gcloudArgs --quiet
  if ($LASTEXITCODE -ne 0) { throw "gcloud failed: $what" }
}

$owner = "$(& $gcloud config get-value account 2>$null)".Trim()
if (-not $owner) { throw 'No gcloud account. Run: gcloud auth login' }
Write-Output "Project: $project   Owner account: $owner   Reader: $sa"

Invoke-Gcloud @('services', 'enable', 'iamcredentials.googleapis.com', '--project', $project) 'enable IAM Credentials API'

& $gcloud iam service-accounts describe $sa --project $project *> $null
if ($LASTEXITCODE -ne 0) {
  Invoke-Gcloud @('iam', 'service-accounts', 'create', $FsReaderName, '--project', $project,
    '--display-name', 'Bug log reader (read-only)',
    '--description', 'Read-only Firestore access for scripts/fetch-bug-logs.ps1. No keys.') 'create service account'
} else {
  Write-Output "-> service account already exists"
}

Invoke-Gcloud @('projects', 'add-iam-policy-binding', $project,
  '--member', "serviceAccount:$sa", '--role', 'roles/datastore.viewer', '--condition', 'None',
  '--format', 'none') 'grant Cloud Datastore Viewer (read-only)'

Invoke-Gcloud @('iam', 'service-accounts', 'add-iam-policy-binding', $sa, '--project', $project,
  '--member', "user:$owner", '--role', 'roles/iam.serviceAccountTokenCreator',
  '--format', 'none') "allow $owner to borrow the reader"

Write-Output ''
Write-Output 'Checking (new permissions can take up to ~2 minutes to apply)...'
for ($i = 1; $i -le 12; $i++) {
  $token = (& $gcloud auth print-access-token "--impersonate-service-account=$sa" 2>$null)
  if ($token) { Write-Output 'OK - read-only token works. Try: .\scripts\fetch-bug-logs.ps1 -Hours 24'; exit 0 }
  Start-Sleep -Seconds 10
}
Write-Output 'Setup done, but the token is not ready yet. Wait a minute and run fetch-bug-logs.ps1.'
