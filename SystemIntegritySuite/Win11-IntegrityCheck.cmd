@echo off
setlocal EnableExtensions EnableDelayedExpansion

net session >nul 2>&1
if not %errorlevel%==0 (
  echo Relaunching with administrative privileges...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b 0
)

set "REPORT=%~dp0Win11_IntegrityReport_%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.log"
set "REPORT=%REPORT: =0%"
set /a SCORE=0

echo Windows 11 Integrity Check > "%REPORT%"
echo Started: %DATE% %TIME%>> "%REPORT%"
echo ------------------------------------>> "%REPORT%"

echo [1/7] Checking OS Build...
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild ^| find "CurrentBuild"') do set BUILD=%%A
if %BUILD% LSS 22000 (
  echo CRITICAL: Build %BUILD% is below Windows 11 baseline.>> "%REPORT%"
  set /a SCORE+=3
) else (
  echo PASS: Build %BUILD% detected.>> "%REPORT%"
)

echo [2/7] Running SFC verifyonly (this may take time)...
sfc /verifyonly > "%TEMP%\sfc_verify.log"
find /i "did not find any integrity violations" "%TEMP%\sfc_verify.log" >nul
if errorlevel 1 (
  find /i "found integrity violations" "%TEMP%\sfc_verify.log" >nul
  if not errorlevel 1 (
    echo FAIL: SFC found integrity violations.>> "%REPORT%"
    set /a SCORE+=2
  ) else (
    echo WARNING: Could not conclusively parse SFC output.>> "%REPORT%"
    set /a SCORE+=1
  )
) else (
  echo PASS: SFC found no integrity violations.>> "%REPORT%"
)

echo [3/7] Running DISM CheckHealth...
DISM /Online /Cleanup-Image /CheckHealth > "%TEMP%\dism_check.log"
find /i "No component store corruption detected" "%TEMP%\dism_check.log" >nul
if errorlevel 1 (
  find /i "component store is repairable" "%TEMP%\dism_check.log" >nul
  if not errorlevel 1 (
    echo FAIL: DISM reports component store corruption.>> "%REPORT%"
    set /a SCORE+=2
  ) else (
    echo WARNING: Could not conclusively parse DISM output.>> "%REPORT%"
    set /a SCORE+=1
  )
) else (
  echo PASS: DISM reports healthy component store.>> "%REPORT%"
)

echo [4/7] Checking boot configuration...
bcdedit /enum {current} >nul 2>&1
if errorlevel 1 (
  echo CRITICAL: Unable to read BCD current entry.>> "%REPORT%"
  set /a SCORE+=3
) else (
  echo PASS: BCD current entry accessible.>> "%REPORT%"
)

echo [5/7] Checking volume errors on system drive...
chkdsk %SystemDrive% /scan > "%TEMP%\chkdsk_scan.log"
find /i "Windows has scanned the file system and found no problems" "%TEMP%\chkdsk_scan.log" >nul
if errorlevel 1 (
  echo WARNING: CHKDSK reported findings; review %TEMP%\chkdsk_scan.log.>> "%REPORT%"
  set /a SCORE+=1
) else (
  echo PASS: CHKDSK scan found no file system problems.>> "%REPORT%"
)

echo [6/7] Checking servicing health via CBS log presence...
if exist "%windir%\Logs\CBS\CBS.log" (
  echo PASS: CBS log exists for servicing diagnostics.>> "%REPORT%"
) else (
  echo WARNING: CBS.log not found.>> "%REPORT%"
  set /a SCORE+=1
)

echo [7/7] Checking free space on system drive...
for /f "tokens=3" %%A in ('dir %SystemDrive% ^| find "bytes free"') do set FREE=%%A
set FREE=%FREE:,=%
if %FREE% LSS 21474836480 (
  echo FAIL: Less than 20GB free on system drive.>> "%REPORT%"
  set /a SCORE+=2
) else (
  echo PASS: Adequate free space available.>> "%REPORT%"
)

echo ------------------------------------>> "%REPORT%"
if %SCORE% GEQ 6 (
  echo OVERALL: REINSTALL OR IN-PLACE REPAIR HIGHLY RECOMMENDED>> "%REPORT%"
) else if %SCORE% GEQ 3 (
  echo OVERALL: REPAIR ACTION RECOMMENDED>> "%REPORT%"
) else (
  echo OVERALL: NO REINSTALL SIGNAL DETECTED>> "%REPORT%"
)

echo Done. Report: "%REPORT%"
type "%REPORT%"
start "Integrity Report" notepad.exe "%REPORT%"
exit /b 0
