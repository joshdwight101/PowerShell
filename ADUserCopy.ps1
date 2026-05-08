<#
.SYNOPSIS
ADUserCopy - Active Directory user lifecycle automation utility.

.VERSION
1.0.0

.AUTHOR
Joshua Dwight
https://github.com/joshdwight101/
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#requires -Modules ActiveDirectory
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$Script:AppName = 'ADUserCopy'
$Script:Version = '1.0.0'
$Script:Author = 'Joshua Dwight'
$Script:AuthorUrl = 'https://github.com/joshdwight101/'
$Script:DataDir = Join-Path $env:ProgramData 'ADUserCopy'
$Script:SettingsFile = Join-Path $Script:DataDir 'settings.json'
$Script:DescriptionsFile = Join-Path $Script:DataDir 'descriptions.json'
$Script:TemplateFile = Join-Path $Script:DataDir 'emailTemplate.txt'

if (-not (Test-Path $Script:DataDir)) { New-Item -Path $Script:DataDir -ItemType Directory | Out-Null }

function Get-JsonFile {
    param([string]$Path, $Default)
    if (-not (Test-Path $Path)) { return $Default }
    try { return (Get-Content -Raw -Path $Path | ConvertFrom-Json) }
    catch { return $Default }
}

function Set-JsonFile {
    param([string]$Path, $Object)
    $Object | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function New-StrongPassword {
    param(
        [int]$Length = 16,
        [bool]$Upper = $true,
        [bool]$Lower = $true,
        [bool]$Numbers = $true,
        [bool]$Symbols = $true
    )

    $upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $lowerChars = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $numberChars = '0123456789'.ToCharArray()
    $symbolChars = '!@#$%^&*()-_=+[]{}:;,.?'.ToCharArray()

    $charSets = @()
    if ($Upper) { $charSets += ,$upperChars }
    if ($Lower) { $charSets += ,$lowerChars }
    if ($Numbers) { $charSets += ,$numberChars }
    if ($Symbols) { $charSets += ,$symbolChars }

    if ($charSets.Count -eq 0) { throw 'Select at least one character type for password generation.' }

    $allChars = ($charSets | ForEach-Object { $_ })
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] ($Length * 4)
    $rng.GetBytes($bytes)

    $result = New-Object System.Collections.Generic.List[char]
    foreach ($set in $charSets) {
        $result.Add($set[$bytes[$result.Count] % $set.Length])
    }
    while ($result.Count -lt $Length) {
        $idx = $bytes[$result.Count] % $allChars.Length
        $result.Add($allChars[$idx])
    }

    for ($i = $result.Count - 1; $i -gt 0; $i--) {
        $b = New-Object byte[] 1
        $rng.GetBytes($b)
        $j = $b[0] % ($i + 1)
        $tmp = $result[$i]
        $result[$i] = $result[$j]
        $result[$j] = $tmp
    }

    -join $result
}

function Get-AllDomainUsers {
    Get-ADUser -Filter * -Properties DisplayName,SamAccountName,Mail,Description,TelephoneNumber,DistinguishedName,OfficePhone,Department,Title |
        Sort-Object SamAccountName
}

function Get-AllOUs {
    Get-ADOrganizationalUnit -Filter * | Sort-Object Name
}

function Copy-UserGroups {
    param([string]$SourceSam, [string]$TargetSam, [switch]$Additive)
    $sourceGroups = Get-ADPrincipalGroupMembership -Identity $SourceSam | Where-Object { $_.Name -ne 'Domain Users' }
    if (-not $Additive) {
        $targetGroups = Get-ADPrincipalGroupMembership -Identity $TargetSam | Where-Object { $_.Name -ne 'Domain Users' }
        foreach ($g in $targetGroups) { Remove-ADGroupMember -Identity $g -Members $TargetSam -Confirm:$false -ErrorAction SilentlyContinue }
    }
    foreach ($g in $sourceGroups) { Add-ADGroupMember -Identity $g -Members $TargetSam -ErrorAction SilentlyContinue }
}

function Create-NewCopiedUser {
    param(
        [string]$SourceSam,
        [string]$NewGiven,
        [string]$NewSurname,
        [string]$NewSam,
        [string]$NewUPN,
        [string]$Password,
        [string]$TargetOU,
        [string]$Description
    )

    $source = Get-ADUser -Identity $SourceSam -Properties *
    if (-not $TargetOU) { $TargetOU = ($source.DistinguishedName -replace '^CN=.*?,') }

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    New-ADUser -Name "$NewGiven $NewSurname" -GivenName $NewGiven -Surname $NewSurname -SamAccountName $NewSam -UserPrincipalName $NewUPN `
        -EmailAddress $NewUPN -DisplayName "$NewGiven $NewSurname" -Path $TargetOU -Enabled $true -AccountPassword $securePassword `
        -Description $Description -OfficePhone $source.OfficePhone -Department $source.Department -Title $source.Title -OtherAttributes @{telephoneNumber=$source.telephoneNumber}

    Copy-UserGroups -SourceSam $SourceSam -TargetSam $NewSam -Additive
}

function Disable-UserWorkflow {
    param([string]$Sam,[string]$TempPassword,[string]$DefaultDisabledOU,[switch]$MoveToOu)
    Set-ADAccountPassword -Identity $Sam -Reset -NewPassword (ConvertTo-SecureString $TempPassword -AsPlainText -Force)
    Disable-ADAccount -Identity $Sam
    if ($MoveToOu -and $DefaultDisabledOU) {
        Move-ADObject -Identity (Get-ADUser $Sam).DistinguishedName -TargetPath $DefaultDisabledOU
    }
}

$settings = Get-JsonFile -Path $Script:SettingsFile -Default @{ DefaultDisabledOU = '' }
$descriptions = Get-JsonFile -Path $Script:DescriptionsFile -Default @('Employee','Contractor','Intern')
$template = if (Test-Path $Script:TemplateFile) { Get-Content -Raw $Script:TemplateFile } else { "Hello {DisplayName},`r`nUsername: {SamAccountName}`r`nTemporary Password: {Password}" }

$form = New-Object Windows.Forms.Form
$form.Text = "$($Script:AppName) v$($Script:Version) - $($Script:Author)"
$form.Size = New-Object Drawing.Size(1200,760)
$form.StartPosition = 'CenterScreen'

$menuStrip = New-Object Windows.Forms.MenuStrip
$fileMenu = New-Object Windows.Forms.ToolStripMenuItem('File')
$helpMenu = New-Object Windows.Forms.ToolStripMenuItem('Help')
$exitItem = New-Object Windows.Forms.ToolStripMenuItem('Exit')
$aboutItem = New-Object Windows.Forms.ToolStripMenuItem('About ADUserCopy')
$exitItem.add_Click({ $form.Close() })
$aboutItem.add_Click({
    [Windows.Forms.MessageBox]::Show("ADUserCopy v$($Script:Version)`r`nAuthor: $($Script:Author)`r`n$($Script:AuthorUrl)`r`n`r`nBuilt for domain controllers to streamline AD user creation, group mirroring/additive copy, password generation, deactivation workflows, and email template automation.", 'About ADUserCopy')
})
$fileMenu.DropDownItems.Add($exitItem) | Out-Null
$helpMenu.DropDownItems.Add($aboutItem) | Out-Null
$menuStrip.Items.AddRange(@($fileMenu,$helpMenu))
$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

$tabUsers = New-Object Windows.Forms.TabPage('User Copy / Group Mirror')
$tabPassword = New-Object Windows.Forms.TabPage('Password Generator')
$tabDescriptions = New-Object Windows.Forms.TabPage('Descriptions')
$tabEmail = New-Object Windows.Forms.TabPage('Email Templates')
$tabDeactivate = New-Object Windows.Forms.TabPage('User Deactivation')
$tabs.TabPages.AddRange(@($tabUsers,$tabPassword,$tabDescriptions,$tabEmail,$tabDeactivate))

# Users tab controls
$userGrid = New-Object Windows.Forms.DataGridView
$userGrid.Dock = 'Left'; $userGrid.Width = 520; $userGrid.ReadOnly = $true; $userGrid.SelectionMode = 'FullRowSelect'
$tabUsers.Controls.Add($userGrid)
$users = Get-AllDomainUsers
$userGrid.DataSource = $users

$panel = New-Object Windows.Forms.Panel
$panel.Dock = 'Fill'
$tabUsers.Controls.Add($panel)

$labels = @('Source SAM','New Given Name','New Surname','New SAM','New UPN','Email (Auto)','Description','Target OU (optional)')
$boxes = @{}
for ($i=0;$i -lt $labels.Count;$i++) {
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $labels[$i]; $lbl.Location = New-Object Drawing.Point(10,(20+($i*35))); $lbl.AutoSize = $true
    $tb = New-Object Windows.Forms.TextBox
    $tb.Location = New-Object Drawing.Point(170,(15+($i*35))); $tb.Width = 450
    $panel.Controls.AddRange(@($lbl,$tb)); $boxes[$labels[$i]] = $tb
}

$descDrop = New-Object Windows.Forms.ComboBox
$descDrop.Location = New-Object Drawing.Point(170,225); $descDrop.Width=450; $descDrop.DropDownStyle='DropDownList'
$descDrop.Items.AddRange([string[]]$descriptions)
$panel.Controls.Add($descDrop)

$ouList = New-Object Windows.Forms.ListBox
$ouList.Location = New-Object Drawing.Point(170,295); $ouList.Size = New-Object Drawing.Size(450,120)
$ouList.Items.AddRange([string[]](Get-AllOUs | ForEach-Object DistinguishedName))
$panel.Controls.Add($ouList)

$btnCreate = New-Object Windows.Forms.Button
$btnCreate.Text = 'Create New User from Copy'
$btnCreate.Location = New-Object Drawing.Point(170,430)
$btnMirror = New-Object Windows.Forms.Button
$btnMirror.Text = 'Mirror Groups to Existing User'
$btnMirror.Location = New-Object Drawing.Point(170,470)
$btnAdditive = New-Object Windows.Forms.Button
$btnAdditive.Text = 'Additive Group Copy'
$btnAdditive.Location = New-Object Drawing.Point(380,470)
$panel.Controls.AddRange(@($btnCreate,$btnMirror,$btnAdditive))

# Password tab
$lenTrack = New-Object Windows.Forms.TrackBar
$lenTrack.Minimum = 8; $lenTrack.Maximum = 64; $lenTrack.Value = 16; $lenTrack.Location = '20,30'; $lenTrack.Width=300
$lenLbl = New-Object Windows.Forms.Label
$lenLbl.Text = 'Length: 16'; $lenLbl.Location = '340,30'; $lenLbl.AutoSize = $true
$checks = @{}
foreach ($entry in @(@('Uppercase',20,80),@('Lowercase',20,110),@('Numbers',20,140),@('Symbols',20,170))) {
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = $entry[0]; $cb.Location = New-Object Drawing.Point($entry[1],$entry[2]); $cb.Checked = $true
    $checks[$entry[0]] = $cb; $tabPassword.Controls.Add($cb)
}
$pwdOut = New-Object Windows.Forms.TextBox
$pwdOut.Location='20,220'; $pwdOut.Width=500
$genBtn = New-Object Windows.Forms.Button
$genBtn.Text='Generate'; $genBtn.Location='20,260'
$usePwdForCreate = New-Object Windows.Forms.CheckBox
$usePwdForCreate.Text='Use generated password for new user creation'; $usePwdForCreate.Location='120,265'; $usePwdForCreate.Checked=$true
$tabPassword.Controls.AddRange(@($lenTrack,$lenLbl,$pwdOut,$genBtn,$usePwdForCreate))
$lenTrack.add_Scroll({ $lenLbl.Text = "Length: $($lenTrack.Value)" })
$genBtn.add_Click({ $pwdOut.Text = New-StrongPassword -Length $lenTrack.Value -Upper $checks['Uppercase'].Checked -Lower $checks['Lowercase'].Checked -Numbers $checks['Numbers'].Checked -Symbols $checks['Symbols'].Checked })

# Descriptions tab
$descList = New-Object Windows.Forms.ListBox
$descList.Location='20,20';$descList.Size='500,280';$descList.Items.AddRange([string[]]$descriptions)
$descInput = New-Object Windows.Forms.TextBox
$descInput.Location='20,320';$descInput.Width=380
$addDesc = New-Object Windows.Forms.Button
$addDesc.Text='Add';$addDesc.Location='420,318'
$removeDesc = New-Object Windows.Forms.Button
$removeDesc.Text='Remove Selected';$removeDesc.Location='20,360'
$tabDescriptions.Controls.AddRange(@($descList,$descInput,$addDesc,$removeDesc))

# Email tab
$emailEdit = New-Object Windows.Forms.TextBox
$emailEdit.Multiline = $true; $emailEdit.ScrollBars='Vertical'; $emailEdit.Location='20,20'; $emailEdit.Size='520,260'; $emailEdit.Text=$template
$emailPreview = New-Object Windows.Forms.TextBox
$emailPreview.Multiline = $true; $emailPreview.ScrollBars='Vertical'; $emailPreview.Location='560,20'; $emailPreview.Size='520,260'
$saveTemplate = New-Object Windows.Forms.Button
$saveTemplate.Text='Save Template'; $saveTemplate.Location='20,300'
$previewTemplate = New-Object Windows.Forms.Button
$previewTemplate.Text='Preview'; $previewTemplate.Location='140,300'
$copyEmail = New-Object Windows.Forms.Button
$copyEmail.Text='Copy Output'; $copyEmail.Location='230,300'
$tabEmail.Controls.AddRange(@($emailEdit,$emailPreview,$saveTemplate,$previewTemplate,$copyEmail))

# Deactivate tab
$deSam = New-Object Windows.Forms.TextBox; $deSam.Location='180,30';$deSam.Width=300
$deOu = New-Object Windows.Forms.TextBox; $deOu.Location='180,70';$deOu.Width=700; $deOu.Text=[string]$settings.DefaultDisabledOU
$deMove = New-Object Windows.Forms.CheckBox; $deMove.Text='Move to default deactivation OU'; $deMove.Location='180,110'; $deMove.Checked=$true
$dePwd = New-Object Windows.Forms.TextBox; $dePwd.Location='180,150';$dePwd.Width=300
$deGen = New-Object Windows.Forms.Button; $deGen.Text='Generate Password'; $deGen.Location='500,147'
$deRun = New-Object Windows.Forms.Button; $deRun.Text='Disable User Workflow'; $deRun.Location='180,190'
foreach ($pair in @(@('User SAM',30),@('Default Disabled OU',70),@('Temporary Password',150))) {
  $l=New-Object Windows.Forms.Label;$l.Text=$pair[0];$l.Location=New-Object Drawing.Point(20,$pair[1]);$l.AutoSize=$true;$tabDeactivate.Controls.Add($l)
}
$tabDeactivate.Controls.AddRange(@($deSam,$deOu,$deMove,$dePwd,$deGen,$deRun))

# Events
$userGrid.add_SelectionChanged({
    if ($userGrid.SelectedRows.Count -gt 0) {
        $r = $userGrid.SelectedRows[0].DataBoundItem
        $boxes['Source SAM'].Text = $r.SamAccountName
        $boxes['Email (Auto)'].Text = $r.Mail
        $boxes['Description'].Text = $r.Description
    }
})

$btnCreate.add_Click({
    $desc = if ($descDrop.SelectedItem) { [string]$descDrop.SelectedItem } else { $boxes['Description'].Text }
    $targetOu = if ($ouList.SelectedItem) { [string]$ouList.SelectedItem } else { $boxes['Target OU (optional)'].Text }
    $passwordToUse = if ($usePwdForCreate.Checked -and $pwdOut.Text) { $pwdOut.Text } else { New-StrongPassword }
    Create-NewCopiedUser -SourceSam $boxes['Source SAM'].Text -NewGiven $boxes['New Given Name'].Text -NewSurname $boxes['New Surname'].Text -NewSam $boxes['New SAM'].Text -NewUPN $boxes['New UPN'].Text -Password $passwordToUse -TargetOU $targetOu -Description $desc
    [Windows.Forms.MessageBox]::Show('User created and group memberships copied successfully.')
})

$btnMirror.add_Click({
    $target = [Windows.Forms.Interaction]::InputBox('Target existing user SAM for mirroring:','Mirror Groups','')
    if ($target) { Copy-UserGroups -SourceSam $boxes['Source SAM'].Text -TargetSam $target; [Windows.Forms.MessageBox]::Show('Mirrored successfully.') }
})
$btnAdditive.add_Click({
    $target = [Windows.Forms.Interaction]::InputBox('Target existing user SAM for additive group copy:','Additive Groups','')
    if ($target) { Copy-UserGroups -SourceSam $boxes['Source SAM'].Text -TargetSam $target -Additive; [Windows.Forms.MessageBox]::Show('Additive copy done.') }
})

$addDesc.add_Click({ if ($descInput.Text) { $descList.Items.Add($descInput.Text); $descDrop.Items.Add($descInput.Text); $descInput.Clear() } })
$removeDesc.add_Click({ if ($descList.SelectedItem) { $descDrop.Items.Remove($descList.SelectedItem); $descList.Items.Remove($descList.SelectedItem) } })
$form.add_FormClosing({
    Set-JsonFile -Path $Script:DescriptionsFile -Object @($descList.Items)
    Set-JsonFile -Path $Script:SettingsFile -Object @{ DefaultDisabledOU = $deOu.Text }
})

$saveTemplate.add_Click({ $emailEdit.Text | Set-Content -Path $Script:TemplateFile -Encoding UTF8; [Windows.Forms.MessageBox]::Show('Template saved.') })
$previewTemplate.add_Click({
    $preview = $emailEdit.Text.Replace('{DisplayName}',"$($boxes['New Given Name'].Text) $($boxes['New Surname'].Text)").Replace('{SamAccountName}',$boxes['New SAM'].Text).Replace('{Password}',$pwdOut.Text)
    $emailPreview.Text = $preview
})
$copyEmail.add_Click({ [Windows.Forms.Clipboard]::SetText($emailPreview.Text); [Windows.Forms.MessageBox]::Show('Copied to clipboard.') })

$deGen.add_Click({ $dePwd.Text = New-StrongPassword -Length 18 })
$deRun.add_Click({
    Disable-UserWorkflow -Sam $deSam.Text -TempPassword $dePwd.Text -DefaultDisabledOU $deOu.Text -MoveToOu:($deMove.Checked)
    [Windows.Forms.MessageBox]::Show('Deactivation workflow complete.')
})

[void]$form.ShowDialog()
