[CmdletBinding()]
param(
    [string]$OutputPath = ".\Win11_IntegrityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    if (-not $Silent) { Write-Host "Relaunching with administrative privileges..." }
    $silentArg = if ($Silent) { '-Silent' } else { '' }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -OutputPath `"$OutputPath`" $silentArg"
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $argList | Out-Null
    exit 0
}

$score = 0
$lines = New-Object System.Collections.Generic.List[string]

function Add-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$stamp] $Message"
    $script:lines.Add($line)
    if (-not $Silent) { Write-Host $line }
}

function Add-Result {
    param([string]$Message,[int]$Points=0)
    $script:score += $Points
    Add-Log $Message
}

$hostname = $env:COMPUTERNAME
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$ips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
    Select-Object -ExpandProperty IPAddress -Unique)
if (-not $ips) { $ips = @('Unavailable') }

Add-Log 'Windows 11 Integrity Check'
Add-Log "Hostname: $hostname"
Add-Log "User: $user"
Add-Log "IPv4: $($ips -join ', ')"
Add-Log '------------------------------------'

Add-Log '[1/7] Checking OS Build...'
$build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
if ($build -lt 22000) { Add-Result "CRITICAL: Build $build is below Windows 11 baseline." 3 }
else { Add-Result "PASS: Build $build detected." }

Add-Log '[2/7] Running SFC verifyonly...'
$sfcText = cmd /c 'sfc /verifyonly' | Out-String
if ($sfcText -match 'did not find any integrity violations') { Add-Result 'PASS: SFC found no integrity violations.' }
elseif ($sfcText -match 'found integrity violations') { Add-Result 'FAIL: SFC found integrity violations.' 2 }
else { Add-Result 'WARNING: Could not conclusively parse SFC output.' 1 }

Add-Log '[3/7] Running DISM CheckHealth...'
$dismText = cmd /c 'DISM /Online /Cleanup-Image /CheckHealth' | Out-String
if ($dismText -match 'No component store corruption detected') { Add-Result 'PASS: DISM reports healthy component store.' }
elseif ($dismText -match 'component store is repairable') { Add-Result 'FAIL: DISM reports component store corruption.' 2 }
else { Add-Result 'WARNING: Could not conclusively parse DISM output.' 1 }

Add-Log '[4/7] Checking boot configuration...'
cmd /c 'bcdedit /enum {current}' > $null 2>&1
if ($LASTEXITCODE -ne 0) { Add-Result 'CRITICAL: Unable to read BCD current entry.' 3 }
else { Add-Result 'PASS: BCD current entry accessible.' }

Add-Log '[5/7] Checking volume errors on system drive...'
$chkText = cmd /c "chkdsk $env:SystemDrive /scan" | Out-String
if ($chkText -match 'found no problems') { Add-Result 'PASS: CHKDSK scan found no file system problems.' }
else { Add-Result 'WARNING: CHKDSK reported findings; review output.' 1 }

Add-Log '[6/7] Checking servicing health via CBS log presence...'
if (Test-Path "$env:windir\Logs\CBS\CBS.log") { Add-Result 'PASS: CBS log exists for servicing diagnostics.' }
else { Add-Result 'WARNING: CBS.log not found.' 1 }

Add-Log '[7/7] Checking free space on system drive...'
$free = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free
if ($free -lt 20GB) { Add-Result 'FAIL: Less than 20GB free on system drive.' 2 }
else { Add-Result 'PASS: Adequate free space available.' }

Add-Log '------------------------------------'
if ($score -ge 6) { $overall = 'OVERALL: REINSTALL OR IN-PLACE REPAIR HIGHLY RECOMMENDED' }
elseif ($score -ge 3) { $overall = 'OVERALL: REPAIR ACTION RECOMMENDED' }
else { $overall = 'OVERALL: NO REINSTALL SIGNAL DETECTED' }
Add-Log $overall

$lines | Set-Content -Path $OutputPath -Encoding UTF8
Add-Log "Report saved to $OutputPath"
$lines | Set-Content -Path $OutputPath -Encoding UTF8

if (-not $Silent) {
    Get-Content $OutputPath
    Start-Process notepad.exe $OutputPath
}
