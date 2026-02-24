# Define On-Time and Off-Time variables
$offTime = "23:30"  # Off time in 24-hour format (e.g., 22:00 for 10 PM)
$onTime = "07:00"   # On time in 24-hour format (e.g., 06:00 for 6 AM)

# Convert string times to DateTime objects
$offTimeDateTime = [datetime]::ParseExact($offTime, "HH:mm", $null)
$onTimeDateTime = [datetime]::ParseExact($onTime, "HH:mm", $null)

# Get current time
$currentTime = Get-Date

# Function to determine if the current time is between off time and on time
function IsBetweenOffAndOnTime($current, $off, $on) {
    if ($off -lt $on) {
        # off time and on time are on the same day
        return ($current -ge $off -and $current -lt $on)
    } else {
        # off time and on time span across midnight
        return ($current -ge $off -or $current -lt $on)
    }
}

# Check if current time is between off time and on time
if (IsBetweenOffAndOnTime $currentTime $offTimeDateTime $onTimeDateTime) {
    Write-Host "Shutting down the computer..."
    Stop-Computer -Force
} else {
    Write-Host "Computer is in usable time frame."
    # Optionally, you can add any other logic here that should execute when the computer is in usable time
}
