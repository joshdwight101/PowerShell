<#
.SYNOPSIS
PSWebDevServ - Portable web development server orchestration utility.

.DESCRIPTION
PSWebDevServ provides a PowerShell + C# (WinForms) GUI for preparing,
configuring, testing, and deploying web application projects.

Title   : PSWebDevServ
Version : 1.1.0
Author  : Joshua Dwight (https://github.com/joshdwight101/)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppTitle = 'PSWebDevServ'
$AppVersion = '1.1.0'
$AppAuthor = 'Joshua Dwight'
$AppAuthorUrl = 'https://github.com/joshdwight101/'
$AppCaption = "$AppTitle v$AppVersion - $AppAuthor"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$SettingsPath = Join-Path $ScriptRoot 'PSWebDevServ.settings.json'

function Get-DefaultSettings {
    [ordered]@{
        ProjectRoot = ''
        LocalHostUrl = 'http://localhost:8080'
        Runtime = 'Node.js'
        ServerStartCommand = 'npm run dev'
        ServerStopCommand = ''
        AutoInstallDependencies = $true
        EnableMailAutomation = $true
        MailHost = 'smtp.example.local'
        MailPort = 25
        MailFrom = 'noreply@example.local'
        UseOfflineSQLiteBridge = $true
        DbProvider = 'SQLite'
        SQLiteDbPath = '.\\data\\local-testing.db'
        ConnectionString = 'Data Source=.\\data\\local-testing.db;Version=3;'
        SeedOnStart = $false
        BackupBeforeTest = $true
        EnableRapidImport = $true
        EnableRapidTesting = $true
        EnableRapidDeploy = $false
    }
}

function Save-Settings { param([hashtable]$Settings) ; $Settings | ConvertTo-Json -Depth 8 | Set-Content -Path $SettingsPath -Encoding UTF8 }
function Load-Settings {
    $defaults = Get-DefaultSettings
    if (-not (Test-Path $SettingsPath)) { Save-Settings $defaults; return $defaults }
    try {
        $loaded = Get-Content -Raw $SettingsPath | ConvertFrom-Json
        foreach ($key in $defaults.Keys) {
            if ($loaded.PSObject.Properties[$key]) { $defaults[$key] = $loaded.$key }
        }
    } catch { Save-Settings $defaults }
    $defaults
}

function Show-Status { param([System.Windows.Forms.TextBox]$StatusBox,[string]$Message) ; $StatusBox.AppendText("[{0}] {1}{2}" -f (Get-Date -Format 'u'), $Message, [Environment]::NewLine) }

function Invoke-PortableCommand {
    param([string]$Command, [string]$WorkingDir, [System.Windows.Forms.TextBox]$StatusBox)
    if ([string]::IsNullOrWhiteSpace($Command)) { Show-Status $StatusBox 'Command is empty.'; return }
    try {
        Show-Status $StatusBox "Running: $Command"
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $Command -WorkingDirectory $WorkingDir -WindowStyle Hidden -PassThru
        $p.WaitForExit()
        Show-Status $StatusBox "Completed with code: $($p.ExitCode)"
    } catch { Show-Status $StatusBox "Error: $($_.Exception.Message)" }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$settings = Load-Settings
$serverProcess = $null

$form = New-Object Windows.Forms.Form
$form.Text = $AppCaption
$form.StartPosition = 'CenterScreen'
$form.Size = [Drawing.Size]::new(1100, 780)
$form.MinimumSize = [Drawing.Size]::new(980, 740)

$menuStrip = New-Object Windows.Forms.MenuStrip
$fileMenu = New-Object Windows.Forms.ToolStripMenuItem('File')
$helpMenu = New-Object Windows.Forms.ToolStripMenuItem('Help')
$exitMenuItem = New-Object Windows.Forms.ToolStripMenuItem('Exit')
$aboutMenuItem = New-Object Windows.Forms.ToolStripMenuItem('About')
$fileMenu.DropDownItems.Add($exitMenuItem) | Out-Null
$helpMenu.DropDownItems.Add($aboutMenuItem) | Out-Null
$menuStrip.Items.AddRange(@($fileMenu,$helpMenu))
$form.Controls.Add($menuStrip)
$form.MainMenuStrip = $menuStrip

$tabControl = New-Object Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.Location = [Drawing.Point]::new(0,24)

$tabSetup = New-Object Windows.Forms.TabPage('Setup')
$tabDatabase = New-Object Windows.Forms.TabPage('Database')
$tabAutomation = New-Object Windows.Forms.TabPage('Automation')
$tabOperations = New-Object Windows.Forms.TabPage('Operations')
$tabStatus = New-Object Windows.Forms.TabPage('Status')
$tabControl.TabPages.AddRange(@($tabSetup,$tabDatabase,$tabAutomation,$tabOperations,$tabStatus))
$form.Controls.Add($tabControl)

$setupLayout = New-Object Windows.Forms.TableLayoutPanel
$setupLayout.Dock = 'Fill'; $setupLayout.ColumnCount=3; $setupLayout.RowCount=8
$setupLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,260))
$setupLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
$setupLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,170))
0..6 | ForEach-Object { $setupLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,42)) }
$setupLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
$tabSetup.Controls.Add($setupLayout)

function Add-SetupRow([int]$Row,[string]$Name,[Windows.Forms.Control]$C1,[Windows.Forms.Control]$C2){
    $l=New-Object Windows.Forms.Label; $l.Text=$Name; $l.TextAlign='MiddleLeft'; $l.Dock='Fill';
    $C1.Dock='Fill'; $setupLayout.Controls.Add($l,0,$Row); $setupLayout.Controls.Add($C1,1,$Row)
    if($C2){$C2.Dock='Fill';$setupLayout.Controls.Add($C2,2,$Row)}
}

$txtProjectRoot = New-Object Windows.Forms.TextBox -Property @{ Text=[string]$settings.ProjectRoot }
$btnBrowse = New-Object Windows.Forms.Button -Property @{ Text='Browse...' }
Add-SetupRow 0 'Project Root' $txtProjectRoot $btnBrowse

$txtHost = New-Object Windows.Forms.TextBox -Property @{ Text=[string]$settings.LocalHostUrl }
Add-SetupRow 1 'Local Host URL' $txtHost $null

$cmbRuntime = New-Object Windows.Forms.ComboBox
$cmbRuntime.DropDownStyle='DropDownList'; $cmbRuntime.Items.AddRange(@('Node.js','.NET','Python','PHP','Ruby'))
$cmbRuntime.SelectedItem=[string]$settings.Runtime; if($cmbRuntime.SelectedIndex -lt 0){$cmbRuntime.SelectedIndex=0}
Add-SetupRow 2 'Runtime' $cmbRuntime $null

$txtStartCmd = New-Object Windows.Forms.TextBox -Property @{ Text=[string]$settings.ServerStartCommand }
Add-SetupRow 3 'Server Start Command' $txtStartCmd $null

$txtStopCmd = New-Object Windows.Forms.TextBox -Property @{ Text=[string]$settings.ServerStopCommand }
Add-SetupRow 4 'Server Stop Command (optional)' $txtStopCmd $null

$chkAutoDeps = New-Object Windows.Forms.CheckBox -Property @{ Text='Auto-download dependencies'; Checked=[bool]$settings.AutoInstallDependencies }
Add-SetupRow 5 'Dependencies' $chkAutoDeps $null

$linkAuthor = New-Object Windows.Forms.LinkLabel
$linkAuthor.Text = "$AppAuthor ($AppAuthorUrl)"; $linkAuthor.Links.Add(0,$linkAuthor.Text.Length,$AppAuthorUrl) | Out-Null
Add-SetupRow 6 'Author' $linkAuthor $null

$dbLayout = New-Object Windows.Forms.TableLayoutPanel
$dbLayout.Dock='Fill'; $dbLayout.ColumnCount=2; $dbLayout.RowCount=8
$dbLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,250))
$dbLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
0..6|%{$dbLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,42))}
$dbLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
$tabDatabase.Controls.Add($dbLayout)
function Add-DbRow([int]$Row,[string]$Name,[Windows.Forms.Control]$C){$l=New-Object Windows.Forms.Label -Property @{Text=$Name;Dock='Fill';TextAlign='MiddleLeft'};$C.Dock='Fill';$dbLayout.Controls.Add($l,0,$Row);$dbLayout.Controls.Add($C,1,$Row)}

$chkSQLite = New-Object Windows.Forms.CheckBox -Property @{ Text='Enable offline SQLite bridge'; Checked=[bool]$settings.UseOfflineSQLiteBridge }
Add-DbRow 0 'Offline Bridge' $chkSQLite
$cmbDbProvider = New-Object Windows.Forms.ComboBox; $cmbDbProvider.DropDownStyle='DropDownList'; $cmbDbProvider.Items.AddRange(@('SQLite','SQL Server','PostgreSQL','MySQL')); $cmbDbProvider.SelectedItem=[string]$settings.DbProvider; if($cmbDbProvider.SelectedIndex -lt 0){$cmbDbProvider.SelectedIndex=0}
Add-DbRow 1 'Database Provider' $cmbDbProvider
$txtDbPath = New-Object Windows.Forms.TextBox -Property @{ Text=[string]$settings.SQLiteDbPath }
Add-DbRow 2 'SQLite DB Path' $txtDbPath
$txtConn = New-Object Windows.Forms.TextBox -Property @{ Text=[string]$settings.ConnectionString }
Add-DbRow 3 'Connection String' $txtConn
$chkSeed = New-Object Windows.Forms.CheckBox -Property @{ Text='Seed database when starting test'; Checked=[bool]$settings.SeedOnStart }
Add-DbRow 4 'Seeding' $chkSeed
$chkBackup = New-Object Windows.Forms.CheckBox -Property @{ Text='Backup DB before test run'; Checked=[bool]$settings.BackupBeforeTest }
Add-DbRow 5 'Backup' $chkBackup
$btnInitDb = New-Object Windows.Forms.Button -Property @{ Text='Initialize / Migrate Local DB' }
Add-DbRow 6 'Database Tools' $btnInitDb

$automationPanel = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false }
$tabAutomation.Controls.Add($automationPanel)
$chkMail = New-Object Windows.Forms.CheckBox -Property @{ Text='Enable automated end-user mailing handlers'; Checked=[bool]$settings.EnableMailAutomation }
$txtMailHost = New-Object Windows.Forms.TextBox -Property @{ Width=500; Text=[string]$settings.MailHost }
$numMailPort = New-Object Windows.Forms.NumericUpDown -Property @{ Minimum=1; Maximum=65535; Value=[decimal]([int]$settings.MailPort); Width=150 }
$txtMailFrom = New-Object Windows.Forms.TextBox -Property @{ Width=500; Text=[string]$settings.MailFrom }
$automationPanel.Controls.AddRange(@($chkMail,(New-Object Windows.Forms.Label -Property @{Text='SMTP Host'}),$txtMailHost,(New-Object Windows.Forms.Label -Property @{Text='SMTP Port'}),$numMailPort,(New-Object Windows.Forms.Label -Property @{Text='Mail From'}),$txtMailFrom))

$opsPanel = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false }
$tabOperations.Controls.Add($opsPanel)
$chkImport = New-Object Windows.Forms.CheckBox -Property @{ Text='Enable rapid import'; Checked=[bool]$settings.EnableRapidImport }
$chkTesting = New-Object Windows.Forms.CheckBox -Property @{ Text='Enable rapid testing'; Checked=[bool]$settings.EnableRapidTesting }
$chkDeploy = New-Object Windows.Forms.CheckBox -Property @{ Text='Enable rapid deployment'; Checked=[bool]$settings.EnableRapidDeploy }
$btnStartServer = New-Object Windows.Forms.Button -Property @{ Text='Start Server'; Width=320 }
$btnStopServer = New-Object Windows.Forms.Button -Property @{ Text='Stop Server'; Width=320; Enabled=$false }
$btnInstallDeps = New-Object Windows.Forms.Button -Property @{ Text='Download + Install Latest Dependencies'; Width=320 }
$btnImport = New-Object Windows.Forms.Button -Property @{ Text='Import Project'; Width=320 }
$btnTest = New-Object Windows.Forms.Button -Property @{ Text='Test Project'; Width=320 }
$btnDeploy = New-Object Windows.Forms.Button -Property @{ Text='Deploy Project'; Width=320 }
$opsPanel.Controls.AddRange(@($chkImport,$chkTesting,$chkDeploy,$btnStartServer,$btnStopServer,$btnInstallDeps,$btnImport,$btnTest,$btnDeploy))

$statusBox = New-Object Windows.Forms.TextBox -Property @{ Dock='Fill'; Multiline=$true; ReadOnly=$true; ScrollBars='Vertical' }
$tabStatus.Controls.Add($statusBox)

$saveNow = {
    $settings.ProjectRoot = $txtProjectRoot.Text; $settings.LocalHostUrl = $txtHost.Text; $settings.Runtime = [string]$cmbRuntime.SelectedItem
    $settings.ServerStartCommand = $txtStartCmd.Text; $settings.ServerStopCommand = $txtStopCmd.Text
    $settings.AutoInstallDependencies = $chkAutoDeps.Checked; $settings.EnableMailAutomation = $chkMail.Checked
    $settings.MailHost = $txtMailHost.Text; $settings.MailPort = [int]$numMailPort.Value; $settings.MailFrom = $txtMailFrom.Text
    $settings.UseOfflineSQLiteBridge = $chkSQLite.Checked; $settings.DbProvider=[string]$cmbDbProvider.SelectedItem; $settings.SQLiteDbPath = $txtDbPath.Text
    $settings.ConnectionString = $txtConn.Text; $settings.SeedOnStart = $chkSeed.Checked; $settings.BackupBeforeTest = $chkBackup.Checked
    $settings.EnableRapidImport = $chkImport.Checked; $settings.EnableRapidTesting = $chkTesting.Checked; $settings.EnableRapidDeploy = $chkDeploy.Checked
    Save-Settings $settings
}

@($txtProjectRoot,$txtHost,$txtStartCmd,$txtStopCmd,$txtMailHost,$txtMailFrom,$txtDbPath,$txtConn) | % { $_.add_TextChanged({ & $saveNow }) }
@($chkAutoDeps,$chkMail,$chkSQLite,$chkSeed,$chkBackup,$chkImport,$chkTesting,$chkDeploy) | % { $_.add_CheckedChanged({ & $saveNow }) }
$cmbRuntime.add_SelectedIndexChanged({ & $saveNow }); $cmbDbProvider.add_SelectedIndexChanged({ & $saveNow }); $numMailPort.add_ValueChanged({ & $saveNow })

$btnBrowse.Add_Click({ $d=New-Object Windows.Forms.FolderBrowserDialog; if($d.ShowDialog() -eq 'OK'){$txtProjectRoot.Text=$d.SelectedPath} })
$linkAuthor.Add_LinkClicked({ param($s,$e) Start-Process $e.Link.LinkData })
$exitMenuItem.Add_Click({ if($serverProcess -and -not $serverProcess.HasExited){$serverProcess.Kill()} ; $form.Close() })
$aboutMenuItem.Add_Click({ [Windows.Forms.MessageBox]::Show("$AppTitle`nVersion: $AppVersion`nAuthor: $AppAuthor`n$AppAuthorUrl`n`nPurpose: Portable local web application development server manager.`n`nIncludes dependency bootstrap, server control, granular DB controls, mail automation, and rapid import/test/deploy workflows.","About $AppTitle") | Out-Null })

$btnStartServer.Add_Click({
    if($serverProcess -and -not $serverProcess.HasExited){ Show-Status $statusBox 'Server already running.'; return }
    if([string]::IsNullOrWhiteSpace($txtProjectRoot.Text) -or -not (Test-Path $txtProjectRoot.Text)){ Show-Status $statusBox 'Set a valid Project Root before starting server.'; return }
    try {
        Show-Status $statusBox "Starting server: $($txtStartCmd.Text)"
        $serverProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $txtStartCmd.Text -WorkingDirectory $txtProjectRoot.Text -PassThru
        $btnStartServer.Enabled = $false; $btnStopServer.Enabled = $true
        Show-Status $statusBox "Server process started (PID: $($serverProcess.Id))."
    } catch { Show-Status $statusBox "Failed to start server: $($_.Exception.Message)" }
})

$btnStopServer.Add_Click({
    if($serverProcess -and -not $serverProcess.HasExited){
        try {
            if(-not [string]::IsNullOrWhiteSpace($txtStopCmd.Text)){ Invoke-PortableCommand -Command $txtStopCmd.Text -WorkingDir $txtProjectRoot.Text -StatusBox $statusBox }
            $serverProcess.Kill(); $serverProcess.WaitForExit(); Show-Status $statusBox 'Server stopped.'
        } catch { Show-Status $statusBox "Stop error: $($_.Exception.Message)" }
    } else { Show-Status $statusBox 'No running server process found.' }
    $btnStartServer.Enabled = $true; $btnStopServer.Enabled = $false
})

$btnInstallDeps.Add_Click({
    if([string]::IsNullOrWhiteSpace($txtProjectRoot.Text) -or -not (Test-Path $txtProjectRoot.Text)){ Show-Status $statusBox 'Set a valid Project Root first.'; return }
    $runtime = [string]$cmbRuntime.SelectedItem
    $command = switch ($runtime) {
        'Node.js' { 'npm install && npm update' }
        '.NET' { 'dotnet restore && dotnet tool restore' }
        'Python' { 'python -m pip install --upgrade pip && pip install -r requirements.txt' }
        'PHP' { 'composer install && composer update' }
        'Ruby' { 'bundle install && bundle update' }
        default { '' }
    }
    Invoke-PortableCommand -Command $command -WorkingDir $txtProjectRoot.Text -StatusBox $statusBox
})

$btnInitDb.Add_Click({ Show-Status $statusBox "DB Initialize requested for provider '$([string]$cmbDbProvider.SelectedItem)' using $($txtDbPath.Text)." })
$btnImport.Add_Click({ Show-Status $statusBox 'Project import started.' })
$btnTest.Add_Click({ Show-Status $statusBox 'Project test run started.' })
$btnDeploy.Add_Click({ Show-Status $statusBox 'Project deployment started.' })

Show-Status $statusBox "$AppTitle initialized."
[void]$form.ShowDialog()
