Set-StrictMode -Version Latest

function New-EasConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $default = [ordered]@{
        Organization = 'Contoso'
        LowDiskFreePercent = 12
        LocalDataRoot = "$env:ProgramData\EnterpriseAssetSuite"
        IntegrityHashAlgorithm = 'SHA256'
        RunMode = 'UserLogonSilent'
        SharePoint = [ordered]@{
            Enabled = $false
            TenantId = ''
            ClientId = ''
            ClientSecret = ''
            SiteId = ''
            AssetListId = ''
            EventListId = ''
        }
    }

    $default | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    Get-Item -Path $Path
}

function Get-EasConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Configuration file not found: $Path"
    }

    Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 8
}

function Get-EasMonitorHistory {
    [CmdletBinding()]
    param()

    $items = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        [pscustomobject]@{
            InstanceName = $item.InstanceName
            SerialNumber = (-join ($item.SerialNumberID | Where-Object { $_ -gt 0 } | ForEach-Object {[char]$_})).Trim()
            Manufacturer = (-join ($item.ManufacturerName | Where-Object { $_ -gt 0 } | ForEach-Object {[char]$_})).Trim()
            Model = (-join ($item.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object {[char]$_})).Trim()
        }
    }
}

function Get-EasLoginHistory {
    [CmdletBinding()]
    param(
        [int]$Days = 30
    )

    $start = (Get-Date).AddDays(-1 * [math]::Abs($Days))
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4624,4634
        StartTime = $start
    } -ErrorAction SilentlyContinue

    foreach ($event in $events) {
        $eventType = if ($event.Id -eq 4624) { 'Logon' } else { 'Logoff' }
        [pscustomobject]@{
            TimeCreated = $event.TimeCreated
            EventType = $eventType
            Message = $event.Message
            RecordId = $event.RecordId
        }
    }
}

function Get-EasPendingRebootStatus {
    [CmdletBinding()]
    param()

    $checks = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    )

    $isPending = $false
    foreach ($path in $checks) {
        if (Test-Path -Path $path) { $isPending = $true }
    }

    [pscustomobject]@{
        PendingReboot = $isPending
        LastBootUpTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    }
}

function Get-EasAssetSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $network = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = true"
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"
    $pending = Get-EasPendingRebootStatus

    $diskInfo = foreach ($disk in $disks) {
        $freePct = if ($disk.Size -gt 0) { [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2) } else { 0 }
        [pscustomobject]@{
            Drive = $disk.DeviceID
            SizeGB = [math]::Round($disk.Size / 1GB, 2)
            FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            FreePercent = $freePct
            LowSpaceFlag = $freePct -lt [double]$Configuration.LowDiskFreePercent
        }
    }

    [pscustomobject]@{
        CapturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Hostname = $env:COMPUTERNAME
        UserName = "$env:USERDOMAIN\$env:USERNAME"
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        SerialNumber = $bios.SerialNumber
        WindowsVersion = $os.Caption
        WindowsBuild = $os.BuildNumber
        LastBootUpTime = $os.LastBootUpTime
        PendingReboot = $pending.PendingReboot
        IPAddresses = @($network | ForEach-Object { $_.IPAddress } | Select-Object -ExpandProperty * -ErrorAction SilentlyContinue)
        MacAddresses = @($network | ForEach-Object { $_.MACAddress })
        DiskStatus = $diskInfo
        MonitorStatus = @(Get-EasMonitorHistory)
        LoginEvents = @(Get-EasLoginHistory -Days 14 | Select-Object -First 500)
    }
}

function Test-EasIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot,
        [string]$Algorithm = 'SHA256'
    )

    $files = Get-ChildItem -Path $ScriptRoot -File -Recurse | Where-Object { $_.Extension -in '.ps1','.psm1' }
    $hashes = foreach ($file in $files) {
        $hash = Get-FileHash -Path $file.FullName -Algorithm $Algorithm
        [pscustomobject]@{
            Path = $file.FullName
            Algorithm = $Algorithm
            Hash = $hash.Hash
        }
    }

    [pscustomobject]@{
        CheckedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        FileCount = $hashes.Count
        Hashes = $hashes
    }
}

function Export-EasLocalState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,
        [Parameter(Mandatory)]
        [pscustomobject]$AssetSnapshot,
        [Parameter(Mandatory)]
        [pscustomobject]$IntegrityStatus
    )

    $root = $Configuration.LocalDataRoot
    if (-not (Test-Path $root)) { New-Item -Path $root -ItemType Directory -Force | Out-Null }

    $assetPath = Join-Path $root 'asset-latest.json'
    $integrityPath = Join-Path $root 'integrity-latest.json'
    $eventPath = Join-Path $root 'event-history.ndjson'

    $AssetSnapshot | ConvertTo-Json -Depth 10 | Set-Content -Path $assetPath -Encoding UTF8
    $IntegrityStatus | ConvertTo-Json -Depth 10 | Set-Content -Path $integrityPath -Encoding UTF8
    ($AssetSnapshot | ConvertTo-Json -Depth 10 -Compress) | Add-Content -Path $eventPath -Encoding UTF8

    [pscustomobject]@{ AssetPath = $assetPath; IntegrityPath = $integrityPath; EventPath = $eventPath }
}

function Publish-EasSharePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,
        [Parameter(Mandatory)]
        [pscustomobject]$AssetSnapshot,
        [Parameter(Mandatory)]
        [pscustomobject]$IntegrityStatus
    )

    if (-not $Configuration.SharePoint.Enabled) {
        Write-Verbose 'SharePoint publishing is disabled.'
        return
    }

    throw 'SharePoint publishing integration stub: wire this to Microsoft Graph ListItem APIs with your tenant app registration.'
}

function Invoke-EasCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationPath,
        [string]$ScriptRoot = $PSScriptRoot
    )

    $config = Get-EasConfiguration -Path $ConfigurationPath
    $snapshot = Get-EasAssetSnapshot -Configuration $config
    $integrity = Test-EasIntegrity -ScriptRoot $ScriptRoot -Algorithm $config.IntegrityHashAlgorithm
    $local = Export-EasLocalState -Configuration $config -AssetSnapshot $snapshot -IntegrityStatus $integrity
    Publish-EasSharePoint -Configuration $config -AssetSnapshot $snapshot -IntegrityStatus $integrity

    [pscustomobject]@{
        Snapshot = $snapshot
        Integrity = $integrity
        LocalState = $local
    }
}

Export-ModuleMember -Function *-Eas*
