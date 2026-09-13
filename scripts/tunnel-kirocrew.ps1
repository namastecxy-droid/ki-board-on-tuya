<#
.SYNOPSIS
  Open an SSH tunnel so this machine's 127.0.0.1:5476 reaches the Kiro Crew
  gateway running on the EC2 devbox -- required for the companion (FP-4).

.DESCRIPTION
  FP-4's session-control client calls http://127.0.0.1:5476 (the gateway). The
  gateway runs on the devbox and only listens on its own loopback, so this script
  forwards local 5476 -> devbox 127.0.0.1:5476 over the `devbox` SSH alias (the
  same alias flash.ps1 uses). Leave this window OPEN while using the companion;
  Ctrl+C closes the tunnel.

  Pair with sync-local-secret.ps1 (the gateway also checks X-Internal-Secret, so
  the local .local_secret must match the devbox's).

.PARAMETER Remote
  SSH host alias / target for the EC2 devbox. Default: devbox

.PARAMETER LocalPort
  Local port to listen on. Default: 5476

.PARAMETER RemotePort
  Gateway port on the devbox. Default: 5476

.EXAMPLE
  .\scripts\tunnel-kirocrew.ps1
#>
param(
    [string]$Remote     = "devbox",
    [int]$LocalPort     = 5476,
    [int]$RemotePort    = 5476
)

Write-Host "Forwarding 127.0.0.1:$LocalPort -> ${Remote}:127.0.0.1:$RemotePort"
Write-Host "Keep this window open while using the companion. Ctrl+C to stop."
ssh -N -L "${LocalPort}:127.0.0.1:${RemotePort}" $Remote
