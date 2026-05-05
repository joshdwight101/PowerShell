@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SILENT=0"
set "FORCE=0"
set "DEEP=0"
set "NOREBOOT=0"
set "RESET_WU=0"
set "RESET_NETWORK=0"
set "SKIP_WU_RESET=0"
set "DEBUG_NETWORK=0"

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="-silent" set "SILENT=1"
if /I "%~1"=="-force" set "FORCE=1"
if /I "%~1"=="-deep" set "DEEP=1"
if /I "%~1"=="-no-reboot" set "NOREBOOT=1"
if /I "%~1"=="-reset-wu" set "RESET_WU=1"
if /I "%~1"=="-reset-network" set "RESET_NETWORK=1"
if /I "%~1"=="-skip-wu-reset" set "SKIP_WU_RESET=1"
if /I "%~1"=="-debug-network" set "DEBUG_NETWORK=1"
if /I "%~1"=="-help" goto help
shift
goto parse

:help
echo Usage: %~n0 [-silent] [-force] [-deep] [-no-reboot] [-reset-wu] [-reset-network] [-skip-wu-reset] [-debug-network] [-help]
exit /b 0

:parsed
net session >nul 2>&1 || (powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs" & exit /b 0)
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "STAMP=%%T"
set "REPORT=%~dp0Win11_IntegrityReport_%STAMP%.log"
> "%REPORT%" echo. 2>nul
if errorlevel 1 set "REPORT=%TEMP%\Win11_IntegrityReport_%STAMP%.log"

call :log "Windows 11 Integrity Check + Repair + Recheck"
call :log "Arguments: %*"
call :collect_inventory
call :pending_reboot PRE_REBOOT
if "%PRE_REBOOT%"=="1" call :log "Pending reboot detected BEFORE checks."

call :run_checks first
call :determine_need_repair first NEEDREPAIR
if /I "%first_FREESPACE%"=="FAIL" (
  call :log "Free space is below 10 GB. Heavy repairs may fail."
  if "%FORCE%"=="0" (
    if "%SILENT%"=="1" (call :log "Silent mode without -force: skipping heavy repair." & set "NEEDREPAIR=0") else (
      call :prompt_low_space_continue
      if errorlevel 2 set "NEEDREPAIR=0"
    )
  )
)

if "%NEEDREPAIR%"=="1" (
  call :repair first
  call :log "--- Recheck after repair ---"
  call :run_checks final
) else (
  call :copy_results first final
)

call :pending_reboot POST_REBOOT
if "%POST_REBOOT%"=="1" call :log "Pending reboot detected AFTER checks/repairs."

if "%RESET_WU%"=="1" call :reset_wu
if "%RESET_NETWORK%"=="1" call :reset_network

call :score_results final
call :final_verdict
if "%POST_REBOOT%"=="1" call :prompt_low_space_continue
setlocal
set "PROMPTMSG=Low free space under 10GB. Continue heavy repairs? [Y/N]: "
choice /C YN /N /M "%PROMPTMSG%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

:handle_reboot_prompt

call :log "Report saved to: %REPORT%"
if "%SILENT%"=="0" (type "%REPORT%" & start "Integrity Report" notepad "%REPORT%")
exit /b 0

:collect_inventory
set "HOST=%COMPUTERNAME%"
set "SERIAL=Unknown"
set "MFG=Unknown"
set "MODEL=Unknown"
set "OSVER=Unknown"
set "PRODUCT=Unknown"
set "EDITION=Unknown"
set "BUILD=Unknown"
set "UBR=Unknown"
set "FULLBUILD=Unknown"
set "USERCTX=%USERDOMAIN%\%USERNAME%"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_BIOS -EA SilentlyContinue).SerialNumber"`) do if not "%%A"=="" set "SERIAL=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).Manufacturer"`) do if not "%%A"=="" set "MFG=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).Model"`) do if not "%%A"=="" set "MODEL=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).Version"`) do if not "%%A"=="" set "OSVER=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue).ProductName"`) do if not "%%A"=="" set "PRODUCT=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue).EditionID"`) do if not "%%A"=="" set "EDITION=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue).CurrentBuild"`) do if not "%%A"=="" set "BUILD=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue).UBR"`) do if not "%%A"=="" set "UBR=%%A"
set "FULLBUILD=%BUILD%.%UBR%"

call :collect_network_inventory

call :log "Computer Inventory"
call :log "------------------"
call :log "Host Name: %HOST%"
call :log "Manufacturer: %MFG%"
call :log "Model: %MODEL%"
call :log "Serial Number: %SERIAL%"
call :log "Windows: %PRODUCT% (%EDITION%)"
call :log "Build: %FULLBUILD%"
call :log "OS Version: %OSVER%"
call :log "Logged On User: %USERCTX%"
call :log "Primary IPv4: %IPV4%"
call :log "MAC Address: %MAC%"
exit /b

:: Robust network inventory using single PowerShell invocation with line-based key output.
:collect_network_inventory
set "IPV4=Unavailable"
set "MAC=Unavailable"
set "NET_NAME=Unknown"
set "NET_ALIAS=Unknown"
set "NET_DESC=Unknown"
set "NET_INDEX=Unknown"
set "IPV6=Unavailable"
set "GATEWAY=Unavailable"
set "DNS_SERVERS=Unavailable"
set "DHCP_STATUS=Unknown"
set "NETWORK_CATEGORY=Unknown"
set "LINK_SPEED=Unknown"

set "PSNETOUT=%TEMP%\net_inventory_%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue';$all=Get-NetIPConfiguration|?{$_.NetAdapter};$usable=$all|?{$_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address.IPAddress -and $_.IPv4Address.IPAddress -notlike '169.254*' -and $_.IPv4Address.IPAddress -ne '127.0.0.1'};$ranked=$usable|Sort-Object @{Expression={if($_.IPv4DefaultGateway.NextHop){0}else{1}}},@{Expression={if($_.NetAdapter.InterfaceDescription -match 'Hyper-V|Virtual|VMware|VirtualBox|VPN|TAP|TUN|Bluetooth|Wi-Fi Direct|Loopback|Teredo'){1}else{0}}},InterfaceIndex;$p=$ranked|Select-Object -First 1;if(-not $p){$f=Get-CimInstance Win32_NetworkAdapterConfiguration|?{$_.IPEnabled -eq $true -and $_.IPAddress -and $_.MACAddress}|Select-Object -First 1;if($f){$ipv4=($f.IPAddress|?{$_ -match '^\d+\.' -and $_ -notlike '169.254*'}|select -first 1);if(-not $ipv4){$ipv4='Unavailable'};"PRIMARY|$($f.Description)|$($f.Description)|$($f.Description)|$($f.InterfaceIndex)|$($f.MACAddress)|$ipv4|Unavailable|$($f.DefaultIPGateway -join ',')|$($f.DNSServerSearchOrder -join ',')|Unknown|Unknown|Unknown"}else{"PRIMARY|Unknown|Unknown|Unknown|Unknown|Unavailable|Unavailable|Unavailable|Unavailable|Unavailable|Unknown|Unknown|Unknown"}} else {$a=$p.NetAdapter;$ipv4=($p.IPv4Address|?{$_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1'}|select -first 1 -ExpandProperty IPAddress);$ipv6=($p.IPv6Address|select -first 1 -ExpandProperty IPAddress);$gw=($p.IPv4DefaultGateway|select -first 1 -ExpandProperty NextHop);$dns=($p.DNSServer.ServerAddresses -join ',');$profile=Get-NetConnectionProfile -InterfaceIndex $a.InterfaceIndex;$dhcp=(Get-NetIPInterface -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4).Dhcp;"PRIMARY|$($a.Name)|$($a.InterfaceAlias)|$($a.InterfaceDescription)|$($a.InterfaceIndex)|$($a.MacAddress)|$ipv4|$ipv6|$gw|$dns|$dhcp|$($profile.NetworkCategory)|$($a.LinkSpeed)"};$i=0;$all|%{$i++;$a=$_.NetAdapter;if($a){$ipv4s=($_.IPv4Address|select -ExpandProperty IPAddress)-join ',';$ipv6s=($_.IPv6Address|select -ExpandProperty IPAddress)-join ',';$gw=($_.IPv4DefaultGateway|select -ExpandProperty NextHop)-join ',';"ADAPTER|$i|$($a.Name)|$($a.InterfaceAlias)|$($a.InterfaceDescription)|$($a.InterfaceIndex)|$($a.Status)|$($a.MacAddress)|$ipv4s|$ipv6s|$gw|$($a.LinkSpeed)"}}" > "%PSNETOUT%" 2>nul

if "%DEBUG_NETWORK%"=="1" (
  call :log "[DEBUG-NETWORK] Raw network output:"
  for /f "usebackq delims=" %%L in ("%PSNETOUT%") do call :log "[DEBUG-NETWORK] %%L"
)

for /f "usebackq tokens=1-13 delims=|" %%A in ("%PSNETOUT%") do (
  if /I "%%A"=="PRIMARY" (
    set "NET_NAME=%%B"
    set "NET_ALIAS=%%C"
    set "NET_DESC=%%D"
    set "NET_INDEX=%%E"
    set "MAC=%%F"
    set "IPV4=%%G"
    set "IPV6=%%H"
    set "GATEWAY=%%I"
    set "DNS_SERVERS=%%J"
    set "DHCP_STATUS=%%K"
    set "NETWORK_CATEGORY=%%L"
    set "LINK_SPEED=%%M"
  )
  if /I "%%A"=="ADAPTER" call :log "Adapter %%B: Name=%%C Alias=%%D Status=%%G MAC=%%H IPv4=%%I GW=%%K"
)
if "%IPV4%"=="" set "IPV4=Unavailable"
if "%MAC%"=="" set "MAC=Unavailable"

call :log "Network Inventory"
call :log "-----------------"
call :log "Primary Adapter: %NET_NAME%"
call :log "Interface Alias: %NET_ALIAS%"
call :log "Description: %NET_DESC%"
call :log "Interface Index: %NET_INDEX%"
call :log "MAC Address: %MAC%"
call :log "IPv4 Address: %IPV4%"
call :log "IPv6 Address: %IPV6%"
call :log "Default Gateway: %GATEWAY%"
call :log "DNS Servers: %DNS_SERVERS%"
call :log "DHCP: %DHCP_STATUS%"
call :log "Network Category: %NETWORK_CATEGORY%"
call :log "Link Speed: %LINK_SPEED%"
if exist "%PSNETOUT%" del /q "%PSNETOUT%" >nul 2>&1
exit /b

:run_checks
set "PFX=%~1"
call :reset_results %PFX%
call :step 1 7 "Checking OS build baseline"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild ^| find "CurrentBuild"') do set "CURBUILD=%%A"
if not defined CURBUILD set "CURBUILD=0"
if %CURBUILD% GEQ 22000 (set "%PFX%_OSBuild=PASS") else (set "%PFX%_OSBuild=CRITICAL")
call :log "RESULT [PASS/FAIL]: OS Build Status=!%PFX%_OSBuild!"
call :step 2 7 "Running SFC /verifyonly"
call :run_long "SFC /verifyonly" "sfc /verifyonly" "%TEMP%\integrity_sfc_%PFX%.log"
type "%TEMP%\integrity_sfc_%PFX%.log" >> "%REPORT%"
find /i "did not find any integrity violations" "%TEMP%\integrity_sfc_%PFX%.log" >nul && set "%PFX%_SFC=PASS"
if not defined %PFX%_SFC (find /i "found integrity violations" "%TEMP%\integrity_sfc_%PFX%.log" >nul && set "%PFX%_SFC=FAIL")
if not defined %PFX%_SFC set "%PFX%_SFC=WARNING"
call :log "RESULT [PASS/FAIL]: SFC Verify Status=!%PFX%_SFC!"
call :step 3 7 "Running DISM /CheckHealth"
call :run_long "DISM /CheckHealth" "DISM /Online /Cleanup-Image /CheckHealth" "%TEMP%\integrity_dism_%PFX%.log"
type "%TEMP%\integrity_dism_%PFX%.log" >> "%REPORT%"
find /i "No component store corruption detected" "%TEMP%\integrity_dism_%PFX%.log" >nul && set "%PFX%_DISM=PASS"
if not defined %PFX%_DISM (find /i "component store is repairable" "%TEMP%\integrity_dism_%PFX%.log" >nul && set "%PFX%_DISM=FAIL")
if not defined %PFX%_DISM set "%PFX%_DISM=WARNING"
call :log "RESULT [PASS/FAIL]: DISM CheckHealth Status=!%PFX%_DISM!"
call :step 4 7 "Checking boot configuration"
bcdedit /enum {current} > "%TEMP%\integrity_bcd_%PFX%.log" 2>&1
type "%TEMP%\integrity_bcd_%PFX%.log" >> "%REPORT%"
if errorlevel 1 (set "%PFX%_BOOT=CRITICAL") else (set "%PFX%_BOOT=PASS")
call :log "RESULT [PASS/FAIL]: Boot Config Status=!%PFX%_BOOT!"
call :step 5 7 "Running CHKDSK scan"
call :run_long "CHKDSK /scan" "chkdsk %SystemDrive% /scan" "%TEMP%\integrity_chkdsk_%PFX%.log"
type "%TEMP%\integrity_chkdsk_%PFX%.log" >> "%REPORT%"
find /i "found no problems" "%TEMP%\integrity_chkdsk_%PFX%.log" >nul && set "%PFX%_CHKDSK=PASS"
if not defined %PFX%_CHKDSK set "%PFX%_CHKDSK=WARNING"
call :log "RESULT [PASS/FAIL]: CHKDSK Status=!%PFX%_CHKDSK!"
call :step 6 7 "Checking CBS log presence"
if exist "%windir%\Logs\CBS\CBS.log" (set "%PFX%_CBS=PASS") else (set "%PFX%_CBS=WARNING")
call :log "RESULT [PASS/FAIL]: CBS Log Status=!%PFX%_CBS!"
call :step 7 7 "Checking system drive free space"
call :check_free_space %PFX%
exit /b

:check_free_space
set "PFX=%~1"
set "%PFX%_FREESPACE=WARNING"
set "SYSTEM_DRIVE_CHECKED=%SystemDrive%"
set "SYSTEM_DRIVE_TOTAL_GB=Unknown"
set "SYSTEM_DRIVE_FREE_GB=Unknown"
set "SYSTEM_DRIVE_FREE_PCT=Unknown"
set "SYSTEM_DRIVE_FREE_BYTES=Unknown"
for /f "usebackq tokens=1-6 delims=|" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$drive=$env:SystemDrive; try{$disk=Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='$env:SystemDrive'\" -EA Stop; $tb=[int64]$disk.Size; $fb=[int64]$disk.FreeSpace; $tg=[math]::Round($tb/1GB,2); $fg=[math]::Round($fb/1GB,2); $fp=if($tb -gt 0){[math]::Round(($fb/$tb)*100,2)}else{0}; $st=if($fb -ge 20GB){'PASS'}elseif($fb -ge 10GB){'WARNING'}else{'FAIL'}; \"$st|$drive|$tg|$fg|$fp|$fb\" }catch{ \"WARNING|$drive|Unknown|Unknown|Unknown|Unknown\" }"`) do (
  set "%PFX%_FREESPACE=%%A"
  set "SYSTEM_DRIVE_CHECKED=%%B"
  set "SYSTEM_DRIVE_TOTAL_GB=%%C"
  set "SYSTEM_DRIVE_FREE_GB=%%D"
  set "SYSTEM_DRIVE_FREE_PCT=%%E"
  set "SYSTEM_DRIVE_FREE_BYTES=%%F"
)
call :log "System Drive Free Space Check"
call :log "Drive: %SYSTEM_DRIVE_CHECKED%"
call :log "Total: %SYSTEM_DRIVE_TOTAL_GB% GB"
call :log "Free: %SYSTEM_DRIVE_FREE_GB% GB"
call :log "Free Percent: %SYSTEM_DRIVE_FREE_PCT%%"
call :log "Raw Free Bytes: %SYSTEM_DRIVE_FREE_BYTES%"
call :log "Thresholds: PASS>=20GB, WARNING>=10GB and <20GB, FAIL<10GB"
call :log "RESULT [PASS/FAIL]: Free Space Status=!%PFX%_FREESPACE!"
exit /b

:determine_need_repair
set "PFX=%~1"
set "RET=%~2"
set "%RET%=0"
for %%V in (SFC DISM CHKDSK BOOT) do if /I not "!%PFX%_%%V!"=="PASS" set "%RET%=1"
if "%RESET_WU%"=="1" set "%RET%=1"
exit /b

:repair
set "PFX=%~1"
call :log "--- Repair phase started ---"
if /I not "!%PFX%_DISM!"=="PASS" (
  call :step 1 5 "Repair: DISM /RestoreHealth"
  call :run_long "DISM /RestoreHealth" "DISM /Online /Cleanup-Image /RestoreHealth" "%TEMP%\integrity_dism_restore.log"
  type "%TEMP%\integrity_dism_restore.log" >> "%REPORT%"
)
if /I not "!%PFX%_SFC!"=="PASS" (
  call :step 2 5 "Repair: SFC /scannow"
  call :run_long "SFC /scannow" "sfc /scannow" "%TEMP%\integrity_sfc_scannow.log"
  type "%TEMP%\integrity_sfc_scannow.log" >> "%REPORT%"
)
if /I not "!%PFX%_CHKDSK!"=="PASS" (
  call :step 3 5 "Repair: CHKDSK re-scan"
  call :run_long "CHKDSK repair /scan" "chkdsk %SystemDrive% /scan" "%TEMP%\integrity_chkdsk_repair.log"
  type "%TEMP%\integrity_chkdsk_repair.log" >> "%REPORT%"
)
if "%SKIP_WU_RESET%"=="0" if /I not "!%PFX%_DISM!"=="PASS" (call :step 4 5 "Repair: Conditional Windows Update reset" & call :reset_wu)
if "%RESET_NETWORK%"=="1" (call :step 5 5 "Repair: Reset network stack" & call :reset_network)
call :log "--- Repair phase completed ---"
exit /b

:reset_wu
call :log "Windows Update reset starting..."
if exist "%systemroot%\SoftwareDistribution.bak" ren "%systemroot%\SoftwareDistribution.bak" "SoftwareDistribution.bak.old.%RANDOM%" >nul 2>&1
if exist "%systemroot%\System32\catroot2.bak" ren "%systemroot%\System32\catroot2.bak" "catroot2.bak.old.%RANDOM%" >nul 2>&1
net stop wuauserv >> "%REPORT%" 2>&1
net stop bits >> "%REPORT%" 2>&1
net stop cryptsvc >> "%REPORT%" 2>&1
if exist "%systemroot%\SoftwareDistribution" ren "%systemroot%\SoftwareDistribution" "SoftwareDistribution.bak" >> "%REPORT%" 2>&1
if exist "%systemroot%\System32\catroot2" ren "%systemroot%\System32\catroot2" "catroot2.bak" >> "%REPORT%" 2>&1
net start cryptsvc >> "%REPORT%" 2>&1
net start bits >> "%REPORT%" 2>&1
net start wuauserv >> "%REPORT%" 2>&1
call :log "Windows Update reset completed."
exit /b

:reset_network
call :log "Resetting network stack..."
ipconfig /flushdns >> "%REPORT%" 2>&1
netsh winsock reset >> "%REPORT%" 2>&1
netsh int ip reset >> "%REPORT%" 2>&1
call :log "Network reset commands completed."
exit /b

:pending_reboot
set "%~1=0"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1 && set "%~1=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1 && set "%~1=1"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1 && set "%~1=1"
exit /b

:handle_reboot_prompt
if "%NOREBOOT%"=="1" (call :log "Reboot skipped due to -no-reboot option." & exit /b)
if "%SILENT%"=="1" if "%FORCE%"=="1" (call :log "Silent+force mode: rebooting now" & shutdown /r /f /t 0 & exit /b)
if "%SILENT%"=="1" (call :log "Silent mode: reboot required but skipped without -force." & exit /b)
choice /C YN /N /M "Pending reboot detected. Reboot now? [Y/N]: "
if errorlevel 2 (call :log "User declined reboot.") else (call :log "User approved reboot." & shutdown /r /f /t 0)
exit /b

:score_results
set "PFX=%~1"
set /a SCORE=0
for %%V in (OSBuild SFC DISM BOOT CHKDSK CBS FREESPACE) do call :score_one !%PFX%_%%V!
exit /b

:score_one
if /I "%~1"=="PASS" exit /b
if /I "%~1"=="WARNING" set /a SCORE+=1
if /I "%~1"=="FAIL" set /a SCORE+=2
if /I "%~1"=="CRITICAL" set /a SCORE+=3
exit /b

:final_verdict
if /I "%final_FREESPACE%"=="FAIL" call :log "NOTICE: Free space is low. This does not prove corruption but can break DISM/SFC/WU repairs."
if /I "%final_FREESPACE%"=="WARNING" call :log "NOTICE: Free space is between 10GB and 20GB. Free additional space before deep repairs."
if %SCORE% GEQ 6 (
  call :log "OVERALL: REINSTALL RECOMMENDED"
) else if %SCORE% GEQ 3 (
  call :log "OVERALL: REPAIR INSTALL RECOMMENDED"
) else (
  call :log "OVERALL: HEALTHY / REPAIRED"
)
exit /b

:copy_results
for %%V in (OSBuild SFC DISM BOOT CHKDSK CBS FREESPACE) do set "%~2_%%V=!%~1_%%V!"
exit /b

:reset_results
for %%V in (OSBuild SFC DISM BOOT CHKDSK CBS FREESPACE) do set "%~1_%%V="
exit /b

:run_long
setlocal
set "TASKNAME=%~1"
set "COMMAND=%~2"
set "OUTFILE=%~3"
if exist "%OUTFILE%" del /q "%OUTFILE%" >nul 2>&1
call :log "START: %TASKNAME% (this can take a while; please wait)"
if "%SILENT%"=="0" echo [INFO] %TASKNAME% is running...
cmd /c "%COMMAND%" > "%OUTFILE%" 2>&1
set "RC=%ERRORLEVEL%"
call :log "END: %TASKNAME% exit code=%RC%"
endlocal & set "RUN_LONG_RC=%RC%"
exit /b

:step
call :log "[%~1/%~2] %~3"
exit /b

:log
set "TS=%date% %time%"
>> "%REPORT%" echo [!TS!] %~1
if "%SILENT%"=="0" echo [!TS!] %~1
exit /b
