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
  Remote app directory name under the project. Default: ref_projects/signal_light_demo/source/embedded
  For our own tests later, pass e.g. -App "firmware/tests/lcd".

.PARAMETER Build
  If set, run `tos.py build` on the devbox before pulling the bin.

.PARAMETER Monitor
  If set, open a serial monitor after flashing (tyutool_cli monitor).

.PARAMETER NoPull
  Skip the scp download entirely and flash the existing local fw.bin. Fastest
  path for repeat flashing or when offline. Fails if no local fw.bin exists yet.

.PARAMETER Force
  Force a fresh scp download even if the local fw.bin already matches the remote
  (by size + modification time recorded in fw.bin.meta).

.PARAMETER Baud
  Flash/monitor baud rate. T5 uses 460800 by default.

.NOTES
  Download is skipped automatically when the local fw.bin already matches the
  newest remote QIO bin (same size + mtime). Port defaults to the CH342F A port
  (download/debug) when no -Port is given.

.EXAMPLE
  .\flash.ps1
  Pull latest bin only if it changed, then flash the CH342F A port.

.EXAMPLE
  .\flash.ps1 -NoPull
  Flash the existing local fw.bin without contacting the devbox (fastest).

.EXAMPLE
  .\flash.ps1 -Port COM5 -Build -Monitor
  Build on devbox first, then flash, then open serial monitor.

.EXAMPLE
  .\flash.ps1 -Force
  Re-download the firmware even if it looks unchanged, then flash.

.EXAMPLE
  .\flash.ps1 -App "firmware/tests/lcd/source/embedded"
  Flash a specific test app's bin.
#>
[CmdletBinding()]
param(
    [string]$Port,
    [string]$App = "ref_projects/signal_light_demo/source/embedded",
    [switch]$Build,
    [switch]$Monitor,
    # Skip the scp download entirely and flash the existing local fw.bin.
    # Fastest path when the firmware hasn't changed (offline / repeat flashing).
    [switch]$NoPull,
    # Force a fresh download even if the local fw.bin already matches the remote.
    [switch]$Force,
    [int]$Baud = 460800,
    [string]$SshHost = "devbox-ssm",
    [string]$RemoteProjectRoot = "/data/projects/tuya-powered-agentic-keyboard-for-kiro",
    [string]$TuyaOpenRoot = "/data/projects/TuyaOpen",
    [string]$TyuTool = "tyutool_cli",
    [string]$Device = "t5ai"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$localBin  = Join-Path $scriptDir "fw.bin"
# Sidecar file caching the remote fingerprint (path|size|mtime) of the last
# successful pull, so we can skip re-downloading an unchanged firmware.
$localMeta = Join-Path $scriptDir "fw.bin.meta"

function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[ OK ] $msg" -ForegroundColor Green }

# --- 0. Sanity: ssh + scp available ---
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Fail "ssh not found. Install OpenSSH client." }
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { Fail "scp not found. Install OpenSSH client." }

# Resolve tyutool: if the user did not override -TyuTool, prefer a copy sitting
# next to this script (scripts\tyutool_cli.exe) so it works regardless of the
# current working directory or PATH. Fall back to the bare name (PATH lookup).
if ($TyuTool -eq "tyutool_cli") {
    $localTyu = Join-Path $scriptDir "tyutool_cli.exe"
    if (Test-Path $localTyu) { $TyuTool = $localTyu }
}

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

# --- 2/3. Obtain firmware (skip the slow scp when nothing changed) ---
if ($NoPull) {
    # Offline / repeat-flash path: use whatever fw.bin is already here.
    if (-not (Test-Path $localBin)) {
        Fail "-NoPull was given but no local fw.bin exists at $localBin. Run once without -NoPull to fetch it."
    }
    Info "Using existing local firmware (-NoPull): $localBin"
    # Recover the original firmware filename from the cached fingerprint, if any.
    $srcName = if (Test-Path $localMeta) {
        Split-Path -Leaf ((Get-Content $localMeta -Raw).Trim() -split '\|')[0]
    } else { "unknown (no fw.bin.meta)" }
} else {
    # --- 2. Locate newest *_QIO_*.bin on devbox, capturing its fingerprint ---
    Info "Locating latest QIO bin under $remoteApp/dist or $remoteApp/.build/bin ..."
    # Current TuyaOpen writes release artifacts to dist/<version>/; older versions
    # used .build/bin. Return the newest match as "mtime|size|path" so we can
    # fingerprint it without a second round-trip.
    $findCmd = "find '$remoteApp/dist' '$remoteApp/.build/bin' -type f -name '*_QIO_*.bin' -printf '%T@ %s %p\n' 2>/dev/null | sort -nr | head -1"
    $findOut = (ssh $SshHost $findCmd).Trim()
    if ([string]::IsNullOrWhiteSpace($findOut)) {
        Fail "No *_QIO_*.bin found on $SshHost under $remoteApp/dist or $remoteApp/.build/bin. Run with -Build first, or check the -App path."
    }
    # Split into: <mtime> <size> <path...>  (path may contain spaces)
    $parts       = $findOut -split '\s+', 3
    $remoteMtime = $parts[0]
    $remoteSize  = $parts[1]
    $remoteBin   = $parts[2]
    $remoteFp    = "$remoteBin|$remoteSize|$remoteMtime"
    $srcName     = Split-Path -Leaf $remoteBin
    Info "Remote bin: $remoteBin ($([math]::Round([long]$remoteSize / 1KB, 1)) KB)"

    # Decide whether we can reuse the local copy.
    $localFp = if (Test-Path $localMeta) { (Get-Content $localMeta -Raw).Trim() } else { "" }
    $localSizeOk = (Test-Path $localBin) -and ((Get-Item $localBin).Length -eq [long]$remoteSize)

    if (-not $Force -and (Test-Path $localBin) -and $localSizeOk -and ($localFp -eq $remoteFp)) {
        Ok "Local firmware already matches remote; skipping download (use -Force to re-pull)."
    } else {
        # --- 3. Pull it via scp ---
        if (Test-Path $localBin) { Remove-Item $localBin -Force }
        Info "Pulling bin -> $localBin"
        scp "${SshHost}:${remoteBin}" $localBin
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $localBin)) { Fail "scp failed." }
        # Record the remote fingerprint for the next run.
        Set-Content -Path $localMeta -Value $remoteFp -NoNewline
    }
}
$sizeKB = [math]::Round((Get-Item $localBin).Length / 1KB, 1)
if (-not $srcName) { $srcName = "unknown" }
Ok "Firmware ready: $srcName -> fw.bin ($sizeKB KB)"

# --- 4. Ensure tyutool is available (needed both for port listing and flashing) ---
if (-not (Get-Command $TyuTool -ErrorAction SilentlyContinue) -and -not (Test-Path $TyuTool)) {
    Fail "tyutool CLI '$TyuTool' not found. Install from https://tuyaopen.ai/tyutool or pass -TyuTool <path>. (You may also flash fw.bin manually via the WebTool: https://tuyaopen.ai/web-serial)"
}

# --- 5. Resolve COM port ---
if (-not $Port) {
    # Enumerate ports via tyutool itself (`list-ports --json`) rather than the
    # OS-level [SerialPort]::GetPortNames() or Get-PnpDevice. tyutool's view is
    # the ground truth for "can this port actually be flashed": a port that
    # tyutool cannot see cannot be opened for flashing, even if Device Manager
    # shows the underlying hardware. This keeps port detection and flashing on a
    # single, consistent source.
    # tyutool writes its version/log banner to stderr. With $ErrorActionPreference
    # = "Stop", PowerShell treats any native-command stderr output as a terminating
    # error, so we relax it locally and merge stderr into stdout (2>&1). The banner
    # lines are harmless here because we slice from the first '[' below.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $portJson = & $TyuTool list-ports --json --plain 2>&1
    $ErrorActionPreference = $eap
    # tyutool prints a couple of banner lines (version / log path) before the
    # JSON array; grab everything from the first '[' onward so ConvertFrom-Json
    # only sees the array. Coerce each record to string (2>&1 yields ErrorRecords).
    $joined   = (($portJson | ForEach-Object { $_.ToString() }) -join "`n")
    $startIdx = $joined.IndexOf('[')
    $ports    = @()
    if ($startIdx -ge 0) {
        try   { $ports = @($joined.Substring($startIdx) | ConvertFrom-Json) }
        catch { $ports = @() }
    }

    if (-not $ports -or $ports.Count -eq 0) {
        Fail ("tyutool sees no serial ports. Checklist:`n" +
              "  1. USB must be plugged into the T5AI-Core dev board (its CH342F exposes TWO COM ports).`n" +
              "     A bare CH340 adapter shows only one port and cannot flash the board.`n" +
              "  2. Board POWER SWITCH is ON, then re-plug USB.`n" +
              "  3. Use a USB *data* cable (not charge-only); if needed, install the WCH driver: https://www.wch.cn/downloads/CH343SER_EXE.html`n" +
              "Re-check with:  $TyuTool list-ports --plain")
    }

    Write-Host "Ports visible to tyutool (flashable):" -ForegroundColor Yellow
    foreach ($p in $ports) {
        # CH342F on the T5AI-Core enumerates as VID 0x1A86 (6790) & PID 0x55D2 (21970),
        # exposing two ports: SERIAL-A (download/debug, Uart1) and SERIAL-B.
        $isCH342 = ($p.usbVid -eq 6790 -and $p.usbPid -eq 21970)
        $isA     = $isCH342 -and ($p.name -match 'SERIAL-A')
        $tag = if ($isA) { "  <- CH342F port A (download)" }
               elseif ($isCH342) { "  <- CH342F port B" }
               else { "" }
        Write-Host ("  {0,-6} {1}{2}" -f $p.path, $p.name, $tag) -ForegroundColor Gray
    }

    # Default to the CH342F A port (download/debug). Fall back to any CH342 port,
    # then to the first port available.
    $default = ($ports | Where-Object { $_.usbVid -eq 6790 -and $_.usbPid -eq 21970 -and $_.name -match 'SERIAL-A' } | Select-Object -First 1)
    if (-not $default) { $default = ($ports | Where-Object { $_.usbVid -eq 6790 -and $_.usbPid -eq 21970 } | Select-Object -First 1) }
    if (-not $default) { $default = $ports[0] }

    $Port = Read-Host "Enter COM port to flash (default: $($default.path))"
    if (-not $Port) { $Port = $default.path }
}

# --- 6. Flash with tyutool ---
Write-Host ""
Write-Host "  >>> Make sure the board POWER SWITCH is ON before flashing. <<<" -ForegroundColor Yellow
Write-Host ""
Info "Flashing $localBin -> $Port @ $Baud (device=$Device)"
# NOTE: exact subcommand/flags depend on your tyutool version; adjust per `tyutool_cli --help`.
& $TyuTool write -d $Device -p $Port -b $Baud -f $localBin
if ($LASTEXITCODE -ne 0) { Fail "Flash failed (exit $LASTEXITCODE). Check port, baud, power switch, and download mode." }
Ok "Flash complete."

# --- 7. Optional monitor ---
if ($Monitor) {
    Info "Opening serial monitor on $Port @ $Baud (Ctrl+] or Ctrl+C to exit)"
    & $TyuTool monitor -d $Device -p $Port -b $Baud
}
