#requires -version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$AppTitle = 'Sage 300 DB Backup Utility'
$Version = 'v1.0.0'
$Author = 'Joshua Dwight'

function Write-UiLog {
    param(
        [System.Windows.Forms.TextBox]$TextBox,
        [string]$Message
    )
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $TextBox.AppendText($line + [Environment]::NewLine)
    $TextBox.SelectionStart = $TextBox.Text.Length
    $TextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SageDatabaseCandidates {
    param(
        [string]$SqlServer,
        [string]$SqlUser,
        [string]$SqlPassword,
        [switch]$UseIntegratedSecurity
    )

    Add-Type -AssemblyName System.Data
    $connString = if ($UseIntegratedSecurity) {
        "Server=$SqlServer;Database=master;Integrated Security=True;TrustServerCertificate=True"
    }
    else {
        "Server=$SqlServer;Database=master;User ID=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True"
    }

    $query = @"
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND name NOT IN ('master','model','msdb','tempdb')
  AND (name LIKE '%DAT' OR name LIKE '%SYS')
ORDER BY name;
"@

    $conn = New-Object System.Data.SqlClient.SqlConnection $connString
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $query
    $conn.Open()
    try {
        $reader = $cmd.ExecuteReader()
        $result = @()
        while ($reader.Read()) {
            $result += [string]$reader['name']
        }
        return $result
    }
    finally {
        $conn.Close()
    }
}

function Invoke-SageDbDumpBackup {
    param(
        [string]$RuntimePath,
        [string]$BackupRoot,
        [string[]]$DatabaseNames,
        [string]$SageAdminUser,
        [string]$SageAdminPassword,
        [System.Windows.Forms.TextBox]$LogBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$EtaLabel
    )

    $dbDumpPath = Join-Path $RuntimePath 'dbdump32.exe'
    if (-not (Test-Path $dbDumpPath)) {
        throw "dbdump32.exe not found at $dbDumpPath"
    }

    $runFolder = Join-Path $BackupRoot (Get-Date -Format 'yyyy-MM-dd')
    New-Item -Path $runFolder -ItemType Directory -Force | Out-Null

    $total = $DatabaseNames.Count
    $durations = New-Object System.Collections.Generic.List[double]
    $i = 0

    foreach ($db in $DatabaseNames) {
        $i++
        $friendlyTime = Get-Date -Format 'yyyy-MM-dd_hh-mm-ss_tt'
        $dbFolder = Join-Path $runFolder ("{0}_backup_{1}" -f $db, $friendlyTime)
        New-Item -Path $dbFolder -ItemType Directory -Force | Out-Null

        Write-UiLog -TextBox $LogBox -Message "Starting backup for $db"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $args = @("/U$SageAdminUser", "/P$SageAdminPassword", "/L$db", '/Q', "/D$dbFolder")
        $proc = Start-Process -FilePath $dbDumpPath -ArgumentList $args -WorkingDirectory $RuntimePath -PassThru -Wait -NoNewWindow
        $sw.Stop()

        if ($proc.ExitCode -ne 0) {
            Write-UiLog -TextBox $LogBox -Message "Backup FAILED for $db (exit code $($proc.ExitCode))"
            throw "dbdump32.exe failed for $db"
        }

        $durations.Add($sw.Elapsed.TotalSeconds)
        $percent = [math]::Round(($i / $total) * 100)
        $ProgressBar.Value = [Math]::Min([int]$percent, 100)

        $avg = ($durations | Measure-Object -Average).Average
        $remaining = [Math]::Max($total - $i, 0)
        $eta = [TimeSpan]::FromSeconds([Math]::Round($avg * $remaining))
        $EtaLabel.Text = "Estimated time remaining: {0:hh\:mm\:ss}" -f $eta

        Write-UiLog -TextBox $LogBox -Message "Completed backup for $db in $([int]$sw.Elapsed.TotalSeconds)s"
    }

    $EtaLabel.Text = 'Estimated time remaining: 00:00:00'
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppTitle $Version  |  Author: $Author"
$form.Size = New-Object System.Drawing.Size(980, 700)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = 'SQL Server:'
$lblServer.Location = New-Object System.Drawing.Point(20, 20)
$lblServer.AutoSize = $true
$form.Controls.Add($lblServer)

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Location = New-Object System.Drawing.Point(140, 16)
$txtServer.Size = New-Object System.Drawing.Size(280, 28)
$txtServer.Text = 'localhost'
$form.Controls.Add($txtServer)

$chkIntegrated = New-Object System.Windows.Forms.CheckBox
$chkIntegrated.Text = 'Use Windows Authentication'
$chkIntegrated.Location = New-Object System.Drawing.Point(440, 18)
$chkIntegrated.AutoSize = $true
$chkIntegrated.Checked = $true
$form.Controls.Add($chkIntegrated)

$lblSqlUser = New-Object System.Windows.Forms.Label
$lblSqlUser.Text = 'SQL User:'
$lblSqlUser.Location = New-Object System.Drawing.Point(20, 55)
$lblSqlUser.AutoSize = $true
$form.Controls.Add($lblSqlUser)

$txtSqlUser = New-Object System.Windows.Forms.TextBox
$txtSqlUser.Location = New-Object System.Drawing.Point(140, 50)
$txtSqlUser.Size = New-Object System.Drawing.Size(200, 28)
$txtSqlUser.Enabled = $false
$form.Controls.Add($txtSqlUser)

$lblSqlPass = New-Object System.Windows.Forms.Label
$lblSqlPass.Text = 'SQL Password:'
$lblSqlPass.Location = New-Object System.Drawing.Point(360, 55)
$lblSqlPass.AutoSize = $true
$form.Controls.Add($lblSqlPass)

$txtSqlPass = New-Object System.Windows.Forms.TextBox
$txtSqlPass.Location = New-Object System.Drawing.Point(480, 50)
$txtSqlPass.Size = New-Object System.Drawing.Size(220, 28)
$txtSqlPass.UseSystemPasswordChar = $true
$txtSqlPass.Enabled = $false
$form.Controls.Add($txtSqlPass)

$lblRuntime = New-Object System.Windows.Forms.Label
$lblRuntime.Text = 'Sage Runtime Path:'
$lblRuntime.Location = New-Object System.Drawing.Point(20, 90)
$lblRuntime.AutoSize = $true
$form.Controls.Add($lblRuntime)

$txtRuntime = New-Object System.Windows.Forms.TextBox
$txtRuntime.Location = New-Object System.Drawing.Point(140, 86)
$txtRuntime.Size = New-Object System.Drawing.Size(560, 28)
$txtRuntime.Text = 'C:\Sage300\runtime'
$form.Controls.Add($txtRuntime)

$lblBackupRoot = New-Object System.Windows.Forms.Label
$lblBackupRoot.Text = 'Backup Root:'
$lblBackupRoot.Location = New-Object System.Drawing.Point(20, 125)
$lblBackupRoot.AutoSize = $true
$form.Controls.Add($lblBackupRoot)

$txtBackupRoot = New-Object System.Windows.Forms.TextBox
$txtBackupRoot.Location = New-Object System.Drawing.Point(140, 121)
$txtBackupRoot.Size = New-Object System.Drawing.Size(560, 28)
$txtBackupRoot.Text = 'C:\Sage300\dbdump'
$form.Controls.Add($txtBackupRoot)

$btnDetect = New-Object System.Windows.Forms.Button
$btnDetect.Text = 'Detect Databases'
$btnDetect.Location = New-Object System.Drawing.Point(720, 16)
$btnDetect.Size = New-Object System.Drawing.Size(220, 36)
$form.Controls.Add($btnDetect)

$listDb = New-Object System.Windows.Forms.CheckedListBox
$listDb.Location = New-Object System.Drawing.Point(20, 170)
$listDb.Size = New-Object System.Drawing.Size(920, 200)
$listDb.CheckOnClick = $true
$form.Controls.Add($listDb)

$lblSageUser = New-Object System.Windows.Forms.Label
$lblSageUser.Text = 'Sage Admin User:'
$lblSageUser.Location = New-Object System.Drawing.Point(20, 390)
$lblSageUser.AutoSize = $true
$form.Controls.Add($lblSageUser)

$txtSageUser = New-Object System.Windows.Forms.TextBox
$txtSageUser.Location = New-Object System.Drawing.Point(160, 385)
$txtSageUser.Size = New-Object System.Drawing.Size(180, 28)
$txtSageUser.Text = 'ADMIN'
$form.Controls.Add($txtSageUser)

$lblSagePass = New-Object System.Windows.Forms.Label
$lblSagePass.Text = 'Sage Admin Password:'
$lblSagePass.Location = New-Object System.Drawing.Point(360, 390)
$lblSagePass.AutoSize = $true
$form.Controls.Add($lblSagePass)

$txtSagePass = New-Object System.Windows.Forms.TextBox
$txtSagePass.Location = New-Object System.Drawing.Point(530, 385)
$txtSagePass.Size = New-Object System.Drawing.Size(220, 28)
$txtSagePass.UseSystemPasswordChar = $true
$form.Controls.Add($txtSagePass)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Sequential Backup'
$btnStart.Location = New-Object System.Drawing.Point(770, 382)
$btnStart.Size = New-Object System.Drawing.Size(170, 34)
$form.Controls.Add($btnStart)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 430)
$progress.Size = New-Object System.Drawing.Size(920, 24)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$lblEta = New-Object System.Windows.Forms.Label
$lblEta.Text = 'Estimated time remaining: --:--:--'
$lblEta.Location = New-Object System.Drawing.Point(20, 460)
$lblEta.AutoSize = $true
$form.Controls.Add($lblEta)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(20, 490)
$logBox.Size = New-Object System.Drawing.Size(920, 150)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$form.Controls.Add($logBox)

$chkIntegrated.Add_CheckedChanged({
    $enabled = -not $chkIntegrated.Checked
    $txtSqlUser.Enabled = $enabled
    $txtSqlPass.Enabled = $enabled
})

$btnDetect.Add_Click({
    try {
        $listDb.Items.Clear()
        Write-UiLog -TextBox $logBox -Message 'Detecting Sage candidate databases...'
        $dbs = Get-SageDatabaseCandidates -SqlServer $txtServer.Text -SqlUser $txtSqlUser.Text -SqlPassword $txtSqlPass.Text -UseIntegratedSecurity:$chkIntegrated.Checked
        foreach ($db in $dbs) { [void]$listDb.Items.Add($db, $true) }
        Write-UiLog -TextBox $logBox -Message "Detected $($dbs.Count) database(s)."
    }
    catch {
        Write-UiLog -TextBox $logBox -Message "Detection error: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Detection failed', 'OK', 'Error') | Out-Null
    }
})

$btnStart.Add_Click({
    try {
        if ($listDb.CheckedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Select at least one database to backup.', 'No databases selected', 'OK', 'Warning') | Out-Null
            return
        }
        $selected = @()
        foreach ($item in $listDb.CheckedItems) { $selected += [string]$item }

        Write-UiLog -TextBox $logBox -Message "Backup job started. Selected DBs: $($selected -join ', ')"
        $progress.Value = 0
        Invoke-SageDbDumpBackup -RuntimePath $txtRuntime.Text -BackupRoot $txtBackupRoot.Text -DatabaseNames $selected -SageAdminUser $txtSageUser.Text -SageAdminPassword $txtSagePass.Text -LogBox $logBox -ProgressBar $progress -EtaLabel $lblEta
        Write-UiLog -TextBox $logBox -Message 'All selected database backups completed successfully.'
        [System.Windows.Forms.MessageBox]::Show('Backup completed successfully.', 'Complete', 'OK', 'Information') | Out-Null
    }
    catch {
        Write-UiLog -TextBox $logBox -Message "Backup error: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Backup failed', 'OK', 'Error') | Out-Null
    }
})

[void]$form.ShowDialog()
