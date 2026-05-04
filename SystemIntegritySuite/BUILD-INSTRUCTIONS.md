# Integrity Checking & Repair Tool - Build Instructions

## Build (Debug)
```powershell
dotnet build .\IntegrityCheckGui.csproj
```

## Publish single-file standalone EXE
```powershell
dotnet publish .\IntegrityCheckGui.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true
```

Output:
`bin\Release\net8.0-windows\win-x64\publish\IntegrityCheckGui.exe`

## Run with verbose debug logging
```powershell
.\IntegrityCheckGui.exe --debug
```

Log output path:
`C:\ProgramData\SystemIntegritySuite\IntegrityTool_yyyyMMdd_HHmmss.log`
