Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppName = 'USB Power Bulk Manager'
$AppVersion = '1.0.0'
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
        form.Size = new Size(1300, 820);
        form.StartPosition = FormStartPosition.CenterScreen;
        return form;
    }
}
"@
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')

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

function Get-UsbDevices {
    $wakeArmedDevices = Get-PowerCfgDeviceSet -QueryType 'wake_armed'
    $wakeProgrammableDevices = Get-PowerCfgDeviceSet -QueryType 'wake_programmable'

    $devices = Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like 'USB*' -and $_.ConfigManagerErrorCode -eq 0 }
    foreach ($d in $devices) {
        $wakeSupported = $wakeProgrammableDevices.Contains($d.Name)
        [pscustomobject]@{
            Selected = $false
            Name = $d.Name
            PnpDeviceId = $d.PNPDeviceID
            Status = $d.Status
            PowerSavingAllowed = (Get-PowerSavingAllowed -PnpDeviceId $d.PNPDeviceID)
            WakeAllowed = ($wakeSupported -and $wakeArmedDevices.Contains($d.Name))
            WakeToggleSupported = $wakeSupported
        }
    }
}

function Get-PowerSavingAllowed {
    param([string]$PnpDeviceId)
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$PnpDeviceId\Device Parameters"
        $value = (Get-ItemProperty -Path $regPath -Name PnPCapabilities -ErrorAction Stop).PnPCapabilities
        return -not (($value -band 0x20) -eq 0x20)
    } catch { return $true }
}

function Set-PowerSavingAllowed {
    param([string]$PnpDeviceId,[bool]$Allow)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$PnpDeviceId\Device Parameters"
    if (-not (Test-Path $regPath)) { return }
    $current = 0
    try { $current = (Get-ItemProperty -Path $regPath -Name PnPCapabilities -ErrorAction Stop).PnPCapabilities } catch {}

    if ($Allow) { $newValue = ($current -band (-bnot 0x20)) } else { $newValue = ($current -bor 0x20) }
    New-ItemProperty -Path $regPath -Name PnPCapabilities -PropertyType DWord -Value $newValue -Force | Out-Null
}

function Set-WakeAllowed {
    param([string]$DeviceName,[bool]$Allow)
    if ($Allow) { powercfg /deviceenablewake "$DeviceName" | Out-Null }
    else { powercfg /devicedisablewake "$DeviceName" | Out-Null }
}

$form = [UsbPowerBulkGuiFactory]::CreateMainForm("$AppName v$AppVersion | By $AppAuthor")

$banner = New-Object Windows.Forms.Label
$banner.Location = New-Object Drawing.Point(15,15)
$banner.Size = New-Object Drawing.Size(1200,24)
$banner.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$banner.Text = 'USB bulk power-management controller'
$form.Controls.Add($banner)

$toggleSelect = New-Object Windows.Forms.Button
$toggleSelect.Location = New-Object Drawing.Point(15,50)
$toggleSelect.Size = New-Object Drawing.Size(150,32)
$toggleSelect.Text = 'Select All'
$form.Controls.Add($toggleSelect)

$refreshBtn = New-Object Windows.Forms.Button
$refreshBtn.Location = New-Object Drawing.Point(175,50)
$refreshBtn.Size = New-Object Drawing.Size(110,32)
$refreshBtn.Text = 'Refresh'
$form.Controls.Add($refreshBtn)

$disableSavingBtn = New-Object Windows.Forms.Button
$disableSavingBtn.Location = New-Object Drawing.Point(305,50)
$disableSavingBtn.Size = New-Object Drawing.Size(220,32)
$disableSavingBtn.Text = 'Disable Power Saving (Uncheck)'
$form.Controls.Add($disableSavingBtn)

$enableSavingBtn = New-Object Windows.Forms.Button
$enableSavingBtn.Location = New-Object Drawing.Point(535,50)
$enableSavingBtn.Size = New-Object Drawing.Size(220,32)
$enableSavingBtn.Text = 'Enable Power Saving (Check)'
$form.Controls.Add($enableSavingBtn)

$disableWakeBtn = New-Object Windows.Forms.Button
$disableWakeBtn.Location = New-Object Drawing.Point(765,50)
$disableWakeBtn.Size = New-Object Drawing.Size(220,32)
$disableWakeBtn.Text = 'Disable Wake on USB'
$form.Controls.Add($disableWakeBtn)

$enableWakeBtn = New-Object Windows.Forms.Button
$enableWakeBtn.Location = New-Object Drawing.Point(995,50)
$enableWakeBtn.Size = New-Object Drawing.Size(220,32)
$enableWakeBtn.Text = 'Enable Wake on USB'
$form.Controls.Add($enableWakeBtn)

$grid = New-Object Windows.Forms.DataGridView
$grid.Location = New-Object Drawing.Point(15,95)
$grid.Size = New-Object Drawing.Size(1240,640)
$grid.AutoGenerateColumns = $false
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.RowHeadersVisible = $false

$selectedCol = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$selectedCol.Name = 'Selected'
$selectedCol.HeaderText = 'Selected'
$selectedCol.DataPropertyName = 'Selected'
$selectedCol.FillWeight = 12
$grid.Columns.Add($selectedCol) | Out-Null

foreach ($colName in @('Name','PnpDeviceId','Status','PowerSavingAllowed','WakeAllowed')) {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    if ($colName -in @('PowerSavingAllowed','WakeAllowed')) {
        $col = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    }
    $col.Name = $colName
    $col.HeaderText = $colName
    $col.DataPropertyName = $colName
    $col.ReadOnly = ($colName -ne 'Selected')
    $grid.Columns.Add($col) | Out-Null
}

$form.Controls.Add($grid)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(15,745)
$status.Size = New-Object Drawing.Size(1240,24)
$form.Controls.Add($status)


$contextMenu = New-Object Windows.Forms.ContextMenuStrip
$ctxSelect = $contextMenu.Items.Add('Check Selected')
$ctxUnselect = $contextMenu.Items.Add('Uncheck Selected')
[void]$contextMenu.Items.Add('-')
$ctxEnableSaving = $contextMenu.Items.Add('Enable Power Saving')
$ctxDisableSaving = $contextMenu.Items.Add('Disable Power Saving')
$ctxEnableWake = $contextMenu.Items.Add('Enable Wake on USB')
$ctxDisableWake = $contextMenu.Items.Add('Disable Wake on USB')
$grid.ContextMenuStrip = $contextMenu

$script:deviceRows = @()
$script:allSelected = $false
$script:isBulkSelecting = $false

function Refresh-Grid {
    $script:deviceRows = @(Get-UsbDevices)
    $grid.Rows.Clear()

    foreach ($device in $script:deviceRows) {
        $rowIndex = $grid.Rows.Add($device.Selected, $device.Name, $device.PnpDeviceId, $device.Status, $device.PowerSavingAllowed, $device.WakeAllowed)
        if (-not $device.WakeToggleSupported) {
            $wakeCell = $grid.Rows[$rowIndex].Cells['WakeAllowed']
            $wakeCell.ReadOnly = $true
            $wakeCell.Style.BackColor = [Drawing.Color]::LightGray
            $wakeCell.ToolTipText = 'Wake on USB is not supported for this device.'
        }
    }

    $status.Text = "Loaded $($script:deviceRows.Count) USB devices."
}

function Get-SelectedRows {
    return @($script:deviceRows | Where-Object { $_.Selected })
}


function Set-SelectedState {
    param([bool]$Value)

    foreach ($row in @($grid.SelectedRows)) {
        $row.Cells['Selected'].Value = $Value
        $script:deviceRows[$row.Index].Selected = $Value
    }
}

function Apply-Bulk {
    param([scriptblock]$Action,[string]$ActionName)
    if (-not (Test-IsAdministrator)) {
        [Windows.Forms.MessageBox]::Show('Run this app as Administrator for bulk changes.','Permission Required','OK','Warning') | Out-Null
        return
    }

    $targets = Get-SelectedRows
    if ($targets.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show('Select at least one USB device first.','No Selection','OK','Information') | Out-Null
        return
    }

    foreach ($t in $targets) { & $Action $t }
    Refresh-Grid
    $status.Text = "$ActionName completed for $($targets.Count) selected devices."
}


$grid.add_CellValueChanged({
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0 -or $script:isBulkSelecting) { return }

    $columnName = $grid.Columns[$e.ColumnIndex].Name
    if ($columnName -ne 'Selected') { return }

    $newValue = [bool]$grid.Rows[$e.RowIndex].Cells[$e.ColumnIndex].Value

    $targetRows = @()
    if ($grid.Rows[$e.RowIndex].Selected -and $grid.SelectedRows.Count -gt 1) {
        $targetRows = @($grid.SelectedRows)
    } else {
        $targetRows = @($grid.Rows[$e.RowIndex])
    }

    $script:isBulkSelecting = $true
    try {
        foreach ($row in $targetRows) {
            $row.Cells['Selected'].Value = $newValue
            $script:deviceRows[$row.Index].Selected = $newValue
        }
    } finally {
        $script:isBulkSelecting = $false
    }
})

$grid.add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})


$grid.add_CellPainting({
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0) { return }
    if ($grid.Columns[$e.ColumnIndex].Name -ne 'WakeAllowed') { return }
    if ($script:deviceRows[$e.RowIndex].WakeToggleSupported) { return }

    $e.PaintBackground($e.CellBounds, $true)
    $e.PaintContent($e.CellBounds)

    $pen = New-Object Drawing.Pen([Drawing.Color]::Red, 3)
    $pad = 4
    $e.Graphics.DrawLine($pen, $e.CellBounds.Left + $pad, $e.CellBounds.Top + $pad, $e.CellBounds.Right - $pad, $e.CellBounds.Bottom - $pad)
    $e.Graphics.DrawLine($pen, $e.CellBounds.Right - $pad, $e.CellBounds.Top + $pad, $e.CellBounds.Left + $pad, $e.CellBounds.Bottom - $pad)
    $pen.Dispose()
    $e.Handled = $true
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
$ctxEnableSaving.add_Click({ Apply-Bulk -Action { param($d) Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $true } -ActionName 'Power-saving enable (context)' })
$ctxDisableSaving.add_Click({ Apply-Bulk -Action { param($d) Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $false } -ActionName 'Power-saving disable (context)' })
$ctxEnableWake.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -DeviceName $d.Name -Allow $true } } -ActionName 'Wake enable (context)' })
$ctxDisableWake.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -DeviceName $d.Name -Allow $false } } -ActionName 'Wake disable (context)' })

$toggleSelect.add_Click({
    $script:allSelected = -not $script:allSelected
    for ($i = 0; $i -lt $script:deviceRows.Count; $i++) {
        $script:deviceRows[$i].Selected = $script:allSelected
        $grid.Rows[$i].Cells['Selected'].Value = $script:allSelected
    }

    $toggleSelect.Text = if ($script:allSelected) { 'Select None' } else { 'Select All' }
})

$refreshBtn.add_Click({ Refresh-Grid })
$disableSavingBtn.add_Click({ Apply-Bulk -Action { param($d) Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $false } -ActionName 'Power-saving disable' })
$enableSavingBtn.add_Click({ Apply-Bulk -Action { param($d) Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $true } -ActionName 'Power-saving enable' })
$disableWakeBtn.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -DeviceName $d.Name -Allow $false } } -ActionName 'Wake disable' })
$enableWakeBtn.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -DeviceName $d.Name -Allow $true } } -ActionName 'Wake enable' })

Refresh-Grid
[void]$form.ShowDialog()
