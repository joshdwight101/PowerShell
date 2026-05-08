# Matchbox C#

Enterprise-grade Windows desktop developer/admin tool with a PowerShell execution backend and C# WPF frontend.

## Solution Layout

- `src/MatchboxCSharp.App` - WPF UI, MVVM, orchestration services.
- `backend/Matchbox.Backend.psm1` - PowerShell execution module wrapping `dotnet`/`msbuild` workflows.
- `docs/ImplementationSpecification.md` - Production-ready design specification.

## Quick Start (Scaffold)

1. Open in Visual Studio 2022+.
2. Restore NuGet packages.
3. Ensure PowerShell 7+ is installed.
4. Run `MatchboxCSharp.App`.

## Status

This repository area provides initial production scaffolding and a full implementation blueprint.
