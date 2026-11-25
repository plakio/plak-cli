# Plak for Windows: WSL2 + Ubuntu 24.04 bootstrap.
#
# Run from PowerShell:
#   irm https://plak.sh/install.ps1 | iex
#
# This script is idempotent. If Windows needs a reboot, it stops with the exact
# command to rerun. It never installs Docker and never changes to another Linux
# distribution without an explicit decision.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptUrl = if ($env:PLAK_WINDOWS_INSTALL_URL) { $env:PLAK_WINDOWS_INSTALL_URL } else { 'https://plak.sh/install.ps1' }
$ElevatedChild = $env:PLAK_WINDOWS_ELEVATED -eq '1'
$DistroFallbacks = @('Ubuntu-24.04', 'Ubuntu', 'Ubuntu-22.04')

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}
function Write-Ok([string]$Message) { Write-Host "  OK: $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  Warning: $Message" -ForegroundColor Yellow }
function Stop-Setup([string]$Message) {
    Write-Host ""
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-FeatureState([string]$Name) {
    try {
        return (Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop).State
    } catch {
        return 'Unknown'
    }
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($key in $keys) {
        if (Test-Path $key) { return $true }
    }
    try {
        $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
        if ($pending) { return $true }
    } catch { }
    return $false
}

function Invoke-ElevatedSelf {
    $escapedUrl = $ScriptUrl.Replace("'", "''")
    $command = "`$env:PLAK_WINDOWS_ELEVATED='1'; `$env:PLAK_WINDOWS_INSTALL_URL='$escapedUrl'; irm '$escapedUrl' | iex"
    Write-Step 'Administrator permission is required for WSL2 setup; opening an elevated PowerShell'
    try {
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command)
    } catch {
        Stop-Setup 'Administrator permission was cancelled. Run the same command again and accept the UAC prompt.'
    }
    exit $process.ExitCode
}

function Get-WslDistros {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return @() }
    $old = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        $raw = (& wsl.exe --list --quiet 2>$null | Out-String)
    } catch {
        $raw = ''
    } finally {
        if ($null -eq $old) {
            Remove-Item Env:WSL_UTF8 -ErrorAction SilentlyContinue
        } else {
            $env:WSL_UTF8 = $old
        }
    }
    $raw = $raw -replace "`0", ''
    return @($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Get-WslOutput {
    param([string]$Distro, [string]$User, [string]$Command)
    $arguments = @('-d', $Distro)
    if ($User) { $arguments += @('-u', $User) }
    $arguments += @('--', 'bash', '-lc', $Command)
    $old = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        $raw = (& wsl.exe @arguments 2>&1 | Out-String)
    } finally {
        if ($null -eq $old) {
            Remove-Item Env:WSL_UTF8 -ErrorAction SilentlyContinue
        } else {
            $env:WSL_UTF8 = $old
        }
    }
    return (($raw -replace "`0", '').Trim())
}

function Invoke-Wsl {
    param([string]$Distro, [string]$User, [string]$Command)
    $arguments = @('-d', $Distro)
    if ($User) { $arguments += @('-u', $User) }
    $arguments += @('--', 'bash', '-lc', $Command)
    & wsl.exe @arguments
    return $LASTEXITCODE
}

function Get-UbuntuDistro {
    $distros = Get-WslDistros
    $distro = $distros | Where-Object { $_ -eq 'Ubuntu-24.04' } | Select-Object -First 1
    if (-not $distro) {
        $distro = $distros | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1
    }
    return $distro
}

function Test-WindowsPrepNeeded {
    foreach ($feature in @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux')) {
        $state = Get-FeatureState $feature
        if ($state -ne 'Enabled' -and $state -ne 'EnablePending') { return $true }
    }
    if (-not (Get-UbuntuDistro)) { return $true }
    return $false
}

function Get-WslUser([string]$Distro) {
    $command = 'awk -F: ''$3 >= 1000 && $3 < 65534 { print $1; exit }'' /etc/passwd'
    return (Get-WslOutput -Distro $Distro -User 'root' -Command $command)
}

# --- Host checks -----------------------------------------------------------

if ($env:OS -ne 'Windows_NT') {
    Stop-Setup 'This bootstrapper is for Windows. On macOS or Linux use: curl -fsSL https://plak.sh/install | PLAK_YES=1 bash'
}
if ([Environment]::OSVersion.Version.Build -lt 19041) {
    Stop-Setup 'Windows 10 version 2004 (build 19041) or newer is required for WSL2.'
}
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne 'AMD64' -and $arch -ne 'ARM64') {
    Stop-Setup "Unsupported Windows architecture '$arch'. Use Windows x64 or ARM64 with WSL2."
}
Write-Host ""
Write-Host "Plak for Windows" -ForegroundColor Cyan
Write-Host "Ubuntu 24.04 LTS on WSL2; Docker is not required."

try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    if ($cpu -and $cpu.VirtualizationFirmwareEnabled -eq $false) {
        Stop-Setup 'Virtualization is disabled in the firmware. Enable Intel VT-x/AMD-V in the BIOS/UEFI and retry.'
    }
} catch {
    Write-Warn 'Could not read the virtualization firmware state; continuing.'
}

$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    if ($ElevatedChild) {
        Stop-Setup 'The elevated process did not receive administrator rights. Accept the UAC prompt and retry.'
    }
    if (Test-WindowsPrepNeeded) { Invoke-ElevatedSelf }
}

if (Test-PendingReboot) {
    Write-Host ""
    Write-Host 'Windows has a pending reboot. Restart Windows, then run the same command again:' -ForegroundColor Yellow
    Write-Host '  irm https://plak.sh/install.ps1 | iex'
    exit 3010
}

# --- Windows features ------------------------------------------------------

$rebootNeeded = $false
foreach ($feature in @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux')) {
    $state = Get-FeatureState $feature
    if ($state -eq 'Enabled' -or $state -eq 'EnablePending') {
        Write-Ok "$feature is enabled."
        continue
    }
    Write-Step "Enabling Windows feature $feature"
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
    if ($result.RestartNeeded) { $rebootNeeded = $true }
    Write-Ok "$feature enabled."
}
if ($rebootNeeded -or (Test-PendingReboot)) {
    Write-Host ""
    Write-Host 'Windows needs to restart to finish the WSL2 setup.' -ForegroundColor Yellow
    Write-Host 'Restart Windows, then run the same command again:' -ForegroundColor Yellow
    Write-Host '  irm https://plak.sh/install.ps1 | iex'
    exit 3010
}

# --- WSL2 and Ubuntu -------------------------------------------------------

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Stop-Setup 'wsl.exe is not available after enabling WSL. Restart Windows and run the same command again.'
}

Write-Step 'Updating WSL'
& wsl.exe --update
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'wsl --update failed; continuing with the current WSL installation.'
}
& wsl.exe --set-default-version 2
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Could not set the default WSL version to 2. Verify with: wsl --list --verbose'
}

$distro = Get-UbuntuDistro
if (-not $distro) {
    $installed = $false
    foreach ($candidate in $DistroFallbacks) {
        Write-Step "Installing $candidate"
        & wsl.exe --install -d $candidate --web-download --no-launch
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            $distro = $candidate
            $installed = $true
            break
        }
        if ($code -eq 3010) {
            Write-Host ""
            Write-Host 'Windows needs to restart to finish the Ubuntu installation.' -ForegroundColor Yellow
            Write-Host 'Restart Windows, then run the same command again:' -ForegroundColor Yellow
            Write-Host '  irm https://plak.sh/install.ps1 | iex'
            exit 3010
        }
        Write-Warn "Could not install $candidate (exit $code)."
    }
    if (-not $installed) {
        Stop-Setup 'Ubuntu could not be installed. Run "wsl --update", retry, and do not switch to Debian unless you explicitly want that.'
    }
    Write-Ok "$distro installed."
} else {
    Write-Ok "Using existing $distro."
}

Write-Step "Preparing $distro (systemd and user)"
& wsl.exe --set-version $distro 2
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Could not confirm $distro as WSL2; verify with: wsl --list --verbose"
}
$init = Get-WslOutput -Distro $distro -User 'root' -Command 'ps -p 1 -o comm='
if ($init -ne 'systemd') {
    Write-Warn 'systemd is not running; enabling it in /etc/wsl.conf.'
    $enableSystemd = 'if ! grep -q "^systemd=true" /etc/wsl.conf 2>/dev/null; then printf "\n[boot]\nsystemd=true\n" >> /etc/wsl.conf; fi'
    $code = Invoke-Wsl -Distro $distro -User 'root' -Command $enableSystemd
    if ($code -ne 0) { Stop-Setup 'Could not write /etc/wsl.conf.' }
    & wsl.exe --shutdown
    Start-Sleep -Seconds 2
    $init = Get-WslOutput -Distro $distro -User 'root' -Command 'ps -p 1 -o comm='
    if ($init -ne 'systemd') {
        Stop-Setup 'systemd is still not running. Add [boot] systemd=true to /etc/wsl.conf, run wsl --shutdown, reopen Ubuntu, and retry.'
    }
}
Write-Ok 'systemd is running.'

$linuxUser = Get-WslUser $distro
if (-not $linuxUser) {
    Write-Step 'Ubuntu needs its first UNIX user'
    Write-Host 'A new Ubuntu session will open. Create your Linux username and password, then type "exit" to continue.'
    & wsl.exe -d $distro
    $linuxUser = Get-WslUser $distro
    if (-not $linuxUser) {
        Stop-Setup 'No non-root Linux user was found. Open Ubuntu, create a user, and run this command again.'
    }
}
Write-Ok "Using Linux user $linuxUser."

Write-Step 'Installing base dependencies inside Ubuntu'
$deps = 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y python3 openssh-client curl ca-certificates'
$code = Invoke-Wsl -Distro $distro -User 'root' -Command $deps
if ($code -ne 0) { Stop-Setup 'Could not install python3, openssh-client, curl or ca-certificates.' }
Write-Ok 'Base dependencies installed.'

# --- Plak ------------------------------------------------------------------

Write-Step 'Installing Plak CLI and the local stack'
$installer = 'curl -fsSL https://plak.sh/install | PLAK_YES=1 bash'
$code = Invoke-Wsl -Distro $distro -User $linuxUser -Command $installer
if ($code -ne 0) {
    Stop-Setup "Plak installation failed. Open Ubuntu with 'wsl -d $distro' and run: $installer"
}

$version = Get-WslOutput -Distro $distro -User $linuxUser -Command 'plak version'
Write-Ok $version
$status = Get-WslOutput -Distro $distro -User $linuxUser -Command 'plak status --json'
Write-Host '  plak status --json:'
Write-Host $status

Write-Host ""
Write-Host 'Plak is installed.' -ForegroundColor Green
Write-Host "Next steps (inside Ubuntu: wsl -d $distro):"
Write-Host '  plak add demo --static'
Write-Host '  plak url demo'
Write-Host '  plak trust'
Write-Host '  plak wsl-hosts    # only if *.localhost does not resolve in Windows'
Write-Host '  plak connect      # optional: connect this machine to the panel'
Write-Host ''
Write-Host 'Docker was not installed. Plak runs on Ubuntu/WSL2 with FrankenPHP and Caddy.'
exit 0
