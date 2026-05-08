function New-MatchboxDotnetArguments {
    param(
        [string]$Configuration = 'Debug',
        [string]$Framework,
        [string]$Runtime,
        [string]$Output,
        [switch]$SelfContained,
        [switch]$SingleFile,
        [string]$CustomArgs
    )

    $args = @("--configuration", $Configuration)
    if ($Framework) { $args += @("--framework", $Framework) }
    if ($Runtime) { $args += @("--runtime", $Runtime) }
    if ($Output) { $args += @("--output", $Output) }
    if ($SelfContained) { $args += "--self-contained" }
    if ($SingleFile) { $args += "/p:PublishSingleFile=true" }
    if ($CustomArgs) { $args += $CustomArgs }
    return ($args -join ' ')
}

function Invoke-MatchboxDotnetCommand {
    param(
        [Parameter(Mandatory)][ValidateSet('build','run','publish','clean','restore','test','pack','msbuild')][string]$Command,
        [string]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'dotnet'
    $psi.Arguments = "$Command $Arguments"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()

    while (-not $proc.StandardOutput.EndOfStream) {
        $proc.StandardOutput.ReadLine()
    }
    while (-not $proc.StandardError.EndOfStream) {
        Write-Error $proc.StandardError.ReadLine()
    }

    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "dotnet command failed: $Command" }
}

Export-ModuleMember -Function New-MatchboxDotnetArguments, Invoke-MatchboxDotnetCommand
