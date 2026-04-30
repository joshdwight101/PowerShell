<#
.SYNOPSIS
SecureVault Encryptor - standalone PowerShell + C# encryption GUI.

.DESCRIPTION
Independent encryption utility (no dependencies on other scripts in this repo).
Uses certificate or password keying, multithreaded processing, and built-in certificate creation.
Designed to run on Windows PowerShell 5.1+ and PowerShell 7+.
#>

param(
    [switch]$DebugMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:startupDebugMode = $DebugMode.IsPresent
$script:debugLogPath = $null
$script:transcriptPath = $null
$script:logRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:cancelSource = $null
$script:lastOperation = $null
$script:isRunning = $false

function Initialize-CryptoAssembly {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.IO;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

public static class FastCryptoEngine
{
    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("PSENCV2");

    private static void FillRandom(byte[] buffer)
    {
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(buffer);
        }
    }

    private static bool FixedTimeEquals(byte[] a, byte[] b)
    {
        if (a == null || b == null || a.Length != b.Length) return false;
        int diff = 0;
        for (int i = 0; i < a.Length; i++) diff |= a[i] ^ b[i];
        return diff == 0;
    }


    private static RSA GetPublicRsa(X509Certificate2 cert)
    {
        if (cert == null) throw new ArgumentNullException("cert");
        var key = cert.PublicKey != null ? cert.PublicKey.Key : null;
        var rsa = key as RSA;
        if (rsa == null) throw new InvalidOperationException("Certificate has no RSA public key.");
        return rsa;
    }

    private static RSA GetPrivateRsa(X509Certificate2 cert)
    {
        if (cert == null) throw new ArgumentNullException("cert");
        var rsa = cert.PrivateKey as RSA;
        if (rsa == null) throw new InvalidOperationException("Selected certificate does not include an RSA private key.");
        return rsa;
    }

    private static byte[] RsaEncryptCompat(RSA rsa, byte[] data)
    {
        var csp = rsa as RSACryptoServiceProvider;
        if (csp == null) throw new InvalidOperationException("RSA provider is not supported on this host.");
        return csp.Encrypt(data, true); // OAEP (SHA1) for broad framework compatibility
    }

    private static byte[] RsaDecryptCompat(RSA rsa, byte[] data)
    {
        var csp = rsa as RSACryptoServiceProvider;
        if (csp == null) throw new InvalidOperationException("RSA provider is not supported on this host.");
        return csp.Decrypt(data, true); // OAEP (SHA1)
    }
    private static byte[] DeriveKeyMaterial(string password, byte[] salt)
    {
        if (String.IsNullOrWhiteSpace(password))
            throw new InvalidOperationException("Password is required for password mode.");

        // Uses framework-compatible constructor for Windows PowerShell 5.1 environments.
        using (var derive = new Rfc2898DeriveBytes(password, salt, 200000))
        {
            return derive.GetBytes(64); // 32 bytes ENC + 32 bytes HMAC
        }
    }

    private static byte[] EncryptAesCbc(byte[] plain, byte[] encKey, byte[] iv)
    {
        using (var aes = Aes.Create())
        {
            aes.KeySize = 256;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            aes.Key = encKey;
            aes.IV = iv;
            using (var encryptor = aes.CreateEncryptor())
            {
                return encryptor.TransformFinalBlock(plain, 0, plain.Length);
            }
        }
    }

    private static byte[] DecryptAesCbc(byte[] cipher, byte[] encKey, byte[] iv)
    {
        using (var aes = Aes.Create())
        {
            aes.KeySize = 256;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            aes.Key = encKey;
            aes.IV = iv;
            using (var decryptor = aes.CreateDecryptor())
            {
                return decryptor.TransformFinalBlock(cipher, 0, cipher.Length);
            }
        }
    }

    private static byte[] BuildAuthData(byte flags, byte[] salt, byte[] iv, byte[] wrappedKey, byte[] cipher)
    {
        using (var ms = new MemoryStream())
        using (var bw = new BinaryWriter(ms))
        {
            bw.Write(Magic);
            bw.Write(flags);
            bw.Write(salt);
            bw.Write(iv);
            bw.Write(wrappedKey.Length);
            if (wrappedKey.Length > 0) bw.Write(wrappedKey);
            bw.Write(cipher.Length);
            bw.Write(cipher);
            bw.Flush();
            return ms.ToArray();
        }
    }

    public static void EncryptFile(string inputPath, string outputPath, string password, string certBase64)
    {
        byte[] plain = File.ReadAllBytes(inputPath);
        byte[] salt = new byte[16];
        byte[] iv = new byte[16];
        FillRandom(salt);
        FillRandom(iv);

        bool useCert = !String.IsNullOrWhiteSpace(certBase64);
        bool usePassword = !String.IsNullOrWhiteSpace(password);
        if (!useCert && !usePassword)
            throw new InvalidOperationException("Provide either a password or a certificate.");

        byte[] keyMaterial;
        byte[] wrappedKey = new byte[0];

        if (useCert)
        {
            keyMaterial = new byte[64];
            FillRandom(keyMaterial);
            using (var cert = new X509Certificate2(Convert.FromBase64String(certBase64)))
            using (var rsa = GetPublicRsa(cert))
            {
                wrappedKey = RsaEncryptCompat(rsa, keyMaterial);
            }
        }
        else
        {
            keyMaterial = DeriveKeyMaterial(password, salt);
        }

        byte[] encKey = new byte[32];
        byte[] macKey = new byte[32];
        Buffer.BlockCopy(keyMaterial, 0, encKey, 0, 32);
        Buffer.BlockCopy(keyMaterial, 32, macKey, 0, 32);

        byte[] cipher = EncryptAesCbc(plain, encKey, iv);
        byte flags = 0;
        if (useCert) flags |= 0x1;
        if (usePassword) flags |= 0x2;

        byte[] authData = BuildAuthData(flags, salt, iv, wrappedKey, cipher);
        byte[] tag;
        using (var hmac = new HMACSHA256(macKey))
        {
            tag = hmac.ComputeHash(authData);
        }

        using (var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None))
        using (var bw = new BinaryWriter(fs))
        {
            bw.Write(authData);
            bw.Write(tag);
        }

        Array.Clear(keyMaterial, 0, keyMaterial.Length);
        Array.Clear(encKey, 0, encKey.Length);
        Array.Clear(macKey, 0, macKey.Length);
    }

    public static void DecryptFile(string inputPath, string outputPath, string password, string privateCertBase64)
    {
        using (var fs = new FileStream(inputPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        using (var br = new BinaryReader(fs))
        {
            byte[] magic = br.ReadBytes(Magic.Length);
            if (magic.Length != Magic.Length || !FixedTimeEquals(magic, Magic))
                throw new InvalidDataException("Unsupported encrypted file format.");

            byte flags = br.ReadByte();
            bool certMode = (flags & 0x1) == 0x1;
            bool passwordMode = (flags & 0x2) == 0x2;

            byte[] salt = br.ReadBytes(16);
            byte[] iv = br.ReadBytes(16);
            int wrappedLen = br.ReadInt32();
            byte[] wrappedKey = wrappedLen > 0 ? br.ReadBytes(wrappedLen) : new byte[0];
            int cipherLen = br.ReadInt32();
            byte[] cipher = br.ReadBytes(cipherLen);
            byte[] tag = br.ReadBytes(32);

            byte[] keyMaterial;
            if (certMode)
            {
                if (String.IsNullOrWhiteSpace(privateCertBase64))
                    throw new InvalidOperationException("A private-key certificate is required for certificate mode decryption.");

                using (var cert = new X509Certificate2(Convert.FromBase64String(privateCertBase64)))
                using (var rsa = GetPrivateRsa(cert))
                {
                    keyMaterial = RsaDecryptCompat(rsa, wrappedKey);
                }
            }
            else if (passwordMode)
            {
                keyMaterial = DeriveKeyMaterial(password, salt);
            }
            else
            {
                throw new InvalidDataException("No supported key mode found in file header.");
            }

            byte[] encKey = new byte[32];
            byte[] macKey = new byte[32];
            Buffer.BlockCopy(keyMaterial, 0, encKey, 0, 32);
            Buffer.BlockCopy(keyMaterial, 32, macKey, 0, 32);

            byte[] authData = BuildAuthData(flags, salt, iv, wrappedKey, cipher);
            byte[] computedTag;
            using (var hmac = new HMACSHA256(macKey))
            {
                computedTag = hmac.ComputeHash(authData);
            }

            if (!FixedTimeEquals(tag, computedTag))
                throw new CryptographicException("Authentication failed. Wrong key/certificate or file tampered.");

            byte[] plain = DecryptAesCbc(cipher, encKey, iv);
            File.WriteAllBytes(outputPath, plain);

            Array.Clear(keyMaterial, 0, keyMaterial.Length);
            Array.Clear(encKey, 0, encKey.Length);
            Array.Clear(macKey, 0, macKey.Length);
        }
    }
}
"@
}

function Get-CertificateList {
    Get-ChildItem -Path Cert:\CurrentUser\My |
        Where-Object { $_.HasPrivateKey -and $_.PublicKey.Oid.FriendlyName -eq 'RSA' } |
        Sort-Object NotAfter -Descending
}

function New-EncryptionCertificate {
    param(
        [string]$SubjectName = 'CN=SecureVault Encryption',
        [int]$ValidYears = 5
    )

    New-SelfSignedCertificate -Subject $SubjectName `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA `
        -KeyLength 4096 `
        -HashAlgorithm 'SHA256' `
        -KeyExportPolicy Exportable `
        -KeyUsage KeyEncipherment, DataEncipherment, DigitalSignature `
        -NotAfter (Get-Date).AddYears($ValidYears)
}

function Get-TargetFiles {
    param(
        [string]$Path,
        [switch]$Recurse,
        [switch]$EncryptMode
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return ,(Resolve-Path -LiteralPath $Path).Path
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path '$Path' does not exist."
    }

    $allFiles = Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse
    if ($EncryptMode) {
        return $allFiles | Where-Object { $_.Extension -ne '.psenc' } | ForEach-Object FullName
    }

    return $allFiles | Where-Object { $_.Extension -eq '.psenc' } | ForEach-Object FullName
}

function Get-RecommendWorkerThreads {
    $logical = [Math]::Max(1, [Environment]::ProcessorCount)
    try {
        $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue
        $freePct = [Math]::Max(0, 100 - $cpu)
        $recommended = [int][Math]::Floor($logical * ($freePct / 100))
        if ($recommended -lt 1) { $recommended = 1 }
        if ($recommended -gt $logical) { $recommended = $logical }
        return $recommended
    }
    catch {
        return [Math]::Max(1, $logical - 1)
    }
}

function New-DebugLogPath {
    param(
        [string]$Prefix = 'SecureVault-Debug'
    )
    Join-Path $script:logRoot ("{0}-{1}.log" -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function Start-SecureVaultGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Initialize-CryptoAssembly

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'SecureVault Encryptor'
    $form.Size = New-Object System.Drawing.Size(980, 780)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 780)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $menu = New-Object System.Windows.Forms.MenuStrip
    $menu.BackColor = [System.Drawing.Color]::FromArgb(42, 42, 42)
    $menu.ForeColor = [System.Drawing.Color]::White
    $helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Help')
    $helpIndexItem = New-Object System.Windows.Forms.ToolStripMenuItem('Help Index')
    $cryptoItem = New-Object System.Windows.Forms.ToolStripMenuItem('Encryption Details')
    $aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem('About SecureVault')
    [void]$helpMenu.DropDownItems.Add($helpIndexItem)
    [void]$helpMenu.DropDownItems.Add($cryptoItem)
    [void]$helpMenu.DropDownItems.Add($aboutItem)
    [void]$menu.Items.Add($helpMenu)
    $form.MainMenuStrip = $menu

    $tips = New-Object System.Windows.Forms.ToolTip
    $tips.AutoPopDelay = 12000
    $tips.InitialDelay = 400
    $tips.ReshowDelay = 250
    $tips.ShowAlways = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'SecureVault Encryptor (Compatible Standalone Build)'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(20, 50)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = 'File or Directory:'
    $pathLabel.Location = New-Object System.Drawing.Point(20, 100)
    $pathLabel.AutoSize = $true

    $pathText = New-Object System.Windows.Forms.TextBox
    $pathText.Location = New-Object System.Drawing.Point(20, 125)
    $pathText.Size = New-Object System.Drawing.Size(700, 28)
    $pathText.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $pathText.ForeColor = [System.Drawing.Color]::White

    $browseFile = New-Object System.Windows.Forms.Button
    $browseFile.Text = 'Browse File'
    $browseFile.Location = New-Object System.Drawing.Point(735, 124)
    $browseFile.Size = New-Object System.Drawing.Size(85, 30)

    $browseFolder = New-Object System.Windows.Forms.Button
    $browseFolder.Text = 'Browse Dir'
    $browseFolder.Location = New-Object System.Drawing.Point(825, 124)
    $browseFolder.Size = New-Object System.Drawing.Size(85, 30)

    $modeLabel = New-Object System.Windows.Forms.Label
    $modeLabel.Text = 'Mode:'
    $modeLabel.Location = New-Object System.Drawing.Point(20, 172)
    $modeLabel.AutoSize = $true

    $modeCombo = New-Object System.Windows.Forms.ComboBox
    $modeCombo.Location = New-Object System.Drawing.Point(20, 197)
    $modeCombo.Size = New-Object System.Drawing.Size(150, 30)
    $modeCombo.DropDownStyle = 'DropDownList'
    [void]$modeCombo.Items.Add('Encrypt')
    [void]$modeCombo.Items.Add('Decrypt')
    $modeCombo.SelectedIndex = 0

    $recurseCheck = New-Object System.Windows.Forms.CheckBox
    $recurseCheck.Text = 'Recurse subdirectories'
    $recurseCheck.Location = New-Object System.Drawing.Point(190, 200)
    $recurseCheck.AutoSize = $true
    $recurseCheck.Checked = $true

    $threadsLabel = New-Object System.Windows.Forms.Label
    $threadsLabel.Text = 'Worker Threads:'
    $threadsLabel.Location = New-Object System.Drawing.Point(400, 172)
    $threadsLabel.AutoSize = $true

    $threadsBox = New-Object System.Windows.Forms.NumericUpDown
    $threadsBox.Location = New-Object System.Drawing.Point(400, 197)
    $threadsBox.Minimum = 1
    $threadsBox.Maximum = [Math]::Max(1, [Environment]::ProcessorCount)
    $threadsBox.Value = [Environment]::ProcessorCount

    $threadsInfo = New-Object System.Windows.Forms.Label
    $threadsInfo.Text = "Auto-detected cores: $([Environment]::ProcessorCount)"
    $threadsInfo.Location = New-Object System.Drawing.Point(535, 201)
    $threadsInfo.AutoSize = $true
    
    $autoThreadsCheck = New-Object System.Windows.Forms.CheckBox
    $autoThreadsCheck.Text = 'Auto-manage threads'
    $autoThreadsCheck.Location = New-Object System.Drawing.Point(400, 223)
    $autoThreadsCheck.AutoSize = $true
    $autoThreadsCheck.Checked = $true

    $refreshThreadsBtn = New-Object System.Windows.Forms.Button
    $refreshThreadsBtn.Text = 'Recalculate'
    $refreshThreadsBtn.Location = New-Object System.Drawing.Point(540, 220)
    $refreshThreadsBtn.Size = New-Object System.Drawing.Size(110, 26)
    
    $debugModeCheck = New-Object System.Windows.Forms.CheckBox
    $debugModeCheck.Text = 'Debug mode'
    $debugModeCheck.Location = New-Object System.Drawing.Point(665, 223)
    $debugModeCheck.AutoSize = $true
    
    $copyDebugBtn = New-Object System.Windows.Forms.Button
    $copyDebugBtn.Text = 'Copy Debug Report'
    $copyDebugBtn.Location = New-Object System.Drawing.Point(760, 219)
    $copyDebugBtn.Size = New-Object System.Drawing.Size(150, 28)

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = 'Password (optional if certificate selected):'
    $passwordLabel.Location = New-Object System.Drawing.Point(20, 252)
    $passwordLabel.AutoSize = $true

    $passwordText = New-Object System.Windows.Forms.TextBox
    $passwordText.Location = New-Object System.Drawing.Point(20, 277)
    $passwordText.Size = New-Object System.Drawing.Size(350, 28)
    $passwordText.UseSystemPasswordChar = $true
    $passwordText.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $passwordText.ForeColor = [System.Drawing.Color]::White

    $certLabel = New-Object System.Windows.Forms.Label
    $certLabel.Text = 'Certificate (optional if password entered):'
    $certLabel.Location = New-Object System.Drawing.Point(400, 252)
    $certLabel.AutoSize = $true

    $certCombo = New-Object System.Windows.Forms.ComboBox
    $certCombo.Location = New-Object System.Drawing.Point(400, 277)
    $certCombo.Size = New-Object System.Drawing.Size(510, 30)
    $certCombo.DropDownStyle = 'DropDownList'

    $refreshCerts = New-Object System.Windows.Forms.Button
    $refreshCerts.Text = 'Refresh Certs'
    $refreshCerts.Location = New-Object System.Drawing.Point(400, 315)
    $refreshCerts.Size = New-Object System.Drawing.Size(120, 30)

    $newCert = New-Object System.Windows.Forms.Button
    $newCert.Text = 'Generate Certificate'
    $newCert.Location = New-Object System.Drawing.Point(530, 315)
    $newCert.Size = New-Object System.Drawing.Size(180, 30)

    $startBtn = New-Object System.Windows.Forms.Button
    $startBtn.Text = 'Start Operation'
    $startBtn.Location = New-Object System.Drawing.Point(20, 360)
    $startBtn.Size = New-Object System.Drawing.Size(170, 38)
    
    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'Cancel'
    $cancelBtn.Location = New-Object System.Drawing.Point(20, 404)
    $cancelBtn.Size = New-Object System.Drawing.Size(170, 32)
    $cancelBtn.Enabled = $false

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(210, 365)
    $progress.Size = New-Object System.Drawing.Size(700, 28)

    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Multiline = $true
    $logBox.ScrollBars = 'Vertical'
    $logBox.Location = New-Object System.Drawing.Point(20, 460)
    $logBox.Size = New-Object System.Drawing.Size(920, 260)

    $form.Controls.Add($menu)
    $form.Controls.AddRange(@($title,$pathLabel,$pathText,$browseFile,$browseFolder,$modeLabel,$modeCombo,$recurseCheck,$threadsLabel,$threadsBox,$threadsInfo,$autoThreadsCheck,$refreshThreadsBtn,$debugModeCheck,$copyDebugBtn,$passwordLabel,$passwordText,$certLabel,$certCombo,$refreshCerts,$newCert,$startBtn,$cancelBtn,$progress,$logBox))

    $tips.SetToolTip($pathText, 'Select a single file or a directory to process.')
    $tips.SetToolTip($browseFile, 'Pick one file to encrypt/decrypt.')
    $tips.SetToolTip($browseFolder, 'Pick a directory for batch processing.')
    $tips.SetToolTip($modeCombo, 'Encrypt creates .psenc files. Decrypt restores from .psenc files.')
    $tips.SetToolTip($recurseCheck, 'When enabled, includes all subfolders during directory processing.')
    $tips.SetToolTip($threadsBox, 'Maximum parallel workers. Auto mode adjusts this to currently available CPU headroom.')
    $tips.SetToolTip($autoThreadsCheck, 'When enabled, thread count is automatically set from current CPU availability.')
    $tips.SetToolTip($refreshThreadsBtn, 'Refresh worker-thread recommendation based on current CPU utilization.')
    $tips.SetToolTip($debugModeCheck, 'Verbose troubleshooting mode with event log + optional transcript files in the script folder.')
    $tips.SetToolTip($copyDebugBtn, 'Copies a support-ready diagnostic report to clipboard for sharing.')
    $tips.SetToolTip($passwordText, 'Password mode: Enter passphrase. Leave blank if certificate mode is used.')
    $tips.SetToolTip($certCombo, 'Certificate mode: Select an RSA certificate. Leave [None] for password mode.')
    $tips.SetToolTip($refreshCerts, 'Reload certificates from Cert:\\CurrentUser\\My.')
    $tips.SetToolTip($newCert, 'Create a new self-signed RSA encryption certificate in your user certificate store.')
    $tips.SetToolTip($startBtn, 'Start the current encryption/decryption job.')
    $tips.SetToolTip($cancelBtn, 'Request cancellation of the current running job.')
    $tips.SetToolTip($progress, 'Overall progress across files in the current job.')
    $tips.SetToolTip($logBox, 'Live operation log with success/failure details per file.')

    if ($script:startupDebugMode) {
        if (-not $script:transcriptPath) {
            $script:transcriptPath = New-DebugLogPath -Prefix 'SecureVault-LaunchDebug'
        }
        if (-not $script:debugLogPath) {
            $script:debugLogPath = New-DebugLogPath -Prefix 'SecureVault-Debug'
        }
        try {
            Start-Transcript -Path $script:transcriptPath -Append | Out-Null
        }
        catch {
            # Continue even if transcript cannot be started.
        }
        $debugModeCheck.Checked = $true
    }

    $script:certMap = @{}

    $loadCerts = {
        $certCombo.Items.Clear()
        $script:certMap = @{}
        [void]$certCombo.Items.Add('[None]')
        foreach ($c in Get-CertificateList) {
            $display = "{0} | Thumbprint: {1} | Expires: {2:yyyy-MM-dd}" -f $c.Subject, $c.Thumbprint, $c.NotAfter
            $script:certMap[$display] = $c
            [void]$certCombo.Items.Add($display)
        }
        $certCombo.SelectedIndex = 0
    }

    & $loadCerts

    $appendLog = {
        param([string]$msg)
        $line = "[$((Get-Date).ToString('HH:mm:ss'))] $msg"
        $logBox.AppendText("$line`r`n")
        if ($debugModeCheck.Checked) {
            try {
                Add-Content -LiteralPath $script:debugLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
            }
            catch {
                # Avoid crashing UI from debug log write issues.
            }
        }
    }

    $helpIndexText = @'
SecureVault Help Index

1) File or Directory
   - Choose one file or one directory as input.
   - File mode processes exactly one file.
   - Directory mode can process many files (optionally recursive).

2) Mode
   - Encrypt: Produces .psenc encrypted output files.
   - Decrypt: Reads .psenc files and restores plaintext output.

3) Recurse subdirectories
   - Applies only when a directory is selected.
   - Includes files from subfolders automatically.

4) Worker Threads
   - Controls how many files are processed in parallel.
   - Auto-manage threads uses current CPU utilization to avoid overcommitting busy cores.
   - Recalculate refreshes the recommendation before a run.
   - Debug mode writes detailed traces to a log file for troubleshooting hangs/errors.

5) Password
   - Optional when a certificate is selected.
   - Required if certificate is [None].
   - Used to derive encryption/authentication keys.

6) Certificate
   - Optional when password is provided.
   - Required for certificate-based decryption.
   - Refresh Certs updates the list from your cert store.
   - Generate Certificate creates a self-signed RSA cert.

7) Start Operation / Progress / Log
   - Start begins processing.
   - Cancel requests a graceful stop of the current job.
   - Progress bar shows overall completion.
   - Log shows per-file success/failure diagnostics.
   - Debug mode writes event logs to a timestamped file in the script folder.
   - Copy Debug Report copies a full diagnostic package to clipboard for support/troubleshooting.

8) Launch option
   - Start script with `-DebugMode` to force debug logging at launch.
   - In launch debug mode, SecureVault also writes a transcript file in the script folder.
   - The Debug mode checkbox does the same logging behavior without requiring relaunch.
'@

    $refreshThreads = {
        $recommended = Get-RecommendWorkerThreads
        if ($recommended -gt $threadsBox.Maximum) { $recommended = [int]$threadsBox.Maximum }
        if ($recommended -lt $threadsBox.Minimum) { $recommended = [int]$threadsBox.Minimum }
        $threadsBox.Value = $recommended
        $threadsInfo.Text = "Auto-detected cores: $([Environment]::ProcessorCount) | Recommended now: $recommended"
    }

    $autoThreadsCheck.Add_CheckedChanged({
        $threadsBox.Enabled = -not $autoThreadsCheck.Checked
        $refreshThreadsBtn.Enabled = $autoThreadsCheck.Checked
        if ($autoThreadsCheck.Checked) { & $refreshThreads }
    })
    $refreshThreadsBtn.Add_Click({ & $refreshThreads; & $appendLog "Thread recommendation refreshed: $($threadsBox.Value)" })
    & $refreshThreads
    if ($script:startupDebugMode) {
        & $appendLog "Launch parameter -DebugMode detected. Transcript: $script:transcriptPath"
        & $appendLog "Debug event log file: $script:debugLogPath"
    }

    $copyDebugBtn.Add_Click({
        try {
            $settings = @(
                "Timestamp (UTC): $([DateTime]::UtcNow.ToString('u'))"
                "PowerShell: $($PSVersionTable.PSVersion)"
                ".NET: $([Environment]::Version)"
                "OS: $([Environment]::OSVersion.VersionString)"
                "Mode: $($modeCombo.SelectedItem)"
                "Target Path: $($pathText.Text)"
                "Recurse: $($recurseCheck.Checked)"
                "Threads: $($threadsBox.Value)"
                "Auto Threads: $($autoThreadsCheck.Checked)"
                "Debug Mode: $($debugModeCheck.Checked)"
                "Cert Selected: $($certCombo.SelectedItem)"
                "Debug Log Path: $($script:debugLogPath)"
                "Transcript Path: $($script:transcriptPath)"
                "Last Operation: $($script:lastOperation)"
            ) -join "`r`n"

            $logLines = ($logBox.Text -split "`r?`n" | Where-Object { $_ }) 
            $tail = ($logLines | Select-Object -Last 200) -join "`r`n"
            $report = @"
=== SecureVault Debug Report ===
$settings

=== Recent UI Log (last 200 lines) ===
$tail
"@
            [System.Windows.Forms.Clipboard]::SetText($report)
            & $appendLog 'Debug report copied to clipboard.'
        }
        catch {
            & $appendLog "Unable to copy debug report: $($_.Exception.Message)"
        }
    })

    $helpIndexItem.Add_Click({
        [System.Windows.Forms.MessageBox]::Show($helpIndexText, 'SecureVault Help Index', 'OK', 'Information') | Out-Null
    })

    $cryptoItem.Add_Click({
        $details = @'
Encryption Details

- File encryption: AES-256-CBC with PKCS7 padding.
- Integrity/authentication: HMAC-SHA256 over header + ciphertext.
- Password mode: PBKDF2 (200000 iterations).
- Certificate mode: RSA OAEP compatibility path for broad Windows PowerShell support.
- File extension used for encrypted output: .psenc
'@
        [System.Windows.Forms.MessageBox]::Show($details, 'Encryption Details', 'OK', 'Information') | Out-Null
    })

    $aboutItem.Add_Click({
        $about = @'
About SecureVault

SecureVault Encryptor is a standalone PowerShell GUI application.
It supports:
- Password-based file protection
- Certificate-based key wrapping
- Parallel batch processing for directories
'@
        [System.Windows.Forms.MessageBox]::Show($about, 'About SecureVault', 'OK', 'Information') | Out-Null
    })

    $browseFile.Add_Click({ $ofd = New-Object System.Windows.Forms.OpenFileDialog; if ($ofd.ShowDialog() -eq 'OK') { $pathText.Text = $ofd.FileName } })
    $browseFolder.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq 'OK') { $pathText.Text = $fbd.SelectedPath } })
    $refreshCerts.Add_Click({ & $loadCerts; & $appendLog 'Certificate list refreshed.' })
    $newCert.Add_Click({ try { $cert = New-EncryptionCertificate; & $appendLog "Created cert: $($cert.Thumbprint)"; & $loadCerts } catch { & $appendLog "Cert creation failed: $($_.Exception.Message)" } })
    $cancelBtn.Add_Click({
        if ($script:cancelSource) {
            $script:cancelSource.Cancel()
            $script:isRunning = $false
            $startBtn.Enabled = $true
            $cancelBtn.Enabled = $false
            & $appendLog 'Cancellation requested...'
        }
    })

    $startBtn.Add_Click({
        try {
            if ($script:isRunning) {
                throw 'A job is already running. Click Cancel and wait for cancellation to complete.'
            }
            $targetPath = $pathText.Text.Trim()
            if (-not $targetPath) { throw 'Please select a file or directory.' }

            $isEncrypt = $modeCombo.SelectedItem -eq 'Encrypt'
            $files = @(Get-TargetFiles -Path $targetPath -Recurse:$recurseCheck.Checked -EncryptMode:$isEncrypt)
            if (-not $files -or $files.Count -eq 0) { throw 'No matching files found.' }

            $selectedCert = if ($certCombo.SelectedIndex -gt 0) { $script:certMap[$certCombo.SelectedItem] } else { $null }
            if (-not $selectedCert -and [string]::IsNullOrWhiteSpace($passwordText.Text)) {
                throw 'Provide either a password or a certificate.'
            }

            if ($autoThreadsCheck.Checked) { & $refreshThreads }
            $threads = [int]$threadsBox.Value
            $progress.Value = 0
            $progress.Maximum = $files.Count
            $startBtn.Enabled = $false
            $cancelBtn.Enabled = $true
            $script:isRunning = $true
            $script:cancelSource = [System.Threading.CancellationTokenSource]::new()
            $script:debugLogPath = New-DebugLogPath -Prefix 'SecureVault-Debug'
            $debugEnabled = $debugModeCheck.Checked
            $script:lastOperation = "{0} | Path={1} | Files={2} | Threads={3}" -f $modeCombo.SelectedItem, $targetPath, $files.Count, $threads
            if ($debugModeCheck.Checked) {
                & $appendLog "Debug mode enabled. Event log: $script:debugLogPath"
            }
            & $appendLog "Processing $($files.Count) file(s) in $($modeCombo.SelectedItem) mode."

            $certBlob = if ($selectedCert) { [Convert]::ToBase64String($selectedCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)) } else { $null }
            $password = $passwordText.Text

            [System.Threading.Tasks.Task]::Factory.StartNew([Action]{
                try {
                    $counter = [hashtable]::Synchronized(@{ Done = 0 })
                    foreach ($file in $files) {
                        if ($script:cancelSource.IsCancellationRequested) {
                            $form.BeginInvoke([Action]{ & $appendLog 'Operation cancelled by user.' }) | Out-Null
                            break
                        }
                        try {
                            if ($debugEnabled) {
                                $form.BeginInvoke([Action]{ & $appendLog "DEBUG start: $file" }) | Out-Null
                            }
                            if ($isEncrypt) {
                                $out = Join-Path (Split-Path -Path $file -Parent) ("{0}.psenc" -f (Split-Path -Path $file -Leaf))
                                [FastCryptoEngine]::EncryptFile($file, $out, $password, $certBlob)
                            }
                            else {
                                $parent = Split-Path -Path $file -Parent
                                $leaf = Split-Path -Path $file -Leaf
                                $out = if ($leaf.EndsWith('.psenc')) {
                                    Join-Path $parent $leaf.Substring(0, $leaf.Length - 6)
                                }
                                else {
                                    Join-Path $parent ("{0}.decrypted" -f $leaf)
                                }
                                [FastCryptoEngine]::DecryptFile($file, $out, $password, $certBlob)
                            }
                            if ($debugEnabled) {
                                $form.BeginInvoke([Action]{ & $appendLog "DEBUG done: $file" }) | Out-Null
                            }
                            $msg = "OK: $file"
                        }
                        catch {
                            $msg = "FAIL: $file -> $($_.Exception.Message)"
                        }

                        [System.Threading.Interlocked]::Increment([ref]$counter.Done) | Out-Null
                        $form.BeginInvoke([Action]{
                            $progress.Value = [Math]::Min($progress.Maximum, [int]$counter.Done)
                            & $appendLog $msg
                        }) | Out-Null
                    }

                    $form.BeginInvoke([Action]{ & $appendLog 'Operation complete.' }) | Out-Null
                }
                catch {
                    $err = $_.Exception.Message
                    $form.BeginInvoke([Action]{ & $appendLog "Background job failed: $err" }) | Out-Null
                }
                finally {
                    $form.BeginInvoke([Action]{
                        $script:isRunning = $false
                        $startBtn.Enabled = $true
                        $cancelBtn.Enabled = $false
                    }) | Out-Null
                }
            }, [System.Threading.CancellationToken]::None, [System.Threading.Tasks.TaskCreationOptions]::LongRunning, [System.Threading.Tasks.TaskScheduler]::Default) | Out-Null
        }
        catch {
            & $appendLog "Cannot start operation: $($_.Exception.Message)"
            $script:isRunning = $false
            $startBtn.Enabled = $true
            $cancelBtn.Enabled = $false
        }
    })

    $form.Add_FormClosing({
        if ($script:startupDebugMode) {
            try {
                Stop-Transcript | Out-Null
            }
            catch {
                # Ignore transcript shutdown issues.
            }
        }
    })

    [void]$form.ShowDialog()
}

Start-SecureVaultGui
