<#
.SYNOPSIS
  Sync the Kiro Crew gateway's .local_secret from the EC2 devbox to this machine,
  so the companion (FP-4 kirocrew-control) can authenticate to the gateway.

.DESCRIPTION
  FP-4's session-control client sends header X-Internal-Secret = the contents of
  the gateway's .local_secret. The gateway runs on the EC2 devbox, so this machine
  needs the SAME secret locally. This script scp's it over the `devbox` SSH alias
  (the same alias flash.ps1 uses) into the local KiroCrew home.

  The secret VALUE never appears on screen or in the repo -- only the byte count is
  printed as a sanity check. Pair this with tunnel-kirocrew.ps1 (forwards 5476).

  Remote path: /data/kiro/.kiro/crew/.local_secret  (the migrated, ACTIVE gateway
  secret -- NOT ~/.kiro/crew/.local_secret, which is a stale pre-migration copy).

.PARAMETER Remote
  SSH host alias / target for the EC2 devbox. Default: devbox

.PARAMETER RemotePath
  Path of the secret on the devbox. Default: /data/kiro/.kiro/crew/.local_secret

.PARAMETER LocalPath
  Destination on this machine. Default: $HOME\.kiro\crew\.local_secret

.EXAMPLE
  .\scripts\sync-local-secret.ps1
  .\scripts\sync-local-secret.ps1 -Remote devbox
#>
param(
    [string]$Remote     = "devbox-ssm",
    [string]$RemotePath = "/data/kiro/.kiro/crew/.local_secret",
    [string]$LocalPath  = "$HOME\.kiro\crew\.local_secret"
)

$ErrorActionPreference = "Stop"

$localDir = Split-Path -Parent $LocalPath
if (-not (Test-Path $localDir)) {
    New-Item -ItemType Directory -Force -Path $localDir | Out-Null
    Write-Host "created $localDir"
}

Write-Host "syncing ${Remote}:${RemotePath} -> $LocalPath ..."
scp "${Remote}:${RemotePath}" "$LocalPath"
if ($LASTEXITCODE -ne 0) {
    throw "scp failed (exit $LASTEXITCODE). Check that 'ssh $Remote' works and the remote path exists."
}

$len = (Get-Item $LocalPath).Length
Write-Host "OK: wrote $LocalPath ($len bytes)  [value not shown]"
Write-Host "Next: run scripts\tunnel-kirocrew.ps1 to forward 127.0.0.1:5476 to the gateway, then start the companion."
