[CmdletBinding()]
param(
    [switch]$ExportJson,
    [string]$OutputPath = ".\Win11IntegrityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-CheckResult {
    param(
        [string]$Name,
        [string]$Category,
        [string]$Status,
        [string]$Details,
        [double]$Seconds,
        [string]$Recommendation = ''
    )

    [pscustomobject]@{
        Name           = $Name
        Category       = $Category
        Status         = $Status
        Details        = $Details
        DurationSecond = [Math]::Round($Seconds, 2)
        Recommendation = $Recommendation
        Timestamp      = (Get-Date).ToString('s')
    }
}

$checks = @(
    @{ Name='OS Build and Edition'; Category='Platform'; Script={
        $os = Get-CimInstance Win32_OperatingSystem
        $build = [int]$os.BuildNumber
        if ($build -lt 22000) {
            New-CheckResult -Name 'OS Build and Edition' -Category 'Platform' -Status 'Critical' -Details "Detected build $build ($($os.Caption)). Not a Windows 11 baseline build." -Seconds $elapsed.TotalSeconds -Recommendation 'Perform in-place upgrade or clean install of Windows 11.'
        } else {
            New-CheckResult -Name 'OS Build and Edition' -Category 'Platform' -Status 'Pass' -Details "Detected $($os.Caption) build $build." -Seconds $elapsed.TotalSeconds
        }
    }}
    @{ Name='System File Checker'; Category='Repairability'; Script={
        $text = cmd /c 'sfc /verifyonly'
        $details = ($text | Out-String).Trim()
        if ($details -match 'Windows Resource Protection found integrity violations') {
            New-CheckResult -Name 'System File Checker' -Category 'Repairability' -Status 'Fail' -Details 'SFC detected integrity violations.' -Seconds $elapsed.TotalSeconds -Recommendation 'Run sfc /scannow. If unresolved, run DISM /RestoreHealth or reinstall.'
        } elseif ($details -match 'Windows Resource Protection did not find any integrity violations') {
            New-CheckResult -Name 'System File Checker' -Category 'Repairability' -Status 'Pass' -Details 'No SFC integrity violations.' -Seconds $elapsed.TotalSeconds
        } else {
            New-CheckResult -Name 'System File Checker' -Category 'Warning' -Status 'Warning' -Details ($details.Substring(0, [Math]::Min($details.Length, 400))) -Seconds $elapsed.TotalSeconds -Recommendation 'Review full SFC output manually.'
        }
    }}
    @{ Name='DISM Component Store Health'; Category='Repairability'; Script={
        $text = cmd /c 'DISM /Online /Cleanup-Image /CheckHealth'
        $details = ($text | Out-String).Trim()
        if ($details -match 'component store is repairable') {
            New-CheckResult -Name 'DISM Component Store Health' -Category 'Repairability' -Status 'Fail' -Details 'Component store corruption detected (repairable).' -Seconds $elapsed.TotalSeconds -Recommendation 'Run DISM /Online /Cleanup-Image /RestoreHealth.'
        } elseif ($details -match 'No component store corruption detected') {
            New-CheckResult -Name 'DISM Component Store Health' -Category 'Repairability' -Status 'Pass' -Details 'No component store corruption detected.' -Seconds $elapsed.TotalSeconds
        } else {
            New-CheckResult -Name 'DISM Component Store Health' -Category 'Repairability' -Status 'Warning' -Details ($details.Substring(0, [Math]::Min($details.Length, 400))) -Seconds $elapsed.TotalSeconds -Recommendation 'Review DISM logs in C:\\Windows\\Logs\\DISM.'
        }
    }}
    @{ Name='Disk Health (SMART)'; Category='Storage'; Script={
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        if (-not $disks) {
            New-CheckResult -Name 'Disk Health (SMART)' -Category 'Storage' -Status 'Warning' -Details 'Unable to query physical disks.' -Seconds $elapsed.TotalSeconds -Recommendation 'Verify storage driver and admin privileges.'
        } else {
            $bad = $disks | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -notcontains 'OK' }
            if ($bad) {
                New-CheckResult -Name 'Disk Health (SMART)' -Category 'Storage' -Status 'Critical' -Details ((($bad | Select-Object FriendlyName,HealthStatus,OperationalStatus) | Out-String).Trim()) -Seconds $elapsed.TotalSeconds -Recommendation 'Back up immediately and replace failing drive; reinstall may be required after hardware replacement.'
            } else {
                New-CheckResult -Name 'Disk Health (SMART)' -Category 'Storage' -Status 'Pass' -Details 'All queried physical disks report healthy.' -Seconds $elapsed.TotalSeconds
            }
        }
    }}
    @{ Name='Windows Update Errors (last 30 days)'; Category='Servicing'; Script={
        $start = (Get-Date).AddDays(-30)
        $events = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=2; StartTime=$start } -ErrorAction SilentlyContinue
        if ($events.Count -gt 20) {
            New-CheckResult -Name 'Windows Update Errors (last 30 days)' -Category 'Servicing' -Status 'Fail' -Details "Found $($events.Count) error events in last 30 days." -Seconds $elapsed.TotalSeconds -Recommendation 'Reset Windows Update components; consider in-place repair if persistent.'
        } else {
            New-CheckResult -Name 'Windows Update Errors (last 30 days)' -Category 'Servicing' -Status 'Pass' -Details "Found $($events.Count) update errors in last 30 days." -Seconds $elapsed.TotalSeconds
        }
    }}
    @{ Name='Boot Configuration Data'; Category='Boot'; Script={
        $bcd = cmd /c 'bcdedit /enum {current}'
        $details = ($bcd | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($details)) {
            New-CheckResult -Name 'Boot Configuration Data' -Category 'Boot' -Status 'Critical' -Details 'Failed to enumerate BCD.' -Seconds $elapsed.TotalSeconds -Recommendation 'Repair boot configuration from Windows Recovery Environment.'
        } else {
            New-CheckResult -Name 'Boot Configuration Data' -Category 'Boot' -Status 'Pass' -Details 'Current boot entry enumerated successfully.' -Seconds $elapsed.TotalSeconds
        }
    }}
)

$queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$jobs = @()

foreach ($check in $checks) {
    $jobs += Start-ThreadJob -Name $check.Name -ScriptBlock {
        param($check)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $elapsed = [TimeSpan]::Zero
        try {
            $result = & $check.Script
        } catch {
            $elapsed = $stopwatch.Elapsed
            $result = [pscustomobject]@{
                Name           = $check.Name
                Category       = $check.Category
                Status         = 'Error'
                Details        = $_.Exception.Message
                DurationSecond = [Math]::Round($elapsed.TotalSeconds, 2)
                Recommendation = 'Review error and run this check manually.'
                Timestamp      = (Get-Date).ToString('s')
            }
        }
        $stopwatch.Stop()
        if ($result.DurationSecond -eq 0) {
            $result.DurationSecond = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        }
        return $result
    } -ArgumentList $check
}

Write-Host "Running $($jobs.Count) integrity checks in parallel..." -ForegroundColor Cyan
$results = @()
$completed = 0

while ($completed -lt $jobs.Count) {
    foreach ($job in $jobs | Where-Object { $_.State -in 'Completed','Failed','Stopped' -and -not $_.HasMoreData -eq $false }) {}
    $doneJobs = $jobs | Where-Object { $_.State -in 'Completed','Failed','Stopped' }
    $newCount = $doneJobs.Count
    if ($newCount -ne $completed) {
        $completed = $newCount
        Write-Progress -Activity 'Windows 11 Integrity Check' -Status "$completed / $($jobs.Count) checks complete" -PercentComplete (($completed / $jobs.Count) * 100)
    }
    Start-Sleep -Milliseconds 300
}

$results = Receive-Job -Job $jobs
$jobs | Remove-Job -Force
Write-Progress -Activity 'Windows 11 Integrity Check' -Completed

$severity = @{ Pass=0; Warning=1; Fail=2; Critical=3; Error=3 }
$ordered = $results | Sort-Object { $severity[$_.Status] } -Descending
$overall = if ($ordered.Status -contains 'Critical' -or $ordered.Status -contains 'Error') { 'REINSTALL RECOMMENDED' }
           elseif ($ordered.Status -contains 'Fail') { 'REPAIR INSTALL RECOMMENDED' }
           elseif ($ordered.Status -contains 'Warning') { 'ATTENTION NEEDED' }
           else { 'HEALTHY' }

$ordered | Format-Table Name,Category,Status,DurationSecond,Recommendation -AutoSize
Write-Host "`nOverall Assessment: $overall" -ForegroundColor Yellow

if ($ExportJson) {
    $payload = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('o')
        Overall     = $overall
        Results     = $ordered
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Report exported to $OutputPath" -ForegroundColor Green
}
