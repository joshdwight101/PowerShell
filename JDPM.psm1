# Josh Dwight's Print Module
# JDPM.psm1
# Revision Date: 08/28/2024
#
# Commands:
# Install-Printer -PrinterName <name> -PrinterIP <ip> -DriverName <name> -InfPath <path.inf> -Duplex <0,1,2>
# Duplex Options Explained:
# 0 = Off/Single-Sided; 1 = TwoSidedShortEdge; 2 = TwoSidedLongEdge
#
# Uninstall-Printer -PrinterName <name>
#
# Usage:
# Import-Module JDPM.psm1  # This makes the functions from JDPM.psm1 available in your powershell script.
# Command(s) Listed Above

# Define the printer class
class printer {
    [string]$ip     # The IP address of the printer
    [string]$name   # The name of the printer
    [string]$exists # Indicates if the printer exists

    # Example usage:
    # $myPrinter = [printer]::new()
    # $myPrinter.ip = "192.168.1.100"
}

# Define the driver class
class driver {
    [string]$name    # The name of the driver
    [string]$inf     # The INF file for the driver
    [string]$exists
}

# Define the port class
class port {
    [string]$name   # The name of the port
    [string]$exists
}

$ErrorActionPreference = 'SilentlyContinue'


function Install-Printer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PrinterName,
        [Parameter(Mandatory=$true)]
        [string]$PrinterIP,
        [Parameter(Mandatory=$true)]
        [string]$DriverName,
        [Parameter(Mandatory=$true)]
        [string]$InfPath,
        [Parameter(Mandatory=$false)]
        [int]$Duplex    # 0 = Off/Single-Sided; 1 = TwoSidedShortEdge; 2 = TwoSidedLongEdge
    )

    # driver handling
    $printer_driver = [driver]::new()
    $printer_driver.name = $DriverName
    Write-Host "Driver Name: " + $printer_driver.name
    $printer_driver.inf = $InfPath
    $pnputil = $printer_driver.inf
    Write-Host "INF Path: " + $pnputil

    # port handling
    $printer_port = [port]::new()
    $printer_port.name = "IP_"

    # printer handling
    $my_printer = [printer]::new()
    $my_printer.name = $PrinterName
    Write-Host "Printer Name: $PrinterName"
    $my_printer.ip = $PrinterIP
    Write-Host "Printer IP: " + $my_printer.ip
    $my_printer.exists = Get-PrinterDriver - Name $printer_driver.name

    $printer_port.name += $PrinterIP # append the printer IP to the port name
    Write-Host = $printer_port.name

    # installation logic
    if (-not $my_printer.exists) {  
        $printer_driver.exists = $Null  # set variable to nothing (this may be unnecessary)
        $printer_driver.exists = Get-PrinterDriver -Name $printer_driver.name   #The method used to determine if the driver exists
        if (-not $printer_driver.exists) {
            pnputil.exe /install /add-driver $pnputil
            Add-PrinterDriver -Name $printer_driver.name
        }
        $printer_port.exists = Get-PrinterPort -Name $printer_port.name
        if (-not $printer_port.exists) {
            Add-PrinterPort -Name $printer_port.name -PrinterHostAddress $my_printer.ip
        }
        # Assuming $Duplex is passed as an integer parameter
	if (-not $Duplex -and $Duplex -ne 0) {
	    $duplex_mode = "OneSided"
	} else {
	    switch ($Duplex) {
		0 { $duplex_mode = "OneSided" }
		1 { $duplex_mode = "TwoSidedShortEdge" }
		2 { $duplex_mode = "TwoSidedLongEdge" }
		default { $duplex_mode = "OneSided" }
	    }
	}

	Write-Host "Duplex mode is: $duplex_mode"
        
        Add-Printer -Name $my_printer.name -DriverName $printer_driver.name -PortName $printer_port.name #-ShareName $my_printer.name  # I think this shares the printer
        Get-Printer -Name $my_printer.name | Set-PrintConfiguration -DuplexingMode $duplex_mode

    }


}

function Uninstall-Printer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PrinterName
    )

    # Get the printer object
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if (!$printer) {
        Write-Host "Printer '$PrinterName' not found."
        exit 1
    }

    # Remove the printer
    try {
        Remove-Printer -InputObject $printer -ErrorAction Stop
    } catch {
        Write-Host "Error removing printer: $_"
        exit 1
    }

    # Get the driver object
    $driver_name = $printer.DriverName
    $driver = Get-PrinterDriver -Name $driver_name -ErrorAction SilentlyContinue
    if (!$driver) {
        Write-Host "Printer driver '$driver_name' not found."
        exit 1
    }

    # Remove the driver
    try {
        Remove-PrinterDriver -InputObject $driver -ErrorAction Stop
    } catch {
        Write-Host "Error removing printer driver: $_"
        exit 1
    }

    # Get the port object
    $port_name = $printer.PortName
    $port = Get-PrinterPort -Name $port_name -ErrorAction SilentlyContinue
    if (!$port) {
        Write-Host "Printer port '$port_name' not found."
        exit 1
    }

    # Remove the port
    try {
        Remove-PrinterPort -InputObject $port -ErrorAction Stop
    } catch {
        Write-Host "Error removing printer port: $_"
        exit 1
    }
}


function purge_printers {
    Write-Host "Removing printer objects."
    Get-WmiObject -Class Win32_Printer | Where-Object {$_.Name -notmatch 'PDF|OneNote|Microsoft'} | ForEach-Object{$_.delete()} 
    cscript.exe 'C:\Windows\System32\Printing_Admin_Scripts\en-US\prndrvr.vbs' -x	#  This will remove all (not in use) drivers; drivers in use will fail to be removed
}
