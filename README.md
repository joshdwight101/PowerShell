# PowerShell

PowerShell scripts working/worked on.

File - Description

Add-Signature.ps1 - This file when ran will prompt for a file and when the path is entered into the console it will utilize the signature that you have stored at Cert:\\CurrentUser\\My and sign the file at the path you specified. Note: Don't use quotes around the path that you enter when using the script, I will mitigate this bug in the future so that both ways are accepted but for now don't use any quotes in the path.



AutoPilot-CSV-Gen.ps1 - This file aims to grab the hardware hash from a computer and then create the csv file that is utilized for adding a computer into Microsoft Intune AutoPilot. In essence you run this script, get the CSV, log into Intune and Import the CSV and the device is imported into AutoPilot.



DirectorySign.ps1 - DirectorySign opens up a simple gui where you can enter a path, and click a button and the script/app will sign all the powershell scripts in that directory and/or any subdirectories but utilizing the signature that is stored at Cert:\\CurrentUser\\My, so be careful when using this tool that you understand that it will sign scripts in subdirectories underneath the path you specify. Utilize the other script Add-Signature.ps1 if you want to sign a single script at a time (recommended for one-off tasks).



Get-Monitor-Information.ps1 - This script is a simple script that attempts to obtain information about the display monitors that are hooked up to a workstation. By default it outputs to C:\\Temp, but the variables are at the top of the script for easy editing.



JDPM.psm1 - JDPM is a PowerShell module that aim's to simplify printer management in your scripting. You simply drop this script next to your installation script, import the module into your script utilizing: Import-Module JDPM.psm1. After that you can simply automate installing printers with Install-Printer and a few arguments: PrinterName, PrinterIP, DriverName, InfPath, Duplex. There is a function to uninstall printers with the Uninstall-Printer function. There's an ability to purge all printers utilizing a function called purge\_printers, this is in case you're looking to clear the printers and re-add new ones. The module automates adding the ports and drivers and even does it's own checking to see if they exist prior to creating them if they do not exist. Spend less time writing the script, and more time getting the job done.



PowershellShortcutMaker.ps1 - a WinForms-based utility designed to generate Windows shortcuts that launch PowerShell scripts with standardized execution parameters.

The tool provides a simple GUI that allows administrators to:

-Browse and select a .ps1 script

-Define a custom shortcut name

-Automatically generate a .lnk file in the script’s directory

-Launch the script using PowerShell with -WindowStyle Hidden and -NoProfile

Primary use case is enterprise deployment. Administrators can store signed PowerShell scripts in secured, read-only directories and use this utility to create shortcuts that can be distributed via Intune, Group Policy, or other endpoint management solutions.

This approach supports centralized script management, consistent execution behavior, and user-context shortcut deployment.



RandomStringGenerator.ps1 - RandomStringGenerator is a simple powershell gui with a slider that allows you to generate a random string of a specified length. Each time you press the button it copies a new randomly generated string into the clipboard to be pasted wherever.



Shutdown-PC.ps1 - built to be utilized as a script launched by Scheduled Task as a startup script. The purpose is in the event that you absolutely do not want a computer to stay on during a specified set of hours. This script enforces that rule by checking at startup and if the time is in between the specified window configured in the script then the computer will initiate shut down immediately. This means no matter how many times a user turns the computer on during that window the computer will just repeatedly shut down as soon as it starts up.



SecureVault-Encryptor.ps1 - A full GUI-oriented encryption application built in PowerShell with embedded C# cryptography routines for high throughput operations. The app provides:

- Standalone design (no dependencies on other scripts in this repository)
- AES-256-CBC encryption + HMAC-SHA256 authentication (compatible with Windows PowerShell 5.1+)
- Optional certificate-backed key protection using RSA-OAEP (compatibility mode for older PowerShell/.NET hosts)
- Optional password-based encryption mode using PBKDF2 (high iteration count)
- Output files are written in-place in the same directory as source files (`.psenc` for encrypt, restored/`.decrypted` for decrypt)
- Reliable background job processing with worker recommendations based on available cores
- Auto-manage thread recommendation based on live CPU utilization to reduce overcommitting busy systems
- Built-in self-signed encryption certificate generation (4096-bit RSA)
- Modern dark-themed WinForms interface for intuitive operation
- Full control labeling, per-control tooltips, and an in-app Help menu with guided index/training text
- Debug mode with verbose per-file event logs (and launch transcript file) in the script directory for troubleshooting
- "Copy Debug Report" button to capture environment/settings/log tail for rapid issue handoff
- Launch switch `-DebugMode` to automatically enable debug logging/transcript output at startup
- Cancel button for graceful interruption of active jobs and immediate re-enable of Start control

Potential expansion roadmap for production hardening and feature growth:

- Add Argon2id (memory-hard KDF) support for password mode
- Add optional hardware-backed key storage via TPM/HSM/Windows CNG providers
- Add pause/resume queues, retry policy, and job persistence for very large batches
- Add secure erase mode and configurable post-encryption source cleanup
- Add signed update pipeline and telemetry-free crash reporting
- Add package format with manifest/signature for encrypted bundles and key escrow workflows

EnterpriseAssetSuite/EnterpriseAssetSuite.psm1 - Enterprise endpoint telemetry and asset management module for Intune-friendly background execution. Captures serial number, manufacturer, model, hostname, Windows version/build, IP/MAC history snapshot, login/logoff events, pending reboot state, last reboot time, attached monitor identities, disk free-space health flags, and script integrity hash status. Writes JSON state locally and includes a SharePoint/Office 365 publishing integration point for Graph API-based list updates.

EnterpriseAssetSuite/Invoke-EnterpriseAssetCollection.ps1 - Silent orchestrator entry point intended for logon-triggered scheduled task execution.

EnterpriseAssetSuite/Install-EnterpriseAssetScheduledTask.ps1 - Helper script to register a hidden per-user scheduled task that runs collection at user logon.
