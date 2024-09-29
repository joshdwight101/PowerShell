# PowerShell
PowerShell scripts working/worked on.

File - Description

Add-Signature.ps1 - This file when ran will prompt for a file and when the path is entered into the console it will utilize the signature that you have stored at Cert:\CurrentUser\My and sign the file at the path you specified. Note: Don't use quotes around the path that you enter when using the script, I will mitigate this bug in the future so that both ways are accepted but for now don't use any quotes in the path.

AutoPilot-CSV-Gen.ps1 - This file aims to grab the hardware hash from a computer and then create the csv file that is utilized for adding a computer into Microsoft Intune AutoPilot. In essence you run this script, get the CSV, log into Intune and Import the CSV and the device is imported into AutoPilot.

DirectorySign.ps1 - DirectorySign opens up a simple gui where you can enter a path, and click a button and the script/app will sign all the powershell scripts in that directory and/or any subdirectories but utilizing the signature that is stored at Cert:\CurrentUser\My, so be careful when using this tool that you understand that it will sign scripts in subdirectories underneath the path you specify. Utilize the other script Add-Signature.ps1 if you want to sign a single script at a time (recommended for one-off tasks).

Get-Monitor-Information.ps1 - This script is a simple script that attempts to obtain information about the display monitors that are hooked up to a workstation. By default it outputs to C:\Temp, but the variables are at the top of the script for easy editing.

RandomStringGenerator.ps1 - RandomStringGenerator is a simple powershell gui with a slider that allows you to generate a random string of a specified length. Each time you press the button it copies a new randomly generated string into the clipboard to be pasted wherever.
