# Windows 11 Integrity Suite

## What is `IntegrityCheckGui.cs`?
`IntegrityCheckGui.cs` is an **optional C# WinForms GUI** example that runs integrity checks and streams status live in a window.
It is separate from the scripts.

## Independent script usage
Both scripts are standalone and perform the same 7 checks.

### Interactive mode (default)
- Writes report
- Prints progress to console
- Opens report in Notepad at end

#### PowerShell
```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-IntegrityCheck.ps1
```

#### CMD
```cmd
Win11-IntegrityCheck.cmd
```

### Silent mode (`-silent`)
- Writes report only
- No console output and no Notepad pop-up
- Useful for scheduled/background runs

#### PowerShell
```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-IntegrityCheck.ps1 -Silent
```

#### CMD
```cmd
Win11-IntegrityCheck.cmd -silent
```

## Logged metadata
At startup each report includes:
- Hostname
- User account running the script
- IPv4 address
- Timestamped line-by-line logging for each check

## Optional GUI usage
If you want to run the C# GUI as a .NET 8 single-file app:
1. Create a WinForms project.
2. Replace `Program.cs` with `IntegrityCheckGui.cs` content.
3. Build and run on Windows.


## Build portable standalone EXE (GUI)
From `SystemIntegritySuite` folder on Windows with .NET 8 SDK installed:

```powershell
dotnet publish .\IntegrityCheckGui.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true
```

Output EXE:
`bin\Release\net8.0-windows\win-x64\publish\IntegrityCheckGui.exe`

This publish profile creates a self-contained single-file executable (portable, no separate .NET runtime install required).


## Pending reboot behavior
- GUI: checks pending reboot first and prompts user to restart immediately. If approved, it runs `shutdown /r /f /t 0`.
- PowerShell/CMD: checks pending reboot before checks.
  - Interactive mode: prompts user to restart now.
  - Silent mode: restarts automatically with force flag.

## GUI repair + recheck flow
The GUI now includes **Attempt Repair + Recheck**:
- Runs repair actions for common failures (SFC scan/repair, DISM restore health, Windows Update service reset).
- Automatically reruns full checks after repair attempts to verify whether problems persist.
