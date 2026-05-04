@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "SILENT=0"
if /I "%~1"=="-silent" set "SILENT=1"
net session >nul 2>&1 || (powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs" & exit /b)

set "REPORT=%~dp0Win11_IntegrityReport_%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.log"
set "REPORT=%REPORT: =0%"
call :log "Windows 11 Integrity Check + Auto Repair"
call :collect_metadata
call :log "Host: %COMPUTERNAME% | Serial: %SERIAL% | Manufacturer: %MFG% | Model: %MODEL%"
call :log "IP: %IP% | MAC: %MAC% | Windows Version: %OSVER%"
call :log "Run start time: %date% %time%"
call :run_checks first
if not "%first_SFC%"=="PASS" set NEEDREPAIR=1
if not "%first_DISM%"=="PASS" set NEEDREPAIR=1
if not "%first_CHKDSK%"=="PASS" set NEEDREPAIR=1
if defined NEEDREPAIR (
  call :repair
  call :log "--- Recheck after repair ---"
  call :run_checks final
) else (
  call :copy_first_to_final
)

call :pending_reboot
if "%PENDING_REBOOT%"=="1" (
  call :log "Pending reboot detected after checks/repairs."
  if "%SILENT%"=="1" (
    call :log "Silent mode: rebooting immediately."
    shutdown /r /f /t 0
  ) else (
    choice /C YN /N /M "Pending reboot exists. Restart now? [Y/N]: "
    if errorlevel 2 (
      call :log "User declined reboot; report will indicate reboot pending."
    ) else (
      call :log "User approved reboot. Restarting now..."
      shutdown /r /f /t 0
    )
  )
)

set /a SCORE=0
for %%S in (!final_OSBuild! !final_SFC! !final_DISM! !final_Boot! !final_CHKDSK! !final_CBS! !final_FreeSpace!) do call :score %%S
if !SCORE! GEQ 6 (call :log "OVERALL: REINSTALL RECOMMENDED") else if !SCORE! GEQ 3 (call :log "OVERALL: REPAIR INSTALL RECOMMENDED") else (call :log "OVERALL: HEALTHY/REPAIRED")
if !SCORE! GEQ 6 (call :log "SUGGESTION: Repairs did not resolve critical integrity issues. Reinstall Windows 11 is recommended.")
if !SCORE! GEQ 3 if !SCORE! LSS 6 (call :log "SUGGESTION: Consider in-place repair install if issues persist after reboot.")
if !SCORE! LSS 3 (call :log "SUGGESTION: System appears healthy/repaired. Continue monitoring.")
call :log "Run end time: %date% %time%"
if "%SILENT%"=="0" (type "%REPORT%" & start "Report" notepad "%REPORT%")
exit /b

:run_checks
set PFX=%~1
call :step 1 7 "Checking OS build baseline..."
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild ^| find "CurrentBuild"') do set BUILD=%%A
if !BUILD! GEQ 22000 (set %PFX%_OSBuild=PASS) else (set %PFX%_OSBuild=CRITICAL)
call :log "OS Build => !%PFX%_OSBuild!"
call :log "RESULT [PASS/FAIL]: OS Build validation completed. Status=!%PFX%_OSBuild!"

call :step 2 7 "Running SFC /verifyonly (can take several minutes)..."
sfc /verifyonly > "%TEMP%\sfc_v.log"
find /i "did not find any integrity violations" "%TEMP%\sfc_v.log" >nul && set %PFX%_SFC=PASS
if not defined %PFX%_SFC (find /i "found integrity violations" "%TEMP%\sfc_v.log" >nul && set %PFX%_SFC=FAIL)
if not defined %PFX%_SFC set %PFX%_SFC=WARNING
call :log "SFC Verify => !%PFX%_SFC!"
call :log "RESULT [PASS/FAIL]: SFC verify completed. Status=!%PFX%_SFC!"

call :step 3 7 "Running DISM /CheckHealth..."
DISM /Online /Cleanup-Image /CheckHealth > "%TEMP%\dism_c.log"
find /i "No component store corruption detected" "%TEMP%\dism_c.log" >nul && set %PFX%_DISM=PASS
if not defined %PFX%_DISM (find /i "component store is repairable" "%TEMP%\dism_c.log" >nul && set %PFX%_DISM=FAIL)
if not defined %PFX%_DISM set %PFX%_DISM=WARNING
call :log "DISM CheckHealth => !%PFX%_DISM!"
call :log "RESULT [PASS/FAIL]: DISM CheckHealth completed. Status=!%PFX%_DISM!"

call :step 4 7 "Checking Boot Configuration Data (BCD)..."
bcdedit /enum {current} >nul 2>&1 && set %PFX%_Boot=PASS || set %PFX%_Boot=CRITICAL
call :log "Boot Config => !%PFX%_Boot!"
call :log "RESULT [PASS/FAIL]: Boot configuration check completed. Status=!%PFX%_Boot!"

call :step 5 7 "Running CHKDSK online scan..."
chkdsk %SystemDrive% /scan > "%TEMP%\chk.log"
find /i "found no problems" "%TEMP%\chk.log" >nul && set %PFX%_CHKDSK=PASS || set %PFX%_CHKDSK=WARNING
call :log "CHKDSK => !%PFX%_CHKDSK!"
call :log "RESULT [PASS/FAIL]: CHKDSK scan completed. Status=!%PFX%_CHKDSK!"

call :step 6 7 "Checking CBS servicing log presence..."
if exist "%windir%\Logs\CBS\CBS.log" (set %PFX%_CBS=PASS) else (set %PFX%_CBS=WARNING)
call :log "CBS Log => !%PFX%_CBS!"
call :log "RESULT [PASS/FAIL]: CBS log presence check completed. Status=!%PFX%_CBS!"
call :step 7 7 "Checking free space threshold (>=20GB)..."
for /f "tokens=3" %%A in ('dir %SystemDrive% ^| find "bytes free"') do set FREE=%%A
set FREE=!FREE:,=!
if !FREE! GEQ 21474836480 (set %PFX%_FreeSpace=PASS) else (set %PFX%_FreeSpace=FAIL)
call :log "Free Space => !%PFX%_FreeSpace!"
call :log "RESULT [PASS/FAIL]: Free space threshold check completed. Status=!%PFX%_FreeSpace!"
exit /b

:repair
call :log "--- Repair phase started ---"
if not "%first_DISM%"=="PASS" (call :step 1 4 "Repair: DISM /RestoreHealth" & DISM /Online /Cleanup-Image /RestoreHealth >nul)
if not "%first_SFC%"=="PASS" (call :step 2 4 "Repair: SFC /scannow" & sfc /scannow >nul)
if not "%first_CHKDSK%"=="PASS" (call :step 3 4 "Repair: CHKDSK online retry" & chkdsk %SystemDrive% /scan >nul)
call :step 4 4 "Repair: Reset Windows Update components"
cmd /c "net stop wuauserv & net stop bits & net stop cryptsvc & ren %systemroot%\SoftwareDistribution SoftwareDistribution.bak & ren %systemroot%\System32\catroot2 catroot2.bak & net start cryptsvc & net start bits & net start wuauserv" >nul
call :log "--- Repair phase completed ---"
exit /b

:copy_first_to_final
for %%V in (OSBuild SFC DISM Boot CHKDSK CBS FreeSpace) do set final_%%V=!first_%%V!
exit /b

:pending_reboot
set PENDING_REBOOT=0
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1 && set PENDING_REBOOT=1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1 && set PENDING_REBOOT=1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1 && set PENDING_REBOOT=1
exit /b

:score
if /I "%~1"=="PASS" exit /b
if /I "%~1"=="WARNING" set /a SCORE+=1
if /I "%~1"=="FAIL" set /a SCORE+=2
if /I "%~1"=="CRITICAL" set /a SCORE+=3
exit /b

:log
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss.fff\""') do set "TS=%%T"
>> "%REPORT%" echo [!TS!] %~1
if "%SILENT%"=="0" echo [!TS!] %~1
exit /b

:step
call :log "[%~1/%~2] %~3"
exit /b

:collect_metadata
set "SERIAL=Unknown"
set "MFG=Unknown"
set "MODEL=Unknown"
set "OSVER=Unknown"
set "IP=Unknown"
set "MAC=Unknown"
where powershell >nul 2>&1 || exit /b 0
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_BIOS -EA SilentlyContinue).SerialNumber" 2^>nul`) do if not "%%A"=="" set "SERIAL=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).Manufacturer" 2^>nul`) do if not "%%A"=="" set "MFG=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).Model" 2^>nul`) do if not "%%A"=="" set "MODEL=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).Version" 2^>nul`) do if not "%%A"=="" set "OSVER=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue ^| ? {$_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1'} ^| Select-Object -First 1 -ExpandProperty IPAddress)" 2^>nul`) do if not "%%A"=="" set "IP=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-NetAdapter -EA SilentlyContinue ^| ? Status -eq 'Up' ^| Select-Object -First 1 -ExpandProperty MacAddress)" 2^>nul`) do if not "%%A"=="" set "MAC=%%A"
exit /b
