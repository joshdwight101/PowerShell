# Matchbox C# - Production Implementation Specification

## Assumptions
- Target OS: Windows 11/10 with PowerShell 7 and .NET SDK 8+.
- UI stack: WPF on .NET 8.
- Execution backend: local PowerShell module invoked by WPF app.

## 1) Full Architecture Design
- **Frontend (WPF/MVVM):** Views (XAML), ViewModels, domain services.
- **Execution Layer:** `DotnetExecutionService` launches `pwsh` wrapper script with cancellation and streaming output.
- **Backend (PowerShell):** `Matchbox.Backend.psm1` validates command, builds argument strings, invokes `dotnet`/`msbuild`.
- **Persistence Layer:** JSON settings service with auto-save debounce and atomic write.
- **Telemetry/Logs:** buffered producer-consumer channel; file sink + UI sink.

## 2) Responsive UI Design Spec
- Root layout: `DockPanel` (Menu top, StatusBar bottom, body fill).
- Content body: `Grid` with two columns `3*` and `2*`; rows `Auto` + `*`.
- No absolute `Canvas` positioning; all controls hosted in `GroupBox` with nested `Grid`/`StackPanel`.
- Min window size and star-sizing prevent overlap; long content scrolls inside panels.

## 3) Text Wireframe
- Top: `[File] [Help]`
- Left pane:
  - Build Options (configuration/runtime/framework/output/toggles)
  - Project + Arguments
- Right pane:
  - Command buttons (Build/Run/Test/Cancel)
  - Real-time console log output
- Bottom: status strip.

## 4) Menu System
- File > Exit: command binding triggers unsaved state check and graceful shutdown.
- Help > Manual: opens embedded manual window.
- Help > About: opens model-bound dialog with app metadata.

## 5) Manual System
- Embedded `WebView2` or `Frame` showing local manual HTML.
- Left indexed nav list binds to section anchors.
- Search box filters section index + highlights text in document.

## 6) About Dialog
- Fields: Name, Version, Author, GitHub URL, Purpose, Description, Features.
- Bind to immutable `AboutInfoViewModel`.

## 7) PowerShell Backend Design
- `New-MatchboxDotnetArguments` builds validated CLI options.
- `Invoke-MatchboxDotnetCommand` executes whitelisted commands.
- Wrapper script exposes stable invocation contract for WPF layer.

## 8) Command Mapping Table
| GUI Action | PS Function | CLI Command |
|---|---|---|
| Build | Invoke-MatchboxDotnetCommand | dotnet build |
| Run | Invoke-MatchboxDotnetCommand | dotnet run |
| Publish | Invoke-MatchboxDotnetCommand | dotnet publish |
| Clean | Invoke-MatchboxDotnetCommand | dotnet clean |
| Restore | Invoke-MatchboxDotnetCommand | dotnet restore |
| Test | Invoke-MatchboxDotnetCommand | dotnet test |
| Pack | Invoke-MatchboxDotnetCommand | dotnet pack |
| MSBuild | Invoke-MatchboxDotnetCommand | dotnet msbuild |

## 9) Multi-threading Plan
- Use `AsyncRelayCommand` for all heavy UI actions.
- Process IO readers run on background tasks.
- UI updates marshaled with `Dispatcher.Invoke`/`InvokeAsync`.
- Cancellation propagated via `CancellationTokenSource`.
- Parallel scanning uses `Parallel.ForEachAsync` with bounded degree.

## 10) JSON Settings Schema
```json
{
  "version": "1.0",
  "lastProject": "C:/src/MyApp/MyApp.sln",
  "paths": { "output": "\\\\server\\share\\drop" },
  "build": {
    "configuration": "Release",
    "framework": "net8.0",
    "runtime": "win-x64",
    "singleFile": true,
    "selfContained": false,
    "customArgs": "-v minimal"
  },
  "ui": {
    "windowWidth": 1400,
    "windowHeight": 900,
    "leftPanelRatio": 0.6
  }
}
```

## 11) Performance Strategy
- Non-blocking command execution and buffered output aggregation.
- Batch log appends to reduce UI render churn.
- Virtualize long lists/grids.
- Reuse runspaces/process wrappers where safe.
- For file discovery: partition directories and scan in parallel.

## 12) Sample Snippets
- See scaffold files:
  - `Views/MainWindow.xaml` for Grid + DockPanel responsive layout.
  - `ViewModels/MainWindowViewModel.cs` for async command orchestration + dispatcher updates.
  - `Services/DotnetExecutionService.cs` for PowerShell wrapper invocation and cancellation.
  - `backend/Matchbox.Backend.psm1` for command mapping + argument builder.

## 13) Dual Implementation Strategy (PowerShell + C#)
- **PowerShell-first app**: `powershell/MatchboxCSharp.ps1` runs the full WPF shell, menu system, build options, and execution console directly from PowerShell.
- **C# app parity**: `src/MatchboxCSharp.App` mirrors the same UI regions, commands, and backend command mapping for equivalent operator workflow.
- **Shared backend**: both modes consume `backend/Matchbox.Backend.psm1` to keep command construction and execution policy consistent.
