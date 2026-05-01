#requires -Version 5.1
<#
.SYNOPSIS
  CertSage LE Toolkit - GUI PowerShell utility for Let's Encrypt certificate lifecycle management.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$AppName   = 'CertSage LE Toolkit'
$AppAuthor = 'Joshua Dwight'
$AppRepo   = 'https://github.com/joshdwight101/'
$VersionFile = Join-Path $PSScriptRoot '.certsage.version.json'

function Get-AppVersion {
    if (-not (Test-Path $VersionFile)) {
        [pscustomobject]@{ Major = 0; Minor = 1; Patch = 0 }
    }
    else {
        Get-Content -Path $VersionFile -Raw | ConvertFrom-Json
    }
}

function Save-AppVersion {
    param([int]$Major, [int]$Minor, [int]$Patch)
    [pscustomobject]@{ Major = $Major; Minor = $Minor; Patch = $Patch } |
        ConvertTo-Json | Set-Content -Path $VersionFile -Encoding UTF8
}

function Get-VersionString {
    $v = Get-AppVersion
    "{0}.{1}.{2}" -f $v.Major, $v.Minor, $v.Patch
}

if (-not (Test-Path $VersionFile)) {
    Save-AppVersion -Major 0 -Minor 1 -Patch 0
}

$AppVersion = Get-VersionString

$ConfigPath = Join-Path $PSScriptRoot 'certsage.config.json'
$DefaultCertDir = Join-Path $PSScriptRoot 'certs'

function Get-AppConfig {
    if (Test-Path $ConfigPath) {
        Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }
    else {
        [pscustomobject]@{ CertDirectory = $DefaultCertDir }
    }
}

function Save-AppConfig {
    param([string]$CertDirectory)
    [pscustomobject]@{ CertDirectory = $CertDirectory } |
        ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$config = Get-AppConfig
if (-not (Test-Path $config.CertDirectory)) {
    New-Item -Path $config.CertDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([System.Windows.Forms.TextBox]$Target, [string]$Message)
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Target.AppendText("[$ts] $Message`r`n")
}

function Ensure-Dependencies {
    param([System.Windows.Forms.TextBox]$Target)
    Write-Log $Target 'Checking PowerShell dependencies...'

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log $Target 'Installing NuGet provider...'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
    }

    if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
        Write-Log $Target 'Installing Posh-ACME module...'
        Install-Module -Name Posh-ACME -Repository PSGallery -Scope CurrentUser -Force
    }

    Import-Module Posh-ACME -ErrorAction Stop
    Write-Log $Target 'Dependencies are installed and loaded.'
}

function Parse-KeyValueText {
    param([string]$Text)
    $hash = @{}
    foreach ($line in ($Text -split "`n")) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith('#')) { continue }
        $parts = $trim -split '=', 2
        if ($parts.Count -eq 2) {
            $hash[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $hash
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName v$AppVersion - Author: $AppAuthor"
$form.Size = New-Object System.Drawing.Size(1100, 760)
$form.StartPosition = 'CenterScreen'

$menu = New-Object System.Windows.Forms.MenuStrip
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem('File')
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem('Exit')
$exitItem.add_Click({ $form.Close() })
$fileMenu.DropDownItems.Add($exitItem) | Out-Null

$optionsMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Options')
$certDirItem = New-Object System.Windows.Forms.ToolStripMenuItem('Set Certificates Directory')
$certDirItem.add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.SelectedPath = $script:config.CertDirectory
    if ($folderDialog.ShowDialog() -eq 'OK') {
        $script:config.CertDirectory = $folderDialog.SelectedPath
        Save-AppConfig -CertDirectory $script:config.CertDirectory
        $certPathBox.Text = $script:config.CertDirectory
    }
})
$optionsMenu.DropDownItems.Add($certDirItem) | Out-Null

$aboutMenu = New-Object System.Windows.Forms.ToolStripMenuItem('About')
$aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem('App and Author Info')
$aboutItem.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
@"$AppName
Version: $AppVersion
Author: $AppAuthor
GitHub: $AppRepo

A certificate power tool built specifically for Let's Encrypt users.
Supports account setup, issue, renew, revoke and import workflows via Posh-ACME (ACME API)."@,
'About') | Out-Null
})
$aboutMenu.DropDownItems.Add($aboutItem) | Out-Null

$menu.Items.AddRange(@($fileMenu, $optionsMenu, $aboutMenu))
$form.MainMenuStrip = $menu
$form.Controls.Add($menu)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 35)
$tabs.Size = New-Object System.Drawing.Size(1060, 680)
$form.Controls.Add($tabs)

$mainTab = New-Object System.Windows.Forms.TabPage('Operations')
$advTab = New-Object System.Windows.Forms.TabPage('API Controls')
$tabs.TabPages.AddRange(@($mainTab, $advTab))

$y = 20
function Add-Label($parent,$text,$x,$y){ $l=New-Object System.Windows.Forms.Label;$l.Text=$text;$l.Location=New-Object System.Drawing.Point($x,$y);$l.AutoSize=$true;$parent.Controls.Add($l);$l }
function Add-Text($parent,$x,$y,$w){ $t=New-Object System.Windows.Forms.TextBox;$t.Location=New-Object System.Drawing.Point($x,$y);$t.Size=New-Object System.Drawing.Size($w,22);$parent.Controls.Add($t);$t }
function Add-Combo($parent,$x,$y,$w,$items){ $c=New-Object System.Windows.Forms.ComboBox;$c.Location=New-Object System.Drawing.Point($x,$y);$c.Size=New-Object System.Drawing.Size($w,22);$c.DropDownStyle='DropDownList';$items|%{$null=$c.Items.Add($_)};$c.SelectedIndex=0;$parent.Controls.Add($c);$c }

Add-Label $mainTab 'Primary Domain:' 20 $y | Out-Null
$domainBox = Add-Text $mainTab 170 $y 280
Add-Label $mainTab 'SANs (comma separated):' 470 $y | Out-Null
$sansBox = Add-Text $mainTab 650 $y 300
$y += 35

Add-Label $mainTab 'Email:' 20 $y | Out-Null
$emailBox = Add-Text $mainTab 170 $y 280
Add-Label $mainTab 'Friendly Name:' 470 $y | Out-Null
$friendlyBox = Add-Text $mainTab 650 $y 300
$y += 35

Add-Label $mainTab 'Plugin:' 20 $y | Out-Null
$pluginBox = Add-Combo $mainTab 170 $y 150 @('Manual','Cloudflare','Route53','Azure','GoogleDomains')
Add-Label $mainTab 'Challenge Type:' 340 $y | Out-Null
$challengeBox = Add-Combo $mainTab 470 $y 120 @('dns-01','http-01','tls-alpn-01')
Add-Label $mainTab 'Key Length:' 620 $y | Out-Null
$keyLenBox = Add-Combo $mainTab 710 $y 120 @('ec-256','ec-384','rsa-2048','rsa-3072','rsa-4096')
$y += 35

Add-Label $mainTab 'Certificates Directory:' 20 $y | Out-Null
$certPathBox = Add-Text $mainTab 170 $y 780
$certPathBox.Text = $config.CertDirectory
$y += 45

$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = 'Install Dependencies'
$installBtn.Location = New-Object System.Drawing.Point(20, $y)
$installBtn.Size = New-Object System.Drawing.Size(160, 30)
$mainTab.Controls.Add($installBtn)

$newAcctBtn = New-Object System.Windows.Forms.Button
$newAcctBtn.Text = 'Create/Select ACME Account'
$newAcctBtn.Location = New-Object System.Drawing.Point(190, $y)
$newAcctBtn.Size = New-Object System.Drawing.Size(210, 30)
$mainTab.Controls.Add($newAcctBtn)

$issueBtn = New-Object System.Windows.Forms.Button
$issueBtn.Text = 'Obtain Certificate'
$issueBtn.Location = New-Object System.Drawing.Point(410, $y)
$issueBtn.Size = New-Object System.Drawing.Size(140, 30)
$mainTab.Controls.Add($issueBtn)

$renewBtn = New-Object System.Windows.Forms.Button
$renewBtn.Text = 'Renew Certificate'
$renewBtn.Location = New-Object System.Drawing.Point(560, $y)
$renewBtn.Size = New-Object System.Drawing.Size(140, 30)
$mainTab.Controls.Add($renewBtn)

$revokeBtn = New-Object System.Windows.Forms.Button
$revokeBtn.Text = 'Revoke Certificate'
$revokeBtn.Location = New-Object System.Drawing.Point(710, $y)
$revokeBtn.Size = New-Object System.Drawing.Size(140, 30)
$mainTab.Controls.Add($revokeBtn)

$listBtn = New-Object System.Windows.Forms.Button
$listBtn.Text = 'List Orders'
$listBtn.Location = New-Object System.Drawing.Point(860, $y)
$listBtn.Size = New-Object System.Drawing.Size(120, 30)
$mainTab.Controls.Add($listBtn)

$y += 45
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(20, $y)
$logBox.Size = New-Object System.Drawing.Size(1000, 480)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$mainTab.Controls.Add($logBox)

Add-Label $advTab 'Advanced Parameters (key=value, one per line). Used for plugin args and granular API settings:' 20 20 | Out-Null
$advBox = New-Object System.Windows.Forms.TextBox
$advBox.Location = New-Object System.Drawing.Point(20, 45)
$advBox.Size = New-Object System.Drawing.Size(1000, 520)
$advBox.Multiline = $true
$advBox.ScrollBars = 'Vertical'
$advBox.Text = @'
# Examples
# CFToken=xxxxx
# DNSSleep=120
# LifetimeDays=90
# UseModernPfxEncryption=True
'@
$advTab.Controls.Add($advBox)

$installBtn.add_Click({
    try { Ensure-Dependencies -Target $logBox } catch { Write-Log $logBox $_.Exception.Message }
})

$newAcctBtn.add_Click({
    try {
        Ensure-Dependencies -Target $logBox
        $email = $emailBox.Text.Trim()
        if (-not $email) { throw 'Email is required for account registration.' }
        New-PAAccount -Contact "mailto:$email" -AcceptTOS -ErrorAction Stop | Out-Null
        Write-Log $logBox "ACME account ready for $email"
    } catch { Write-Log $logBox $_.Exception.Message }
})

$issueBtn.add_Click({
    try {
        Ensure-Dependencies -Target $logBox
        $domain = $domainBox.Text.Trim()
        if (-not $domain) { throw 'Primary domain is required.' }
        $args = Parse-KeyValueText -Text $advBox.Text
        $plugins = if ($pluginBox.Text -eq 'Manual') { @('Manual') } else { @($pluginBox.Text) }
        $allDomains = @($domain) + (($sansBox.Text -split ',').Trim() | Where-Object { $_ })
        $params = @{
            Domain = $allDomains
            AcceptTOS = $true
            Plugin = $plugins
            ChallengeType = $challengeBox.Text
            KeyLength = $keyLenBox.Text
            Install = $true
            PfxPassSecure = (ConvertTo-SecureString -String 'changeit' -AsPlainText -Force)
        }
        foreach ($k in $args.Keys) { $params[$k] = $args[$k] }
        $cert = New-PACertificate @params -ErrorAction Stop
        Write-Log $logBox "Certificate issued: $($cert.MainDomain)"
        Write-Log $logBox "Output path: $($cert.PfxFullChain)"
    } catch { Write-Log $logBox $_.Exception.Message }
})

$renewBtn.add_Click({
    try {
        Ensure-Dependencies -Target $logBox
        Submit-Renewal -AllOrders -ErrorAction Stop | Out-Null
        Write-Log $logBox 'Renewal job submitted for all eligible orders.'
    } catch { Write-Log $logBox $_.Exception.Message }
})

$revokeBtn.add_Click({
    try {
        Ensure-Dependencies -Target $logBox
        $domain = $domainBox.Text.Trim()
        if (-not $domain) { throw 'Domain is required to revoke.' }
        Revoke-PACertificate -MainDomain $domain -ErrorAction Stop
        Write-Log $logBox "Revoked certificate for $domain"
    } catch { Write-Log $logBox $_.Exception.Message }
})

$listBtn.add_Click({
    try {
        Ensure-Dependencies -Target $logBox
        $orders = Get-PAOrder
        foreach ($o in $orders) {
            Write-Log $logBox ("Order: {0} | Status: {1} | Expires: {2}" -f $o.MainDomain, $o.status, $o.expires)
        }
    } catch { Write-Log $logBox $_.Exception.Message }
})

[void]$form.ShowDialog()
