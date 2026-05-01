#if WINDOWS
using System.Drawing;
using System.Windows.Forms;
using System.Diagnostics;
using System.Management;
using System.Text;
using System.Runtime.Versioning;

namespace IntegrityCheckGui;

[SupportedOSPlatform("windows")]
internal static class Program
{
    [STAThread]
    private static void Main()
    {
        AppLog.Initialize(Environment.GetCommandLineArgs().Any(a => a.Equals("--debug", StringComparison.OrdinalIgnoreCase)));
        AppLog.Log("Application start.");
        ApplicationConfiguration.Initialize();
        Application.ThreadException += (_, e) => AppLog.Log($"UI thread exception: {e.Exception}");
        AppDomain.CurrentDomain.UnhandledException += (_, e) => AppLog.Log($"Unhandled exception: {e.ExceptionObject}");
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private readonly Label _header;
    private readonly RichTextBox _output;
    private readonly Button _runButton;
    private readonly Button _repairButton;
    private CheckResult[] _lastResults = Array.Empty<CheckResult>();

    public MainForm()
    {
        Text = "Windows 11 Integrity Check";
        Width = 1100;
        Height = 760;

        _header = new Label { Dock = DockStyle.Top, Height = 30, Text = "Ready.", TextAlign = ContentAlignment.MiddleLeft };
        _runButton = new Button { Dock = DockStyle.Top, Height = 35, Text = "Run Integrity Check" };
        _repairButton = new Button { Dock = DockStyle.Top, Height = 35, Text = "Attempt Repair + Recheck", Enabled = false };

        _runButton.Click += async (_, _) => await RunChecksAsync(false);
        _repairButton.Click += async (_, _) => await AttemptRepairAndRecheckAsync();

        _output = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, Font = new Font("Consolas", 10) };

        Controls.Add(_output);
        Controls.Add(_repairButton);
        Controls.Add(_runButton);
        Controls.Add(_header);
    }

    private async Task RunChecksAsync(bool append)
    {
        AppLog.Log($"RunChecksAsync started. append={append}");
        _runButton.Enabled = false;
        _repairButton.Enabled = false;
        if (!append) _output.Clear();

        if (PendingRebootHelper.IsPendingReboot())
        {
            var prompt = MessageBox.Show("A pending reboot is detected. Restart now?", "Pending Reboot", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (prompt == DialogResult.Yes)
            {
                AppLog.Log("Pending reboot approved by user.");
                Process.Start(new ProcessStartInfo("shutdown", "/r /f /t 0") { UseShellExecute = false, CreateNoWindow = true });
                return;
            }
            AppLog.Log("Pending reboot declined by user.");
        }

        _header.Text = "Running checks...";
        var checks = CheckCatalog.BuildChecks();
        var tasks = checks.Select(check => Task.Run(check)).ToArray();
        _lastResults = await Task.WhenAll(tasks);
        AppLog.Log($"Checks completed. Result count: {_lastResults.Length}");

        foreach (var result in _lastResults) AppendResult(result);

        var overall = AssessOverall(_lastResults);
        _header.Text = $"Completed. Overall: {overall}";
        _output.AppendText($"{Environment.NewLine}Overall Assessment: {overall}{Environment.NewLine}");

        _runButton.Enabled = true;
        _repairButton.Enabled = _lastResults.Any(r => r.Status is "Fail" or "Critical" or "Warning");
    }

    private async Task AttemptRepairAndRecheckAsync()
    {
        AppLog.Log("AttemptRepairAndRecheckAsync started.");
        _runButton.Enabled = false;
        _repairButton.Enabled = false;
        _output.AppendText($"{Environment.NewLine}--- Attempting repairs ---{Environment.NewLine}");

        var failed = _lastResults.Where(r => r.Status is "Fail" or "Critical" or "Warning").Select(r => r.Name).ToHashSet();
        if (failed.Contains("SFC Verify")) AppendRepairResult(RepairAction("SFC Repair", "sfc", "/scannow"));
        if (failed.Contains("DISM CheckHealth")) AppendRepairResult(RepairAction("DISM Repair", "DISM", "/Online /Cleanup-Image /RestoreHealth"));
        if (failed.Contains("Windows Update Health")) AppendRepairResult(RepairAction("Reset Windows Update Services", "cmd", "/c net stop wuauserv && net start wuauserv"));

        _output.AppendText($"{Environment.NewLine}--- Rechecking integrity ---{Environment.NewLine}");
        await RunChecksAsync(true);
    }

    private static CheckResult RepairAction(string name, string file, string args)
    {
        AppLog.Log($"RepairAction start: {name} => {file} {args}");
        var sw = Stopwatch.StartNew();
        var pr = ProcessRunner.Run(file, args);
        sw.Stop();
        return pr.ExitCode == 0
            ? new(name, "Pass", "Repair command completed.", sw.Elapsed.TotalSeconds, "")
            : new(name, "Warning", $"Repair command may have failed: {pr.Output}", sw.Elapsed.TotalSeconds, "Review command output manually.");
    }

    private void AppendResult(CheckResult result)
    {
        _output.AppendText($"[{DateTime.Now:HH:mm:ss}] {result.Name} | {result.Status} | {result.Seconds:F1}s{Environment.NewLine}");
        _output.AppendText($"  {result.Details}{Environment.NewLine}");
        if (!string.IsNullOrWhiteSpace(result.Recommendation)) _output.AppendText($"  Recommendation: {result.Recommendation}{Environment.NewLine}");
        _output.AppendText(Environment.NewLine);
    }

    private void AppendRepairResult(CheckResult result)
    {
        _output.AppendText($"[{DateTime.Now:HH:mm:ss}] {result.Name} | {result.Status}{Environment.NewLine}");
        _output.AppendText($"  {result.Details}{Environment.NewLine}{Environment.NewLine}");
    }

    private static string AssessOverall(IEnumerable<CheckResult> results)
    {
        if (results.Any(r => r.Status == "Critical")) return "REINSTALL RECOMMENDED";
        if (results.Any(r => r.Status == "Fail")) return "REPAIR INSTALL RECOMMENDED";
        if (results.Any(r => r.Status == "Warning")) return "ATTENTION NEEDED";
        return "HEALTHY";
    }
}

internal static class CheckCatalog
{
    public static List<Func<CheckResult>> BuildChecks() =>
    [
        CheckOsBuild,
        () => CheckExternal("SFC Verify", "sfc", "/verifyonly", "did not find any integrity violations", "found integrity violations"),
        () => CheckExternal("DISM CheckHealth", "DISM", "/Online /Cleanup-Image /CheckHealth", "No component store corruption detected", "component store is repairable"),
        CheckBootConfig,
        CheckFreeSpace,
        CheckCbsLog,
        () => CheckExternal("CHKDSK Scan", "chkdsk", $"{Environment.GetEnvironmentVariable("SystemDrive") ?? "C:"} /scan", "found no problems", "Windows has made corrections"),
        CheckWindowsUpdateHealth
    ];

    private static CheckResult CheckOsBuild()
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Caption, BuildNumber FROM Win32_OperatingSystem");
            var os = searcher.Get().Cast<ManagementObject>().First();
            var build = int.Parse(os["BuildNumber"]?.ToString() ?? "0");
            sw.Stop();
            return build < 22000 ? new("OS Build", "Critical", $"Build {build} below Windows 11 baseline.", sw.Elapsed.TotalSeconds, "Reinstall or upgrade to Windows 11.") : new("OS Build", "Pass", $"{os["Caption"]} build {build}.", sw.Elapsed.TotalSeconds, "");
        }
        catch (Exception ex) { sw.Stop(); return new("OS Build", "Warning", ex.Message, sw.Elapsed.TotalSeconds, "Check WMI health."); }
    }

    private static CheckResult CheckBootConfig() => FromProcess("Boot Config", "bcdedit", "/enum {current}", "Pass", "Critical", "BCD current entry accessible.", "Could not read BCD current entry.", "Repair bootloader from WinRE.");

    private static CheckResult CheckFreeSpace()
    {
        var sw = Stopwatch.StartNew();
        var drive = new DriveInfo(Environment.GetEnvironmentVariable("SystemDrive") ?? "C:");
        sw.Stop();
        return drive.AvailableFreeSpace < 20L * 1024 * 1024 * 1024 ? new("Free Space", "Fail", "Less than 20GB free.", sw.Elapsed.TotalSeconds, "Free up space.") : new("Free Space", "Pass", "Adequate free space.", sw.Elapsed.TotalSeconds, "");
    }

    private static CheckResult CheckCbsLog()
    {
        var sw = Stopwatch.StartNew();
        var exists = File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Logs", "CBS", "CBS.log"));
        sw.Stop();
        return exists ? new("CBS Log", "Pass", "CBS log exists.", sw.Elapsed.TotalSeconds, "") : new("CBS Log", "Warning", "CBS log not found.", sw.Elapsed.TotalSeconds, "Review servicing logs.");
    }

    private static CheckResult CheckWindowsUpdateHealth()
    {
        var sw = Stopwatch.StartNew();
        var pr = ProcessRunner.Run(
            "powershell",
            "-NoProfile -Command \"$e=Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=2; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue; if($e.Count -gt 20){exit 2}else{exit 0}\"");
        sw.Stop();
        return pr.ExitCode == 0 ? new("Windows Update Health", "Pass", "Update error volume not excessive.", sw.Elapsed.TotalSeconds, "") : new("Windows Update Health", "Warning", "High Windows Update error count detected.", sw.Elapsed.TotalSeconds, "Reset update components.");
    }

    private static CheckResult CheckExternal(string name, string file, string args, string passMarker, string failMarker)
    {
        var sw = Stopwatch.StartNew();
        var pr = ProcessRunner.Run(file, args);
        sw.Stop();
        if (pr.Output.Contains(passMarker, StringComparison.OrdinalIgnoreCase)) return new(name, "Pass", "No integrity issue detected.", sw.Elapsed.TotalSeconds, "");
        if (pr.Output.Contains(failMarker, StringComparison.OrdinalIgnoreCase)) return new(name, "Fail", "Integrity issue detected.", sw.Elapsed.TotalSeconds, "Run repair and recheck.");
        return new(name, "Warning", "Could not parse command output.", sw.Elapsed.TotalSeconds, "Review raw output.");
    }

    private static CheckResult FromProcess(string name, string file, string args, string passStatus, string failStatus, string passDetail, string failDetail, string recommendation)
    {
        var sw = Stopwatch.StartNew();
        var pr = ProcessRunner.Run(file, args);
        sw.Stop();
        return pr.ExitCode == 0 ? new(name, passStatus, passDetail, sw.Elapsed.TotalSeconds, "") : new(name, failStatus, failDetail, sw.Elapsed.TotalSeconds, recommendation);
    }
}

internal static class PendingRebootHelper
{
    [SupportedOSPlatform("windows")]
    public static bool IsPendingReboot()
    {
        return RegistryKeyExists(@"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
            || RegistryKeyExists(@"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
            || RegistryValueExists(@"HKLM\SYSTEM\CurrentControlSet\Control\Session Manager", "PendingFileRenameOperations");
    }

    [SupportedOSPlatform("windows")]
    private static bool RegistryKeyExists(string path)
    {
        using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(path.Replace(@"HKLM\", string.Empty));
        return key is not null;
    }

    [SupportedOSPlatform("windows")]
    private static bool RegistryValueExists(string path, string valueName)
    {
        using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(path.Replace(@"HKLM\", string.Empty));
        return key?.GetValue(valueName) is not null;
    }
}

internal static class ProcessRunner
{
    public static ProcessResult Run(string file, string args)
    {
        AppLog.Log($"Process start: {file} {args}");
        try
        {
            var psi = new ProcessStartInfo(file, args) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            using var process = Process.Start(psi);
            if (process is null) return new ProcessResult(-1, "Process failed to start.");
            var output = new StringBuilder();
            output.AppendLine(process.StandardOutput.ReadToEnd());
            output.AppendLine(process.StandardError.ReadToEnd());
            process.WaitForExit();
            AppLog.Log($"Process exit: {file} code={process.ExitCode}");
            return new ProcessResult(process.ExitCode, output.ToString());
        }
        catch (Exception ex) { AppLog.Log($"Process error: {file} {ex}"); return new ProcessResult(-1, ex.Message); }
    }
}

internal sealed record CheckResult(string Name, string Status, string Details, double Seconds, string Recommendation);
internal sealed record ProcessResult(int ExitCode, string Output);

internal static class AppLog
{
    private static readonly object Sync = new();
    private static bool _debug;
    private static string _path = string.Empty;

    public static void Initialize(bool debug)
    {
        _debug = debug;
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "SystemIntegritySuite");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, $"IntegrityCheckGui_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        Log($"Logger initialized. Debug={_debug}. Path={_path}");
    }

    public static void Log(string message)
    {
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}";
        lock (Sync)
        {
            File.AppendAllText(_path, line + Environment.NewLine);
        }
        if (_debug) Debug.WriteLine(line);
    }
}
#else
Console.WriteLine("IntegrityCheckGui.cs is part of a Windows Forms project.");
Console.WriteLine("Build with: dotnet build .\\IntegrityCheckGui.csproj");
#endif
