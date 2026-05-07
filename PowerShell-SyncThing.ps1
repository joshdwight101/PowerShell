#requires -Version 5.1
<#!
.SYNOPSIS
  PowerShell SyncThing by Joshua Dwight
.VERSION
  1.0.0
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
            MaxCoresLimit = 0
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
            switch ($pair.Mode) {
                'BtoA' { $msgs += Sync-Directory -Source $pair.PathB -Destination $pair.PathA }
                'AtoB' { $msgs += Sync-Directory -Source $pair.PathA -Destination $pair.PathB }
                default {
                    $msgs += Sync-Directory -Source $pair.PathA -Destination $pair.PathB
                    $msgs += Sync-Directory -Source $pair.PathB -Destination $pair.PathA
                }
            }
            if ($msgs.Count -eq 0) { "IDLE: No changes for pair '$($pair.Name)'" } else { $msgs }
            Start-Sleep -Milliseconds $settings.App.PollingMs
        }
    }).AddArgument($pair).AddArgument($settings)

    $coreCount = [Environment]::ProcessorCount
    $limit = [int]$settings.App.MaxCoresLimit
    $effectiveThreads = if ($limit -gt 0) { [Math]::Min($coreCount, $limit) } else { $coreCount }
    $effectiveThreads = [Math]::Max(1, $effectiveThreads)
    $ps.RunspacePool = [runspacefactory]::CreateRunspacePool(1, $effectiveThreads)
    $ps.RunspacePool.Open()
    $asyncResult = $ps.BeginInvoke()
    $script:workers[$pair.Name] = [ordered]@{ PowerShell = $ps; Handle = $asyncResult }
    Write-VerboseLog -Message "Started sync pair '$($pair.Name)' with thread cap $effectiveThreads (cores: $coreCount, limit: $limit)." -StatusTextBox $statusBox -Settings $settings
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
$form.Text = "$script:AppTitle v$script:AppVersion by $script:Author"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.StartPosition = 'CenterScreen'
$form.WindowState = 'Maximized'

$menu = New-Object System.Windows.Forms.MenuStrip

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
    $about = New-Object System.Windows.Forms.Form
    $about.Text = 'About PowerShell Sync-Thing'
    $about.Size = '520,300'
    $about.StartPosition = 'CenterParent'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = '20,20'; $lbl.Size = '470,170'
    $lbl.Text = "$script:AppTitle v$script:AppVersion`r`nAuthor: $script:Author`r`n`r`nPurpose:`r`nEnterprise-friendly sync manager with 1-way/2-way modes and UNC-aware path entry.`r`n`r`nKey Uses:`r`n- Manage many sync pairs in-grid`r`n- Per-pair sync mode toggle (B->A, A->B, 2-way)`r`n- Start/Stop sync workers`r`n- Verbose status + persistent logging"

    $lnk = New-Object System.Windows.Forms.LinkLabel
    $lnk.Location = '20,200'; $lnk.Size = '470,24'
    $lnk.Text = $script:GitHubUrl
    $lnk.add_Click({ Start-Process $script:GitHubUrl })

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Location = '400,225'; $btnOk.Size = '90,28'; $btnOk.Text = 'Close'
    $btnOk.add_Click({ $about.Close() })

    $about.Controls.AddRange(@($lbl,$lnk,$btnOk))
    $about.ShowDialog() | Out-Null
})
$manualItem.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
@"
PowerShell Sync-Thing - User Manual
Version: $script:AppVersion

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
$appTitleLabel = New-Object System.Windows.Forms.Label
$appTitleLabel.Location = '20,36'; $appTitleLabel.Size = '360,24'
$appTitleLabel.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$appTitleLabel.Text = 'PowerShell Sync-Thing'

$pairGridLabel = New-Object System.Windows.Forms.Label
$pairGridLabel.Location = '20,64'; $pairGridLabel.Size = '650,22'
$pairGridLabel.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
$pairGridLabel.Text = 'Sync Pair Configuration (edit directly in grid) - dynamic cores auto-detected'

$pairGrid = New-Object System.Windows.Forms.DataGridView
$pairGrid.Location = '20,90'; $pairGrid.Size = '1120,350'
$pairGrid.AllowUserToAddRows = $false
$pairGrid.AllowUserToDeleteRows = $false
$pairGrid.RowHeadersVisible = $false
$pairGrid.AutoSizeRowsMode = 'None'
$pairGrid.SelectionMode = 'CellSelect'
$pairGrid.Anchor = 'Top,Bottom,Left,Right'
$pairGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill

$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.Name = 'Name'; $colName.HeaderText = 'Sync Pair Name'; $colName.MinimumWidth = 160
$colPathA = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPathA.Name = 'PathA'; $colPathA.HeaderText = 'Directory Path A'; $colPathA.MinimumWidth = 260
$colBrowseA = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colBrowseA.Name = 'BrowseA'; $colBrowseA.HeaderText = 'Browse A'; $colBrowseA.MinimumWidth = 90; $colBrowseA.Text = 'Browse...'; $colBrowseA.UseColumnTextForButtonValue = $true
$colBrowseA.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
$colPathB = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPathB.Name = 'PathB'; $colPathB.HeaderText = 'Directory Path B'; $colPathB.MinimumWidth = 260
$colBrowseB = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colBrowseB.Name = 'BrowseB'; $colBrowseB.HeaderText = 'Browse B'; $colBrowseB.MinimumWidth = 90; $colBrowseB.Text = 'Browse...'; $colBrowseB.UseColumnTextForButtonValue = $true
$colBrowseB.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
$colMode = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colMode.Name = 'Mode'; $colMode.HeaderText = 'Sync Mode'; $colMode.MinimumWidth = 110; $colMode.Text = '<--2-way-->'; $colMode.UseColumnTextForButtonValue = $false
$colMode.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
$colDelete = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colDelete.Name = 'Delete'; $colDelete.HeaderText = 'Remove'; $colDelete.MinimumWidth = 80; $colDelete.Text = 'Delete'; $colDelete.UseColumnTextForButtonValue = $true
$colDelete.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
$gridColumns = [System.Windows.Forms.DataGridViewColumn[]]@($colName,$colPathA,$colBrowseA,$colPathB,$colBrowseB,$colMode,$colDelete)
$pairGrid.Columns.AddRange($gridColumns)

$btnAddRow = New-Object System.Windows.Forms.Button; $btnAddRow.Location='20,450'; $btnAddRow.Size='60,32'; $btnAddRow.Text='+'
$btnStart = New-Object System.Windows.Forms.Button; $btnStart.Location='100,450'; $btnStart.Size='170,32'; $btnStart.Text='Start Sync Server'
$btnStop = New-Object System.Windows.Forms.Button; $btnStop.Location='280,450'; $btnStop.Size='170,32'; $btnStop.Text='Stop Sync Server'
$btnAddRow.BackColor = [System.Drawing.Color]::FromArgb(170,230,170)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(0,100,0)
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(139,0,0)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnAddRow.Anchor = 'Left,Bottom'
$btnStart.Anchor = 'Left,Bottom'
$btnStop.Anchor = 'Left,Bottom'

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Location='20,495'; $statusBox.Size='1120,205'; $statusBox.Multiline=$true; $statusBox.ScrollBars='Vertical'
$statusBox.Anchor = 'Left,Right,Bottom'

$pathPicker = New-Object System.Windows.Forms.OpenFileDialog
$pathPicker.CheckFileExists = $false
$pathPicker.CheckPathExists = $true
$pathPicker.ValidateNames = $false
$pathPicker.FileName = 'Select Folder'
$pathPicker.Title = 'Select folder (supports UNC paths)'

$btnAddRow.add_Click({
    $pairGrid.Rows.Add('','','Browse...','','Browse...','<--2-way-->','Delete') | Out-Null
})

$pairGrid.add_CellContentClick({
    param($sender,$e)
    if ($e.RowIndex -lt 0) { return }
    $columnName = $pairGrid.Columns[$e.ColumnIndex].Name
    if ($columnName -eq 'BrowseA') {
        if ($pathPicker.ShowDialog() -eq 'OK') { $pairGrid.Rows[$e.RowIndex].Cells['PathA'].Value = Split-Path $pathPicker.FileName -Parent }
    } elseif ($columnName -eq 'BrowseB') {
        if ($pathPicker.ShowDialog() -eq 'OK') { $pairGrid.Rows[$e.RowIndex].Cells['PathB'].Value = Split-Path $pathPicker.FileName -Parent }
    } elseif ($columnName -eq 'Mode') {
        $current = [string]$pairGrid.Rows[$e.RowIndex].Cells['Mode'].Value
        $next = switch ($current) { '<--2-way-->' { '<--' } '<--' { '-->' } default { '<--2-way-->' } }
        $pairGrid.Rows[$e.RowIndex].Cells['Mode'].Value = $next
    } elseif ($columnName -eq 'Delete') {
        $pairGrid.Rows.RemoveAt($e.RowIndex)
    }
})

$btnStart.add_Click({
    $script:syncPairs.Clear()
    foreach ($row in $pairGrid.Rows) {
        $name = [string]$row.Cells['Name'].Value
        $pathA = [string]$row.Cells['PathA'].Value
        $pathB = [string]$row.Cells['PathB'].Value
        $modeLabel = [string]$row.Cells['Mode'].Value
        $modeValue = switch ($modeLabel) { '<--' { 'BtoA' } '-->' { 'AtoB' } default { 'TwoWay' } }
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($pathA) -or [string]::IsNullOrWhiteSpace($pathB)) { continue }
        $script:syncPairs.Add([ordered]@{ Name = $name.Trim(); PathA = $pathA.Trim(); PathB = $pathB.Trim(); Mode = $modeValue })
    }
    $settings.SyncPairs = @($script:syncPairs)
    Save-Settings $settings
    foreach ($pair in $script:syncPairs) { Start-SyncPair -pair $pair -settings $settings -statusBox $statusBox }
    Write-VerboseLog -Message 'Sync server started.' -StatusTextBox $statusBox -Settings $settings
})
$btnStop.add_Click({ Stop-AllSync -settings $settings -statusBox $statusBox; Write-VerboseLog -Message 'Sync server stopped.' -StatusTextBox $statusBox -Settings $settings })

$settingsItem.add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Application Options'; $dlg.Size = '620,450'
    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location='10,10'; $tabs.Size='585,360'
    $tabMain = New-Object System.Windows.Forms.TabPage('Main')
    $tabLogging = New-Object System.Windows.Forms.TabPage('Logging')
    $lblCoreLimit = New-Object System.Windows.Forms.Label
    $lblCoreLimit.Location='20,20'; $lblCoreLimit.Size='360,20'; $lblCoreLimit.Text='Max cores to use (0 = auto/all available)'
    $numCoreLimit = New-Object System.Windows.Forms.NumericUpDown
    $numCoreLimit.Location='20,44'; $numCoreLimit.Size='140,24'; $numCoreLimit.Minimum=0; $numCoreLimit.Maximum=256; $numCoreLimit.Value=[decimal]$settings.App.MaxCoresLimit
    $tabMain.Controls.AddRange(@($lblCoreLimit,$numCoreLimit))

    $lblLogName = New-Object System.Windows.Forms.Label; $lblLogName.Location='20,20'; $lblLogName.Size='160,20'; $lblLogName.Text='Log File Name'
    $txtLogName = New-Object System.Windows.Forms.TextBox; $txtLogName.Location='20,42'; $txtLogName.Size='520,24'; $txtLogName.Text=$settings.Logging.FileName
    $lblLogDir = New-Object System.Windows.Forms.Label; $lblLogDir.Location='20,76'; $lblLogDir.Size='220,20'; $lblLogDir.Text='Log Directory'
    $txtLogDir = New-Object System.Windows.Forms.TextBox; $txtLogDir.Location='20,98'; $txtLogDir.Size='520,24'; $txtLogDir.Text=$settings.Logging.LogDirectory
    $lblMode = New-Object System.Windows.Forms.Label; $lblMode.Location='20,132'; $lblMode.Size='120,20'; $lblMode.Text='Log Mode'
    $cmbMode = New-Object System.Windows.Forms.ComboBox; $cmbMode.Location='20,154'; $cmbMode.Size='220,24'; $cmbMode.Items.AddRange(@('Append','Overwrite')); $cmbMode.Text=$settings.Logging.Mode
    $lblMax = New-Object System.Windows.Forms.Label; $lblMax.Location='260,132'; $lblMax.Size='180,20'; $lblMax.Text='Max File Size (MB)'
    $numMax = New-Object System.Windows.Forms.NumericUpDown; $numMax.Location='260,154'; $numMax.Size='140,24'; $numMax.Minimum=1; $numMax.Maximum=1024; $numMax.Value=[decimal]$settings.Logging.MaxFileMB
    $chkPrune = New-Object System.Windows.Forms.CheckBox; $chkPrune.Location='20,194'; $chkPrune.Size='220,24'; $chkPrune.Text='Enable auto pruning'; $chkPrune.Checked=[bool]$settings.Logging.AutoPrune
    $chkVerbose = New-Object System.Windows.Forms.CheckBox; $chkVerbose.Location='20,224'; $chkVerbose.Size='240,24'; $chkVerbose.Text='Verbose console logging'; $chkVerbose.Checked=[bool]$settings.Logging.Verbose
    $btnSave = New-Object System.Windows.Forms.Button; $btnSave.Location='20,265'; $btnSave.Size='120,30'; $btnSave.Text='Save'

    $btnSave.add_Click({
        $settings.Logging.FileName = $txtLogName.Text
        $settings.Logging.LogDirectory = $txtLogDir.Text
        $settings.Logging.Mode = $cmbMode.Text
        $settings.Logging.MaxFileMB = [int]$numMax.Value
        $settings.Logging.AutoPrune = $chkPrune.Checked
        $settings.Logging.Verbose = $chkVerbose.Checked
        $settings.App.MaxCoresLimit = [int]$numCoreLimit.Value
        Save-Settings $settings
        Write-VerboseLog -Message 'Options saved.' -StatusTextBox $statusBox -Settings $settings
        $dlg.Close()
    })

    $tabLogging.Controls.AddRange(@($lblLogName,$txtLogName,$lblLogDir,$txtLogDir,$lblMode,$cmbMode,$lblMax,$numMax,$chkPrune,$chkVerbose,$btnSave))
    $tabs.TabPages.Add($tabMain) | Out-Null
    $tabs.TabPages.Add($tabLogging) | Out-Null
    $dlg.Controls.Add($tabs)
    $dlg.ShowDialog() | Out-Null
})

# Load saved pairs
foreach ($p in $settings.SyncPairs) {
    $modeLabel = switch ($p.Mode) { 'BtoA' { '<--' } 'AtoB' { '-->' } default { '<--2-way-->' } }
    $script:syncPairs.Add([ordered]@{ Name=$p.Name; PathA=$p.PathA; PathB=$p.PathB; Mode=$p.Mode })
    $pairGrid.Rows.Add($p.Name,$p.PathA,'Browse...',$p.PathB,'Browse...',$modeLabel,'Delete') | Out-Null
}

$form.Controls.AddRange(@($appTitleLabel,$pairGridLabel,$pairGrid,$btnAddRow,$btnStart,$btnStop,$statusBox))
$form.add_FormClosing({ Stop-AllSync -settings $settings -statusBox $statusBox; Save-Settings $settings })

[void]$form.ShowDialog()
