Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Set the dimensions and title of the window
$window = New-Object System.Windows.Forms.Form
$window.Text = 'Random String Generator'
$window.Size = New-Object System.Drawing.Size(400,260)
$window.FormBorderStyle = 'FixedDialog'
$window.MaximizeBox = $false

# Create a label to display the string length
$lengthLabel = New-Object System.Windows.Forms.Label
$lengthLabel.Font = New-Object System.Drawing.Font($lengthLabel.Font.FontFamily, 26)  # Set the font size to 32
$lengthLabel.Location = New-Object System.Drawing.Point(150,20)  # Position the label above the slider
$lengthLabel.Size = New-Object System.Drawing.Size(300,40)  # Adjust the size to fit the larger font
$window.Controls.Add($lengthLabel)

# Create the slider for string length
$slider = New-Object System.Windows.Forms.TrackBar
$slider.Minimum = 1
$slider.Maximum = 255
$slider.TickFrequency = 255
$slider.Location = New-Object System.Drawing.Point(50,70)  # Moved the slider down to make room for the new label
$slider.Size = New-Object System.Drawing.Size(300,50)
$window.Controls.Add($slider)

# Create checkboxes for symbols and numbers
$symbolsCheckbox = New-Object System.Windows.Forms.CheckBox
$symbolsCheckbox.Text = 'Symbols'
$symbolsCheckbox.Location = New-Object System.Drawing.Point(50,130)
$symbolsCheckbox.Checked = $true  # Set the checkbox to be checked by default
$window.Controls.Add($symbolsCheckbox)

$numbersCheckbox = New-Object System.Windows.Forms.CheckBox
$numbersCheckbox.Text = 'Numbers'
$numbersCheckbox.Location = New-Object System.Drawing.Point(160,130)
$numbersCheckbox.Checked = $true  # Set the checkbox to be checked by default
$window.Controls.Add($numbersCheckbox)

# Create the Copy button
$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = 'Copy'
$copyButton.Location = New-Object System.Drawing.Point(50,180)
$copyButton.Size = New-Object System.Drawing.Size(300,30)
$window.Controls.Add($copyButton)

# Function to generate random string
function Get-RandomString {
    param(
        [int]$Length,
        [bool]$IncludeSymbols,
        [bool]$IncludeNumbers
    )
    $lowercase = "abcdefghijklmnopqrstuvwxyz"
    $uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $numbers = "0123456789"
    $symbols = "!@#$%"

    $characters = ""
    if ($Length -gt 0) { $characters += Get-Random -InputObject $lowercase.ToCharArray() }  # Ensure at least one lowercase letter
    if ($Length -gt 1) { $characters += Get-Random -InputObject $uppercase.ToCharArray() }  # Ensure at least one uppercase letter
    if ($IncludeNumbers -and $Length -gt 2) { $characters += Get-Random -InputObject $numbers.ToCharArray() }  # Ensure at least one number
    if ($IncludeSymbols -and $Length -gt 3) { $characters += Get-Random -InputObject $symbols.ToCharArray() }  # Ensure at least one symbol

    # Fill the rest of the string with random characters
    $remainingCharacters = $lowercase + $uppercase
    if ($IncludeNumbers) { $remainingCharacters += $numbers }
    if ($IncludeSymbols) { $remainingCharacters += $symbols }
    $characters += -join ((1..($Length - $characters.Length)) | ForEach-Object { Get-Random -InputObject $remainingCharacters.ToCharArray() })

    # Shuffle the characters to make the string random
    $randomString = -join ($characters.ToCharArray() | Get-Random -Count $characters.Length)
    return $randomString
}

# Update the clipboard when the Copy button is clicked
$copyButton.Add_Click({
    $length = $slider.Value
    $includeSymbols = $symbolsCheckbox.Checked
    $includeNumbers = $numbersCheckbox.Checked
    $randomString = Get-RandomString -Length $length -IncludeSymbols $includeSymbols -IncludeNumbers $includeNumbers
    Set-Clipboard -Value $randomString
})

# Update the label when the slider value or checkbox state changes
$slider.Add_ValueChanged({ UpdateString })
$symbolsCheckbox.Add_CheckedChanged({ UpdateString })
$numbersCheckbox.Add_CheckedChanged({ UpdateString })

# Function to update the generated string and length label
function UpdateString {
    $length = $slider.Value
    $includeSymbols = $symbolsCheckbox.Checked
    $includeNumbers = $numbersCheckbox.Checked
    $randomString = Get-RandomString -Length $length -IncludeSymbols $includeSymbols -IncludeNumbers $includeNumbers
    $lengthLabel.Text = $length.ToString()  # Update the length label with the current string length
}

# Show the window
$window.ShowDialog()

