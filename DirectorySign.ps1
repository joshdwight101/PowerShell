# DirectorySign - PowerShell Script Signer

Add-Type -AssemblyName System.Windows.Forms

# Window attributes
$windowTitle = "DirectorySign by Joshua Dwight"
$windowWidth = 400
$windowHeight = 150

# Create the main form
$form = New-Object Windows.Forms.Form
$form.Text = $windowTitle
$form.Width = $windowWidth
$form.Height = $windowHeight

# Create label and input field for the path
$pathLabel = New-Object Windows.Forms.Label
$pathLabel.Text = "Path:"
$pathLabel.AutoSize = $true  # Adjust label width to fit content
$pathLabel.Location = New-Object Drawing.Point 20, 25
$form.Controls.Add($pathLabel)

$pathTextBox = New-Object Windows.Forms.TextBox
$pathTextBox.Location = New-Object Drawing.Point 60, 20
$pathTextBox.Width = 225  # Decrease the width
$form.Controls.Add($pathTextBox)

# Create button to browse for directory
$browseButton = New-Object Windows.Forms.Button
$browseButton.Text = "Browse"
$browseButton.Location = New-Object Drawing.Point 290, 20
$browseButton.Add_Click({
    $folderBrowser = New-Object Windows.Forms.FolderBrowserDialog
    $result = $folderBrowser.ShowDialog()
    if ($result -eq [Windows.Forms.DialogResult]::OK) {
        $pathTextBox.Text = $folderBrowser.SelectedPath
    }
})
$form.Controls.Add($browseButton)


# Create button to add signature
$addSignatureButton = New-Object Windows.Forms.Button
$addSignatureButton.Text = "Add Signature"
$addSignatureButton.Location = New-Object Drawing.Point 150, 60
$addSignatureButton.Width = 200
$addSignatureButton.Height = 40
$addSignatureButton.Add_Click({
    $directory = $pathTextBox.Text
    if (-not (Test-Path $directory)) {
        Write-Host "Directory $directory does not exist."
        return
    }

    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
    Get-ChildItem -Path $directory -Include *.ps1,*.psm1 -Recurse | ForEach-Object {
        $file = $_.FullName
        Set-AuthenticodeSignature -FilePath $file -Certificate $cert
        Write-Host "Signed $file"
    }
})
$form.Controls.Add($addSignatureButton)

# Handle Enter key press for the input field
$pathTextBox.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $addSignatureButton.PerformClick()
    }
})

# Show the form
$form.ShowDialog() | Out-Null
