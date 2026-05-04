#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    Start-Process -FilePath 'powershell.exe' -ArgumentList ($argList -join ' ') -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$paths = [ordered]@{
    Shortcuts   = Join-Path $scriptRoot 'Shortcuts'
    Maintenance = Join-Path $scriptRoot 'Maintenance'
    Tools       = Join-Path $scriptRoot 'Tools'
}

foreach ($p in $paths.Values) {
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p | Out-Null
    }
}

$settingsPath = Join-Path $scriptRoot 'super-admin-settings.json'
if (-not (Test-Path $settingsPath)) {
    $defaultSettings = [pscustomobject]@{
        Shortcuts = @()
        Window    = [pscustomobject]@{ Width = 1100; Height = 700 }
    }
    $defaultSettings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

function Get-Settings {
    try {
        $raw = Get-Content -LiteralPath $settingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'Settings empty' }
        return $raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{ Shortcuts = @(); Window = [pscustomobject]@{ Width = 1100; Height = 700 } }
    }
}

function Save-Settings([object]$settings) {
    $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

$settings = Get-Settings

$form = New-Object Windows.Forms.Form
$form.Text = 'Super Admin Tool'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size([int]$settings.Window.Width, [int]$settings.Window.Height)
$form.MinimumSize = New-Object Drawing.Size(900, 600)

$tabControl = New-Object Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$form.Controls.Add($tabControl)

$tabShortcuts = New-Object Windows.Forms.TabPage
$tabShortcuts.Text = 'Shortcuts'
$tabTools = New-Object Windows.Forms.TabPage
$tabTools.Text = 'Tools'
$tabMaintenance = New-Object Windows.Forms.TabPage
$tabMaintenance.Text = 'Maintenance'

$tabControl.TabPages.AddRange(@($tabShortcuts, $tabTools, $tabMaintenance))

function New-ScrollablePanel {
    $panel = New-Object Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Fill'
    $panel.AutoScroll = $true
    $panel.WrapContents = $true
    $panel.FlowDirection = 'LeftToRight'
    return $panel
}

$shortcutButtonsPanel = New-ScrollablePanel
$toolButtonsPanel = New-ScrollablePanel
$maintenancePanel = New-Object Windows.Forms.TextBox
$maintenancePanel.Multiline = $true
$maintenancePanel.ReadOnly = $true
$maintenancePanel.Dock = 'Fill'
$maintenancePanel.Text = "Place maintenance scripts in:`r`n$($paths.Maintenance)"

$shortcutTop = New-Object Windows.Forms.Panel
$shortcutTop.Height = 260
$shortcutTop.Dock = 'Top'
$tabShortcuts.Controls.Add($shortcutButtonsPanel)
$tabShortcuts.Controls.Add($shortcutTop)

$tabTools.Controls.Add($toolButtonsPanel)
$tabMaintenance.Controls.Add($maintenancePanel)

$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $true
$grid.AllowUserToDeleteRows = $true
$grid.AutoSizeColumnsMode = 'Fill'
$grid.ColumnHeadersHeightSizeMode = 'AutoSize'

@('Name','Type','Path','Command','Arguments') | ForEach-Object {
    [void]$grid.Columns.Add($_, $_)
}

$topButtons = New-Object Windows.Forms.FlowLayoutPanel
$topButtons.Dock = 'Top'
$topButtons.Height = 38

$btnAdd = New-Object Windows.Forms.Button
$btnAdd.Text = 'Add Entry'
$btnSave = New-Object Windows.Forms.Button
$btnSave.Text = 'Save'
$btnRefresh = New-Object Windows.Forms.Button
$btnRefresh.Text = 'Refresh All'

$topButtons.Controls.AddRange(@($btnAdd, $btnSave, $btnRefresh))
$shortcutTop.Controls.Add($grid)
$shortcutTop.Controls.Add($topButtons)

function Invoke-ConfiguredShortcut([pscustomobject]$entry) {
    try {
        if ($entry.Type -eq 'PowerShell') {
            Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $entry.Command)
        }
        elseif ($entry.Type -eq 'File') {
            if (Test-Path -LiteralPath $entry.Path) {
                Start-Process -FilePath $entry.Path -ArgumentList $entry.Arguments
            }
        }
    } catch {
        [Windows.Forms.MessageBox]::Show("Failed to run shortcut: $($_.Exception.Message)") | Out-Null
    }
}

function Get-GridEntries {
    $entries = @()
    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }
        $name = [string]$row.Cells['Name'].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $entries += [pscustomobject]@{
            Name      = $name
            Type      = [string]$row.Cells['Type'].Value
            Path      = [string]$row.Cells['Path'].Value
            Command   = [string]$row.Cells['Command'].Value
            Arguments = [string]$row.Cells['Arguments'].Value
        }
    }
    return $entries
}

function Save-GridToSettings {
    $settings.Shortcuts = @(Get-GridEntries)
    $settings.Window.Width = $form.Width
    $settings.Window.Height = $form.Height
    Save-Settings -settings $settings
}

function Load-GridFromSettings {
    $grid.Rows.Clear()
    foreach ($entry in @($settings.Shortcuts)) {
        [void]$grid.Rows.Add($entry.Name, $entry.Type, $entry.Path, $entry.Command, $entry.Arguments)
    }
}

function Add-ScriptButtons([Windows.Forms.FlowLayoutPanel]$panel, [string]$folder) {
    $panel.Controls.Clear()
    $scripts = Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File | Sort-Object Name
    foreach ($script in $scripts) {
        $btn = New-Object Windows.Forms.Button
        $btn.Text = [IO.Path]::GetFileNameWithoutExtension($script.Name)
        $btn.Width = 200
        $btn.Height = 45
        $scriptPath = $script.FullName
        $btn.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $scriptPath)) })
        $panel.Controls.Add($btn)
    }
}

function Rebuild-ShortcutCustomButtons {
    $existing = @($shortcutButtonsPanel.Controls | Where-Object { $_.Tag -eq 'custom' })
    foreach ($ctrl in $existing) { $shortcutButtonsPanel.Controls.Remove($ctrl); $ctrl.Dispose() }

    foreach ($entry in @(Get-GridEntries)) {
        $btn = New-Object Windows.Forms.Button
        $btn.Text = "Custom: $($entry.Name)"
        $btn.Width = 220
        $btn.Height = 45
        $btn.Tag = 'custom'
        $data = $entry
        $btn.Add_Click({ Invoke-ConfiguredShortcut -entry $data })
        $shortcutButtonsPanel.Controls.Add($btn)
    }
}

function Refresh-All {
    Add-ScriptButtons -panel $shortcutButtonsPanel -folder $paths.Shortcuts
    Add-ScriptButtons -panel $toolButtonsPanel -folder $paths.Tools
    Rebuild-ShortcutCustomButtons
}

$btnAdd.Add_Click({ [void]$grid.Rows.Add('New Entry','PowerShell','','Get-Date','') })
$btnSave.Add_Click({ Save-GridToSettings; Refresh-All })
$btnRefresh.Add_Click({ Save-GridToSettings; Refresh-All })
$grid.Add_UserDeletedRow({ Save-GridToSettings; Rebuild-ShortcutCustomButtons })
$grid.Add_CellValueChanged({ Save-GridToSettings; Rebuild-ShortcutCustomButtons })
$form.Add_FormClosing({ Save-GridToSettings })

Load-GridFromSettings
Refresh-All

[void]$form.ShowDialog()
