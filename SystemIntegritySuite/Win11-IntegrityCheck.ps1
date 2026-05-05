param(
    [switch]$Silent,
    [switch]$AutoRepair,
    [switch]$NoReboot,
    [switch]$ResetWU,
    [switch]$ResetNetwork
)

$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$report = Join-Path $PSScriptRoot "Win11_IntegrityReport_$stamp.log"

function Write-Log([string]$msg){
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Add-Content -Path $report -Value $line
    if(-not $Silent){ Write-Host $line }
}

function Run-Step([string]$name,[string]$cmd){
    Write-Log "START: $name"
    Write-Log "CMD: $cmd"
    cmd /c $cmd 2>&1 | Tee-Object -FilePath $report -Append | Out-Null
    $rc = $LASTEXITCODE
    Write-Log "END: $name rc=$rc"
    return $rc
}

function Get-NetworkInventory {
    $all = Get-NetIPConfiguration | Where-Object { $_.NetAdapter }
    $usable = $all | Where-Object {
        $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address.IPAddress -and $_.IPv4Address.IPAddress -notlike '169.254*' -and $_.IPv4Address.IPAddress -ne '127.0.0.1'
    }
    $primary = $usable | Sort-Object @{Expression={if($_.IPv4DefaultGateway.NextHop){0}else{1}}},InterfaceIndex | Select-Object -First 1
    if(-not $primary){
        return [pscustomobject]@{Name='Unavailable';Alias='Unavailable';Description='Unavailable';IPv4='Unavailable';MAC='Unavailable';Gateway='Unavailable';DNS='Unavailable'}
    }
    [pscustomobject]@{
        Name=$primary.NetAdapter.Name
        Alias=$primary.NetAdapter.InterfaceAlias
        Description=$primary.NetAdapter.InterfaceDescription
        IPv4=($primary.IPv4Address|Select-Object -First 1 -ExpandProperty IPAddress)
        MAC=$primary.NetAdapter.MacAddress
        Gateway=($primary.IPv4DefaultGateway|Select-Object -First 1 -ExpandProperty NextHop)
        DNS=($primary.DNSServer.ServerAddresses -join ',')
    }
}

Write-Log "Windows 11 Integrity Check + Repair + Recheck"
Write-Log "Args: $($MyInvocation.Line)"

$osBuild = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
if($osBuild -lt 22000){ Write-Log "OS build $osBuild is not Windows 11 baseline."; exit 5 }

$net = Get-NetworkInventory
Write-Log "Network: IPv4=$($net.IPv4) MAC=$($net.MAC) Name=$($net.Name) Alias=$($net.Alias)"

$check = @{}
Run-Step 'DISM CheckHealth (pre)' 'DISM /Online /Cleanup-Image /CheckHealth' | Out-Null
Run-Step 'SFC VerifyOnly (pre)' 'sfc /verifyonly' | Out-Null
Run-Step 'CHKDSK Scan (pre)' "chkdsk $env:SystemDrive /scan" | Out-Null

$needsRepair = $AutoRepair -or $ResetWU -or $ResetNetwork
if(-not $needsRepair){
    $txt = Get-Content $report -Raw
    if($txt -match 'repairable|integrity violations'){ $needsRepair = $true }
}

if($needsRepair){
    Write-Log 'Repair phase starting.'
    Run-Step 'DISM RestoreHealth' 'DISM /Online /Cleanup-Image /RestoreHealth' | Out-Null
    Run-Step 'SFC Scannow' 'sfc /scannow' | Out-Null
    Run-Step 'CHKDSK Scan' "chkdsk $env:SystemDrive /scan" | Out-Null
    if($ResetWU){
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        Run-Step 'Stop WU services' 'net stop wuauserv & net stop bits & net stop cryptsvc' | Out-Null
        if(Test-Path "$env:windir\SoftwareDistribution"){ Rename-Item "$env:windir\SoftwareDistribution" "SoftwareDistribution.bak.$ts" -ErrorAction SilentlyContinue }
        if(Test-Path "$env:windir\System32\catroot2"){ Rename-Item "$env:windir\System32\catroot2" "catroot2.bak.$ts" -ErrorAction SilentlyContinue }
        Run-Step 'Start WU services' 'net start cryptsvc & net start bits & net start wuauserv' | Out-Null
    }
    if($ResetNetwork){ Run-Step 'Reset network' 'ipconfig /flushdns & netsh winsock reset & netsh int ip reset' | Out-Null }
}

Run-Step 'DISM CheckHealth (post)' 'DISM /Online /Cleanup-Image /CheckHealth' | Out-Null
Run-Step 'SFC VerifyOnly (post)' 'sfc /verifyonly' | Out-Null
Run-Step 'CHKDSK Scan (post)' "chkdsk $env:SystemDrive /scan" | Out-Null

$raw = Get-Content $report -Raw
if($raw -match 'repairable|integrity violations'){ Write-Log 'OVERALL: Repair install likely needed.'; $exit=2 }
elseif($raw -match 'error|failed'){ Write-Log 'OVERALL: Warnings remain.'; $exit=1 }
else { Write-Log 'OVERALL: Healthy or repaired.'; $exit=0 }

if(-not $NoReboot -and $raw -match 'reboot'){ Write-Log 'Reboot is recommended.' }
Write-Log "Report saved: $report"
exit $exit
