# AutoPilot-CSV-Gen
# Author: Josh Dwight
# github.com/joshdwight101

# Script Settings
$default_domain = "yourdomain.com"	# This is the domain utilized in Intune (i.e youcompany.com, .net, .org, etc)
$default_user = "$env:Username@$default_domain" # This should be your intune user for adding devices
$default_group_tag = "main" # set this to the group tag you use the most (for convenience)
$output_dir = "C:\Temp"
$output_file = "Intune_Autopilot"  # script adds the file extension automatically / EXCEPT in prompt when specified

# Grabs hardware hash which is utilized in Intune CSV for autopilot
function get-hardware-id {
    $hardware_hash = (Get-CimInstance -ClassName MDM_DevDetail_Ext01 -Namespace root\cimv2\mdm\dmmap).DeviceHardwareData

    return $hardware_hash
}

# Grabs hardware hash which is utilized in Intune CSV for autopilot and puts into clipboard
function hash_clip {
    $hardware_hash = get-hardware-id
    $hardware_hash | Set-Clipboard
    Write-Host "Hardware Hash copied to clipboard"
}

# Grabs serial number which is utilized in Intune CSV for autopilot
function get-mb-serial {
    $mb_serial = Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber
    return $mb_serial
}
get-mb-serial

# Grabs serial number which is utilized in Intune CSV for autopilot and puts into cliipboard
function serial_clip {
    $mb_serial = get-mb-serial
    $mb_serial | Set-Clipboard
    Write-Host "Serial Number copied to clipboard"
}


function prompt_csv {
    $csv_file = Read-Host "CSV File"
    $device_serial = Read-Host "Serial Number"
    $hash_id = Read-Host "Hash ID"
    $group_tag = Read-Host "Group Tag"
    $assigned_user = Read-Host "Assigned User"
    $csv_info = [PSCustomObject]@{
        "Device Serial Number" = $device_serial
        "Windows Product ID" = $null
        "Hardware Hash" = $hash_id
        "Group Tag" = $group_tag
        "Assigned User" = $assigned_user
    }
    
    # Convert the custom object to CSV format without type information
    $csv_data = $csv_info | ConvertTo-Csv -NoTypeInformation

    # Remove quotes from both headings and data
    $csv_data = $csv_data | ForEach-Object { $_ -replace '"', '' }

    # Write the data (including headers) to the CSV file
    $csv_data | Set-Content $csv_file -Encoding UTF8

}

function auto_csv {
    Write-Host @"
    Auto-CSV has the following defaults if input is not provided:
    CSV File: $output_file
    Assigned User: $default_user
    Group Tag: $default_group_tag
"@
    

    $csv_file = Read-Host "CSV File"
    $device_serial = get-mb-serial
    $hash_id = get-hardware-id
    $group_tag = Read-Host "Group Tag"
    $assigned_user = Read-Host "Assigned User"

    if ([string]::IsNullOrEmpty($csv_file)) {
        Write-Host "No CSV File was Specified"
        # We add workstation serial to csv name and add csv extension.
        $csv_file = "$PSScriptRoot\$output_file-$device_serial.csv" 
        Write-Host "Creating $csv_file"
    }

    if ([string]::IsNullOrEmpty($group_tag)) {
        Write-Host "Group Tag was left blank. Defaulting to $default_group_tag."
        $group_tag = "$default_group_tag"
    }

    if ([string]::IsNullOrEmpty($assigned_user)) {
        Write-Host "Assigned user was not provided. Using current logged on user."
        $assigned_user = $env:USERNAME + "@$default_domain"
    }
    
    $csv_info = [PSCustomObject]@{
    "Device Serial Number" = $device_serial
    "Windows Product ID" = $null
    "Hardware Hash" = $hash_id
    "Group Tag" = $group_tag
    "Assigned User" = $assigned_user
    }

    # Convert the custom object to CSV format without type information
    $csv_data = $csv_info | ConvertTo-Csv -NoTypeInformation

    # Remove quotes from both headings and data
    $csv_data = $csv_data | ForEach-Object { $_ -replace '"', '' }

    # Write the data (including headers) to the CSV file
    $csv_data | Set-Content $csv_file -Encoding UTF8

}

auto_csv

