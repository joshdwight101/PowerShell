<#
.SYNOPSIS
USB Power Bulk Manager (v1.1.1)

.DESCRIPTION
WinForms utility for bulk USB power-management administration with capability-aware controls,
search filtering, multi-select workflows, context-menu actions, and an About dialog.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppName = 'USB Power Bulk Manager'
$AppVersion = '1.1.1'
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
        form.Size = new Size(1300, 940);
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

function Get-UsbDevices {
    $wakeArmedDevices = Get-PowerCfgDeviceSet -QueryType 'wake_armed'
    $wakeProgrammableDevices = Get-PowerCfgDeviceSet -QueryType 'wake_programmable'
    $wakeDetectionAvailable = (@($wakeProgrammableDevices).Count -gt 0)

    $devices = @()
    try {
        $devices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like 'USB*' })
    } catch {}
    if ($devices.Count -eq 0) {
        try {
            $devices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -like '*USB*' -or $_.Service -like 'USB*' })
        } catch {}
    }
    if ($devices.Count -eq 0 -and (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        try {
            $devices = @(
                Get-PnpDevice -PresentOnly -ErrorAction Stop |
                    Where-Object { $_.InstanceId -like 'USB*' } |
                    ForEach-Object {
                        [pscustomobject]@{
                            Name = $_.FriendlyName
                            PNPDeviceID = $_.InstanceId
                            Status = $_.Status
                        }
                    }
            )
        } catch {}
    }

    $devices = @($devices | Sort-Object -Property PNPDeviceID -Unique)
    foreach ($d in $devices) {
        $wakeSupported = $wakeDetectionAvailable -and ($wakeProgrammableDevices.Contains($d.Name) -or $wakeProgrammableDevices.Contains($d.PNPDeviceID))
        if (-not $wakeDetectionAvailable) { $wakeSupported = $true }
        $powerSavingState = Get-PowerSavingState -PnpDeviceId $d.PNPDeviceID
        $powerSupported = $powerSavingState.Supported
        [pscustomobject]@{
            Selected = $false
            Name = $d.Name
            PnpDeviceId = $d.PNPDeviceID
            Status = $d.Status
            PowerSavingAllowed = $powerSavingState.Allowed
            PowerSavingToggleSupported = $powerSupported
            WakeAllowed = ($wakeSupported -and $wakeArmedDevices.Contains($d.Name))
            WakeToggleSupported = $wakeSupported
        }
    }
}

function Get-PowerSavingState {
    param([string]$PnpDeviceId)
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$PnpDeviceId\Device Parameters"
        if (-not (Test-Path -LiteralPath $regPath)) {
            return @{
                Supported = $true
                Allowed = $true
            }
        }

        $value = (Get-ItemProperty -LiteralPath $regPath -Name PnPCapabilities -ErrorAction SilentlyContinue).PnPCapabilities
        if ($null -eq $value) {
            return @{
                Supported = $true
                Allowed = $true
            }
        }

        return @{
            Supported = $true
            Allowed = (-not (($value -band 0x20) -eq 0x20))
        }
    } catch {
        return @{
            Supported = $false
            Allowed = $false
        }
    }
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

$banner = New-Object Windows.Forms.Label
$banner.Location = New-Object Drawing.Point(15,40)
$banner.Size = New-Object Drawing.Size(1200,24)
$banner.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$banner.Text = 'USB bulk power-management controller'
$form.Controls.Add($banner)

$toggleSelect = New-Object Windows.Forms.Button
$toggleSelect.Location = New-Object Drawing.Point(15,75)
$toggleSelect.Size = New-Object Drawing.Size(150,32)
$toggleSelect.Text = 'Select All'
$form.Controls.Add($toggleSelect)

$refreshBtn = New-Object Windows.Forms.Button
$refreshBtn.Location = New-Object Drawing.Point(175,75)
$refreshBtn.Size = New-Object Drawing.Size(110,32)
$refreshBtn.Text = 'Refresh'
$form.Controls.Add($refreshBtn)

$searchLabel = New-Object Windows.Forms.Label
$searchLabel.Location = New-Object Drawing.Point(305,82)
$searchLabel.Size = New-Object Drawing.Size(70,24)
$searchLabel.Text = 'Search:'
$form.Controls.Add($searchLabel)

$searchBox = New-Object Windows.Forms.TextBox
$searchBox.Location = New-Object Drawing.Point(370,78)
$searchBox.Size = New-Object Drawing.Size(360,30)
$form.Controls.Add($searchBox)

$grid = New-Object Windows.Forms.DataGridView
$grid.Location = New-Object Drawing.Point(15,120)
$grid.Size = New-Object Drawing.Size(1240,660)
$grid.AutoGenerateColumns = $false
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.RowHeadersVisible = $false
$grid.ScrollBars = [Windows.Forms.ScrollBars]::Both

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
    if ($colName -eq 'WakeAllowed' -and $col -is [Windows.Forms.DataGridViewCheckBoxColumn]) {
        $col.ThreeState = $false
    }
    $grid.Columns.Add($col) | Out-Null
}

$form.Controls.Add($grid)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(15,855)
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
    $script:deviceRows = @(Get-UsbDevices | Sort-Object -Property Name)
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
        $rowIndex = $grid.Rows.Add($device.Selected, $device.Name, $device.PnpDeviceId, $device.Status, $device.PowerSavingAllowed, $device.WakeAllowed)
        if (-not $device.PowerSavingToggleSupported) {
            $savingTextCell = New-Object Windows.Forms.DataGridViewTextBoxCell
            $savingTextCell.Value = 'Feature Unavailable for this device.'
            $savingTextCell.Style.BackColor = [Drawing.Color]::LightGray
            $savingTextCell.Style.ForeColor = [Drawing.Color]::DimGray
            $savingTextCell.Style.SelectionBackColor = [Drawing.Color]::LightGray
            $savingTextCell.Style.SelectionForeColor = [Drawing.Color]::DimGray
            $savingTextCell.Style.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
            $savingTextCell.ToolTipText = 'Feature Unavailable for this device.'
            $grid.Rows[$rowIndex].Cells['PowerSavingAllowed'] = $savingTextCell
            $grid.Rows[$rowIndex].Cells['PowerSavingAllowed'].ReadOnly = $true
        }
        if (-not $device.WakeToggleSupported) {
            $wakeTextCell = New-Object Windows.Forms.DataGridViewTextBoxCell
            $wakeTextCell.Value = 'Feature Unavailable for this device.'
            $wakeTextCell.Style.BackColor = [Drawing.Color]::LightGray
            $wakeTextCell.Style.ForeColor = [Drawing.Color]::DimGray
            $wakeTextCell.Style.SelectionBackColor = [Drawing.Color]::LightGray
            $wakeTextCell.Style.SelectionForeColor = [Drawing.Color]::DimGray
            $wakeTextCell.Style.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
            $wakeTextCell.ToolTipText = 'Feature Unavailable for this device.'
            $grid.Rows[$rowIndex].Cells['WakeAllowed'] = $wakeTextCell
            $grid.Rows[$rowIndex].Cells['WakeAllowed'].ReadOnly = $true
        }
        $grid.Rows[$rowIndex].Tag = $device
    }

    $status.Text = "Loaded $($script:deviceRows.Count) USB devices. Showing $($rowsToRender.Count)."
}

function Get-SelectedRows {
    return @($script:deviceRows | Where-Object { $_.Selected })
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
            $device = $row.Tag
            if ($null -ne $device) { $device.Selected = $newValue }
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
$ctxDisableSaving.add_Click({ Apply-Bulk -Action { param($d) if ($d.PowerSavingToggleSupported) { Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $false } } -ActionName 'Power-saving disable (context)' })
$ctxEnableSaving.add_Click({ Apply-Bulk -Action { param($d) if ($d.PowerSavingToggleSupported) { Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $true } } -ActionName 'Power-saving enable (context)' })
$ctxEnableWake.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -DeviceName $d.Name -Allow $true } } -ActionName 'Wake enable (context)' })
$ctxDisableWake.add_Click({ Apply-Bulk -Action { param($d) if ($d.WakeToggleSupported) { Set-WakeAllowed -DeviceName $d.Name -Allow $false } } -ActionName 'Wake disable (context)' })

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
  USB Power Bulk Manager helps administrators quickly review and apply USB power-management settings.

Purpose:
  Provide a central, bulk-friendly interface for selecting USB devices and changing power saving and wake behavior.

Usage:
  1. Refresh to load active USB devices.
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
