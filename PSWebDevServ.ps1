<#
.SYNOPSIS
PSWebDevServ - Portable web development server orchestration utility.

.DESCRIPTION
PSWebDevServ provides a PowerShell + C# (WinForms) GUI for quickly preparing,
configuring, testing, and deploying web application projects in a portable way.

Title   : PSWebDevServ
Version : 1.0.0
Author  : Joshua Dwight (https://github.com/joshdwight101/)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Application metadata
# -----------------------------------------------------------------------------
$AppTitle   = 'PSWebDevServ'
$AppVersion = '1.0.0'
$AppAuthor  = 'Joshua Dwight'
$AppAuthorUrl = 'https://github.com/joshdwight101/'
$AppCaption = "$AppTitle v$AppVersion - $AppAuthor"

# -----------------------------------------------------------------------------
# Paths and persistence
# -----------------------------------------------------------------------------
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$SettingsPath = Join-Path $ScriptRoot 'PSWebDevServ.settings.json'

function Get-DefaultSettings {
    [ordered]@{
        ProjectRoot                  = ''
        LocalHostUrl                 = 'http://localhost:8080'
        Runtime                      = 'Node.js'
        AutoInstallDependencies      = $true
        UseOfflineSQLiteBridge       = $true
        SQLiteDbPath                 = '.\\data\\local-testing.db'
        EnableMailAutomation         = $true
        MailHost                     = 'smtp.example.local'
        MailPort                     = 25
        MailFrom                     = 'noreply@example.local'
        EnableRapidImport            = $true
        EnableRapidTesting           = $true
        EnableRapidDeploy            = $false
    }
}

function Save-Settings {
    param([Parameter(Mandatory)] [hashtable]$Settings)

    $json = $Settings | ConvertTo-Json -Depth 8
    Set-Content -Path $SettingsPath -Value $json -Encoding UTF8
}

function Load-Settings {
    $defaults = Get-DefaultSettings

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        Save-Settings -Settings $defaults
        return $defaults
    }

    try {
        $loaded = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
        foreach ($key in $defaults.Keys) {
            if ($null -ne $loaded.PSObject.Properties[$key]) {
                $defaults[$key] = $loaded.$key
            }
        }
    }
    catch {
        Save-Settings -Settings $defaults
    }

    return $defaults
}

function Show-Status {
    param(
        [Parameter(Mandatory)] [System.Windows.Forms.TextBox]$StatusBox,
        [Parameter(Mandatory)] [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date -Format 'u'), $Message
    $StatusBox.AppendText($line + [Environment]::NewLine)
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$settings = Load-Settings

$form = New-Object System.Windows.Forms.Form
$form.Text = $AppCaption
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(980, 760)
$form.MinimumSize = New-Object System.Drawing.Size(900, 700)

$menuStrip = New-Object System.Windows.Forms.MenuStrip
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem('File')
$exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Exit')
$helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Help')
$aboutMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('About')
$fileMenu.DropDownItems.Add($exitMenuItem) | Out-Null
$helpMenu.DropDownItems.Add($aboutMenuItem) | Out-Null
$menuStrip.Items.Add($fileMenu) | Out-Null
$menuStrip.Items.Add($helpMenu) | Out-Null
$form.Controls.Add($menuStrip)
$form.MainMenuStrip = $menuStrip

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.Location = New-Object System.Drawing.Point(0, 24)

$tabSetup = New-Object System.Windows.Forms.TabPage('Setup')
$tabAutomation = New-Object System.Windows.Forms.TabPage('Automation')
$tabOps = New-Object System.Windows.Forms.TabPage('Operations')
$statusTab = New-Object System.Windows.Forms.TabPage('Status')

$tabControl.TabPages.AddRange(@($tabSetup, $tabAutomation, $tabOps, $statusTab))
$form.Controls.Add($tabControl)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 3
$layout.RowCount = 9
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 260)))
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140)))
for ($i = 0; $i -lt 8; $i++) {
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)))
}
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tabSetup.Controls.Add($layout)

function Add-RowControl {
    param(
        [int]$Row,
        [string]$Label,
        [System.Windows.Forms.Control]$Control,
        [System.Windows.Forms.Control]$OptionalControl
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Dock = 'Fill'
    $lbl.TextAlign = 'MiddleLeft'

    $Control.Dock = 'Fill'

    $layout.Controls.Add($lbl, 0, $Row)
    $layout.Controls.Add($Control, 1, $Row)
    if ($OptionalControl) {
        $OptionalControl.Dock = 'Fill'
        $layout.Controls.Add($OptionalControl, 2, $Row)
    }
}

$txtProjectRoot = New-Object System.Windows.Forms.TextBox
$txtProjectRoot.Text = [string]$settings.ProjectRoot
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
Add-RowControl -Row 0 -Label 'Project Root' -Control $txtProjectRoot -OptionalControl $btnBrowse

$txtLocalHost = New-Object System.Windows.Forms.TextBox
$txtLocalHost.Text = [string]$settings.LocalHostUrl
Add-RowControl -Row 1 -Label 'Local Host URL' -Control $txtLocalHost -OptionalControl $null

$comboRuntime = New-Object System.Windows.Forms.ComboBox
$comboRuntime.DropDownStyle = 'DropDownList'
$comboRuntime.Items.AddRange(@('Node.js', '.NET', 'Python', 'PHP', 'Ruby'))
$comboRuntime.SelectedItem = [string]$settings.Runtime
if ($comboRuntime.SelectedIndex -lt 0) { $comboRuntime.SelectedIndex = 0 }
Add-RowControl -Row 2 -Label 'Runtime' -Control $comboRuntime -OptionalControl $null

$chkAutoDeps = New-Object System.Windows.Forms.CheckBox
$chkAutoDeps.Text = 'Auto-download dependencies'
$chkAutoDeps.Checked = [bool]$settings.AutoInstallDependencies
Add-RowControl -Row 3 -Label 'Dependencies' -Control $chkAutoDeps -OptionalControl $null

$chkSQLite = New-Object System.Windows.Forms.CheckBox
$chkSQLite.Text = 'Enable offline SQLite bridge for DB testing'
$chkSQLite.Checked = [bool]$settings.UseOfflineSQLiteBridge
Add-RowControl -Row 4 -Label 'Database' -Control $chkSQLite -OptionalControl $null

$txtSQLite = New-Object System.Windows.Forms.TextBox
$txtSQLite.Text = [string]$settings.SQLiteDbPath
Add-RowControl -Row 5 -Label 'SQLite DB Path' -Control $txtSQLite -OptionalControl $null

$linkAuthor = New-Object System.Windows.Forms.LinkLabel
$linkAuthor.Text = "$AppAuthor ($AppAuthorUrl)"
$linkAuthor.Links.Add(0, $linkAuthor.Text.Length, $AppAuthorUrl) | Out-Null
Add-RowControl -Row 6 -Label 'Author' -Control $linkAuthor -OptionalControl $null

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = 'Settings are saved in real time to local JSON for portability.'
$lblInfo.TextAlign = 'MiddleLeft'
Add-RowControl -Row 7 -Label 'Persistence' -Control $lblInfo -OptionalControl $null

$panelAutomation = New-Object System.Windows.Forms.FlowLayoutPanel
$panelAutomation.Dock = 'Fill'
$panelAutomation.FlowDirection = 'TopDown'
$panelAutomation.WrapContents = $false
$tabAutomation.Controls.Add($panelAutomation)

$chkMail = New-Object System.Windows.Forms.CheckBox
$chkMail.Text = 'Enable automated end-user mailing handlers'
$chkMail.Checked = [bool]$settings.EnableMailAutomation
$panelAutomation.Controls.Add($chkMail)

$txtMailHost = New-Object System.Windows.Forms.TextBox
$txtMailHost.Width = 400
$txtMailHost.Text = [string]$settings.MailHost
$panelAutomation.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = 'SMTP Host' }))
$panelAutomation.Controls.Add($txtMailHost)

$numMailPort = New-Object System.Windows.Forms.NumericUpDown
$numMailPort.Minimum = 1
$numMailPort.Maximum = 65535
$numMailPort.Value = [decimal]([int]$settings.MailPort)
$panelAutomation.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = 'SMTP Port' }))
$panelAutomation.Controls.Add($numMailPort)

$txtMailFrom = New-Object System.Windows.Forms.TextBox
$txtMailFrom.Width = 400
$txtMailFrom.Text = [string]$settings.MailFrom
$panelAutomation.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = 'Mail From' }))
$panelAutomation.Controls.Add($txtMailFrom)

$panelOps = New-Object System.Windows.Forms.FlowLayoutPanel
$panelOps.Dock = 'Fill'
$panelOps.FlowDirection = 'TopDown'
$panelOps.WrapContents = $false
$tabOps.Controls.Add($panelOps)

$chkImport = New-Object System.Windows.Forms.CheckBox
$chkImport.Text = 'Enable rapid import'
$chkImport.Checked = [bool]$settings.EnableRapidImport
$panelOps.Controls.Add($chkImport)

$chkTesting = New-Object System.Windows.Forms.CheckBox
$chkTesting.Text = 'Enable rapid testing'
$chkTesting.Checked = [bool]$settings.EnableRapidTesting
$panelOps.Controls.Add($chkTesting)

$chkDeploy = New-Object System.Windows.Forms.CheckBox
$chkDeploy.Text = 'Enable rapid deployment'
$chkDeploy.Checked = [bool]$settings.EnableRapidDeploy
$panelOps.Controls.Add($chkDeploy)

$btnInstallDeps = New-Object System.Windows.Forms.Button
$btnInstallDeps.Text = 'One-Click Install Dependencies'
$btnInstallDeps.Width = 300
$panelOps.Controls.Add($btnInstallDeps)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = 'Import Project'
$btnImport.Width = 300
$panelOps.Controls.Add($btnImport)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = 'Test Project'
$btnTest.Width = 300
$panelOps.Controls.Add($btnTest)

$btnDeploy = New-Object System.Windows.Forms.Button
$btnDeploy.Text = 'Deploy Project'
$btnDeploy.Width = 300
$panelOps.Controls.Add($btnDeploy)

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Dock = 'Fill'
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = 'Vertical'
$statusTab.Controls.Add($statusBox)

$saveNow = {
    $settings.ProjectRoot = $txtProjectRoot.Text
    $settings.LocalHostUrl = $txtLocalHost.Text
    $settings.Runtime = [string]$comboRuntime.SelectedItem
    $settings.AutoInstallDependencies = $chkAutoDeps.Checked
    $settings.UseOfflineSQLiteBridge = $chkSQLite.Checked
    $settings.SQLiteDbPath = $txtSQLite.Text
    $settings.EnableMailAutomation = $chkMail.Checked
    $settings.MailHost = $txtMailHost.Text
    $settings.MailPort = [int]$numMailPort.Value
    $settings.MailFrom = $txtMailFrom.Text
    $settings.EnableRapidImport = $chkImport.Checked
    $settings.EnableRapidTesting = $chkTesting.Checked
    $settings.EnableRapidDeploy = $chkDeploy.Checked
    Save-Settings -Settings $settings
}

foreach ($control in @($txtProjectRoot, $txtLocalHost, $txtSQLite, $txtMailHost, $txtMailFrom)) {
    $control.add_TextChanged({ & $saveNow })
}
foreach ($control in @($chkAutoDeps, $chkSQLite, $chkMail, $chkImport, $chkTesting, $chkDeploy)) {
    $control.add_CheckedChanged({ & $saveNow })
}
$comboRuntime.add_SelectedIndexChanged({ & $saveNow })
$numMailPort.add_ValueChanged({ & $saveNow })

$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtProjectRoot.Text = $dialog.SelectedPath
    }
})

$linkAuthor.Add_LinkClicked({
    param($sender, $eventArgs)
    Start-Process $eventArgs.Link.LinkData
})

$exitMenuItem.Add_Click({ $form.Close() })

$aboutMenuItem.Add_Click({
    $aboutText = @"
$AppTitle
Version: $AppVersion
Author: $AppAuthor
Author URL: $AppAuthorUrl

Purpose:
Portable PowerShell + C# GUI for web app development orchestration.

Summary:
- One-click dependency bootstrap
- Configurable local/offline SQLite bridge for DB testing
- Automated mailing workflow controls
- Rapid import, test, and deploy workflow toggles
- Real-time settings persistence in portable JSON
"@
    [System.Windows.Forms.MessageBox]::Show($aboutText, "About $AppTitle", 'OK', 'Information') | Out-Null
})

$btnInstallDeps.Add_Click({
    Show-Status -StatusBox $statusBox -Message 'Dependency bootstrap started (placeholder workflow).'
})
$btnImport.Add_Click({
    Show-Status -StatusBox $statusBox -Message 'Project import started (placeholder workflow).'
})
$btnTest.Add_Click({
    Show-Status -StatusBox $statusBox -Message 'Project test run started (placeholder workflow).'
})
$btnDeploy.Add_Click({
    Show-Status -StatusBox $statusBox -Message 'Project deployment started (placeholder workflow).'
})

Show-Status -StatusBox $statusBox -Message "$AppTitle initialized."
[void]$form.ShowDialog()
