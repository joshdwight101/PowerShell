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

## v1.4.0
- Reworked GUI into a diagnostic-command-center style layout.
- Added step-by-step progress grid with status states (Running, PASS, FAIL, WARNING) and color coding.
- Added verbose real-time status output during every workflow step.
- Moved pending reboot inspection to run **after** all integrity checks.
- Added detailed workstation metadata panel: serial, hostname, manufacturer, model, OS version/display version/build.
- Added repair workflow and automatic recheck behavior.
- Added quick action buttons for Reset Windows (Settings Recovery) and Restart.
- Added single-file diagnostic logging for admin troubleshooting.
