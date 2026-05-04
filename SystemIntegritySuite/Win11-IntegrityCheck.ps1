[CmdletBinding()]
param(
    [string]$OutputPath = ".\Win11_IntegrityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    [switch]$Silent
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Test-IsAdmin { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
if(-not (Test-IsAdmin)){ $silentArg=if($Silent){'-Silent'}else{''}; Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -OutputPath `"$OutputPath`" $silentArg"; exit 0 }

$lines=New-Object System.Collections.Generic.List[string]; $score=0
function Log([string]$m){$l="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] $m";$script:lines.Add($l);if(-not $Silent){Write-Host $l}}
function Score([string]$s){switch($s){'PASS'{0};'WARNING'{1};'FAIL'{2};'CRITICAL'{3};default{1}}}
function PendingReboot{ (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -EA SilentlyContinue).PendingFileRenameOperations -ne $null) }

function Run-Checks {
    $r=@{}
    $build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    $r.OSBuild= if($build -ge 22000){'PASS'}else{'CRITICAL'}
    Log "OS Build: $build => $($r.OSBuild)"

    $sfc=cmd /c 'sfc /verifyonly'|Out-String
    $r.SFC= if($sfc -match 'did not find any integrity violations'){'PASS'}elseif($sfc -match 'found integrity violations'){'FAIL'}else{'WARNING'}
    Log "SFC Verify => $($r.SFC)"

    $dism=cmd /c 'DISM /Online /Cleanup-Image /CheckHealth'|Out-String
    $r.DISM= if($dism -match 'No component store corruption detected'){'PASS'}elseif($dism -match 'component store is repairable'){'FAIL'}else{'WARNING'}
    Log "DISM CheckHealth => $($r.DISM)"

    cmd /c 'bcdedit /enum {current}' >$null 2>&1
    $r.Boot= if($LASTEXITCODE -eq 0){'PASS'}else{'CRITICAL'}
    Log "Boot Config => $($r.Boot)"

    $chk=cmd /c "chkdsk $env:SystemDrive /scan"|Out-String
    $r.CHKDSK= if($chk -match 'found no problems'){'PASS'}else{'WARNING'}
    Log "CHKDSK => $($r.CHKDSK)"

    $r.CBS= if(Test-Path "$env:windir\Logs\CBS\CBS.log"){'PASS'}else{'WARNING'}
    Log "CBS Log => $($r.CBS)"

    $free=(Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free
    $r.FreeSpace= if($free -ge 20GB){'PASS'}else{'FAIL'}
    Log "Free Space => $($r.FreeSpace)"
    return $r
}

function Repair-Issues($res){
    Log '--- Repair phase started ---'
    if($res.DISM -in 'FAIL','WARNING'){ Log 'Running DISM RestoreHealth...'; cmd /c 'DISM /Online /Cleanup-Image /RestoreHealth'|Out-Null }
    if($res.SFC -in 'FAIL','WARNING' -or $res.DISM -in 'FAIL','WARNING'){ Log 'Running SFC Scannow...'; cmd /c 'sfc /scannow'|Out-Null }
    if($res.CHKDSK -eq 'WARNING'){ Log 'Running CHKDSK scan retry...'; cmd /c "chkdsk $env:SystemDrive /scan"|Out-Null }
    Log 'Resetting Windows Update components...'
    cmd /c 'net stop wuauserv & net stop bits & net stop cryptsvc & ren %systemroot%\SoftwareDistribution SoftwareDistribution.bak & ren %systemroot%\System32\catroot2 catroot2.bak & net start cryptsvc & net start bits & net start wuauserv' | Out-Null
}

Log 'Windows 11 Integrity Check + Auto Repair'
Log "Host: $env:COMPUTERNAME | User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
$first=Run-Checks
$firstFail=$first.Values | Where-Object {$_ -ne 'PASS'}
if($firstFail){ Repair-Issues $first; Log '--- Recheck after repair ---'; $final=Run-Checks } else { $final=$first }

if(PendingReboot){ Log 'Pending reboot detected after checks/repairs.'; if($Silent){shutdown /r /f /t 0; exit 0} }
$score=($final.Values|ForEach-Object{Score $_}|Measure-Object -Sum).Sum
$overall= if($score -ge 6){'OVERALL: REINSTALL RECOMMENDED'}elseif($score -ge 3){'OVERALL: REPAIR INSTALL RECOMMENDED'}else{'OVERALL: HEALTHY/REPAIRED'}
Log $overall
$lines|Set-Content $OutputPath -Encoding UTF8
if(-not $Silent){Get-Content $OutputPath; Start-Process notepad $OutputPath}
