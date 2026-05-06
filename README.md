# PowerShell Toolkit Repository

A curated collection of PowerShell utilities and small suites for endpoint administration, automation, diagnostics, security operations, and rapid script development/testing.

This repository includes:
- Standalone admin scripts (`*.ps1`)
- Reusable modules (`*.psm1`)
- GUI tooling (PowerShell + embedded C#, and .NET WinForms project assets)
- Multi-script suites for enterprise collection and Windows integrity auditing

---

## Author

**Joshua Dwight**  
GitHub: https://github.com/joshdwight101

---

## Quick Start

### 1) Clone the repository
```powershell
git clone https://github.com/joshdwight101/PowerShell.git
cd PowerShell
```

### 2) Run scripts safely in a dev/test workflow
For iterative testing while developing with Codex:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexPulseLauncher.ps1
```
Or run a script directly:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SomeScript.ps1
```

### 3) Module import pattern
If using module-based tooling (e.g., `JDPM.psm1`):
```powershell
Import-Module .\JDPM.psm1 -Force
```

---

## Repository Structure

### Root Scripts & Modules

| File | Type | Purpose | Typical Usage |
|---|---|---|---|
| `Add-Signature.ps1` | Script | Signs a single script using a certificate from `Cert:\CurrentUser\My`. | One-off script signing operations. |
| `AutoPilot-CSV-Gen.ps1` | Script | Generates hardware-hash CSV workflow for Intune/Autopilot enrollment. | Device provisioning preparation. |
| `CodexPulseLauncher.ps1` | Script + C# GUI | Modern launcher to discover and run repository scripts with `ExecutionPolicy Bypass`. | Fast script testing and iteration with Codex. |
| `DirectorySign.ps1` | Script + GUI | Signs all PowerShell scripts in a target directory tree. | Bulk signing across script folders. |
| `Get-Monitor-Information.ps1` | Script | Collects monitor/display information. | Hardware inventory/troubleshooting. |
| `Get-WinUpdates.ps1` | Script | Windows update discovery/reporting automation. | Update-state checks. |
| `JDPM.psm1` | Module | Printer deployment/management helpers (install/remove/purge style operations). | Printer automation in deployment scripts. |
| `LetsEncrypt-CertPowerTool.ps1` | Script | Certificate/Let’s Encrypt oriented PowerShell automation tooling. | Certificate operations and helper workflows. |
| `PowershellShortcutMaker.ps1` | Script + GUI | Creates `.lnk` shortcuts to launch scripts with standardized parameters. | Enterprise shortcut packaging/deployment. |
| `RandomStringGenerator.ps1` | Script + GUI | Generates random strings and copies output to clipboard. | Password/token seed generation convenience. |
| `ShutDown-PC.ps1` | Script | Enforces shutdown behavior during configured windows (often startup task-driven). | Kiosk/lab/energy policy enforcement. |
| `SuperAdminTool.ps1` | Script | Administrative utility script for elevated workstation/server operations. | Admin action bundling and convenience tasks. |
| `README.md` | Documentation | Repository overview, usage, and operational guidance. | Start here. |
| `LICENSE` | Legal | Project license. | Governance/compliance. |

### `EnterpriseAssetSuite/`

| File | Type | Purpose |
|---|---|---|
| `EnterpriseAssetSuite.psm1` | Module | Collects endpoint telemetry/asset inventory data for enterprise management workflows. |
| `Invoke-EnterpriseAssetCollection.ps1` | Script | Silent orchestrator entry point for asset collection execution. |
| `Install-EnterpriseAssetScheduledTask.ps1` | Script | Registers a hidden per-user scheduled task to run collection at logon. |

### `SystemIntegritySuite/`

| File | Type | Purpose |
|---|---|---|
| `Win11-IntegrityCheck.ps1` | Script | PowerShell-side integrity checks for Windows 11 endpoints. |
| `Win11-IntegrityCheck.cmd` | Cmd wrapper | Convenience launcher/wrapper for integrity checks. |
| `IntegrityCheckGui.cs` | C# source | WinForms GUI implementation for integrity workflow. |
| `IntegrityCheckGui.csproj` | .NET project file | Build definition for GUI app. |
| `SystemIntegritySuite.sln` | Solution | Visual Studio solution for suite components. |
| `app.manifest` | Manifest | Application manifest metadata. |
| `BUILD-INSTRUCTIONS.md` | Documentation | Build/setup details for the suite. |
| `CHANGELOG.md` | Documentation | Release/change history for integrity suite updates. |
| `README.md` | Documentation | Suite-specific overview and usage guidance. |

---

## Detailed Usage Instructions

## 1) Codex-driven script testing (recommended)
Use **CodexPulseLauncher** for rapid iteration during development:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexPulseLauncher.ps1
```

### What it does
- Recursively discovers `*.ps1` files in the repo.
- Provides searchable list with file metadata.
- Launches selected script via `-ExecutionPolicy Bypass`.
- Supports double-click launch and open-folder convenience.
- Includes an aligned top-right script-directory row (label, path, browse) and bottom-right Auto Refresh controls.

### Best practices
- Keep scripts idempotent where possible for repeated test runs.
- Use dedicated test inputs/tenants/dev devices.
- If a script modifies system settings, validate on a lab machine first.

---

## 2) Script signing workflows

### Sign one script
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Add-Signature.ps1
```

### Sign an entire directory tree
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\DirectorySign.ps1
```

**Notes**
- Requires a valid code-signing cert in `Cert:\CurrentUser\My`.
- Prefer single-file signing for high-risk scripts before bulk actions.

---

## 3) Printer deployment automation (JDPM module)

```powershell
Import-Module .\JDPM.psm1 -Force
# Example pattern (adjust parameters to your environment)
# Install-Printer -PrinterName "HQ-Printer-01" -PrinterIP "10.0.0.25" -DriverName "Driver Name" -InfPath "C:\Drivers\printer.inf" -Duplex $true
```

Recommended approach:
1. Validate driver package and INF path in a test machine.
2. Confirm spooler service health.
3. Roll out with logging/transcript enabled.

---

## 4) Endpoint inventory collection (`EnterpriseAssetSuite`)

### Install scheduled collection task
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EnterpriseAssetSuite\Install-EnterpriseAssetScheduledTask.ps1
```

### Run collection immediately (manual test)
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EnterpriseAssetSuite\Invoke-EnterpriseAssetCollection.ps1
```

### Integrate module directly
```powershell
Import-Module .\EnterpriseAssetSuite\EnterpriseAssetSuite.psm1 -Force
```

Use this suite when you need recurring user-context telemetry snapshots suitable for enterprise reporting pipelines.

---

## 5) System integrity workflows (`SystemIntegritySuite`)

### PowerShell check
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SystemIntegritySuite\Win11-IntegrityCheck.ps1
```

### CMD wrapper
```cmd
SystemIntegritySuite\Win11-IntegrityCheck.cmd
```

### Build GUI from source
Open `SystemIntegritySuite\SystemIntegritySuite.sln` in Visual Studio and build using the instructions in:
- `SystemIntegritySuite\BUILD-INSTRUCTIONS.md`
- `SystemIntegritySuite\README.md`

---

## 6) Additional utilities

### Monitor inventory
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Monitor-Information.ps1
```

### Windows update checks
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-WinUpdates.ps1
```

### PowerShell shortcut generation
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PowershellShortcutMaker.ps1
```

### Random string generator
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\RandomStringGenerator.ps1
```

### Startup shutdown enforcement
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ShutDown-PC.ps1
```

### Certificate workflow utility
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\LetsEncrypt-CertPowerTool.ps1
```

### Super admin helper
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SuperAdminTool.ps1
```

---

## Operational Guidance

## Execution Policy & Security
- `Bypass` is useful for rapid internal testing but should be handled carefully.
- For production rollouts, prefer signed scripts and least-privilege execution contexts.
- Store sensitive material (keys, credentials, cert private keys) in secure stores and avoid hardcoding.

## Logging & Troubleshooting
- Run scripts with `-NoProfile` to reduce profile-side effects during debugging.
- Use transcript logging in change-sensitive workflows:
  ```powershell
  Start-Transcript -Path .\script-run.log
  # run your script
  Stop-Transcript
  ```
- Validate on non-production hosts first.

## Compatibility Notes
- Most scripts target Windows environments (GUI, cert store, scheduled task, printer stack, explorer shell).
- GUI scripts require an interactive desktop session.

---

## Contribution Guidelines

1. Keep new scripts focused and well-commented.
2. Add clear parameter help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, examples).
3. Prefer idempotent operations where practical.
4. Update this README when adding/removing files.
5. Include test notes in PRs (manual and/or automated).

---

## License

See `LICENSE` for licensing details.
