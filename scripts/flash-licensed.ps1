<#
.SYNOPSIS
  Pull and flash a firmware build selected by License alias without modifying
  the existing flash.ps1 workflow.

.DESCRIPTION
  Selects one exact QIO artifact from the locked main baseline release, the
  current BLE ownership test candidate, or an explicit branch artifact path;
  downloads it from the devbox, verifies SHA256, installs it as scripts\fw.bin,
  then delegates the actual COM-port flashing to flash.ps1 -NoPull.

  UUID/AuthKey values are never downloaded or printed. LicenseAlias selects a
  prebuilt artifact whose embedded identity was verified on the devbox.

.PARAMETER LicenseAlias
  Required device identity alias: Orange or Purple.

.PARAMETER BuildSet
  Baseline (default): locked main v0.1.8 release 260915_0950.
  Candidate: BLE ownership/Header/LCD-UART test build 260915_0957.
  Branch: pull an exact alias-labelled branch artifact passed via RemoteBinPath.

.PARAMETER RemoteBinPath
  Required with BuildSet=Branch. Absolute path on the devbox to an exact QIO
  binary. Its filename must contain the selected LicenseAlias to prevent
  accidentally flashing an Orange build onto Purple (or vice versa).

.EXAMPLE
  .\flash-licensed.ps1 -LicenseAlias Orange -Port COM6

.EXAMPLE
  .\flash-licensed.ps1 -LicenseAlias Purple -BuildSet Candidate -Port COM6 -Monitor

.EXAMPLE
  .\flash-licensed.ps1 -LicenseAlias Orange -BuildSet Branch `
    -RemoteBinPath "/data/projects/my-branch/test-builds/ak-firmware_QIO_ble-fix-orange.bin" `
    -Port COM6
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Orange", "Purple")]
    [string]$LicenseAlias,

    [ValidateSet("Baseline", "Candidate", "Branch")]
    [string]$BuildSet = "Baseline",

    [string]$Version = "0.1.8",
    [string]$ReleaseId = "260915_0950",
    [string]$CandidateId = "260915_0957",
    [string]$RemoteBinPath,
    [string]$Port = "COM6",
    [switch]$Monitor,
    [int]$Baud = 460800,
    [int]$MonitorBaud = 115200,
    [string]$SshHost = "devbox-ssm",
    [string]$RemoteProjectRoot = "/data/projects/tuya-powered-agentic-keyboard-for-kiro",
    [string]$RemoteCandidateRoot = "/data/kiro/.kiro/crew/workspace/outputs",
    [string]$TyuTool = "tyutool_cli",
    [string]$Device = "t5ai"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$flashScript = Join-Path $scriptDir "flash.ps1"
$localBin = Join-Path $scriptDir "fw.bin"
$localMeta = Join-Path $scriptDir "fw.bin.meta"
$downloadBin = Join-Path $scriptDir "fw.bin.download"
$downloadSums = Join-Path $scriptDir "fw.bin.sha256.download"

function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[ OK ] $msg" -ForegroundColor Green }

if (-not (Test-Path $flashScript)) {
    Fail "Existing flash script not found: $flashScript"
}
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Fail "ssh not found. Install the Windows OpenSSH client."
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Fail "scp not found. Install the Windows OpenSSH client."
}

$aliasLower = $LicenseAlias.ToLowerInvariant()
$useChecksumManifest = $true
if ($BuildSet -eq "Baseline") {
    $remoteDir = "$RemoteProjectRoot/releases/firmware/v$Version/$ReleaseId"
    $remoteName = "ak-firmware_QIO_v${Version}_${aliasLower}_${ReleaseId}.bin"
    $remoteBin = "$remoteDir/$remoteName"
    $sourceLabel = "locked main baseline v$Version/$ReleaseId"
} elseif ($BuildSet -eq "Candidate") {
    $remoteDir = "$RemoteCandidateRoot/ak-ble-owner-candidate-$CandidateId"
    $remoteName = "ak-firmware_QIO_v${Version}_ble-fix-${aliasLower}.bin"
    $remoteBin = "$remoteDir/$remoteName"
    $sourceLabel = "BLE ownership test candidate $CandidateId"
    Write-Host "[WARN] Candidate is not a locked release; use for hardware validation only." -ForegroundColor Yellow
} else {
    if ([string]::IsNullOrWhiteSpace($RemoteBinPath) -or -not $RemoteBinPath.StartsWith("/")) {
        Fail "BuildSet=Branch requires an absolute devbox -RemoteBinPath."
    }
    if ($RemoteBinPath -notmatch '^/[A-Za-z0-9._/-]+$') {
        Fail "RemoteBinPath may contain only letters, digits, dot, underscore, slash and hyphen."
    }
    $remoteBin = $RemoteBinPath.Trim()
    $slash = $remoteBin.LastIndexOf('/')
    if ($slash -lt 1 -or $slash -eq ($remoteBin.Length - 1)) {
        Fail "Invalid -RemoteBinPath: $remoteBin"
    }
    $remoteDir = $remoteBin.Substring(0, $slash)
    $remoteName = $remoteBin.Substring($slash + 1)
    if ($remoteName -notmatch "(?i)$([regex]::Escape($aliasLower))") {
        Fail "Branch artifact filename '$remoteName' does not contain License alias '$aliasLower'. Rename/copy it to an alias-labelled filename before flashing."
    }
    if ($remoteName -notmatch "(?i)QIO" -or $remoteName -notmatch "(?i)\.bin$") {
        Fail "Branch artifact must be an explicitly named QIO .bin file: $remoteName"
    }
    $sourceLabel = "branch artifact $remoteName"
    $useChecksumManifest = $false
    Write-Host "[WARN] Branch artifact is not a locked release; use for hardware validation only." -ForegroundColor Yellow
}

$remoteSums = "$remoteDir/SHA256SUMS"
Info "Selected $sourceLabel, License alias=$LicenseAlias"
Info "Remote artifact: $remoteBin"

try {
    if (Test-Path $downloadBin) { Remove-Item $downloadBin -Force }
    if (Test-Path $downloadSums) { Remove-Item $downloadSums -Force }

    if ($useChecksumManifest) {
        Info "Pulling checksum manifest..."
        scp "${SshHost}:${remoteSums}" $downloadSums
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $downloadSums)) {
            Fail "Could not download SHA256SUMS from $remoteSums"
        }

        $sumLine = Get-Content $downloadSums |
            Where-Object { $_ -match "^[0-9a-fA-F]{64}\s+$([regex]::Escape($remoteName))$" } |
            Select-Object -First 1
        if (-not $sumLine) {
            Fail "No checksum entry found for $remoteName"
        }
        $expectedSha = ($sumLine -split '\s+', 2)[0].ToLowerInvariant()
    } else {
        Info "Reading exact branch artifact SHA256 from devbox..."
        $hashCmd = "sha256sum -- '$remoteBin'"
        $hashOut = (ssh $SshHost $hashCmd).Trim()
        if ($LASTEXITCODE -ne 0) {
            Fail "Could not obtain SHA256 for branch artifact: $remoteBin"
        }
        if ($hashOut -match '^([0-9a-fA-F]{64})\s+') {
            $expectedSha = $Matches[1].ToLowerInvariant()
        } else {
            Fail "Invalid SHA256 response for branch artifact: $remoteBin"
        }
    }

    Info "Pulling selected QIO firmware..."
    scp "${SshHost}:${remoteBin}" $downloadBin
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $downloadBin)) {
        Fail "Could not download firmware from $remoteBin"
    }

    $actualSha = (Get-FileHash -Algorithm SHA256 $downloadBin).Hash.ToLowerInvariant()
    if ($actualSha -ne $expectedSha) {
        Fail "SHA256 mismatch. Expected $expectedSha, got $actualSha. Existing fw.bin was not changed."
    }
    Ok "SHA256 verified: $actualSha"

    Move-Item -Path $downloadBin -Destination $localBin -Force
    $remoteSize = (Get-Item $localBin).Length
    Set-Content -Path $localMeta -Value "$remoteBin|$remoteSize|sha256:$actualSha" -NoNewline
    Ok "Installed $remoteName as $localBin"
} finally {
    if (Test-Path $downloadBin) { Remove-Item $downloadBin -Force }
    if (Test-Path $downloadSums) { Remove-Item $downloadSums -Force }
}

$flashArgs = @(
    "-NoPull",
    "-Port", $Port,
    "-Baud", $Baud,
    "-MonitorBaud", $MonitorBaud,
    "-SshHost", $SshHost,
    "-RemoteProjectRoot", $RemoteProjectRoot,
    "-TyuTool", $TyuTool,
    "-Device", $Device
)
if ($Monitor) { $flashArgs += "-Monitor" }

Info "Delegating flash to existing flash.ps1 (source=$sourceLabel, alias=$LicenseAlias)"
& $flashScript @flashArgs
if ($LASTEXITCODE -ne 0) {
    Fail "flash.ps1 failed with exit code $LASTEXITCODE"
}
Ok "Flashed $sourceLabel / $LicenseAlias to $Port"
