# Windows 11 Integrity Suite

## What is `IntegrityCheckGui.cs`?
`IntegrityCheckGui.cs` is an **optional C# WinForms GUI** example that runs integrity checks and streams status live in a window.
It is separate from the scripts.

## Independent script usage
Both scripts are standalone and perform the same 7 checks.

### PowerShell version (self-elevates, opens report in Notepad)
```powershell
powershell -ExecutionPolicy Bypass -File .\Win11-IntegrityCheck.ps1
```

### CMD version (self-elevates, opens report in Notepad)
```cmd
Win11-IntegrityCheck.cmd
```

## Optional GUI usage
If you want to run the C# GUI as a .NET 8 single-file app:

1. Create a WinForms project.
2. Replace `Program.cs` with `IntegrityCheckGui.cs` content.
3. Build and run on Windows.

The GUI is not required for script usage.
