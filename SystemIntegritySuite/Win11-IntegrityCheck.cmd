@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =========================
:: Win11-IntegrityCheck.cmd
:: =========================

:: ----- Argument parsing -----
set "SILENT=0"
set "FORCE=0"
set "DEEP=0"
set "NOREBOOT=0"
set "RESET_WU=0"
set "RESET_NETWORK=0"
set "SKIP_WU_RESET=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="-silent" set "SILENT=1"
if /I "%~1"=="-force" set "FORCE=1"
if /I "%~1"=="-deep" set "DEEP=1"
if /I "%~1"=="-no-reboot" set "NOREBOOT=1"
if /I "%~1"=="-reset-wu" set "RESET_WU=1"
if /I "%~1"=="-reset-network" set "RESET_NETWORK=1"
if /I "%~1"=="-skip-wu-reset" set "SKIP_WU_RESET=1"
if /I "%~1"=="-help" goto show_help
shift
goto parse_args

:show_help
echo Usage: Win11-IntegrityCheck.cmd [-silent] [-force] [-deep] [-no-reboot] [-reset-wu] [-reset-network] [-skip-wu-reset] [-help]
exit /b 0

:args_done

:: ----- Admin elevation -----
net session >nul 2>&1
if errorlevel 1 (
  if "%SILENT%"=="0" echo Elevating to Administrator...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
  exit /b 0
)

:: ----- Locale-safe report filename -----
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "STAMP=%%T"
if not defined STAMP set "STAMP=%RANDOM%"
set "REPORT=%~dp0Win11_IntegrityReport_%STAMP%.log"
set "REPORT=%REPORT: =0%"

:: ----- globals -----
set /a SCORE=0
set /a REPAIR_ATTEMPTED=0
set "PENDING_REBOOT_PRE=0"
set "PENDING_REBOOT_POST=0"

call :log "Windows 11 Integrity Check + Repair + Recheck"
call :log "Arguments: %*"
call :collect_inventory
call :pending_reboot PENDING_REBOOT_PRE
if "%PENDING_REBOOT_PRE%"=="1" call :log "Pending reboot detected BEFORE checks."

call :run_checks first
call :determine_need_repair first NEEDREPAIR

if "%NEEDREPAIR%"=="1" (
  set /a REPAIR_ATTEMPTED=1
  call :repair first
  call :log "--- Recheck after repair ---"
  call :run_checks final
) else (
  call :copy_results first final
)

call :pending_reboot PENDING_REBOOT_POST
if "%PENDING_REBOOT_POST%"=="1" call :log "Pending reboot detected AFTER checks/repairs."

if "%RESET_WU%"=="1" call :reset_wu
if "%RESET_NETWORK%"=="1" call :reset_network

call :score_results final
call :final_verdict

if "%PENDING_REBOOT_POST%"=="1" call :handle_reboot_prompt

call :log "Report saved to: %REPORT%"
if "%SILENT%"=="0" (
  echo.
  type "%REPORT%"
  start "Integrity Report" notepad.exe "%REPORT%"
)
exit /b 0

:: =========================
:: functions
:: =========================

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
set "IPV4=Unknown"
set "MAC=Unknown"
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
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue ^| ? {$_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1'} ^| select -First 1 -ExpandProperty IPAddress)"`) do if not "%%A"=="" set "IPV4=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-NetAdapter -EA SilentlyContinue ^| ? Status -eq 'Up' ^| select -First 1 -ExpandProperty MacAddress)"`) do if not "%%A"=="" set "MAC=%%A"

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

:run_checks
set "PFX=%~1"
call :reset_results %PFX%

call :step 1 7 "Checking OS build baseline"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild ^| find "CurrentBuild"') do set "CURBUILD=%%A"
if not defined CURBUILD set "CURBUILD=0"
if %CURBUILD% GEQ 22000 (set "%PFX%_OSBuild=PASS") else (set "%PFX%_OSBuild=CRITICAL")
call :log "RESULT [PASS/FAIL]: OS Build Status=!%PFX%_OSBuild! (Build=%CURBUILD%)"

call :step 2 7 "Running SFC /verifyonly"
sfc /verifyonly > "%TEMP%\integrity_sfc_%PFX%.log" 2>&1
type "%TEMP%\integrity_sfc_%PFX%.log" >> "%REPORT%"
find /i "did not find any integrity violations" "%TEMP%\integrity_sfc_%PFX%.log" >nul && set "%PFX%_SFC=PASS"
if not defined %PFX%_SFC (find /i "found integrity violations" "%TEMP%\integrity_sfc_%PFX%.log" >nul && set "%PFX%_SFC=FAIL")
if not defined %PFX%_SFC set "%PFX%_SFC=WARNING"
call :log "RESULT [PASS/FAIL]: SFC Verify Status=!%PFX%_SFC!"

call :step 3 7 "Running DISM /CheckHealth"
DISM /Online /Cleanup-Image /CheckHealth > "%TEMP%\integrity_dism_%PFX%.log" 2>&1
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
chkdsk %SystemDrive% /scan > "%TEMP%\integrity_chkdsk_%PFX%.log" 2>&1
type "%TEMP%\integrity_chkdsk_%PFX%.log" >> "%REPORT%"
find /i "found no problems" "%TEMP%\integrity_chkdsk_%PFX%.log" >nul && set "%PFX%_CHKDSK=PASS"
if not defined %PFX%_CHKDSK set "%PFX%_CHKDSK=WARNING"
call :log "RESULT [PASS/FAIL]: CHKDSK Status=!%PFX%_CHKDSK!"

call :step 6 7 "Checking CBS log presence"
if exist "%windir%\Logs\CBS\CBS.log" (set "%PFX%_CBS=PASS") else (set "%PFX%_CBS=WARNING")
call :log "RESULT [PASS/FAIL]: CBS Log Status=!%PFX%_CBS!"

call :step 7 7 "Checking system drive free space"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "[int64](Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='%SystemDrive%'\").FreeSpace"`) do set "FREESPACE=%%A"
if not defined FREESPACE set "FREESPACE=0"
if %FREESPACE% GEQ 21474836480 (set "%PFX%_FREESPACE=PASS") else (set "%PFX%_FREESPACE=FAIL")
call :log "RESULT [PASS/FAIL]: Free Space Status=!%PFX%_FREESPACE!"
exit /b

:determine_need_repair
set "PFX=%~1"
set "RET=%~2"
set "%RET%=0"
for %%V in (SFC DISM CHKDSK BOOT FREESPACE) do (
  if /I not "!%PFX%_%%V!"=="PASS" set "%RET%=1"
)
if "%RESET_WU%"=="1" set "%RET%=1"
exit /b

:repair
set "PFX=%~1"
call :log "--- Repair phase started ---"
if /I not "!%PFX%_DISM!"=="PASS" (
  call :step 1 5 "Repair: DISM /RestoreHealth"
  DISM /Online /Cleanup-Image /RestoreHealth >> "%REPORT%" 2>&1
)
if /I not "!%PFX%_SFC!"=="PASS" (
  call :step 2 5 "Repair: SFC /scannow"
  sfc /scannow >> "%REPORT%" 2>&1
)
if /I not "!%PFX%_CHKDSK!"=="PASS" (
  call :step 3 5 "Repair: CHKDSK re-scan"
  chkdsk %SystemDrive% /scan >> "%REPORT%" 2>&1
)
if "%SKIP_WU_RESET%"=="0" (
  if /I not "!%PFX%_DISM!"=="PASS" (
    call :step 4 5 "Repair: Conditional Windows Update component reset"
    call :reset_wu
  )
)
if "%RESET_NETWORK%"=="1" (
  call :step 5 5 "Repair: Reset network stack"
  call :reset_network
)
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
call :log "Network reset commands completed. Reboot may be required."
exit /b

:pending_reboot
set "%~1=0"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1 && set "%~1=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1 && set "%~1=1"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1 && set "%~1=1"
exit /b

:handle_reboot_prompt
if "%NOREBOOT%"=="1" (
  call :log "Reboot skipped due to -no-reboot option."
  exit /b
)
if "%SILENT%"=="1" if "%FORCE%"=="1" (
  call :log "Silent+force mode: rebooting immediately..."
  shutdown /r /f /t 0
  exit /b
)
if "%SILENT%"=="1" (
  call :log "Silent mode: reboot required but no reboot triggered without -force."
  exit /b
)
choice /C YN /N /M "Pending reboot detected. Reboot now? [Y/N]: "
if errorlevel 2 (
  call :log "User declined reboot."
) else (
  call :log "User approved reboot. Restarting..."
  shutdown /r /f /t 0
)
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
if %SCORE% GEQ 6 (
  call :log "OVERALL: REINSTALL RECOMMENDED"
  call :log "SUGGESTION: Repairs did not resolve critical integrity issues; reinstall or repair-install Windows 11."
) else if %SCORE% GEQ 3 (
  call :log "OVERALL: REPAIR INSTALL RECOMMENDED"
  call :log "SUGGESTION: Run in-place repair install if issues persist after reboot."
) else (
  call :log "OVERALL: HEALTHY / REPAIRED"
  call :log "SUGGESTION: Continue monitoring event logs and updates."
)
exit /b

:copy_results
for %%V in (OSBuild SFC DISM BOOT CHKDSK CBS FREESPACE) do set "%~2_%%V=!%~1_%%V!"
exit /b

:reset_results
for %%V in (OSBuild SFC DISM BOOT CHKDSK CBS FREESPACE) do set "%~1_%%V="
exit /b

:step
call :log "[%~1/%~2] %~3"
exit /b

:log
set "TS=%date% %time%"
>> "%REPORT%" echo [!TS!] %~1
if "%SILENT%"=="0" echo [!TS!] %~1
exit /b
