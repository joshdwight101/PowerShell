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

function Get-UsbDevices {
    $devices = Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like 'USB*' -and $_.ConfigManagerErrorCode -eq 0 }
    foreach ($d in $devices) {
        [pscustomobject]@{
            Selected = $false
            Name = $d.Name
            PnpDeviceId = $d.PNPDeviceID
            Status = $d.Status
            PowerSavingAllowed = (Get-PowerSavingAllowed -PnpDeviceId $d.PNPDeviceID)
            WakeAllowed = (Get-WakeAllowed -DeviceName $d.Name)
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

function Get-WakeAllowed {
    param([string]$DeviceName)
    $out = powercfg /devicequery wake_armed 2>$null
    return $out -contains $DeviceName
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
$grid.AutoSizeColumnsMode = 'Fill'
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$form.Controls.Add($grid)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(15,745)
$status.Size = New-Object Drawing.Size(1240,24)
$form.Controls.Add($status)

$script:deviceRows = @()
$script:allSelected = $false

function Refresh-Grid {
    $script:deviceRows = @(Get-UsbDevices)
    $grid.DataSource = $null
    $grid.DataSource = $script:deviceRows
    $status.Text = "Loaded $($script:deviceRows.Count) USB devices."
}

function Get-SelectedRows {
    return @($script:deviceRows | Where-Object { $_.Selected })
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

$toggleSelect.add_Click({
    $script:allSelected = -not $script:allSelected
    foreach ($d in $script:deviceRows) { $d.Selected = $script:allSelected }
    $grid.Refresh()
    $toggleSelect.Text = if ($script:allSelected) { 'Select None' } else { 'Select All' }
})

$refreshBtn.add_Click({ Refresh-Grid })
$disableSavingBtn.add_Click({ Apply-Bulk -Action { param($d) Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $false } -ActionName 'Power-saving disable' })
$enableSavingBtn.add_Click({ Apply-Bulk -Action { param($d) Set-PowerSavingAllowed -PnpDeviceId $d.PnpDeviceId -Allow $true } -ActionName 'Power-saving enable' })
$disableWakeBtn.add_Click({ Apply-Bulk -Action { param($d) Set-WakeAllowed -DeviceName $d.Name -Allow $false } -ActionName 'Wake disable' })
$enableWakeBtn.add_Click({ Apply-Bulk -Action { param($d) Set-WakeAllowed -DeviceName $d.Name -Allow $true } -ActionName 'Wake enable' })

Refresh-Grid
[void]$form.ShowDialog()
