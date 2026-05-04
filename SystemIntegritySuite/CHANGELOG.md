# Changelog - Integrity Checking & Repair Tool

## v1.5.0
- Added menu bar with `File` and `About` menus.
- Added About popup dialog with app title, version, purpose summary, and author info.
- Updated title bar to include app name, version, and author name.

## v1.5.1
- Fixed standalone publish build error (`CS0019`) by changing OS build type from `string` to `int`.

## v1.5.2
- Refined GUI layout to a professional docked structure using `TableLayoutPanel` + `SplitContainer`.
- Moved menu bar to standard top-of-window placement.
- Fixed clipping/cutoff issues by improving docking, row sizing, and minimum form size.
- Improved readability of check results with wrapped details and auto-sized grid rows.

## v1.6.0
- Added automatic repair-on-failure behavior to GUI default flow (no manual recheck button required to trigger first repair cycle).
- Updated PowerShell and CMD scripts to perform detect -> repair -> recheck workflow automatically.
- Added smarter DISM/SFC/update-component remediation sequence prior to final reinstall recommendation.

## v1.6.1
- Restored verbose step-by-step console progress in PowerShell and CMD scripts (check phase and repair phase).
- Added clear `[step/total]` progress markers and stage descriptions for better operator visibility.

## v1.6.2
- Expanded script verbosity with explicit `RESULT [PASS/FAIL]` log lines for each step.
- Ensured pending reboot handling prompts interactive users to reboot now while keeping silent-mode auto reboot behavior.
- Preserved full date+time timestamps on all console/report log entries.

## v1.6.3
- Added richer workstation inventory details to script reports (hostname, serial, manufacturer, model, IP, MAC, OS version/build).
- Added explicit run start/end timestamps and phase duration timestamps in PowerShell output.
- Added repair outcome guidance text (including reinstall recommendation when unresolved issues remain).

## v1.6.4
- Fixed CMD startup reliability by replacing fragile WMIC/getmac parsing with PowerShell CIM/network queries.
- Removed `goto`-style metadata parsing blocks that could fail early on some systems.

## v1.6.5
- Hardened CMD startup further by moving metadata collection into a fault-tolerant subroutine with temp-file parsing.
- Added safe defaults and error-tolerant PowerShell metadata export to prevent premature script termination.

## v1.6.6
- Simplified CMD metadata collection again to prevent early-stage failures on strict CMD environments.
- Added explicit fallback when PowerShell is unavailable and per-field non-fatal metadata lookups.

## v1.6.7
- Fixed CMD logging to use native `%date% %time%` timestamps (no PowerShell dependency in logger).
- Eliminated timestamp-related startup/runtime failures tied to repeated PowerShell calls in `:log`.

## v1.7.0
- Added `Get-ComputerInventory` function to PowerShell script for detailed startup inventory collection.
- Added inventory summary at startup and inclusion in main log/final report flow.
- Added optional JSON output (`-JsonReport`) with full structured `ComputerInventory` object and final results.

## v2.0.0
- Rebuilt `Win11-IntegrityCheck.cmd` into a hardened, full-featured CMD workflow.
- Added reliable argument handling (`-silent`, `-force`, `-deep`, `-no-reboot`, `-reset-wu`, `-reset-network`, `-skip-wu-reset`, `-help`).
- Added robust detect -> repair -> recheck workflow with verbose step/status logging and safer reboot behavior.

## v2.0.1
- Added non-freezing long-command execution wrapper with live elapsed progress for DISM/SFC/CHKDSK stages.
- Improved operator visibility during long repairs (especially `DISM /RestoreHealth`) with start/end and periodic status output.

## v2.0.2
- Fixed command-wrapper quoting bug that caused \"The filename, directory name, or volume label syntax is incorrect\" during SFC start.
- Simplified long-run execution wrapper to a safer direct command invocation with explicit start/end logging.

## v2.0.3
- Fixed CMD free-space status false-failure issue by moving threshold comparison into PowerShell (64-bit safe).
- Added verbose free-space reporting (bytes and GB) to improve troubleshooting clarity.

## v1.4.0
- Reworked GUI into a diagnostic-command-center style layout.
- Added step-by-step progress grid with status states (Running, PASS, FAIL, WARNING) and color coding.
- Added verbose real-time status output during every workflow step.
- Moved pending reboot inspection to run **after** all integrity checks.
- Added detailed workstation metadata panel: serial, hostname, manufacturer, model, OS version/display version/build.
- Added repair workflow and automatic recheck behavior.
- Added quick action buttons for Reset Windows (Settings Recovery) and Restart.
- Added single-file diagnostic logging for admin troubleshooting.
