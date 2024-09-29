# PowerShell
Place where I'll upload PowerShell scripts that I'm working/worked on.

File - Description

Add-Signature.ps1 - This file when ran will prompt for a file and when the path is entered into the console it will utilize the signature that you have stored at Cert:\CurrentUser\My and sign the file at the path you specified. Note: Don't use quotes around the path that you enter when using the script, I will mitigate this bug in the future so that both ways are accepted but for now don't use any quotes in the path.

AutoPilot-CSV-Gen.ps1 - This file aims to grab the hardware hash from a computer and then create the csv file that is utilized for adding a computer into Microsoft Intune AutoPilot. In essence you run this script, get the CSV, log into Intune and Import the CSV and the device is imported into AutoPilot.
