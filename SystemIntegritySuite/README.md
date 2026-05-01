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
