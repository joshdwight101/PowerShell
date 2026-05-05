@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SILENT=0"
if /I "%~1"=="-silent" set "SILENT=1"

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "STAMP=%%T"
set "REPORT=%~dp0Win11_IntegrityReport_%STAMP%.log"
> "%REPORT%" echo [START] %date% %time%

call :log "Windows 11 Integrity Repair (single pass)"
call :log "Phase 1: Repair"
call :run "DISM RestoreHealth" "DISM /Online /Cleanup-Image /RestoreHealth"
call :run "SFC Scannow" "sfc /scannow"
call :run "CHKDSK Scan" "chkdsk %SystemDrive% /scan"

call :log "Phase 2: Check after repairs"
call :run "DISM CheckHealth" "DISM /Online /Cleanup-Image /CheckHealth"
call :run "SFC VerifyOnly" "sfc /verifyonly"
call :run "CHKDSK Scan Recheck" "chkdsk %SystemDrive% /scan"

call :recommend
call :log "Report saved to: %REPORT%"
if "%SILENT%"=="0" start "Integrity Report" notepad "%REPORT%"
exit /b 0

:run
set "NAME=%~1"
set "CMD=%~2"
call :log "START: %NAME%"
cmd /c "%CMD%" >> "%REPORT%" 2>&1
set "RC=%ERRORLEVEL%"
call :log "END: %NAME% exit code=%RC%"
exit /b

:recommend
call :log "Recommendations:"
find /i "repairable" "%REPORT%" >nul && call :log "- Component store still repairable: consider in-place repair install."
find /i "integrity violations" "%REPORT%" >nul && call :log "- SFC still reports issues: review CBS.log and consider repair install."
find /i "found no problems" "%REPORT%" >nul || call :log "- CHKDSK did not clearly report healthy volume: run offline chkdsk /f if needed."
call :log "- If issues persist after reboot, run Win11-IntegrityCheck.ps1 for full guided workflow."
exit /b

:log
>> "%REPORT%" echo [%date% %time%] %~1
if "%SILENT%"=="0" echo [%date% %time%] %~1
exit /b
