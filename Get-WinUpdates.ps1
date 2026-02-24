# Pure WUA COM script: scan, download, install (software updates), then reboot if needed
$session   = New-Object -ComObject 'Microsoft.Update.Session'
$searcher  = $session.CreateUpdateSearcher()
$searchRes = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

if ($searchRes.Updates.Count -gt 0) {
    $toDownload = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($u in $searchRes.Updates) { $null = $toDownload.Add($u) }

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $toDownload
    $downloader.Download()

    $toInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($u in $searchRes.Updates) {
        if ($u.IsDownloaded) { $null = $toInstall.Add($u) }
    }

    if ($toInstall.Count -gt 0) {
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $toInstall
        $result = $installer.Install()
        if ($result.RebootRequired) { Restart-Computer -Force }
    }
} else {
    Write-Host "No applicable updates found."
}
