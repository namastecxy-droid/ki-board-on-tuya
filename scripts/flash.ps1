<#
.SYNOPSIS
  One-click flash: pull the latest QIO firmware bin from the devbox (EC2) via scp,
  then flash it to the T5AI-Core over serial with tyutool, optionally opening a serial monitor.

.DESCRIPTION
  Build model: firmware is compiled on the EC2 devbox (`tos.py build`); this machine only
  flashes and debugs. EC2 cannot see the local USB serial port, so flashing happens locally.

  Prerequisites (local Windows):
    - WCH CH343SER driver installed (board uses CH342F -> two COM ports appear)
    - tyutool CLI on PATH (or pass -TyuTool <path>). Download: https://tuyaopen.ai/tyutool
    - OpenSSH client (built into Win10/11) with an SSH host alias `devbox` configured
      (~/.ssh/config), matching how you run `ssh devbox`.

.PARAMETER Port
  Serial COM port to flash (e.g. COM5). If omitted, the script lists candidate ports and asks.

.PARAMETER App
  Remote app directory name under the project. Default: signal_light_demo/source/embedded
  For our own tests later, pass e.g. -App "firmware/tests/lcd".

.PARAMETER Build
  If set, run `tos.py build` on the devbox before pulling the bin.

.PARAMETER Monitor
  If set, open a serial monitor after flashing (tyutool_cli monitor).

.PARAMETER Baud
  Flash/monitor baud rate. T5 uses 460800 by default.

.EXAMPLE
  .\flash.ps1 -Port COM5
  Pull latest signal_light_demo QIO bin and flash to COM5.

.EXAMPLE
  .\flash.ps1 -Port COM5 -Build -Monitor
  Build on devbox first, then flash, then open serial monitor.

.EXAMPLE
  .\flash.ps1 -Port COM5 -App "firmware/tests/lcd/source/embedded"
  Flash a specific test app's bin.
#>
[CmdletBinding()]
param(
    [string]$Port,
    [string]$App = "signal_light_demo/source/embedded",
    [switch]$Build,
    [switch]$Monitor,
    [int]$Baud = 460800,
    [string]$SshHost = "devbox",
    [string]$RemoteProjectRoot = "/data/projects/tuya-powered-agentic-keyboard-for-kiro",
    [string]$TuyaOpenRoot = "/data/projects/TuyaOpen",
    [string]$TyuTool = "tyutool_cli",
    [string]$Device = "t5ai"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$localBin  = Join-Path $scriptDir "fw.bin"

function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[ OK ] $msg" -ForegroundColor Green }

# --- 0. Sanity: ssh + scp available ---
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Fail "ssh not found. Install OpenSSH client." }
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { Fail "scp not found. Install OpenSSH client." }

$remoteApp = "$RemoteProjectRoot/$App"

# --- 1. Optional: build on devbox ---
if ($Build) {
    Info "Building on $SshHost : $remoteApp (tos.py build)"
    # source export.sh to get tos.py on PATH, then clean+build for reproducibility
    $remoteCmd = "cd '$TuyaOpenRoot' && source ./export.sh >/dev/null 2>&1; cd '$remoteApp' && tos.py build 2>&1 | tail -30"
    ssh $SshHost $remoteCmd
    if ($LASTEXITCODE -ne 0) { Fail "Remote build failed (exit $LASTEXITCODE)." }
    Ok "Remote build finished."
}

# --- 2. Locate newest *_QIO_*.bin on devbox ---
Info "Locating latest QIO bin under $remoteApp/.build/bin ..."
# -printf keeps it to a single newest path; fall back to plain find if -printf unsupported
$findCmd = "ls -t '$remoteApp'/.build/bin/*_QIO_*.bin 2>/dev/null | head -1"
$remoteBin = (ssh $SshHost $findCmd).Trim()
if ([string]::IsNullOrWhiteSpace($remoteBin)) {
    Fail "No *_QIO_*.bin found on $SshHost under $remoteApp/.build/bin. Run with -Build first, or check the -App path."
}
Info "Remote bin: $remoteBin"

# --- 3. Pull it via scp ---
if (Test-Path $localBin) { Remove-Item $localBin -Force }
Info "Pulling bin -> $localBin"
scp "${SshHost}:${remoteBin}" $localBin
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $localBin)) { Fail "scp failed." }
$sizeKB = [math]::Round((Get-Item $localBin).Length / 1KB, 1)
Ok "Pulled $sizeKB KB -> $localBin"

# --- 4. Resolve COM port ---
if (-not $Port) {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if (-not $ports) { Fail "No COM ports found. Check CH343SER driver + USB cable + power switch ON." }
    Write-Host "Available COM ports: $($ports -join ', ')" -ForegroundColor Yellow
    $Port = Read-Host "Enter COM port to flash (e.g. $($ports[0]))"
    if (-not $Port) { Fail "No port selected." }
}

# --- 5. Flash with tyutool ---
if (-not (Get-Command $TyuTool -ErrorAction SilentlyContinue) -and -not (Test-Path $TyuTool)) {
    Fail "tyutool CLI '$TyuTool' not found. Install from https://tuyaopen.ai/tyutool or pass -TyuTool <path>. (You may also flash fw.bin manually via the WebTool: https://tuyaopen.ai/web-serial)"
}
Write-Host ""
Write-Host "  >>> Make sure the board POWER SWITCH is ON before flashing. <<<" -ForegroundColor Yellow
Write-Host ""
Info "Flashing $localBin -> $Port @ $Baud (device=$Device)"
# NOTE: exact subcommand/flags depend on your tyutool version; adjust per `tyutool_cli --help`.
& $TyuTool write -d $Device -p $Port -b $Baud -f $localBin
if ($LASTEXITCODE -ne 0) { Fail "Flash failed (exit $LASTEXITCODE). Check port, baud, power switch, and download mode." }
Ok "Flash complete."

# --- 6. Optional monitor ---
if ($Monitor) {
    Info "Opening serial monitor on $Port @ $Baud (Ctrl+C to exit)"
    & $TyuTool monitor -p $Port -b $Baud
}
