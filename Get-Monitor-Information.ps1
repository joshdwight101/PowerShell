# Get-Monitor-Information.ps1
# Author: Josh Dwight
# https://github.com/joshdwight101/PowerShell

$output_path = "C:\Temp"  # path to drop the log into when script is ran
$output_file = "$output_path\$env:computername-monitor-info.log" 


function Get-Monitor-Info {
    Get-CimInstance WmiMonitorID -Namespace root\wmi | ForEach-Object {
    $Serial = [System.Text.Encoding]::ASCII.GetString($_.SerialNumberID).Trim(0x00)
    Write-Output "Monitor Serial Number: $Serial"
    }
}


Get-Monitor-Info | Out-File -FilePath $output_file
& Notepad $output_file
