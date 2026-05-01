@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SILENT=0"
if /I "%~1"=="-silent" set "SILENT=1"

net session >nul 2>&1
if not %errorlevel%==0 (
  if "%SILENT%"=="0" echo Relaunching with administrative privileges...
  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs -WindowStyle Hidden"
  exit /b 0
)

set "REPORT=%~dp0Win11_IntegrityReport_%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.log"
set "REPORT=%REPORT: =0%"
set /a SCORE=0

call :log "Windows 11 Integrity Check"
call :log "Hostname: %COMPUTERNAME%"
call :log "User: %USERDOMAIN%\%USERNAME%"
for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /c:"IPv4 Address"') do (
  set "IP=%%A"
  set "IP=!IP: =!"
  goto :gotip
)
:gotip
if not defined IP set "IP=Unavailable"
call :log "IPv4: %IP%"
call :log "------------------------------------"

call :check_pending_reboot
if "%PENDING_REBOOT%"=="1" (
  call :log "PENDING REBOOT DETECTED."
  if "%SILENT%"=="1" (
    call :log "Silent mode: restarting immediately with force flag."
    shutdown /r /f /t 0
    exit /b 0
  )
  choice /C YN /N /M "Pending reboot detected. Restart now? [Y/N]: "
  if errorlevel 2 (
    call :log "User declined immediate restart; continuing checks."
  ) else (
    call :log "User approved restart. Restarting with force flag."
    shutdown /r /f /t 0
    exit /b 0
  )
)

call :log "[1/7] Checking OS Build..."
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild ^| find "CurrentBuild"') do set BUILD=%%A
if %BUILD% LSS 22000 (
  call :result "CRITICAL: Build %BUILD% is below Windows 11 baseline." 3
) else (
  call :result "PASS: Build %BUILD% detected." 0
)

call :log "[2/7] Running SFC verifyonly..."
sfc /verifyonly > "%TEMP%\sfc_verify.log"
find /i "did not find any integrity violations" "%TEMP%\sfc_verify.log" >nul
if errorlevel 1 (
  find /i "found integrity violations" "%TEMP%\sfc_verify.log" >nul
  if not errorlevel 1 (
    call :result "FAIL: SFC found integrity violations." 2
  ) else (
    call :result "WARNING: Could not conclusively parse SFC output." 1
  )
) else (
  call :result "PASS: SFC found no integrity violations." 0
)

call :log "[3/7] Running DISM CheckHealth..."
DISM /Online /Cleanup-Image /CheckHealth > "%TEMP%\dism_check.log"
find /i "No component store corruption detected" "%TEMP%\dism_check.log" >nul
if errorlevel 1 (
  find /i "component store is repairable" "%TEMP%\dism_check.log" >nul
  if not errorlevel 1 (
    call :result "FAIL: DISM reports component store corruption." 2
  ) else (
    call :result "WARNING: Could not conclusively parse DISM output." 1
  )
) else (
  call :result "PASS: DISM reports healthy component store." 0
)

call :log "[4/7] Checking boot configuration..."
bcdedit /enum {current} >nul 2>&1
if errorlevel 1 (
  call :result "CRITICAL: Unable to read BCD current entry." 3
) else (
  call :result "PASS: BCD current entry accessible." 0
)

call :log "[5/7] Checking volume errors on system drive..."
chkdsk %SystemDrive% /scan > "%TEMP%\chkdsk_scan.log"
find /i "Windows has scanned the file system and found no problems" "%TEMP%\chkdsk_scan.log" >nul
if errorlevel 1 (
  call :result "WARNING: CHKDSK reported findings; review %TEMP%\chkdsk_scan.log." 1
) else (
  call :result "PASS: CHKDSK scan found no file system problems." 0
)

call :log "[6/7] Checking servicing health via CBS log presence..."
if exist "%windir%\Logs\CBS\CBS.log" (
  call :result "PASS: CBS log exists for servicing diagnostics." 0
) else (
  call :result "WARNING: CBS.log not found." 1
)

call :log "[7/7] Checking free space on system drive..."
for /f "tokens=3" %%A in ('dir %SystemDrive% ^| find "bytes free"') do set FREE=%%A
set FREE=%FREE:,=%
if %FREE% LSS 21474836480 (
  call :result "FAIL: Less than 20GB free on system drive." 2
) else (
  call :result "PASS: Adequate free space available." 0
)

call :log "------------------------------------"
if %SCORE% GEQ 6 (
  call :log "OVERALL: REINSTALL OR IN-PLACE REPAIR HIGHLY RECOMMENDED"
) else if %SCORE% GEQ 3 (
  call :log "OVERALL: REPAIR ACTION RECOMMENDED"
) else (
  call :log "OVERALL: NO REINSTALL SIGNAL DETECTED"
)

if "%SILENT%"=="0" (
  echo Done. Report: "%REPORT%"
  type "%REPORT%"
  start "Integrity Report" notepad.exe "%REPORT%"
)
exit /b 0

:result
set /a SCORE+=%~2
call :log "%~1"
exit /b 0

:log
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss.fff\""') do set "TS=%%T"
>> "%REPORT%" echo [!TS!] %~1
if "%SILENT%"=="0" echo [!TS!] %~1
exit /b 0


:check_pending_reboot
set "PENDING_REBOOT=0"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1 && set "PENDING_REBOOT=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1 && set "PENDING_REBOOT=1"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1 && set "PENDING_REBOOT=1"
exit /b 0
