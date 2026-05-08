param(
    [Parameter(Mandatory)][string]$Command,
    [string]$Arguments
)

Import-Module "$PSScriptRoot/Matchbox.Backend.psm1" -Force
Invoke-MatchboxDotnetCommand -Command $Command -Arguments $Arguments
