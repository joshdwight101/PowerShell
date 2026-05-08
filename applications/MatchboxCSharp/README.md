# Matchbox C#

Enterprise-grade Windows desktop developer/admin tool with both:
- a **C# WPF implementation** (`src/MatchboxCSharp.App`), and
- a **PowerShell-first implementation** (`powershell/MatchboxCSharp.ps1`) that hosts the full UI and executes `.NET` commands directly.

## Solution Layout

- `src/MatchboxCSharp.App` - C# WPF UI, MVVM, orchestration services.
- `powershell/MatchboxCSharp.ps1` - full PowerShell application with WPF GUI.
- `backend/Matchbox.Backend.psm1` - shared PowerShell execution module wrapping `dotnet`/`msbuild` workflows.
- `docs/ImplementationSpecification.md` - production design specification.

## Run Modes

### C# mode
1. Open `src/MatchboxCSharp.App` in Visual Studio 2022+.
2. Restore NuGet packages.
3. Ensure PowerShell 7+ is installed.
4. Run `MatchboxCSharp.App`.

### PowerShell mode
1. Open PowerShell 7+.
2. Run:
   ```powershell
   pwsh -NoProfile -File .\applications\MatchboxCSharp\powershell\MatchboxCSharp.ps1
   ```

## Status

Initial production scaffolding exists for both C# and PowerShell-hosted variants, designed to evolve in parallel.
