param(
    [int]$DaysInactive = 90,
    [switch]$DryRun
)

$LogFile = "C:\CHESI\logs\ProfileCleanup.log"
$ProfileRoot = "C:\Users"
$ProfileRegistry = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"

$CutoffDate = (Get-Date).AddDays(-$DaysInactive)

# Ensure log folder exists
$logDir = Split-Path $LogFile
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log "===== Ultra-Fast Profile Cleanup Started ====="
Write-Log "Removing profiles unused since $CutoffDate"

# Accounts to exclude
$ExcludedAccounts = @(
    "Administrator",
    "DefaultAccount",
    "Guest",
    "Public",
    "defaultuser0",
    "WDAGUtilityAccount"
)

# Get registry profile mappings (fast lookup)
$ProfileKeys = Get-ChildItem $ProfileRegistry

foreach ($key in $ProfileKeys) {

    $ProfilePath = (Get-ItemProperty $key.PSPath).ProfileImagePath

    if (!$ProfilePath) { continue }

    if ($ProfilePath -notlike "$ProfileRoot\*") { continue }

    $Username = Split-Path $ProfilePath -Leaf

    if ($ExcludedAccounts -contains $Username) {
        Write-Log "Skipping excluded account $Username"
        continue
    }

    if ($Username -match "^(svc_|service_|sql|backup|admin)") {
        Write-Log "Skipping service/admin account $Username"
        continue
    }

    if (!(Test-Path $ProfilePath)) {
        Write-Log "Profile folder missing for $Username"
        continue
    }

    $LastWrite = (Get-Item $ProfilePath).LastWriteTime

    if ($LastWrite -lt $CutoffDate) {

        Write-Log "Old profile detected: $Username (LastWrite: $LastWrite)"

        if ($DryRun) {

            Write-Log "DRYRUN: Would remove $ProfilePath and registry key"

        } else {

            try {

                # Kill processes belonging to user (prevents locks)
                Get-Process -IncludeUserName -ErrorAction SilentlyContinue |
                Where-Object { $_.UserName -like "*\$Username" } |
                Stop-Process -Force -ErrorAction SilentlyContinue

                # Remove folder (fast)
                Remove-Item $ProfilePath -Recurse -Force -ErrorAction Stop

                # Remove registry entry
                Remove-Item $key.PSPath -Recurse -Force

                Write-Log "SUCCESS: Removed profile $Username"

            }
            catch {

                Write-Log "ERROR removing $Username : $_"

            }

        }

    } else {

        Write-Log "Keeping profile $Username (LastWrite: $LastWrite)"

    }
}

Write-Log "===== Cleanup Completed ====="
# SIG # Begin signature block
# MIIFiwYJKoZIhvcNAQcCoIIFfDCCBXgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUS8fVkwAi0/gHPDMRV60DMdbm
# x+KgggMcMIIDGDCCAgCgAwIBAgIQdTnGUb3fnrZCF1K2xTtGMjANBgkqhkiG9w0B
# AQsFADAkMSIwIAYDVQQDDBlDSEVTSS1KRENvZGUtU2lnbmluZy0yMDI2MB4XDTI2
# MDMwNjE0NDY0NVoXDTI3MDMwNjE0NDY0NVowJDEiMCAGA1UEAwwZQ0hFU0ktSkRD
# b2RlLVNpZ25pbmctMjAyNjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
# AMIvE+cjfWSthiMrydvmvgrd9ucGb77R+W5jS2EfE73xAMxLBjZBbfTdh8Ig1Oj2
# aZuTWPwXoETEdh4ocXbtyYX0WDXqnNwSzDGDLKNiMzQ2bJEgfeegSGazOCUXchya
# x82YR81WyxGd4sIqBBC3JpFxr+O6MZHHtqUHkkHyUY1Q8phH40X6UOH+l7AIB3yC
# zxqyEJ68RNQFh4UhD2dS4DneN0xyPlQ/VhXcMF4dONwQz7lSIIgD+iiJzXo9Ka7F
# ZOGm1jtq7i/p3XwLuq3zMxgeHh3VcVWh2QbO2PODgIxtchRMFBkW5BtiBjV5nSs7
# D879uPSkhTEGk2UAHDDsbKkCAwEAAaNGMEQwDgYDVR0PAQH/BAQDAgeAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQGI/EgF0UkEE5pOr6J/upQmqqo2jAN
# BgkqhkiG9w0BAQsFAAOCAQEABPRv9v2ibkmhWvzlXApwWNScLZ2c6r1ErdcIYEDf
# UHMPwiWV8ztOT9cK6NunF9VjPSb/dCxu2OU+F+HGl1utqoTtPMV+95p9ctwu12KR
# 20/JxfmfoGu1dTYQYZZeWapbBNOwwPg3GEti2PNHMCI+QBSN3MbnfABwVFs9T2X+
# 7tQaOdAhY1kqp8siaCoCpwcoGWlhDdO6+hCrI3Qz5oWN/hMCrL6Sm3afgDoh8xzB
# fxnNdcwQq2+etj+JM9Gcz+C8fUnlZmKPn+wEsMS+oZqfEUt5HEzEIe8LVuuub/Ah
# 8eTO2IA6ouL9V9TyN0aWtV2l0qoqyoY+odq6v1QPInnLfDGCAdkwggHVAgEBMDgw
# JDEiMCAGA1UEAwwZQ0hFU0ktSkRDb2RlLVNpZ25pbmctMjAyNgIQdTnGUb3fnrZC
# F1K2xTtGMjAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU14rypVT22oC/jEXFWYbcX5LeieYwDQYJ
# KoZIhvcNAQEBBQAEggEAZuqbwi1sc4T8c6zufr5pnjP4IgYw+h4qJSENdZ8dscZt
# FJhtmkVrxlxleg7vOhauO/wqYisIzwBt87PQICT7IkXkNb+NTwhUhfw4P2cC6vx8
# lpuwdUosPOEzzgyw36qq5VNKAubSc3dk51079tKD5qRzLyfKQp9AohqMmBNn6BkK
# 9x6xHWgNDtAtBIel+W/WRKuAv+cbc6pHdSYL8UPA/HTGJgErPySmMQ+yUEzeDYPA
# qL56D1QpnTTtt+iq9I96j72+qokXBWaB9hDaydPNmdeWR3wtePRMDjChORhCGyT2
# T4a4UKx9I2mbkuaoNee+MLHuqu3Z5pYlhA9JcSN0Aw==
# SIG # End signature block
