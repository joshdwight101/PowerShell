# PowerShell Shortcut Maker
# by Joshua Dwight
# Version 1.1.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "PowerShell Shortcut Maker"
$form.Size = New-Object System.Drawing.Size(500,250)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Script Path Label
$labelScript = New-Object System.Windows.Forms.Label
$labelScript.Text = "PowerShell Script:"
$labelScript.Location = New-Object System.Drawing.Point(10,20)
$labelScript.Size = New-Object System.Drawing.Size(120,20)
$form.Controls.Add($labelScript)

# Script Path TextBox
$textScript = New-Object System.Windows.Forms.TextBox
$textScript.Location = New-Object System.Drawing.Point(130,20)
$textScript.Size = New-Object System.Drawing.Size(250,20)
$form.Controls.Add($textScript)

# Browse Button
$buttonBrowse = New-Object System.Windows.Forms.Button
$buttonBrowse.Text = "Browse"
$buttonBrowse.Location = New-Object System.Drawing.Point(390,18)
$buttonBrowse.Size = New-Object System.Drawing.Size(75,23)
$form.Controls.Add($buttonBrowse)

$buttonBrowse.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "PowerShell Scripts (*.ps1)|*.ps1"
    if ($openFileDialog.ShowDialog() -eq "OK") {
        $textScript.Text = $openFileDialog.FileName
    }
})

# Shortcut Name Label
$labelName = New-Object System.Windows.Forms.Label
$labelName.Text = "Shortcut Name:"
$labelName.Location = New-Object System.Drawing.Point(10,70)
$labelName.Size = New-Object System.Drawing.Size(120,20)
$form.Controls.Add($labelName)

# Shortcut Name TextBox
$textName = New-Object System.Windows.Forms.TextBox
$textName.Location = New-Object System.Drawing.Point(130,70)
$textName.Size = New-Object System.Drawing.Size(250,20)
$form.Controls.Add($textName)

# Create Button
$buttonCreate = New-Object System.Windows.Forms.Button
$buttonCreate.Text = "Create Shortcut"
$buttonCreate.Location = New-Object System.Drawing.Point(180,120)
$buttonCreate.Size = New-Object System.Drawing.Size(120,30)
$form.Controls.Add($buttonCreate)

# Create Shortcut Logic
$createShortcut = {
    if (-not (Test-Path $textScript.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid PowerShell script.")
        return
    }

    if ([string]::IsNullOrWhiteSpace($textName.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a shortcut name.")
        return
    }

    $scriptPath = $textScript.Text
    $shortcutName = $textName.Text
    $scriptDirectory = Split-Path $scriptPath
    $shortcutPath = Join-Path $scriptDirectory "$shortcutName.lnk"

    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)

    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    # Secure argument construction (Note: Do not change this to add ExecutionPolicy Bypass. You should use script signing.)
    # Learn about Script Signing @ https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5 
    $arguments = @(
        "-WindowStyle Hidden"
        "-NoProfile"
        "-File `"$scriptPath`""
    )

    $shortcut.Arguments = $arguments -join " "
    $shortcut.WorkingDirectory = $scriptDirectory
    $shortcut.Save()

    [System.Windows.Forms.MessageBox]::Show("Shortcut created successfully at:`n$shortcutPath")
}

$buttonCreate.Add_Click($createShortcut)

# Allow Enter Key to Trigger Creation
$form.AcceptButton = $buttonCreate

# Show Form
$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()