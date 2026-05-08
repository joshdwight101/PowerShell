# +------------------------------------------------------------+
# | Author : Joshua Dwight                                     |
# | Github : https://github.com/joshdwight101                  |
# +------------------------------------------------------------+
#
# Author Information:
# Joshua Dwight
# https://github.com/joshdwight101
# https://linkedin.com/in/dwightj

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppName = 'Device Power Bulk Manager'
$AppVersion = '2.0.1'
$AppAuthor = 'Joshua Dwight'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$cs = @"
using System;
using System.Drawing;
using System.Windows.Forms;

public static class UsbPowerBulkGuiFactory
{
    public static Form CreateMainForm(string title)
    {
        var form = new Form();
        form.Text = title;
        // Using ClientSize guarantees the inside of the window is exactly 1280x900 
        // regardless of Windows theme border thickness or title bar height.
        form.ClientSize = new Size(1280, 900);
        form.StartPosition = FormStartPosition.CenterScreen;
        return form;
    }
}
"@
if (-not ('UsbPowerBulkGuiFactory' -as [type])) {
    Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PowerCfgDeviceSet {
    param([string]$QueryType)

    $results = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($line in (powercfg /devicequery $QueryType 2>$null)) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            [void]$results.Add($trimmed)
        }
    } catch {}

    return $results
}

function Convert-NormalizedDeviceKey {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value -replace '[^a-zA-Z0-9]','').ToUpperInvariant())
}

function Get-WmiCapabilityMap {
    param([string]$ClassName)
    $map = @{}
    try {
        $instances = Get-CimInstance -Namespace root/wmi -ClassName $ClassName -ErrorAction Stop
        foreach ($inst in $instances) {
            if ($null -eq $inst.InstanceName) { continue }
            # WMI appends _0, _1, etc to the InstanceName. Strip it off for accurate matching.
            $baseName = $inst.InstanceName -replace '_[0-9]+$', ''
            $norm = Convert-NormalizedDeviceKey -Value $baseName
            $map[$norm] = [bool]$inst.Enable
        }
    } catch {}
    return $map
}

function Get-WmiCapabilityValue {
    param(
        [string]$PnpDeviceId,
        [hashtable]$CapabilityMap
    )
    $deviceKey = Convert-NormalizedDeviceKey -Value $PnpDeviceId
    
    if ($CapabilityMap.ContainsKey($deviceKey)) {
        return @{ Supported = $true; Value = $CapabilityMap[$deviceKey] }
    }
    
    # Fallback to partial match if stripping _0 didn't yield an exact match
    foreach ($key in $CapabilityMap.Keys) {
        if ($key.StartsWith($deviceKey) -or $deviceKey.StartsWith($key)) {
            return @{ Supported = $true; Value = $CapabilityMap[$key] }
        }
    }
    
    return @{ Supported = $false; Value = $false }
}

function Get-PowerDevices {
    $wakeArmedDevices = Get-PowerCfgDeviceSet -QueryType 'wake_armed'
    $powerEnableMap = Get-WmiCapabilityMap -ClassName 'MSPower_DeviceEnable'
    $wakeEnableMap = Get-WmiCapabilityMap -ClassName 'MSPower_DeviceWakeEnable'

    $devices = @()
    try {
        $devices = @(Get-CimInstance Win32_PnPEntity -Property Name, PNPDeviceID, Status -ErrorAction Stop)
    } catch {
        Write-Warning "Failed to fetch PnP entities."
    }

    $validDevices = @()
    $devices = @($devices | Sort-Object -Property PNPDeviceID -Unique)
    
    foreach ($d in $devices) {
        $powerCap = Get-WmiCapabilityValue -PnpDeviceId $d.PNPDeviceID -CapabilityMap $powerEnableMap
        $wakeCap = Get-WmiCapabilityValue -PnpDeviceId $d.PNPDeviceID -CapabilityMap $wakeEnableMap
        
        if (-not ($powerCap.Supported -or $wakeCap.Supported)) { continue }

        $validDevices += [pscustomobject]@{
            Selected = $false
            Name = $d.Name
            PnpDeviceId = $d.PNPDeviceID
            Status = $d.Status
            PowerSavingAllowed = [bool]$powerCap.Value
            PowerSavingToggleSupported = [bool]$powerCap.Supported
            WakeAllowed = [bool]$wakeCap.Value
            WakeToggleSupported = [bool]$wakeCap.Supported
        }
    }
    
    return $validDevices
}

function Set-PowerSavingAllowed {
    param([string]$PnpDeviceId,[bool]$Allow)
    $deviceKey = Convert-NormalizedDeviceKey -Value $PnpDeviceId
    $wmiUpdated = $false
    
    # 1. Primary WMI integration (Immediately updates Device Manager state)
    try {
        $instances = Get-CimInstance -Namespace root/wmi -ClassName MSPower_DeviceEnable -ErrorAction Stop
        foreach ($inst in $instances) {
            $baseName = $inst.InstanceName -replace '_[0-9]+$', ''
            $norm = Convert-NormalizedDeviceKey -Value $baseName
            if ($norm -eq $deviceKey -or $norm.StartsWith($deviceKey) -or $deviceKey.StartsWith($norm)) {
                $inst | Set-CimInstance -Property @{ Enable = $Allow } -ErrorAction Stop
                $wmiUpdated = $true
                break
            }
        }
    } catch { }

    if (-not $wmiUpdated) {
        try {
            $wmiObjs = Get-WmiObject -Namespace root/wmi -Class MSPower_DeviceEnable -ErrorAction Stop
            foreach ($wmi in $wmiObjs) {
                $baseName = $wmi.InstanceName -replace '_[0-9]+$', ''
                $norm = Convert-NormalizedDeviceKey -Value $baseName
                if ($norm -eq $deviceKey -or $norm.StartsWith($deviceKey) -or $deviceKey.StartsWith($norm)) {
                    $wmi.Enable = $Allow
                    $wmi.Put() | Out-Null
                    $wmiUpdated = $true
                    break
                }
            }
        } catch {}
    }

    # 2. Fallback: Registry (If WMI is completely inaccessible)
    $subKeyPath = "SYSTEM\CurrentControlSet\Enum\$PnpDeviceId\Device Parameters"
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $true)
        if ($null -eq $key) {
            $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($subKeyPath)
        }
        if ($null -ne $key) {
            $current = $key.GetValue('PnPCapabilities')
            if ($null -eq $current) { $current = 0 }

            if ($Allow) { 
                $newValue = ($current -band (-bnot 24)) 
            } else { 
                $newValue = ($current -bor 24) 
            }
            
            $key.SetValue('PnPCapabilities', $newValue, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        $key.Close()
    } catch {
        Write-Warning "Failed to set registry for $PnpDeviceId"
    }
}

function Set-WakeAllowed {
    param([string]$PnpDeviceId, [string]$DeviceName, [bool]$Allow)
    $deviceKey = Convert-NormalizedDeviceKey -Value $PnpDeviceId
    $wmiUpdated = $false
    
    # 1. Primary WMI integration (Immediately updates Device Manager state)
    try {
        $instances = Get-CimInstance -Namespace root/wmi -ClassName MSPower_DeviceWakeEnable -ErrorAction Stop
        foreach ($inst in $instances) {
            $baseName = $inst.InstanceName -replace '_[0-9]+$', ''
            $norm = Convert-NormalizedDeviceKey -Value $baseName
            if ($norm -eq $deviceKey -or $norm.StartsWith($deviceKey) -or $deviceKey.StartsWith($norm)) {
                $inst | Set-CimInstance -Property @{ Enable = $Allow } -ErrorAction Stop
                $wmiUpdated = $true
                break
            }
        }
    } catch { }

    if (-not $wmiUpdated) {
        try {
            $wmiObjs = Get-WmiObject -Namespace root/wmi -Class MSPower_DeviceWakeEnable -ErrorAction Stop
            foreach ($wmi in $wmiObjs) {
                $baseName = $wmi.InstanceName -replace '_[0-9]+$', ''
                $norm = Convert-NormalizedDeviceKey -Value $baseName
                if ($norm -eq $deviceKey -or $norm.StartsWith($deviceKey) -or $deviceKey.StartsWith($norm)) {
                    $wmi.Enable = $Allow
                    $wmi.Put() | Out-Null
                    $wmiUpdated = $true
                    break
                }
            }
        } catch {}
    }

    # 2. Fallback: powercfg
    if (-not $wmiUpdated -and (-not [string]::IsNullOrWhiteSpace($DeviceName))) {
        if ($Allow) { powercfg /deviceenablewake "$DeviceName" 2>$null | Out-Null }
        else { powercfg /devicedisablewake "$DeviceName" 2>$null | Out-Null }
    }
}

$form = [UsbPowerBulkGuiFactory]::CreateMainForm("$AppName v$AppVersion | By $AppAuthor")

$menuStrip = New-Object Windows.Forms.MenuStrip
$fileMenuItem = New-Object Windows.Forms.ToolStripMenuItem('&File')
$exitMenuItem = New-Object Windows.Forms.ToolStripMenuItem('E&xit')
$helpMenuItem = New-Object Windows.Forms.ToolStripMenuItem('&Help')
$aboutMenuItem = New-Object Windows.Forms.ToolStripMenuItem('&About')
[void]$fileMenuItem.DropDownItems.Add($exitMenuItem)
[void]$helpMenuItem.DropDownItems.Add($aboutMenuItem)
[void]$menuStrip.Items.Add($fileMenuItem)
[void]$menuStrip.Items.Add($helpMenuItem)
$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

$toggleSelect = New-Object Windows.Forms.Button
$toggleSelect.Location = New-Object Drawing.Point(20,40)
$toggleSelect.Size = New-Object Drawing.Size(150,32)
$toggleSelect.Text = 'Select All'
$form.Controls.Add($toggleSelect)

$refreshBtn = New-Object Windows.Forms.Button
$refreshBtn.Location = New-Object Drawing.Point(180,40)
$refreshBtn.Size = New-Object Drawing.Size(110,32)
$refreshBtn.Text = 'Refresh'
$form.Controls.Add($refreshBtn)

$searchLabel = New-Object Windows.Forms.Label
$searchLabel.Location = New-Object Drawing.Point(830,47)
$searchLabel.Size = New-Object Drawing.Size(70,24)
$searchLabel.Text = 'Search:'
$searchLabel.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($searchLabel)

$searchBox = New-Object Windows.Forms.TextBox
$searchBox.Location = New-Object Drawing.Point(900,43)
$searchBox.Size = New-Object Drawing.Size(360,30)
$searchBox.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($searchBox)

$grid = New-Object Windows.Forms.DataGridView
$grid.Location = New-Object Drawing.Point(20,85)
$grid.Size = New-Object Drawing.Size(1240,535)
$grid.AutoGenerateColumns = $false
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.RowHeadersVisible = $false
$grid.ScrollBars = [Windows.Forms.ScrollBars]::Both
$grid.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right

$selectedCol = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$selectedCol.Name = 'Selected'
$selectedCol.HeaderText = 'Selected'
$selectedCol.DataPropertyName = 'Selected'
$selectedCol.FillWeight = 12
$grid.Columns.Add($selectedCol) | Out-Null

foreach ($colName in @('Name','PnpDeviceId','Status','PowerSavingAllowed','WakeAllowed')) {
    $col = $null
    if ($colName -in @('PowerSavingAllowed','WakeAllowed')) {
        $col = New-Object Windows.Forms.DataGridViewCheckBoxColumn
        $col.ThreeState = $false
        $col.ReadOnly = $false
    } else {
        $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.ReadOnly = $true
    }

    $col.Name = $colName
    if ($colName -eq 'PnpDeviceId') { $col.HeaderText = 'Device ID' }
    elseif ($colName -eq 'PowerSavingAllowed') { $col.HeaderText = 'Power Saving Allowed' }
    elseif ($colName -eq 'WakeAllowed') { $col.HeaderText = 'Wake Allowed' }
    else { $col.HeaderText = $colName }
    
    $col.DataPropertyName = $colName
    $grid.Columns.Add($col) | Out-Null
}

$form.Controls.Add($grid)

$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [Windows.Forms.ScrollBars]::Vertical
$logBox.Location = New-Object Drawing.Point(20,630)
$logBox.Size = New-Object Drawing.Size(1240,250)
$logBox.Anchor = [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
$logBox.Font = New-Object Drawing.Font('Consolas', 10)
$logBox.BackColor = [Drawing.Color]::FromArgb(24,24,28)
$logBox.ForeColor = [Drawing.Color]::LightGray
$form.Controls.Add($logBox)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logBox.AppendText("[$timestamp] $Message`r`n")
}

$contextMenu = New-Object Windows.Forms.ContextMenuStrip
$ctxSelect = $contextMenu.Items.Add('Check Selected')
$ctxUnselect = $contextMenu.Items.Add('Uncheck Selected')
[void]$contextMenu.Items.Add('-')
$ctxEnableSaving = $contextMenu.Items.Add('Enable Power Saving')
$ctxDisableSaving = $contextMenu.Items.Add('Disable Power Saving')
$ctxEnableWake = $contextMenu.Items.Add('Enable Wake on Device')
$ctxDisableWake = $contextMenu.Items.Add('Disable Wake on Device')
$grid.ContextMenuStrip = $contextMenu

$script:deviceRows = @()
$script:allSelected = $false
$script:isBulkSelecting = $false

function Refresh-Grid {
    Write-Log "Refreshing device list from system..."
    $previouslySelected = @($script:deviceRows | Where-Object { $_.Selected } | Select-Object -ExpandProperty PnpDeviceId)
    
    $script:deviceRows = @(Get-PowerDevices | Sort-Object -Property Name)
    
    if ($previouslySelected.Count -gt 0) {
        foreach ($d in $script:deviceRows) {
            if ($d.PnpDeviceId -in $previouslySelected) {
                $d.Selected = $true
            }
        }
    }
    
    Show-GridRows
}

function Show-GridRows {
    $grid.Rows.Clear()
    $filter = $searchBox.Text
    $rowsToRender = $script:deviceRows
    if (-not [string]::IsNullOrWhiteSpace($filter)) {
        $rowsToRender = @(
            $script:deviceRows | Where-Object {
                $_.Name -like "*$filter*" -or $_.PnpDeviceId -like "*$filter*" -or $_.Status -like "*$filter*"
            }
        )
    }

    foreach ($device in $rowsToRender) {
        $rowIndex = $grid.Rows.Add(
            [bool]$device.Selected, 
            [string]$device.Name, 
            [string]$device.PnpDeviceId, 
            [string]$device.Status, 
            [bool]$device.PowerSavingAllowed, 
            [bool]$device.WakeAllowed
        )
        
        if (-not $device.PowerSavingToggleSupported) {
            $savingTextCell = New-Object Windows.Forms.DataGridViewTextBoxCell
            $savingTextCell.Value = 'Unavailable'
            $savingTextCell.Style.BackColor = [Drawing.Color]::LightGray
            $savingTextCell.Style.ForeColor = [Drawing.Color]::DimGray
            $savingTextCell.Style.SelectionBackColor = [Drawing.Color]::LightGray
            $savingTextCell.Style.SelectionForeColor = [Drawing.Color]::DimGray
            $savingTextCell.Style.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
            $savingTextCell.ToolTipText = 'Feature Unavailable for this device.'
            $grid.Rows[$rowIndex].Cells['PowerSavingAllowed'] = $savingTextCell
            $grid.Rows[$rowIndex].Cells['PowerSavingAllowed'].ReadOnly = $true
        }
        if (-not $device.WakeToggleSupported) {
            $wakeTextCell = New-Object Windows.Forms.DataGridViewTextBoxCell
            $wakeTextCell.Value = 'Unavailable'
            $wakeTextCell.Style.BackColor = [Drawing.Color]::LightGray
            $wakeTextCell.Style.ForeColor = [Drawing.Color]::DimGray
            $wakeTextCell.Style.SelectionBackColor = [Drawing.Color]::LightGray
            $wakeTextCell.Style.SelectionForeColor = [Drawing.Color]::DimGray
            $wakeTextCell.Style.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
            $wakeTextCell.ToolTipText = 'Feature Unavailable for this device.'
            $grid.Rows[$rowIndex].Cells['WakeAllowed'] = $wakeTextCell
            $grid.Rows[$rowIndex].Cells['WakeAllowed'].ReadOnly = $true
        }
        $grid.Rows[$rowIndex].Tag = $device
    }

    Write-Log "Found $($script:deviceRows.Count) manageable devices. Showing $($rowsToRender.Count)."
}

function Get-SelectedRows {
    $checked = @($script:deviceRows | Where-Object { $_.Selected })
    if ($checked.Count -gt 0) { return $checked }
    
    $highlighted = @()
    foreach ($row in $grid.SelectedRows) {
        if ($null -ne $row.Tag) { $highlighted += $row.Tag }
    }
    return $highlighted
}


function Set-SelectedState {
    param([bool]$Value)

    foreach ($row in @($grid.SelectedRows)) {
        $row.Cells['Selected'].Value = $Value
        $device = $row.Tag
        if ($null -ne $device) { $device.Selected = $Value }
    }
}

function Apply-Bulk {
    param([scriptblock]$Action,[string]$ActionName)
    if (-not (Test-IsAdministrator)) {
        [Windows.Forms.MessageBox]::Show('Run this app as Administrator for bulk changes.','Permission Required','OK','Warning') | Out-Null
        Write-Log "Failed: Administrator permissions required for bulk changes."
        return
    }

    $targets = @(Get-SelectedRows)
    
    # Safely enforce unique devices by their ID to prevent PowerShell 
    # from accidentally stripping out objects during a generic -Unique call.
    $uniqueTargets = @{}
    foreach ($t in $targets) {
        if ($null -ne $t -and $null -ne $t.PnpDeviceId) {
            $uniqueTargets[$t.PnpDeviceId] = $t
        }
    }

    if ($uniqueTargets.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show('Select at least one device first.','No Selection','OK','Information') | Out-Null
        Write-Log "Failed: No devices selected for bulk action."
        return
    }

    Write-Log "Starting bulk action: $ActionName on $($uniqueTargets.Count) devices..."
    foreach ($t in $uniqueTargets.Values) { & $Action $t }
    Refresh-Grid
    Write-Log "Completed bulk action: $ActionName."
}


$grid.add_CellValueChanged({
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0 -or $script:isBulkSelecting) { return }

    $columnName = $grid.Columns[$e.ColumnIndex].Name
    $row = $grid.Rows[$e.RowIndex]
    $device = $row.Tag
    
    if ($null -eq $device) { return }

    $targetRows = @()
    if ($row.Selected -and $grid.SelectedRows.Count -gt 1) {
        $targetRows = @($grid.SelectedRows)
    } else {
        $targetRows = @($row)
    }

    if ($columnName -eq 'Selected') {
        $newValue = [bool]$row.Cells[$e.ColumnIndex].Value
        $script:isBulkSelecting = $true
        try {
            foreach ($r in $targetRows) {
                $r.Cells['Selected'].Value = $newValue
                $d = $r.Tag
                if ($null -ne $d) { $d.Selected = $newValue }
            }
        } finally {
            $script:isBulkSelecting = $false
        }
    }
    elseif ($columnName -eq 'PowerSavingAllowed') {
        if (-not (Test-IsAdministrator)) {
            [Windows.Forms.MessageBox]::Show('Run this app as Administrator to change settings.','Permission Required','OK','Warning') | Out-Null
            Write-Log "Failed to change Power Saving: Administrator permissions required."
            $script:isBulkSelecting = $true
            $row.Cells[$e.ColumnIndex].Value = [bool]$device.PowerSavingAllowed
            $script:isBulkSelecting = $false
            return
        }
        $newValue = [bool]$row.Cells[$e.ColumnIndex].Value
        $script:isBulkSelecting = $true
        try {
            foreach ($r in $targetRows) {
                $d = $r.Tag
                if ($null -ne $d -and $d.PowerSavingToggleSupported) {
                    Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $newValue
                    $d.PowerSavingAllowed = $newValue
                    $r.Cells[$e.ColumnIndex].Value = $newValue
                    $actionText = if ($newValue) { "Enabled" } else { "Disabled" }
                    Write-Log "$actionText Power Saving for: $($d.Name)"
                }
            }
        } finally {
            $script:isBulkSelecting = $false
        }
    }
    elseif ($columnName -eq 'WakeAllowed') {
        if (-not (Test-IsAdministrator)) {
            [Windows.Forms.MessageBox]::Show('Run this app as Administrator to change settings.','Permission Required','OK','Warning') | Out-Null
            Write-Log "Failed to change Wake Allowed: Administrator permissions required."
            $script:isBulkSelecting = $true
            $row.Cells[$e.ColumnIndex].Value = [bool]$device.WakeAllowed
            $script:isBulkSelecting = $false
            return
        }
        $newValue = [bool]$row.Cells[$e.ColumnIndex].Value
        $script:isBulkSelecting = $true
        try {
            foreach ($r in $targetRows) {
                $d = $r.Tag
                if ($null -ne $d -and $d.WakeToggleSupported) {
                    Set-WakeAllowed -PnpDeviceId $d.PnpDeviceId -DeviceName $d.Name -Allow $newValue
                    $d.WakeAllowed = $newValue
                    $r.Cells[$e.ColumnIndex].Value = $newValue
                    $actionText = if ($newValue) { "Enabled" } else { "Disabled" }
                    Write-Log "$actionText Wake on Device for: $($d.Name)"
                }
            }
        } finally {
            $script:isBulkSelecting = $false
        }
    }
})

$grid.add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$grid.add_DataError({
    param($sender, $e)
    $e.ThrowException = $false
    $e.Cancel = $false
})


$grid.add_CellMouseDown({
    param($sender, $e)
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Right -or $e.RowIndex -lt 0) { return }

    if (-not $grid.Rows[$e.RowIndex].Selected) {
        $grid.ClearSelection()
        $grid.Rows[$e.RowIndex].Selected = $true
    }
})

$ctxSelect.add_Click({ Set-SelectedState -Value $true })
$ctxUnselect.add_Click({ Set-SelectedState -Value $false })
$ctxDisableSaving.add_Click({ Apply-Bulk -Action { param($d) if ($d.PowerSavingToggleSupported) { Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $false; Write-Log "Disabled Power Saving for: $($d.Name)" } } -ActionName 'Power-saving disable' })
$ctxEnableSaving.add_Click({ Apply-Bulk -Action { param($d) if ($d.PowerSavingToggleSupported) { Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $true; Write-Log "Enabled Power Saving for: $($d.Name)" } } -ActionName 'Power-saving enable' })
$ctxEnableWake.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -PnpDeviceId $d.PnpDeviceId -DeviceName $d.Name -Allow $true; Write-Log "Enabled Wake on Device for: $($d.Name)" } } -ActionName 'Wake enable' })
$ctxDisableWake.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -PnpDeviceId $d.PnpDeviceId -DeviceName $d.Name -Allow $false; Write-Log "Disabled Wake on Device for: $($d.Name)" } } -ActionName 'Wake disable' })

$exitMenuItem.add_Click({ $form.Close() })
$aboutMenuItem.add_Click({
    $about = New-Object Windows.Forms.Form
    $about.Text = "About $AppName"
    $about.Size = New-Object Drawing.Size(700,420)
    $about.StartPosition = [Windows.Forms.FormStartPosition]::CenterParent
    $about.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
    $about.MaximizeBox = $false
    $about.MinimizeBox = $false
    $about.BackColor = [Drawing.Color]::FromArgb(24,24,28)

    $titleLabel = New-Object Windows.Forms.Label
    $titleLabel.Text = $AppName
    $titleLabel.ForeColor = [Drawing.Color]::White
    $titleLabel.Font = New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object Drawing.Point(20,16)
    $titleLabel.Size = New-Object Drawing.Size(640,40)
    $about.Controls.Add($titleLabel)

    $versionLabel = New-Object Windows.Forms.Label
    $versionLabel.Text = "Version $AppVersion"
    $versionLabel.ForeColor = [Drawing.Color]::FromArgb(130,200,255)
    $versionLabel.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Regular)
    $versionLabel.Location = New-Object Drawing.Point(22,55)
    $versionLabel.Size = New-Object Drawing.Size(300,24)
    $about.Controls.Add($versionLabel)

    $summaryBox = New-Object Windows.Forms.RichTextBox
    $summaryBox.ReadOnly = $true
    $summaryBox.BorderStyle = [Windows.Forms.BorderStyle]::None
    $summaryBox.BackColor = [Drawing.Color]::FromArgb(32,32,38)
    $summaryBox.ForeColor = [Drawing.Color]::Gainsboro
    $summaryBox.Location = New-Object Drawing.Point(20,92)
    $summaryBox.Size = New-Object Drawing.Size(650,190)
    $summaryBox.Font = New-Object Drawing.Font('Segoe UI',10)
    $summaryBox.DetectUrls = $true
    $summaryBox.Text = @"
Summary:
  Device Power Bulk Manager helps administrators quickly review and apply power-management settings to any capable device.

Purpose:
  Provide a central, bulk-friendly interface for selecting devices and changing power saving and wake behavior.

Usage:
  1. Refresh to load active devices.
  2. Select devices (single, Ctrl+click, or Shift+click).
  3. Use toolbar buttons or right-click actions to enable/disable settings.
"@
    $about.Controls.Add($summaryBox)

    $authorLabel = New-Object Windows.Forms.Label
    $authorLabel.Text = 'Author'
    $authorLabel.ForeColor = [Drawing.Color]::WhiteSmoke
    $authorLabel.Font = New-Object Drawing.Font('Segoe UI Semibold',11,[Drawing.FontStyle]::Bold)
    $authorLabel.Location = New-Object Drawing.Point(20,294)
    $authorLabel.Size = New-Object Drawing.Size(120,25)
    $about.Controls.Add($authorLabel)

    $authorLink = New-Object Windows.Forms.LinkLabel
    $authorLink.Text = 'Joshua Dwight'
    $authorLink.LinkColor = [Drawing.Color]::FromArgb(90,170,255)
    $authorLink.ActiveLinkColor = [Drawing.Color]::FromArgb(130,210,255)
    $authorLink.VisitedLinkColor = [Drawing.Color]::FromArgb(90,170,255)
    $authorLink.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Underline)
    $authorLink.Location = New-Object Drawing.Point(20,320)
    $authorLink.Size = New-Object Drawing.Size(300,28)
    $authorLink.Tag = 'https://github.com/joshdwight101'
    $authorLink.add_LinkClicked({
        param($sender,$e)
        Start-Process $sender.Tag
    })
    $about.Controls.Add($authorLink)

    $urlLink = New-Object Windows.Forms.LinkLabel
    $urlLink.Text = 'https://github.com/joshdwight101'
    $urlLink.LinkColor = [Drawing.Color]::FromArgb(90,170,255)
    $urlLink.ActiveLinkColor = [Drawing.Color]::FromArgb(130,210,255)
    $urlLink.VisitedLinkColor = [Drawing.Color]::FromArgb(90,170,255)
    $urlLink.Font = New-Object Drawing.Font('Consolas',10)
    $urlLink.Location = New-Object Drawing.Point(20,348)
    $urlLink.Size = New-Object Drawing.Size(420,24)
    $urlLink.Tag = 'https://github.com/joshdwight101'
    $urlLink.add_LinkClicked({
        param($sender,$e)
        Start-Process $sender.Tag
    })
    $about.Controls.Add($urlLink)

    [void]$about.ShowDialog($form)
})

$toggleSelect.add_Click({
    $script:allSelected = -not $script:allSelected
    for ($i = 0; $i -lt $script:deviceRows.Count; $i++) {
        if ($i -lt $grid.Rows.Count) {
            $grid.Rows[$i].Cells['Selected'].Value = $script:allSelected
        }
        $script:deviceRows[$i].Selected = $script:allSelected
    }

    $toggleSelect.Text = if ($script:allSelected) { 'Select None' } else { 'Select All' }
})

$refreshBtn.add_Click({ Refresh-Grid })
$searchBox.add_TextChanged({ Show-GridRows })

Refresh-Grid
[void]$form.ShowDialog()
# SIG # Begin signature block
# MIIFiwYJKoZIhvcNAQcCoIIFfDCCBXgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU4fY4EMzlwXdl9qNeap87EQmZ
# oH6gggMcMIIDGDCCAgCgAwIBAgIQdTnGUb3fnrZCF1K2xTtGMjANBgkqhkiG9w0B
# AQsFADAkMSIwIAYDVQQDDBlDSEVTSS1KRENvZGUtU2lnbmluZy0yMDI2MB4XDTI2
# MDMwNjE0NDY0NVoXDTI3MDMwNjE0NDY0NVowJDEiMCAGA1UEAwwZQ0hFU0ktSkRD
# b2RlLVNpZ25pbmctMjAyNjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
# AMIvE+cjfWSthiMrydvmvgrd9ucGb77R+W5jS2EfE73xAMxLBjZBbfTdh8Ig1Oj2
# aZuTWPwXoETEdh4ocXbtyYX0WDXqnNwSzDGDLKNiMzQ2bJEgfeegSGazOCUXchya
# x82YR81WyxGd4sIqBBC3JpFxr+O6MZHHtqUHkkHyUY1Q8phH40X6UOH+l7AIB3yC
# zxqyEJ68RNQFh4UhD2dS4DneN0xyPlQ/VhXcMF4dONwQz7lSIIgD+iiJzXo9Ka7F
# ZOGm1jtq7i/p3XwLuq3zMxgeHh3VcVWh2QbO2PODgIxtchRMFBkW5BtiBjV5nSs7
# D879uPSkhTEGk2UAHDDsbKkCAwEAAaNGMEQwDgYDVR0PAQH/BAQDAgeAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQGI/EgF0UkEE5pOr6J/upQmqqo2jAN
# BgkqhkiG9w0BAQsFAAOCAQEABPRv9v2ibkmhWvzlXApwWNScLZ2c6r1ErdcIYEDf
# UHMPwiWV8ztOT9cK6NunF9VjPSb/dCxu2OU+F+HGl1utqoTtPMV+95p9ctwu12KR
# 20/JxfmfoGu1dTYQYZZeWapbBNOwwPg3GEti2PNHMCI+QBSN3MbnfABwVFs9T2X+
# 7tQaOdAhY1kqp8siaCoCpwcoGWlhDdO6+hCrI3Qz5oWN/hMCrL6Sm3afgDoh8xzB
# fxnNdcwQq2+etj+JM9Gcz+C8fUnlZmKPn+wEsMS+oZqfEUt5HEzEIe8LVuuub/Ah
# 8eTO2IA6ouL9V9TyN0aWtV2l0qoqyoY+odq6v1QPInnLfDGCAdkwggHVAgEBMDgw
# JDEiMCAGA1UEAwwZQ0hFU0ktSkRDb2RlLVNpZ25pbmctMjAyNgIQdTnGUb3fnrZC
# F1K2xTtGMjAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUt/sBqi6u6GBAFYqSDIz/4eOgylMwDQYJ
# KoZIhvcNAQEBBQAEggEAD6T7qdTr2OwT76JKK1+TU2N/O5GdO06Miv9oaydcLyU2
# 7bb8yckvMdAB6cl0QYR8EuCFkiWkxSSJFQCqin0JWZVAGdaVZF+3F+u/Gk1Y299L
# oI5AcUdi0vbDflNHFvekKedD8VAS9rBT0nF0yI5zHLn0fgH7oBhdjGlfedG7TSgn
# yi2pjxLWfk9z3HpcCJSEZ/kWaPpbAMt+2EJ0WKsmt7FLBJYyMv1AN/g5BaOdvZIY
# 3UbJUy1z4EeOfmtIq0DFvM9hQOxnu5AY07dcTbaz5rPeHz9twW/P9J45m0RwPtqT
# M7691lTCemIup/mrHA6EzXd7LSLPM0KFNTPTAfidIw==
# SIG # End signature block
