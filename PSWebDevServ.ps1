<#
.SYNOPSIS
PSWebDevServ - Portable web development server orchestration utility.

.DESCRIPTION
Portable web development server orchestration and automation tool for rapid
prototyping and deployment.

Title   : PSWebDevServ
Version : 1.2.0
Author  : Joshua Dwight (https://github.com/joshdwight101/)
#>

[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$App = [ordered]@{
    Name = 'PSWebDevServ'
    Version = '1.2.0'
    Author = 'Joshua Dwight'
    AuthorUrl = 'https://github.com/joshdwight101/'
    Purpose = 'Portable web development server orchestration and automation tool for rapid prototyping and deployment'
}
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$SettingsPath = Join-Path $ScriptRoot 'PSWebDevServ.settings.json'

$LoggingService = [pscustomobject]@{}
$LoggingService | Add-Member ScriptMethod Log {
    param([System.Windows.Forms.TextBox]$StatusBox,[string]$Message)
    $timestamp = (Get-Date -Format 'u')
    $line = "[$timestamp] $Message" + [Environment]::NewLine
    if ($StatusBox.InvokeRequired) {
        $appendAction = [Action[string]]{
            param($text)
            $StatusBox.AppendText($text)
        }
        $StatusBox.Invoke($appendAction, @($line)) | Out-Null
    } else {
        $StatusBox.AppendText($line)
    }
}

$SettingsManager = [pscustomobject]@{ Path = $SettingsPath }
$SettingsManager | Add-Member ScriptMethod Defaults {
    [ordered]@{
        ProjectRoot=''; Runtime='Node.js'; LocalHostUrl='http://localhost:8080'; AutoLaunchBrowser=$true; AutoRestartOnProjectChange=$true
        ServerStartCommand='npm run dev'; ServerStopCommand=''; AutoInstallDependencies=$true; EnableMailAutomation=$true
        MailHost='smtp.example.local'; MailPort=25; MailFrom='noreply@example.local'; UseOfflineSQLiteBridge=$true
        DbProvider='SQLite'; SQLiteDbPath='.\data\local-testing.db'; ConnectionString='Data Source=.\data\local-testing.db;Version=3;'
        SeedOnStart=$false; BackupBeforeTest=$true; EnableRapidImport=$true; EnableRapidTesting=$true; EnableRapidDeploy=$false
    }
}
$SettingsManager | Add-Member ScriptMethod Save { param([hashtable]$Settings) ; $Settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $this.Path -Encoding UTF8 }
$SettingsManager | Add-Member ScriptMethod Load {
    $d = $this.Defaults()
    if (-not (Test-Path -LiteralPath $this.Path)) { $this.Save($d); return $d }
    try {
        $j = Get-Content -Raw -LiteralPath $this.Path | ConvertFrom-Json
        foreach ($k in $d.Keys) { if ($j.PSObject.Properties[$k]) { $d[$k] = $j.$k } }
    } catch { $this.Save($d) }
    return $d
}

$ProjectManager = [pscustomobject]@{}
$ProjectManager | Add-Member ScriptMethod Detect {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    if (Test-Path (Join-Path $Path 'package.json')) { return @{Runtime='Node.js';Start='npm run dev';Install='npm install'} }
    if (Get-ChildItem -Path $Path -Filter '*.csproj' -File -ErrorAction SilentlyContinue) { return @{Runtime='.NET';Start='dotnet run';Install='dotnet restore'} }
    if (Test-Path (Join-Path $Path 'requirements.txt')) { return @{Runtime='Python';Start='python app.py';Install='python -m pip install -r requirements.txt'} }
    if (Test-Path (Join-Path $Path 'composer.json')) { return @{Runtime='PHP';Start='php -S localhost:8080 -t public';Install='composer install'} }
    if (Test-Path (Join-Path $Path 'Gemfile')) { return @{Runtime='Ruby';Start='bundle exec rails server';Install='bundle install'} }
    return $null
}

$DependencyManager = [pscustomobject]@{}
$DependencyManager | Add-Member ScriptMethod RuntimeChecks {
    @(
        @{Name='Node.js';Cmd='node --version'}, @{Name='.NET SDK';Cmd='dotnet --version'}, @{Name='Python';Cmd='python --version'},
        @{Name='PHP';Cmd='php --version'}, @{Name='Ruby';Cmd='ruby --version'}, @{Name='Git';Cmd='git --version'}
    )
}

$ServerManager = [pscustomobject]@{ Process = $null }
$ServerManager | Add-Member ScriptMethod Start {
    param([hashtable]$Settings,[System.Windows.Forms.TextBox]$StatusBox)
    if ($this.Process -and -not $this.Process.HasExited) { $LoggingService.Log($StatusBox,'Server already running.'); return }
    if ([string]::IsNullOrWhiteSpace($Settings.ProjectRoot) -or -not (Test-Path $Settings.ProjectRoot)) { $LoggingService.Log($StatusBox,'Invalid project root.'); return }
    try {
        $this.Process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $Settings.ServerStartCommand -WorkingDirectory $Settings.ProjectRoot -PassThru
        $LoggingService.Log($StatusBox,"Server started PID=$($this.Process.Id)")
        if ($Settings.AutoLaunchBrowser) { Start-Process $Settings.LocalHostUrl }
    } catch { $LoggingService.Log($StatusBox,"Server start failed: $($_.Exception.Message)") }
}
$ServerManager | Add-Member ScriptMethod Stop {
    param([hashtable]$Settings,[System.Windows.Forms.TextBox]$StatusBox)
    try {
        if ($this.Process -and -not $this.Process.HasExited) {
            if (-not [string]::IsNullOrWhiteSpace($Settings.ServerStopCommand)) { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $Settings.ServerStopCommand -WorkingDirectory $Settings.ProjectRoot -Wait -WindowStyle Hidden }
            $this.Process.Kill(); $this.Process.WaitForExit(); $LoggingService.Log($StatusBox,'Server stopped.')
        } else { $LoggingService.Log($StatusBox,'No server process to stop.') }
    } catch { $LoggingService.Log($StatusBox,"Server stop failed: $($_.Exception.Message)") }
}

$settings = $SettingsManager.Load()

$form = New-Object Windows.Forms.Form -Property @{ Text="$($App.Name) v$($App.Version) - $($App.Author)"; Width=1180; Height=820; StartPosition='CenterScreen' }
$menu = New-Object Windows.Forms.MenuStrip
$fileMenu = New-Object Windows.Forms.ToolStripMenuItem('File'); $helpMenu = New-Object Windows.Forms.ToolStripMenuItem('Help')
$mExit = New-Object Windows.Forms.ToolStripMenuItem('Exit'); $mAbout = New-Object Windows.Forms.ToolStripMenuItem('About')
$fileMenu.DropDownItems.Add($mExit)|Out-Null; $helpMenu.DropDownItems.Add($mAbout)|Out-Null; $menu.Items.AddRange(@($fileMenu,$helpMenu)); $form.Controls.Add($menu)

$tabs = New-Object Windows.Forms.TabControl -Property @{ Dock='Fill'; Location=[Drawing.Point]::new(0,24) }
$tabSetup=New-Object Windows.Forms.TabPage('Setup'); $tabDb=New-Object Windows.Forms.TabPage('Database'); $tabAuto=New-Object Windows.Forms.TabPage('Automation'); $tabOps=New-Object Windows.Forms.TabPage('Operations'); $tabStatus=New-Object Windows.Forms.TabPage('Status')
$tabs.TabPages.AddRange(@($tabSetup,$tabDb,$tabAuto,$tabOps,$tabStatus)); $form.Controls.Add($tabs)

$statusBox = New-Object Windows.Forms.TextBox -Property @{ Dock='Fill'; Multiline=$true; ReadOnly=$true; ScrollBars='Vertical' }; $tabStatus.Controls.Add($statusBox)
$progress = New-Object Windows.Forms.ProgressBar -Property @{ Width=350; Height=24; Minimum=0; Maximum=100; Value=0 }

$setup = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false; AutoScroll=$true }; $tabSetup.Controls.Add($setup)
$txtProject=New-Object Windows.Forms.TextBox -Property @{ Width=800; Text=[string]$settings.ProjectRoot }
$btnBrowse=New-Object Windows.Forms.Button -Property @{ Text='Browse Project'; Width=220 }
$cmbRuntime=New-Object Windows.Forms.ComboBox -Property @{ Width=250; DropDownStyle='DropDownList' }; $cmbRuntime.Items.AddRange(@('Node.js','.NET','Python','PHP','Ruby')); $cmbRuntime.SelectedItem=[string]$settings.Runtime; if($cmbRuntime.SelectedIndex -lt 0){$cmbRuntime.SelectedIndex=0}
$txtHost=New-Object Windows.Forms.TextBox -Property @{ Width=500; Text=[string]$settings.LocalHostUrl }
$chkBrowser=New-Object Windows.Forms.CheckBox -Property @{ Text='Auto-launch browser on start'; Checked=[bool]$settings.AutoLaunchBrowser; Width=350 }
$chkRestart=New-Object Windows.Forms.CheckBox -Property @{ Text='Auto-restart when project path changes'; Checked=[bool]$settings.AutoRestartOnProjectChange; Width=380 }
$txtStart=New-Object Windows.Forms.TextBox -Property @{ Width=800; Text=[string]$settings.ServerStartCommand }
$txtStop=New-Object Windows.Forms.TextBox -Property @{ Width=800; Text=[string]$settings.ServerStopCommand }
$link=New-Object Windows.Forms.LinkLabel -Property @{ Text="$($App.Author) ($($App.AuthorUrl))"; Width=600 }; $link.Links.Add(0,$link.Text.Length,$App.AuthorUrl)|Out-Null
$setup.Controls.AddRange(@((New-Object Windows.Forms.Label -Property @{Text='Project Root';Width=300}),$txtProject,$btnBrowse,(New-Object Windows.Forms.Label -Property @{Text='Runtime';Width=300}),$cmbRuntime,(New-Object Windows.Forms.Label -Property @{Text='LocalHost URL';Width=300}),$txtHost,$chkBrowser,$chkRestart,(New-Object Windows.Forms.Label -Property @{Text='Start Command';Width=300}),$txtStart,(New-Object Windows.Forms.Label -Property @{Text='Stop Command';Width=300}),$txtStop,$link))

$dbPanel=New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false; AutoScroll=$true }; $tabDb.Controls.Add($dbPanel)
$chkSqlite=New-Object Windows.Forms.CheckBox -Property @{ Text='Enable offline SQLite bridge'; Checked=[bool]$settings.UseOfflineSQLiteBridge; Width=320 }
$cmbDb=New-Object Windows.Forms.ComboBox -Property @{ Width=250; DropDownStyle='DropDownList' }; $cmbDb.Items.AddRange(@('SQLite','SQL Server','PostgreSQL','MySQL')); $cmbDb.SelectedItem=[string]$settings.DbProvider; if($cmbDb.SelectedIndex -lt 0){$cmbDb.SelectedIndex=0}
$txtDb=New-Object Windows.Forms.TextBox -Property @{ Width=800; Text=[string]$settings.SQLiteDbPath }
$txtConn=New-Object Windows.Forms.TextBox -Property @{ Width=800; Text=[string]$settings.ConnectionString }
$chkSeed=New-Object Windows.Forms.CheckBox -Property @{ Text='Seed on test start'; Checked=[bool]$settings.SeedOnStart }
$chkBackup=New-Object Windows.Forms.CheckBox -Property @{ Text='Backup before tests'; Checked=[bool]$settings.BackupBeforeTest }
$btnDbInit=New-Object Windows.Forms.Button -Property @{ Text='Initialize/Migrate DB'; Width=260 }
$dbPanel.Controls.AddRange(@($chkSqlite,(New-Object Windows.Forms.Label -Property @{Text='Provider'}),$cmbDb,(New-Object Windows.Forms.Label -Property @{Text='SQLite Path'}),$txtDb,(New-Object Windows.Forms.Label -Property @{Text='Connection String'}),$txtConn,$chkSeed,$chkBackup,$btnDbInit))

$autoPanel=New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false }
$tabAuto.Controls.Add($autoPanel)
$chkMail=New-Object Windows.Forms.CheckBox -Property @{ Text='Enable mailing automation'; Checked=[bool]$settings.EnableMailAutomation }
$txtMailHost=New-Object Windows.Forms.TextBox -Property @{ Width=600; Text=[string]$settings.MailHost }
$numMailPort=New-Object Windows.Forms.NumericUpDown -Property @{ Minimum=1; Maximum=65535; Value=[decimal]([int]$settings.MailPort) }
$txtMailFrom=New-Object Windows.Forms.TextBox -Property @{ Width=600; Text=[string]$settings.MailFrom }
$autoPanel.Controls.AddRange(@($chkMail,(New-Object Windows.Forms.Label -Property @{Text='SMTP Host'}),$txtMailHost,(New-Object Windows.Forms.Label -Property @{Text='SMTP Port'}),$numMailPort,(New-Object Windows.Forms.Label -Property @{Text='SMTP From'}),$txtMailFrom))

$ops=New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false }
$tabOps.Controls.Add($ops)
$btnInstallAll=New-Object Windows.Forms.Button -Property @{ Text='Install / Setup Everything'; Width=320 }
$btnStart=New-Object Windows.Forms.Button -Property @{ Text='Start Server'; Width=320 }
$btnStop=New-Object Windows.Forms.Button -Property @{ Text='Stop Server'; Width=320 }
$btnRestart=New-Object Windows.Forms.Button -Property @{ Text='Restart Server'; Width=320 }
$btnImport=New-Object Windows.Forms.Button -Property @{ Text='Import Project'; Width=320 }
$btnTest=New-Object Windows.Forms.Button -Property @{ Text='Test Project'; Width=320 }
$btnDeploy=New-Object Windows.Forms.Button -Property @{ Text='Deploy Project'; Width=320 }
$ops.Controls.AddRange(@($btnInstallAll,$progress,$btnStart,$btnStop,$btnRestart,$btnImport,$btnTest,$btnDeploy))

$saveNow = {
    $settings.ProjectRoot=$txtProject.Text; $settings.Runtime=[string]$cmbRuntime.SelectedItem; $settings.LocalHostUrl=$txtHost.Text; $settings.AutoLaunchBrowser=$chkBrowser.Checked
    $settings.AutoRestartOnProjectChange=$chkRestart.Checked; $settings.ServerStartCommand=$txtStart.Text; $settings.ServerStopCommand=$txtStop.Text
    $settings.UseOfflineSQLiteBridge=$chkSqlite.Checked; $settings.DbProvider=[string]$cmbDb.SelectedItem; $settings.SQLiteDbPath=$txtDb.Text; $settings.ConnectionString=$txtConn.Text
    $settings.SeedOnStart=$chkSeed.Checked; $settings.BackupBeforeTest=$chkBackup.Checked; $settings.EnableMailAutomation=$chkMail.Checked
    $settings.MailHost=$txtMailHost.Text; $settings.MailPort=[int]$numMailPort.Value; $settings.MailFrom=$txtMailFrom.Text
    $SettingsManager.Save($settings)
}
@($txtProject,$txtHost,$txtStart,$txtStop,$txtDb,$txtConn,$txtMailHost,$txtMailFrom)|%{$_.add_TextChanged({&$saveNow})}
@($chkBrowser,$chkRestart,$chkSqlite,$chkSeed,$chkBackup,$chkMail)|%{$_.add_CheckedChanged({&$saveNow})}
$cmbRuntime.add_SelectedIndexChanged({&$saveNow}); $cmbDb.add_SelectedIndexChanged({&$saveNow}); $numMailPort.add_ValueChanged({&$saveNow})

$btnBrowse.Add_Click({
    $d=New-Object Windows.Forms.FolderBrowserDialog
    if($d.ShowDialog() -eq 'OK'){
        $wasRunning = $ServerManager.Process -and -not $ServerManager.Process.HasExited
        if($wasRunning -and $chkRestart.Checked){ $LoggingService.Log($statusBox,'Project changed while running: stopping server...'); $ServerManager.Stop($settings,$statusBox) }
        $txtProject.Text = $d.SelectedPath
        $det = $ProjectManager.Detect($txtProject.Text)
        if($det){
            $cmbRuntime.SelectedItem=$det.Runtime; $txtStart.Text=$det.Start; $LoggingService.Log($statusBox,"Detected project runtime: $($det.Runtime)")
        } else { $LoggingService.Log($statusBox,'Project type not auto-detected.') }
        if($wasRunning -and $chkRestart.Checked){ $LoggingService.Log($statusBox,'Restarting server after project switch...'); $ServerManager.Start($settings,$statusBox) }
    }
})

$link.Add_LinkClicked({ param($s,$e) Start-Process $e.Link.LinkData })
$mAbout.Add_Click({ [Windows.Forms.MessageBox]::Show("$($App.Name)`nVersion: $($App.Version)`nPurpose: $($App.Purpose)`nAuthor: $($App.Author)`n$($App.AuthorUrl)","About $($App.Name)")|Out-Null })
$mExit.Add_Click({ $ServerManager.Stop($settings,$statusBox); $SettingsManager.Save($settings); $form.Close() })
$btnStart.Add_Click({ $ServerManager.Start($settings,$statusBox) })
$btnStop.Add_Click({ $ServerManager.Stop($settings,$statusBox) })
$btnRestart.Add_Click({ $ServerManager.Stop($settings,$statusBox); Start-Sleep -Milliseconds 400; $ServerManager.Start($settings,$statusBox) })
$btnDbInit.Add_Click({ $LoggingService.Log($statusBox,"DB action for $($settings.DbProvider): initialize/migrate placeholder.") })
$btnImport.Add_Click({ $LoggingService.Log($statusBox,'Import Project action triggered.') })
$btnTest.Add_Click({ $LoggingService.Log($statusBox,'Test Project action triggered.') })
$btnDeploy.Add_Click({ $LoggingService.Log($statusBox,'Deploy Project action triggered.') })

$worker = New-Object ComponentModel.BackgroundWorker
$worker.WorkerReportsProgress = $true
$worker.add_DoWork({
    param($sender,$e)
    $ctx = $e.Argument
    $steps = @()
    foreach($r in $DependencyManager.RuntimeChecks()) { $steps += @{Name="Check $($r.Name)"; Cmd=$r.Cmd; Dir=$ctx.Project} }
    $det = $ProjectManager.Detect($ctx.Project)
    if($det){ $steps += @{Name="Install project dependencies ($($det.Runtime))"; Cmd=$det.Install; Dir=$ctx.Project} }
    $count = [Math]::Max($steps.Count,1)
    for($i=0;$i -lt $steps.Count;$i++){
        $s = $steps[$i]; $ok=$true; $msg='OK'
        try { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $s.Cmd -WorkingDirectory $s.Dir -Wait -WindowStyle Hidden | Out-Null }
        catch { $ok=$false; $msg=$_.Exception.Message }
        $pct = [int](($i+1)/$count*100)
        $sender.ReportProgress($pct, [pscustomobject]@{Step=$s.Name;Success=$ok;Message=$msg})
    }
})
$worker.add_ProgressChanged({ param($s,$e) $progress.Value=[Math]::Min(100,[Math]::Max(0,$e.ProgressPercentage)); $u=$e.UserState; $LoggingService.Log($statusBox,("{0}: {1} ({2})" -f $u.Step, $(if($u.Success){'Success'}else{'Fail'}), $u.Message)) })
$worker.add_RunWorkerCompleted({ $LoggingService.Log($statusBox,'Install / Setup Everything finished.') })
$btnInstallAll.Add_Click({
    if([string]::IsNullOrWhiteSpace($txtProject.Text) -or -not (Test-Path $txtProject.Text)){ $LoggingService.Log($statusBox,'Set a valid project path first.'); return }
    if(-not $worker.IsBusy){ $progress.Value=0; $worker.RunWorkerAsync([pscustomobject]@{Project=$txtProject.Text}) }
})

$LoggingService.Log($statusBox, "$($App.Name) initialized in portable mode at: $ScriptRoot")
[void]$form.ShowDialog()
