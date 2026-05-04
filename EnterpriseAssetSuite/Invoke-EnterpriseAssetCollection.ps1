param(
    [string]$ConfigurationPath = "$PSScriptRoot\config.json",
    [switch]$VerboseLogging
)

Import-Module "$PSScriptRoot\EnterpriseAssetSuite.psm1" -Force

if (-not (Test-Path $ConfigurationPath)) {
    New-EasConfiguration -Path $ConfigurationPath | Out-Null
}

$params = @{
    ConfigurationPath = $ConfigurationPath
    ScriptRoot = $PSScriptRoot
}

if ($VerboseLogging) { $params['Verbose'] = $true }

Invoke-EasCollection @params | Out-Null
