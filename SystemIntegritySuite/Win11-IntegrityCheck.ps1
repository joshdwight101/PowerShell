[CmdletBinding()]
param(
    [string]$OutputPath = ".\Win11_IntegrityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    [switch]$Silent,
    [switch]$JsonReport,
    [string]$JsonReportPath = ".\Win11_IntegrityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Test-IsAdmin { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
if(-not (Test-IsAdmin)){ $silentArg=if($Silent){'-Silent'}else{''}; Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -OutputPath `"$OutputPath`" $silentArg"; exit 0 }

$lines=New-Object System.Collections.Generic.List[string]; $score=0
function Log([string]$m){$l="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] $m";$script:lines.Add($l);if(-not $Silent){Write-Host $l}}
function Step([int]$i,[int]$t,[string]$m){ Log ("[{0}/{1}] {2}" -f $i,$t,$m) }
function Score([string]$s){switch($s){'PASS'{0};'WARNING'{1};'FAIL'{2};'CRITICAL'{3};default{1}}}
function PendingReboot{ (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -EA SilentlyContinue).PendingFileRenameOperations -ne $null) }
function Get-ComputerInventory {
    $unknown='Unknown'
    try{$os=Get-CimInstance Win32_OperatingSystem}catch{$os=$null}
    try{$cs=Get-CimInstance Win32_ComputerSystem}catch{$cs=$null}
    try{$bios=Get-CimInstance Win32_BIOS}catch{$bios=$null}
    try{$cpu=Get-CimInstance Win32_Processor|Select-Object -First 1}catch{$cpu=$null}
    try{$enc=Get-CimInstance Win32_SystemEnclosure|Select-Object -First 1}catch{$enc=$null}
    try{$cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'}catch{$cv=$null}
    try{$adapters=Get-NetAdapter|Where-Object Status -eq Up}catch{$adapters=@()}
    $net=@()
    foreach($a in $adapters){
        try{$cfg=Get-NetIPConfiguration -InterfaceIndex $a.ifIndex}catch{$cfg=$null}
        $prof=$null; try{$prof=Get-NetConnectionProfile -InterfaceIndex $a.ifIndex}catch{}
        $net+=[pscustomobject]@{Name=$a.Name;InterfaceAlias=$a.InterfaceAlias;InterfaceDesc=$a.InterfaceDescription;MacAddress=$a.MacAddress;LinkSpeed=$a.LinkSpeed;Status=$a.Status;IPv4Address=@($cfg.IPv4Address.IPAddress);IPv6Address=@($cfg.IPv6Address.IPAddress);DefaultGateway=@($cfg.IPv4DefaultGateway.NextHop);DnsServers=@($cfg.DNSServer.ServerAddresses);DhcpEnabled=$cfg.NetIPv4Interface.Dhcp;DhcpServer=$null;ConnectionProfileName=$prof.Name;NetworkCategory=$prof.NetworkCategory}
    }
    try{$disks=Get-PhysicalDisk}catch{$disks=@()}
    $diskObjs=$disks|ForEach-Object{[pscustomobject]@{Model=$_.FriendlyName;SerialNumber=$_.SerialNumber;BusType=$_.BusType;MediaType=$_.MediaType;HealthStatus=$_.HealthStatus}}
    $sysDrive="$($env:SystemDrive)\"
    try{$d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" }catch{$d=$null}
    $systemDrive=[pscustomobject]@{DriveLetter=$env:SystemDrive;TotalGB=if($d){[math]::Round($d.Size/1GB,2)}else{$null};FreeGB=if($d){[math]::Round($d.FreeSpace/1GB,2)}else{$null}}
    $lastBoot=if($os){[System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)}else{$null}
    $installDate=if($os){[System.Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)}else{$null}
    $uptime=if($lastBoot){(Get-Date)-$lastBoot}else{$null}
    [pscustomobject]@{
        CollectedAt=Get-Date; HostName=$env:COMPUTERNAME; Fqdn=([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName); LoggedOnUser=([Security.Principal.WindowsIdentity]::GetCurrent().Name); DomainOrWorkgroup=if($cs){if($cs.PartOfDomain){$cs.Domain}else{$cs.Workgroup}}else{$unknown};
        Manufacturer=if($cs){$cs.Manufacturer}else{$unknown}; Model=if($cs){$cs.Model}else{$unknown}; SerialNumber=if($bios){$bios.SerialNumber}else{$unknown}; BiosVersion=if($bios){($bios.SMBIOSBIOSVersion -join ',')}else{$unknown}; BiosReleaseDate=if($bios){$bios.ReleaseDate}else{$null}; SystemSku=if($cs){$cs.SystemSKUNumber}else{$null}; ChassisType=if($enc){$enc.ChassisTypes -join ','}else{$null};
        WindowsProductName=$cv.ProductName; WindowsEdition=$cv.EditionID; WindowsVersion=if($cv.DisplayVersion){$cv.DisplayVersion}else{$cv.ReleaseId}; WindowsBuild=$cv.CurrentBuild; WindowsUBR=$cv.UBR; FullBuild="$($cv.CurrentBuild).$($cv.UBR)"; OsArchitecture=if($os){$os.OSArchitecture}else{$unknown}; InstallDate=$installDate; LastBootTime=$lastBoot; Uptime=$uptime;
        PowerShellVersion=$PSVersionTable.PSVersion.ToString(); ExecutionPolicy=(Get-ExecutionPolicy -List|Out-String).Trim();
        ProcessorName=if($cpu){$cpu.Name}else{$unknown}; PhysicalCores=if($cpu){$cpu.NumberOfCores}else{$null}; LogicalProcessors=if($cpu){$cpu.NumberOfLogicalProcessors}else{$null}; TotalMemoryGB=if($cs){[math]::Round($cs.TotalPhysicalMemory/1GB,2)}else{$null};
        NetworkAdapters=$net; Disks=$diskObjs; SystemDrive=$systemDrive; TpmStatus=(Get-Tpm -EA SilentlyContinue | Select-Object -Property TpmPresent,TpmReady,TpmEnabled -EA SilentlyContinue); SecureBootEnabled=(Confirm-SecureBootUEFI -EA SilentlyContinue); BitLockerStatus=(Get-BitLockerVolume -MountPoint $env:SystemDrive -EA SilentlyContinue | Select-Object -Property ProtectionStatus,VolumeStatus)
    }
}

function Run-Checks {
    $r=@{}
    Step 1 7 'Checking OS build baseline...'
    $build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    $r.OSBuild= if($build -ge 22000){'PASS'}else{'CRITICAL'}
    Log "RESULT [PASS/FAIL]: OS Build validation completed. Build=$build Status=$($r.OSBuild)"

    Step 2 7 'Running SFC /verifyonly (can take several minutes)...'
    $sfc=cmd /c 'sfc /verifyonly'|Out-String
    $r.SFC= if($sfc -match 'did not find any integrity violations'){'PASS'}elseif($sfc -match 'found integrity violations'){'FAIL'}else{'WARNING'}
    Log "RESULT [PASS/FAIL]: SFC verify completed. Status=$($r.SFC)"

    Step 3 7 'Running DISM /CheckHealth...'
    $dism=cmd /c 'DISM /Online /Cleanup-Image /CheckHealth'|Out-String
    $r.DISM= if($dism -match 'No component store corruption detected'){'PASS'}elseif($dism -match 'component store is repairable'){'FAIL'}else{'WARNING'}
    Log "RESULT [PASS/FAIL]: DISM CheckHealth completed. Status=$($r.DISM)"

    Step 4 7 'Checking Boot Configuration Data (BCD)...'
    cmd /c 'bcdedit /enum {current}' >$null 2>&1
    $r.Boot= if($LASTEXITCODE -eq 0){'PASS'}else{'CRITICAL'}
    Log "RESULT [PASS/FAIL]: Boot configuration check completed. Status=$($r.Boot)"

    Step 5 7 'Running CHKDSK online scan...'
    $chk=cmd /c "chkdsk $env:SystemDrive /scan"|Out-String
    $r.CHKDSK= if($chk -match 'found no problems'){'PASS'}else{'WARNING'}
    Log "RESULT [PASS/FAIL]: CHKDSK scan completed. Status=$($r.CHKDSK)"

    Step 6 7 'Checking CBS servicing log presence...'
    $r.CBS= if(Test-Path "$env:windir\Logs\CBS\CBS.log"){'PASS'}else{'WARNING'}
    Log "RESULT [PASS/FAIL]: CBS log presence check completed. Status=$($r.CBS)"

    Step 7 7 'Checking free space threshold (>=20GB)...'
    $free=(Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free
    $r.FreeSpace= if($free -ge 20GB){'PASS'}else{'FAIL'}
    Log "RESULT [PASS/FAIL]: Free space threshold check completed. Status=$($r.FreeSpace)"
    return $r
}

function Repair-Issues($res){
    Log '--- Repair phase started ---'
    if($res.DISM -in 'FAIL','WARNING'){ Step 1 4 'Repair: DISM /RestoreHealth'; cmd /c 'DISM /Online /Cleanup-Image /RestoreHealth'|Out-Null }
    if($res.SFC -in 'FAIL','WARNING' -or $res.DISM -in 'FAIL','WARNING'){ Step 2 4 'Repair: SFC /scannow'; cmd /c 'sfc /scannow'|Out-Null }
    if($res.CHKDSK -eq 'WARNING'){ Step 3 4 'Repair: CHKDSK online retry'; cmd /c "chkdsk $env:SystemDrive /scan"|Out-Null }
    Step 4 4 'Repair: Reset Windows Update components'
    cmd /c 'net stop wuauserv & net stop bits & net stop cryptsvc & ren %systemroot%\SoftwareDistribution SoftwareDistribution.bak & ren %systemroot%\System32\catroot2 catroot2.bak & net start cryptsvc & net start bits & net start wuauserv' | Out-Null
    Log '--- Repair phase completed ---'
}

Log 'Windows 11 Integrity Check + Auto Repair'
 $inventory = Get-ComputerInventory
Log 'Computer Inventory'
Log '------------------'
Log ("Host Name: {0}" -f $inventory.HostName)
Log ("Manufacturer: {0}" -f $inventory.Manufacturer)
Log ("Model: {0}" -f $inventory.Model)
Log ("Serial Number: {0}" -f $inventory.SerialNumber)
Log ("Windows: {0} {1}" -f $inventory.WindowsProductName,$inventory.WindowsVersion)
Log ("Build: {0}" -f $inventory.FullBuild)
Log ("Architecture: {0}" -f $inventory.OsArchitecture)
Log ("Last Boot: {0}" -f $inventory.LastBootTime)
Log ("Uptime: {0}" -f $inventory.Uptime)
Log ("Logged On User: {0}" -f $inventory.LoggedOnUser)
Log ("Primary IPv4: {0}" -f ($inventory.NetworkAdapters | Select-Object -First 1).IPv4Address[0])
Log ("MAC Address: {0}" -f ($inventory.NetworkAdapters | Select-Object -First 1).MacAddress)
Log ("System Drive: {0} {1} GB total / {2} GB free" -f $inventory.SystemDrive.DriveLetter,$inventory.SystemDrive.TotalGB,$inventory.SystemDrive.FreeGB)
Log "Run start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
$phaseStart=Get-Date
$first=Run-Checks
Log "Initial check phase duration: $([math]::Round(((Get-Date)-$phaseStart).TotalSeconds,1))s"
$firstFail=$first.Values | Where-Object {$_ -ne 'PASS'}
if($firstFail){
    $repairStart=Get-Date
    Repair-Issues $first
    Log "Repair phase duration: $([math]::Round(((Get-Date)-$repairStart).TotalSeconds,1))s"
    Log '--- Recheck after repair ---'
    $recheckStart=Get-Date
    $final=Run-Checks
    Log "Recheck phase duration: $([math]::Round(((Get-Date)-$recheckStart).TotalSeconds,1))s"
} else { $final=$first }

if(PendingReboot){
    Log 'Pending reboot detected after checks/repairs.'
    if($Silent){ Log 'Silent mode: rebooting immediately.'; shutdown /r /f /t 0; exit 0 }
    $choice=Read-Host 'Pending reboot exists. Reboot now? (Y/N)'
    if($choice -match '^(Y|y)$'){ Log 'User approved reboot. Rebooting now...'; shutdown /r /f /t 0; exit 0 }
    Log 'User declined reboot; report will indicate reboot pending.'
}
$score=($final.Values|ForEach-Object{Score $_}|Measure-Object -Sum).Sum
$overall= if($score -ge 6){'OVERALL: REINSTALL RECOMMENDED'}elseif($score -ge 3){'OVERALL: REPAIR INSTALL RECOMMENDED'}else{'OVERALL: HEALTHY/REPAIRED'}
Log $overall
if($overall -like '*REINSTALL*'){ Log 'SUGGESTION: Repairs did not return system to healthy state. Windows reinstall/in-place repair strongly recommended.' }
elseif($overall -like '*REPAIR INSTALL*'){ Log 'SUGGESTION: Perform in-place repair install if issues continue after reboot and update cycle.' }
else { Log 'SUGGESTION: System appears repaired/healthy; continue monitoring event logs and update health.' }
Log "Run end time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
$lines|Set-Content $OutputPath -Encoding UTF8
if(-not $Silent){Get-Content $OutputPath; Start-Process notepad $OutputPath}
if($JsonReport){
    $payload=[pscustomobject]@{GeneratedAt=Get-Date;ComputerInventory=$inventory;FinalResults=$final;Overall=$overall}
    $payload|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $JsonReportPath
    Log "JSON report saved to $JsonReportPath"
}
