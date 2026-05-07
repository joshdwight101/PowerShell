Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ToolName = 'Domain Controller Health Tool'
$ToolVersion = '0.1.0'
$ToolAuthor = 'Joshua Dwight'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$cs = @"
using System;
using System.Drawing;
using System.Windows.Forms;

public static class DchUiFactory
{
    public static Form CreateMainForm(string title)
    {
        var form = new Form();
        form.Text = title;
        form.Size = new Size(1400, 900);
        form.StartPosition = FormStartPosition.CenterScreen;

        return form;
    }
}
"@

Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')

function New-Finding {
    param(
        [string]$Category,
        [string]$Check,
        [ValidateSet('Info','Warning','Critical')]
        [string]$Severity,
        [ValidateSet('Healthy','Unhealthy','Error','Unknown')]
        [string]$Status,
        [string]$Evidence,
        [string]$Impact,
        [string]$SuggestedAction,
        [bool]$AutoFixAllowed,
        [ValidateSet('Repairable','Replace This DC','Forest Recovery / Major Escalation')]
        [string]$OutcomeBand,
        [string]$RawOutput
    )

    [pscustomobject]@{
        TimeUtc          = [DateTime]::UtcNow
        Category         = $Category
        Check            = $Check
        Severity         = $Severity
        Status           = $Status
        Evidence         = $Evidence
        Impact           = $Impact
        SuggestedAction  = $SuggestedAction
        AutoFixAllowed   = $AutoFixAllowed
        OutcomeBand      = $OutcomeBand
        RawOutput        = $RawOutput
    }
}

function Invoke-CommandCapture {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 120
    )

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        [void]$proc.Start()

        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $proc.Kill()
            return [pscustomobject]@{ ExitCode = 124; StdOut = ''; StdErr = "Timeout after ${TimeoutSec}s" }
        }

        [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $proc.StandardOutput.ReadToEnd()
            StdErr   = $proc.StandardError.ReadToEnd()
        }
    }
    catch {
        [pscustomobject]@{
            ExitCode = 127
            StdOut   = ''
            StdErr   = $_.Exception.Message
        }
    }
}

function Invoke-DcHealthScan {
    [CmdletBinding()]
    param()

    $findings = [System.Collections.Generic.List[object]]::new()

    $dcdiag = Invoke-CommandCapture -FilePath 'dcdiag.exe' -Arguments @('/q')
    if ($dcdiag.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($dcdiag.StdOut)) {
        $findings.Add((New-Finding -Category 'Directory Self-Test' -Check 'DCDiag Core' -Severity 'Info' -Status 'Healthy' -Evidence 'dcdiag /q returned success with no failing tests.' -Impact 'Core identity and baseline tests passed.' -SuggestedAction 'No action needed.' -AutoFixAllowed $false -OutcomeBand 'Repairable' -RawOutput $dcdiag.StdOut))
    }
    else {
        $combined = ($dcdiag.StdOut + "`n" + $dcdiag.StdErr).Trim()
        $findings.Add((New-Finding -Category 'Directory Self-Test' -Check 'DCDiag Core' -Severity 'Critical' -Status 'Unhealthy' -Evidence 'dcdiag reported failures or could not execute.' -Impact 'Directory service may be unhealthy or inaccessible.' -SuggestedAction 'Review detailed DCDiag failures and remediate failing tests.' -AutoFixAllowed $false -OutcomeBand 'Repairable' -RawOutput $combined))
    }

    $repl = Invoke-CommandCapture -FilePath 'repadmin.exe' -Arguments @('/replsummary')
    $replOut = ($repl.StdOut + "`n" + $repl.StdErr).Trim()
    $replFailed = $repl.ExitCode -ne 0 -or $replOut -match '(?i)fails|error|unreachable|denied'
    $findings.Add((New-Finding -Category 'Replication & Topology' -Check 'repadmin /replsummary' -Severity ($replFailed ? 'Warning' : 'Info') -Status ($replFailed ? 'Unhealthy' : 'Healthy') -Evidence ($replFailed ? 'Replication summary indicates possible failures.' : 'Replication summary does not show obvious failures.') -Impact ($replFailed ? 'Stale directory data and auth inconsistency risk.' : 'Replication appears functional.') -SuggestedAction ($replFailed ? 'Inspect /showrepl and address failing partners.' : 'No immediate action.') -AutoFixAllowed $false -OutcomeBand 'Repairable' -RawOutput $replOut))

    $sysvol = Get-SmbShare -Name SYSVOL,NETLOGON -ErrorAction SilentlyContinue
    if ($null -ne $sysvol -and $sysvol.Count -ge 2) {
        $findings.Add((New-Finding -Category 'SYSVOL & DFSR' -Check 'SYSVOL/NETLOGON Shares' -Severity 'Info' -Status 'Healthy' -Evidence 'SYSVOL and NETLOGON are shared.' -Impact 'Clients can locate scripts and policies.' -SuggestedAction 'No action needed.' -AutoFixAllowed $false -OutcomeBand 'Repairable' -RawOutput ($sysvol | Out-String)))
    }
    else {
        $findings.Add((New-Finding -Category 'SYSVOL & DFSR' -Check 'SYSVOL/NETLOGON Shares' -Severity 'Critical' -Status 'Unhealthy' -Evidence 'One or both critical shares are missing.' -Impact 'Group Policy and logon script delivery can fail.' -SuggestedAction 'Investigate DFSR state and Netlogon/NTDS readiness.' -AutoFixAllowed $false -OutcomeBand 'Replace This DC' -RawOutput (($sysvol | Out-String))))
    }

    return $findings
}

$form = [DchUiFactory]::CreateMainForm("$ToolName v$ToolVersion | Author: $ToolAuthor")

$banner = New-Object System.Windows.Forms.Label
$banner.Text = 'Overall State: Not Run'
$banner.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$banner.AutoSize = $true
$banner.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($banner)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = 'Run Health Scan'
$runButton.Location = New-Object System.Drawing.Point(20, 50)
$runButton.Size = New-Object System.Drawing.Size(180, 34)
$form.Controls.Add($runButton)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = 'Export JSON Report'
$exportButton.Location = New-Object System.Drawing.Point(210, 50)
$exportButton.Size = New-Object System.Drawing.Size(180, 34)
$form.Controls.Add($exportButton)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(20, 100)
$grid.Size = New-Object System.Drawing.Size(1340, 420)
$grid.ReadOnly = $true
$grid.AutoSizeColumnsMode = 'Fill'
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$form.Controls.Add($grid)

$details = New-Object System.Windows.Forms.TextBox
$details.Location = New-Object System.Drawing.Point(20, 530)
$details.Size = New-Object System.Drawing.Size(1340, 300)
$details.Multiline = $true
$details.ScrollBars = 'Vertical'
$details.ReadOnly = $true
$details.Font = New-Object System.Drawing.Font('Consolas', 10)
$form.Controls.Add($details)

$script:lastResults = @()

$grid.add_SelectionChanged({
    if ($grid.SelectedRows.Count -gt 0) {
        $row = $grid.SelectedRows[0].DataBoundItem
        if ($null -ne $row) {
            $details.Text = @(
                "Category: $($row.Category)"
                "Check: $($row.Check)"
                "Severity: $($row.Severity)"
                "Status: $($row.Status)"
                "Outcome Band: $($row.OutcomeBand)"
                "Auto-fix Allowed: $($row.AutoFixAllowed)"
                ''
                "Evidence:"
                $row.Evidence
                ''
                "Impact:"
                $row.Impact
                ''
                "Suggested Action:"
                $row.SuggestedAction
                ''
                "Raw Output:"
                $row.RawOutput
            ) -join "`r`n"
        }
    }
})

$runButton.add_Click({
    $banner.Text = 'Overall State: Running...'
    $form.Refresh()

    try {
        $results = Invoke-DcHealthScan
        $script:lastResults = $results
        $grid.DataSource = $results

        if ($results.Where({ $_.Severity -eq 'Critical' }).Count -gt 0) {
            $banner.Text = 'Overall State: Critical Findings'
            $banner.ForeColor = [System.Drawing.Color]::Crimson
        }
        elseif ($results.Where({ $_.Severity -eq 'Warning' }).Count -gt 0) {
            $banner.Text = 'Overall State: Warnings Present'
            $banner.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $banner.Text = 'Overall State: Healthy'
            $banner.ForeColor = [System.Drawing.Color]::DarkGreen
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Scan failed: $($_.Exception.Message)", 'Scan Error', 'OK', 'Error') | Out-Null
        $banner.Text = 'Overall State: Scan Failed'
        $banner.ForeColor = [System.Drawing.Color]::Crimson
    }
})

$exportButton.add_Click({
    if (-not $script:lastResults -or $script:lastResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Run a scan first.', 'No Results', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'JSON files (*.json)|*.json'
    $dialog.FileName = "dc-health-report-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')).json"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:lastResults | ConvertTo-Json -Depth 6 | Set-Content -Path $dialog.FileName -Encoding UTF8
        [System.Windows.Forms.MessageBox]::Show('Report exported successfully.', 'Export Complete', 'OK', 'Information') | Out-Null
    }
})

[void]$form.ShowDialog()
