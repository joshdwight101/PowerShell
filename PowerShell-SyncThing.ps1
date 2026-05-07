#requires -Version 5.1
<#!
.SYNOPSIS
  PowerShell SyncThing by Joshua Dwight
.DESCRIPTION
  Multi-threaded 2-way sync manager with a C# (WinForms) GUI hosted in PowerShell.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:AppTitle = 'PowerShell SyncThing'
$script:AppVersion = '1.0.0'
$script:Author = 'Joshua Dwight'
$script:GitHubUrl = 'https://github.com/joshdwight101'
$script:SettingsPath = Join-Path -Path $env:APPDATA -ChildPath 'PowerShellSyncThing\settings.json'
$script:workers = @{}
$script:syncPairs = New-Object System.Collections.Generic.List[object]

function Initialize-Settings {
    $cpu = [Environment]::ProcessorCount
    $recommended = [Math]::Max(2, [Math]::Min($cpu, 16))

    $defaults = [ordered]@{
        App = [ordered]@{
            ThreadCount = $recommended
            DarkTheme = $true
            PollingMs = 1200
            AutoSaveSettings = $true
        }
        Logging = [ordered]@{
            Enabled = $true
            FileName = 'powershell-syncthing.log'
            Mode = 'Append'
            AutoPrune = $true
            MaxFileMB = 20
            LogDirectory = (Join-Path $env:APPDATA 'PowerShellSyncThing\logs')
            Verbose = $true
        }
        SyncPairs = @()
    }

    if (Test-Path $script:SettingsPath) {
        try {
            return (Get-Content $script:SettingsPath -Raw | ConvertFrom-Json -AsHashtable)
        } catch {
            return $defaults
        }
    }
    return $defaults
}

function Save-Settings([hashtable]$settings) {
    $folder = Split-Path $script:SettingsPath -Parent
    if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $script:SettingsPath -Encoding UTF8
}

function Write-VerboseLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [System.Windows.Forms.TextBox]$StatusTextBox,
        [Parameter(Mandatory)] [hashtable]$Settings
    )
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$stamp] $Message"
    $StatusTextBox.AppendText($line + [Environment]::NewLine)

    if (-not $Settings.Logging.Enabled) { return }
    $logDir = $Settings.Logging.LogDirectory
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $filePath = Join-Path $logDir $Settings.Logging.FileName

    if ($Settings.Logging.AutoPrune -and (Test-Path $filePath)) {
        $maxBytes = [int64]$Settings.Logging.MaxFileMB * 1MB
        $len = (Get-Item $filePath).Length
        if ($len -gt $maxBytes) {
            $archived = "{0}.{1:yyyyMMddHHmmss}.bak" -f $filePath, (Get-Date)
            Move-Item -Path $filePath -Destination $archived -Force
        }
    }

    if ($Settings.Logging.Mode -eq 'Overwrite') {
        $line | Set-Content -Path $filePath -Encoding UTF8
        $Settings.Logging.Mode = 'Append'
    } else {
        $line | Add-Content -Path $filePath -Encoding UTF8
    }
}

function Start-SyncPair {
    param([hashtable]$pair, [hashtable]$settings, [System.Windows.Forms.TextBox]$statusBox)

    if ($script:workers.ContainsKey($pair.Name)) { return }

    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($pair, $settings)

        function Sync-Directory {
            param([string]$Source, [string]$Destination)
            if (-not (Test-Path $Source)) { return @("WARN: Source path missing: $Source") }
            if (-not (Test-Path $Destination)) { New-Item -Path $Destination -ItemType Directory -Force | Out-Null }

            $messages = @()
            Get-ChildItem -Path $Source -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $relative = $_.FullName.Substring($Source.Length).TrimStart('\\','/')
                $target = Join-Path $Destination $relative
                $targetDir = Split-Path $target -Parent
                if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }

                $copy = $false
                if (-not (Test-Path $target)) { $copy = $true }
                else {
                    $destFile = Get-Item $target
                    if ($_.LastWriteTimeUtc -gt $destFile.LastWriteTimeUtc -or $_.Length -ne $destFile.Length) { $copy = $true }
                }

                if ($copy) {
                    Copy-Item -Path $_.FullName -Destination $target -Force
                    $messages += "SYNC: $($_.FullName) -> $target"
                }
            }
            return $messages
        }

        while ($true) {
            $msgs = @()
            $msgs += Sync-Directory -Source $pair.PathA -Destination $pair.PathB
            $msgs += Sync-Directory -Source $pair.PathB -Destination $pair.PathA
            if ($msgs.Count -eq 0) { "IDLE: No changes for pair '$($pair.Name)'" } else { $msgs }
            Start-Sleep -Milliseconds $settings.App.PollingMs
        }
    }).AddArgument($pair).AddArgument($settings)

    $ps.RunspacePool = [runspacefactory]::CreateRunspacePool(1, $settings.App.ThreadCount)
    $ps.RunspacePool.Open()
    $asyncResult = $ps.BeginInvoke()
    $script:workers[$pair.Name] = [ordered]@{ PowerShell = $ps; Handle = $asyncResult }
    Write-VerboseLog -Message "Started sync pair '$($pair.Name)' with thread cap $($settings.App.ThreadCount)." -StatusTextBox $statusBox -Settings $settings
}

function Stop-AllSync([hashtable]$settings, [System.Windows.Forms.TextBox]$statusBox) {
    foreach ($key in @($script:workers.Keys)) {
        $worker = $script:workers[$key]
        try {
            $worker.PowerShell.Stop()
            $worker.PowerShell.Dispose()
            Write-VerboseLog -Message "Stopped sync pair '$key'." -StatusTextBox $statusBox -Settings $settings
        } catch {}
    }
    $script:workers.Clear()
}

$settings = Initialize-Settings
$cpu = [Environment]::ProcessorCount

$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppTitle by $script:Author"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$form.ForeColor = [System.Drawing.Color]::LightBlue

$menu = New-Object System.Windows.Forms.MenuStrip
$menu.BackColor = [System.Drawing.Color]::FromArgb(40,40,40)
$menu.ForeColor = [System.Drawing.Color]::LightBlue

$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem('File')
$exitMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Exit')
$exitMenu.add_Click({ $form.Close() })
$fileMenu.DropDownItems.Add($exitMenu) | Out-Null

$optionsMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Options')
$settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem('Application Settings')

$helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Help')
$aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem('About')
$manualItem = New-Object System.Windows.Forms.ToolStripMenuItem('Manual')
$aboutItem.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
@" 
$script:AppTitle v$script:AppVersion
Author: $script:Author

Purpose:
Modern multi-threaded, 2-way folder synchronization manager.

Key uses:
- Create/manage many 2-way sync pairs
- Start/Stop all sync workers
- Verbose status and file-level logging
- Persisted settings and logging controls

GitHub:
$script:GitHubUrl
"@,
        'About PowerShell SyncThing',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
})
$manualItem.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
@"
Manual - PowerShell SyncThing

1) Add a Sync Pair:
   - Provide Name, Path A, Path B then click 'Add/Update Pair'.
2) Manage Threading:
   - Set worker thread cap based on CPU recommendation.
3) Start/Stop:
   - Click 'Start Sync Server' to begin all configured sync pairs.
   - Click 'Stop Sync Server' to halt workers.
4) Logging:
   - Use Options > Application Settings to customize file name, location,
     append/overwrite behavior, prune mode, and max log size.
5) Auto-save:
   - Settings and sync pair definitions auto-save on exit and when updated.

Tips:
- Keep folders on fast local storage for best performance.
- Keep thread count around the recommended value for optimal throughput.
"@,
        'Manual',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
})
$helpMenu.DropDownItems.AddRange(@($manualItem,$aboutItem))

$optionsMenu.DropDownItems.Add($settingsItem) | Out-Null
$menu.Items.AddRange(@($fileMenu,$optionsMenu,$helpMenu))
$form.Controls.Add($menu)
$form.MainMenuStrip = $menu

# Controls
$lblThread = New-Object System.Windows.Forms.Label
$lblThread.Location = '20,40'; $lblThread.Size = '560,24'
$lblThread.Text = "Detected CPU cores: $cpu | Recommended threads: $([Math]::Max(2,[Math]::Min($cpu,16)))"

$numThread = New-Object System.Windows.Forms.NumericUpDown
$numThread.Location = '600,38'; $numThread.Size = '80,26'; $numThread.Minimum = 1; $numThread.Maximum = [Math]::Max(128,$cpu*4)
$numThread.Value = [decimal]$settings.App.ThreadCount

$githubLink = New-Object System.Windows.Forms.LinkLabel
$githubLink.Location = '700,40'; $githubLink.Size = '440,24'; $githubLink.Text = $script:GitHubUrl
$githubLink.LinkColor = [System.Drawing.Color]::DeepSkyBlue
$githubLink.add_Click({ Start-Process $script:GitHubUrl })

$pairGrid = New-Object System.Windows.Forms.DataGridView
$pairGrid.Location = '20,80'; $pairGrid.Size = '1120,270'
$pairGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(25,25,25)
$pairGrid.ForeColor = [System.Drawing.Color]::White
$pairGrid.ColumnCount = 3
$pairGrid.Columns[0].Name = 'Name'; $pairGrid.Columns[1].Name = 'PathA'; $pairGrid.Columns[2].Name = 'PathB'

$txtName = New-Object System.Windows.Forms.TextBox; $txtName.Location = '20,370'; $txtName.Size = '180,24'; $txtName.PlaceholderText = 'Pair Name'
$txtA = New-Object System.Windows.Forms.TextBox; $txtA.Location = '210,370'; $txtA.Size = '380,24'; $txtA.PlaceholderText = 'Location A'
$txtB = New-Object System.Windows.Forms.TextBox; $txtB.Location = '600,370'; $txtB.Size = '380,24'; $txtB.PlaceholderText = 'Location B'
$btnBrowseA = New-Object System.Windows.Forms.Button; $btnBrowseA.Location='990,368'; $btnBrowseA.Size='70,28'; $btnBrowseA.Text='A...'
$btnBrowseB = New-Object System.Windows.Forms.Button; $btnBrowseB.Location='1070,368'; $btnBrowseB.Size='70,28'; $btnBrowseB.Text='B...'
$btnAddPair = New-Object System.Windows.Forms.Button; $btnAddPair.Location='20,402'; $btnAddPair.Size='150,30'; $btnAddPair.Text='Add/Update Pair'
$btnRemovePair = New-Object System.Windows.Forms.Button; $btnRemovePair.Location='180,402'; $btnRemovePair.Size='140,30'; $btnRemovePair.Text='Remove Selected'
$btnStart = New-Object System.Windows.Forms.Button; $btnStart.Location='340,402'; $btnStart.Size='170,30'; $btnStart.Text='Start Sync Server'
$btnStop = New-Object System.Windows.Forms.Button; $btnStop.Location='520,402'; $btnStop.Size='170,30'; $btnStop.Text='Stop Sync Server'

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Location='20,450'; $statusBox.Size='1120,250'; $statusBox.Multiline=$true; $statusBox.ScrollBars='Vertical'; $statusBox.BackColor=[System.Drawing.Color]::FromArgb(20,20,20); $statusBox.ForeColor=[System.Drawing.Color]::LightBlue

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog

$btnBrowseA.add_Click({ if ($folderDialog.ShowDialog() -eq 'OK') { $txtA.Text = $folderDialog.SelectedPath } })
$btnBrowseB.add_Click({ if ($folderDialog.ShowDialog() -eq 'OK') { $txtB.Text = $folderDialog.SelectedPath } })

$btnAddPair.add_Click({
    if ([string]::IsNullOrWhiteSpace($txtName.Text) -or [string]::IsNullOrWhiteSpace($txtA.Text) -or [string]::IsNullOrWhiteSpace($txtB.Text)) { return }
    $pair = [ordered]@{ Name=$txtName.Text.Trim(); PathA=$txtA.Text.Trim(); PathB=$txtB.Text.Trim() }
    $existing = $script:syncPairs | Where-Object Name -eq $pair.Name
    if ($existing) {
        $existing.PathA = $pair.PathA; $existing.PathB = $pair.PathB
    } else {
        $script:syncPairs.Add($pair)
        $pairGrid.Rows.Add($pair.Name,$pair.PathA,$pair.PathB) | Out-Null
    }
    $settings.SyncPairs = @($script:syncPairs)
    $settings.App.ThreadCount = [int]$numThread.Value
    Save-Settings $settings
    Write-VerboseLog -Message "Sync pair saved: $($pair.Name)" -StatusTextBox $statusBox -Settings $settings
})

$btnRemovePair.add_Click({
    if ($pairGrid.SelectedRows.Count -lt 1) { return }
    $name = $pairGrid.SelectedRows[0].Cells[0].Value
    $pairGrid.Rows.RemoveAt($pairGrid.SelectedRows[0].Index)
    $script:syncPairs = New-Object 'System.Collections.Generic.List[object]' ($script:syncPairs | Where-Object Name -ne $name)
    $settings.SyncPairs = @($script:syncPairs)
    Save-Settings $settings
    Write-VerboseLog -Message "Removed sync pair: $name" -StatusTextBox $statusBox -Settings $settings
})

$btnStart.add_Click({
    $settings.App.ThreadCount = [int]$numThread.Value
    foreach ($pair in $script:syncPairs) { Start-SyncPair -pair $pair -settings $settings -statusBox $statusBox }
    Write-VerboseLog -Message 'Sync server started.' -StatusTextBox $statusBox -Settings $settings
})
$btnStop.add_Click({ Stop-AllSync -settings $settings -statusBox $statusBox; Write-VerboseLog -Message 'Sync server stopped.' -StatusTextBox $statusBox -Settings $settings })

$settingsItem.add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Application Options'; $dlg.Size = '520,380'; $dlg.BackColor = [System.Drawing.Color]::FromArgb(35,35,35); $dlg.ForeColor=[System.Drawing.Color]::LightBlue

    $txtLogName = New-Object System.Windows.Forms.TextBox; $txtLogName.Location='20,30'; $txtLogName.Size='460,24'; $txtLogName.Text=$settings.Logging.FileName
    $txtLogDir = New-Object System.Windows.Forms.TextBox; $txtLogDir.Location='20,80'; $txtLogDir.Size='460,24'; $txtLogDir.Text=$settings.Logging.LogDirectory
    $cmbMode = New-Object System.Windows.Forms.ComboBox; $cmbMode.Location='20,130'; $cmbMode.Size='200,24'; $cmbMode.Items.AddRange(@('Append','Overwrite')); $cmbMode.Text=$settings.Logging.Mode
    $numMax = New-Object System.Windows.Forms.NumericUpDown; $numMax.Location='240,130'; $numMax.Size='120,24'; $numMax.Minimum=1; $numMax.Maximum=1024; $numMax.Value=[decimal]$settings.Logging.MaxFileMB
    $chkPrune = New-Object System.Windows.Forms.CheckBox; $chkPrune.Location='20,170'; $chkPrune.Text='Enable auto pruning'; $chkPrune.Checked=[bool]$settings.Logging.AutoPrune
    $chkVerbose = New-Object System.Windows.Forms.CheckBox; $chkVerbose.Location='20,200'; $chkVerbose.Text='Verbose console logging'; $chkVerbose.Checked=[bool]$settings.Logging.Verbose
    $btnSave = New-Object System.Windows.Forms.Button; $btnSave.Location='20,250'; $btnSave.Size='120,30'; $btnSave.Text='Save'

    $btnSave.add_Click({
        $settings.Logging.FileName = $txtLogName.Text
        $settings.Logging.LogDirectory = $txtLogDir.Text
        $settings.Logging.Mode = $cmbMode.Text
        $settings.Logging.MaxFileMB = [int]$numMax.Value
        $settings.Logging.AutoPrune = $chkPrune.Checked
        $settings.Logging.Verbose = $chkVerbose.Checked
        Save-Settings $settings
        Write-VerboseLog -Message 'Options saved.' -StatusTextBox $statusBox -Settings $settings
        $dlg.Close()
    })

    $dlg.Controls.AddRange(@($txtLogName,$txtLogDir,$cmbMode,$numMax,$chkPrune,$chkVerbose,$btnSave))
    $dlg.ShowDialog() | Out-Null
})

# Load saved pairs
foreach ($p in $settings.SyncPairs) {
    $script:syncPairs.Add([ordered]@{ Name=$p.Name; PathA=$p.PathA; PathB=$p.PathB })
    $pairGrid.Rows.Add($p.Name,$p.PathA,$p.PathB) | Out-Null
}

$form.Controls.AddRange(@($lblThread,$numThread,$githubLink,$pairGrid,$txtName,$txtA,$txtB,$btnBrowseA,$btnBrowseB,$btnAddPair,$btnRemovePair,$btnStart,$btnStop,$statusBox))
$form.add_FormClosing({ Stop-AllSync -settings $settings -statusBox $statusBox; $settings.App.ThreadCount=[int]$numThread.Value; Save-Settings $settings })

[void]$form.ShowDialog()
