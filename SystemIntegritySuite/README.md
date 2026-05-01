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

## VS Code build fix (important)
If VS Code tries to run:
`dotnet build ...\IntegrityCheckGui.cs`
that is the wrong target and will produce errors like CS8803/CS0246/CS0234.

Build the **project** instead:
```powershell
dotnet build .\IntegrityCheckGui.csproj
```

This repo includes `.vscode/tasks.json` with:
- `build-integrity-gui`
- `publish-integrity-gui-single-file`

Use those tasks so VS Code always builds/publishes the `.csproj` and not the raw `.cs` file.


## Why those CS0234/CS0246 errors happen
Those errors occur when VS Code/C# extension invokes:
`dotnet build ...\IntegrityCheckGui.cs`

That compiles a **single source file** outside the WinForms project context, so it cannot see:
- `<UseWindowsForms>true</UseWindowsForms>`
- Windows target framework (`net8.0-windows`)
- NuGet references such as `System.Management`

### Correct way to build
Always build the project:
```powershell
dotnet build .\IntegrityCheckGui.csproj
```

Or in VS Code run task: **build-integrity-gui**.
The workspace includes `.vscode/settings.json` to point C# tooling at `IntegrityCheckGui.csproj` by default.

## GUI diagnostic logging
The GUI now writes a single diagnostic log file per run to:
`C:\ProgramData\SystemIntegritySuite\IntegrityCheckGui_yyyyMMdd_HHmmss.log`

Enable extra debug tracing by launching with:
```powershell
.\IntegrityCheckGui.exe --debug
```

This log captures lifecycle events, process invocations, exit codes, pending reboot decisions, and unhandled exceptions to speed up troubleshooting.
