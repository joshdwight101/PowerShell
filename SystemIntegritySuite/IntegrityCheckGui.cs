#if WINDOWS
using System.Diagnostics;
using System.Drawing;
using System.Management;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32;
using System.Windows.Forms;

namespace IntegrityCheckGui;

[SupportedOSPlatform("windows")]
internal static class Program
{
    private const string Version = "1.4.0";
    private const string Author = "JD";

    [STAThread]
    private static void Main()
    {
        AppLog.Initialize(Environment.GetCommandLineArgs().Any(a => a.Equals("--debug", StringComparison.OrdinalIgnoreCase)));
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(Version, Author));
    }
}

[SupportedOSPlatform("windows")]
internal sealed class MainForm : Form
{
    private readonly Label _summary;
    private readonly Label _meta;
    private readonly ProgressBar _progress;
    private readonly DataGridView _grid;
    private readonly RichTextBox _log;
    private readonly Button _runBtn;
    private readonly Button _repairBtn;
    private readonly Button _resetWindowsBtn;
    private readonly Button _restartBtn;
    private List<CheckResult> _last = new();

    public MainForm(string version, string author)
    {
        Text = $"Win11 Integrity Checking & Repair Tool v{version} | {author}";
        Width = 1400;
        Height = 900;
        Font = new Font("Segoe UI", 12);

        _summary = new Label { Dock = DockStyle.Top, Height = 36, Text = "Ready", Font = new Font("Segoe UI", 12, FontStyle.Bold) };
        _meta = new Label { Dock = DockStyle.Top, Height = 120, Text = SystemMetadata.BuildSummary(), AutoSize = false };
        _progress = new ProgressBar { Dock = DockStyle.Top, Height = 24 };

        _grid = new DataGridView { Dock = DockStyle.Top, Height = 320, ReadOnly = true, AllowUserToAddRows = false, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill };
        _grid.Columns.Add("Step", "Step");
        _grid.Columns.Add("Status", "Status");
        _grid.Columns.Add("Duration", "Duration (s)");
        _grid.Columns.Add("Details", "Details");

        var panel = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 48 };
        _runBtn = new Button { Text = "Run Integrity Check", Width = 220, Height = 40 };
        _repairBtn = new Button { Text = "Attempt Repairs + Recheck", Width = 270, Height = 40, Enabled = false };
        _resetWindowsBtn = new Button { Text = "Open Reset Windows", Width = 220, Height = 40 };
        _restartBtn = new Button { Text = "Restart Computer", Width = 180, Height = 40 };

        _runBtn.Click += async (_, _) => await RunChecksAsync();
        _repairBtn.Click += async (_, _) => await AttemptRepairAndRecheckAsync();
        _resetWindowsBtn.Click += (_, _) => Process.Start(new ProcessStartInfo("ms-settings:recovery") { UseShellExecute = true });
        _restartBtn.Click += (_, _) => Process.Start(new ProcessStartInfo("shutdown", "/r /t 0") { UseShellExecute = false, CreateNoWindow = true });

        panel.Controls.AddRange(new Control[] { _runBtn, _repairBtn, _resetWindowsBtn, _restartBtn });

        _log = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, Font = new Font("Consolas", 12) };

        Controls.Add(_log);
        Controls.Add(panel);
        Controls.Add(_grid);
        Controls.Add(_progress);
        Controls.Add(_meta);
        Controls.Add(_summary);
    }

    private async Task RunChecksAsync()
    {
        _runBtn.Enabled = false;
        _repairBtn.Enabled = false;
        _grid.Rows.Clear();
        _log.Clear();

        var checks = CheckCatalog.BuildChecks();
        _progress.Value = 0;
        _progress.Maximum = checks.Count;
        _summary.Text = "Running integrity workflow...";

        _last = new List<CheckResult>();
        foreach (var check in checks)
        {
            var row = _grid.Rows.Add(check.Name, "Running", "", "Executing...");
            SetStatusColor(row, "Running");
            WriteLog($"START: {check.Name} | {check.Description}");

            var result = await Task.Run(check.Action);
            _last.Add(result);

            _grid.Rows[row].Cells[1].Value = result.Status;
            _grid.Rows[row].Cells[2].Value = result.Seconds.ToString("F1");
            _grid.Rows[row].Cells[3].Value = result.Details;
            SetStatusColor(row, result.Status);

            WriteLog($"END: {result.Name} => {result.Status} ({result.Seconds:F1}s) :: {result.Details}");
            _progress.Value += 1;
        }

        // Pending reboot check is intentionally done after full integrity checks.
        var pending = PendingRebootInspector.Inspect();
        var pendingRow = _grid.Rows.Add("Pending Reboot Status", pending.IsPending ? "FAIL" : "PASS", "0.0", pending.Summary);
        SetStatusColor(pendingRow, pending.IsPending ? "FAIL" : "PASS");
        WriteLog($"PENDING-REBOOT: {pending.Summary}");

        var overall = DecisionEngine.Overall(_last, pending.IsPending);
        _summary.Text = $"Completed: {overall}";
        WriteLog($"OVERALL: {overall}");

        if (pending.IsPending)
        {
            var prompt = MessageBox.Show("Pending reboot detected after checks. Restart now?", "Pending Reboot", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (prompt == DialogResult.Yes)
            {
                Process.Start(new ProcessStartInfo("shutdown", "/r /t 0") { UseShellExecute = false, CreateNoWindow = true });
            }
        }

        _repairBtn.Enabled = _last.Any(r => r.Status is "FAIL" or "WARNING");
        _runBtn.Enabled = true;
    }

    private async Task AttemptRepairAndRecheckAsync()
    {
        WriteLog("--- Repair Attempt Phase ---");
        var repairs = RepairCatalog.BuildRepairs(_last);
        foreach (var repair in repairs)
        {
            WriteLog($"REPAIR START: {repair.Name}");
            var rr = await Task.Run(repair.Action);
            WriteLog($"REPAIR END: {rr.Name} => {rr.Status} :: {rr.Details}");
        }
        WriteLog("--- Repair attempts complete. Rechecking... ---");
        await RunChecksAsync();
    }

    private void SetStatusColor(int row, string status)
    {
        var cell = _grid.Rows[row].Cells[1];
        cell.Style.ForeColor = status switch
        {
            "PASS" => Color.DarkGreen,
            "FAIL" => Color.DarkRed,
            "WARNING" => Color.DarkOrange,
            "Running" => Color.DarkBlue,
            _ => Color.Black
        };
        cell.Style.Font = new Font("Segoe UI", 12, FontStyle.Bold);
    }

    private void WriteLog(string line)
    {
        var msg = $"[{DateTime.Now:HH:mm:ss}] {line}";
        _log.AppendText(msg + Environment.NewLine);
        AppLog.Log(msg);
    }
}

internal sealed record CheckDefinition(string Name, string Description, Func<CheckResult> Action);
internal sealed record RepairDefinition(string Name, Func<RepairResult> Action);
internal sealed record CheckResult(string Name, string Status, string Details, double Seconds, string Recommendation = "");
internal sealed record RepairResult(string Name, string Status, string Details);

internal static class CheckCatalog
{
    public static List<CheckDefinition> BuildChecks() =>
    [
        new("OS Build", "Validate Windows 11 baseline build", () => Checkers.OsBuild()),
        new("SFC Verify", "System file integrity verification", () => Checkers.External("SFC Verify", "sfc", "/verifyonly", "did not find any integrity violations", "found integrity violations")),
        new("DISM CheckHealth", "Component store health check", () => Checkers.External("DISM CheckHealth", "DISM", "/Online /Cleanup-Image /CheckHealth", "No component store corruption detected", "component store is repairable")),
        new("Boot Config", "Read current BCD entry", () => Checkers.BootConfig()),
        new("CHKDSK Scan", "Online file system scan", () => Checkers.External("CHKDSK Scan", "chkdsk", $"{Environment.GetEnvironmentVariable("SystemDrive") ?? "C:"} /scan", "found no problems", "made corrections")),
        new("CBS Log", "Servicing log availability", () => Checkers.CbsLog()),
        new("Free Space", "Minimum 20GB free on system drive", () => Checkers.FreeSpace()),
        new("Windows Update Health", "Windows Update error trend (30 days)", () => Checkers.UpdateHealth())
    ];
}

internal static class RepairCatalog
{
    public static List<RepairDefinition> BuildRepairs(IEnumerable<CheckResult> results)
    {
        var names = results.Where(r => r.Status is "FAIL" or "WARNING").Select(r => r.Name).ToHashSet();
        var list = new List<RepairDefinition>();
        if (names.Contains("SFC Verify")) list.Add(new("Run SFC Repair", () => Repairers.Run("SFC Repair", "sfc", "/scannow")));
        if (names.Contains("DISM CheckHealth")) list.Add(new("Run DISM RestoreHealth", () => Repairers.Run("DISM Repair", "DISM", "/Online /Cleanup-Image /RestoreHealth")));
        if (names.Contains("Windows Update Health")) list.Add(new("Reset Windows Update Components", Repairers.ResetWindowsUpdate));
        return list;
    }
}

internal static class Checkers
{
    public static CheckResult OsBuild() { var sw=Stopwatch.StartNew(); var os = Wmi.QueryOs(); sw.Stop(); return os.Build >= 22000 ? new("OS Build","PASS",$"{os.Caption} {os.DisplayVersion} build {os.Build}.",sw.Elapsed.TotalSeconds) : new("OS Build","FAIL",$"Build {os.Build} is below Windows 11 baseline.",sw.Elapsed.TotalSeconds,"Reinstall/upgrade recommended."); }
    public static CheckResult BootConfig() => ExternalByExit("Boot Config","bcdedit","/enum {current}","BCD current entry accessible.","Could not read BCD current entry.");
    public static CheckResult CbsLog(){var sw=Stopwatch.StartNew();var e=File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"Logs","CBS","CBS.log"));sw.Stop();return e?new("CBS Log","PASS","CBS log exists.",sw.Elapsed.TotalSeconds):new("CBS Log","WARNING","CBS log missing.",sw.Elapsed.TotalSeconds,"Investigate servicing state.");}
    public static CheckResult FreeSpace(){var sw=Stopwatch.StartNew();var d=new DriveInfo(Environment.GetEnvironmentVariable("SystemDrive")??"C:");sw.Stop();return d.AvailableFreeSpace>=20L*1024*1024*1024?new("Free Space","PASS",$"{d.AvailableFreeSpace/(1024*1024*1024)} GB free.",sw.Elapsed.TotalSeconds):new("Free Space","FAIL","Less than 20GB free.",sw.Elapsed.TotalSeconds,"Free disk space.");}
    public static CheckResult UpdateHealth(){var sw=Stopwatch.StartNew(); var pr=Proc.Run("powershell","-NoProfile -Command \"$e=Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=2; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue; if($e.Count -gt 20){exit 2}else{exit 0}\""); sw.Stop(); return pr.ExitCode==0?new("Windows Update Health","PASS","Update errors within acceptable range.",sw.Elapsed.TotalSeconds):new("Windows Update Health","WARNING","High update error count detected.",sw.Elapsed.TotalSeconds,"Reset Windows Update components.");}
    public static CheckResult External(string name,string file,string args,string pass,string fail){var sw=Stopwatch.StartNew();var pr=Proc.Run(file,args);sw.Stop();if(pr.Output.Contains(pass,StringComparison.OrdinalIgnoreCase)) return new(name,"PASS","No integrity issue detected.",sw.Elapsed.TotalSeconds);if(pr.Output.Contains(fail,StringComparison.OrdinalIgnoreCase)) return new(name,"FAIL","Integrity issue detected.",sw.Elapsed.TotalSeconds,"Attempt repair.");return new(name,"WARNING",$"Could not conclusively parse output. ExitCode={pr.ExitCode}",sw.Elapsed.TotalSeconds,"Review command output/log.");}
    private static CheckResult ExternalByExit(string name,string file,string args,string pass,string fail){var sw=Stopwatch.StartNew();var pr=Proc.Run(file,args);sw.Stop();return pr.ExitCode==0?new(name,"PASS",pass,sw.Elapsed.TotalSeconds):new(name,"FAIL",fail,sw.Elapsed.TotalSeconds,"Manual boot repair may be required.");}
}

internal static class Repairers
{
    public static RepairResult Run(string name, string file, string args)
    {
        var p = Proc.Run(file, args);
        return p.ExitCode == 0 ? new(name, "PASS", "Repair command completed.") : new(name, "FAIL", $"Repair command failed. ExitCode={p.ExitCode}");
    }

    public static RepairResult ResetWindowsUpdate()
    {
        var cmd = "/c net stop wuauserv && net stop bits && net stop cryptsvc && ren %systemroot%\\SoftwareDistribution SoftwareDistribution.bak && ren %systemroot%\\System32\\catroot2 catroot2.bak && net start cryptsvc && net start bits && net start wuauserv";
        return Run("Reset Windows Update Components", "cmd", cmd);
    }
}

internal sealed record ProcResult(int ExitCode, string Output);
internal static class Proc
{
    public static ProcResult Run(string file, string args)
    {
        AppLog.Log($"Process: {file} {args}");
        try
        {
            var psi = new ProcessStartInfo(file, args) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            using var p = Process.Start(psi);
            if (p is null) return new(-1, "Process failed to start");
            var o = p.StandardOutput.ReadToEnd() + Environment.NewLine + p.StandardError.ReadToEnd();
            p.WaitForExit();
            return new(p.ExitCode, o);
        }
        catch (Exception ex) { return new(-1, ex.ToString()); }
    }
}

internal static class DecisionEngine
{
    public static string Overall(IEnumerable<CheckResult> checks, bool pendingReboot)
    {
        if (checks.Any(c => c.Status == "FAIL") && pendingReboot) return "REPAIR ATTEMPTS REQUIRED + REBOOT PENDING";
        if (checks.Any(c => c.Status == "FAIL")) return "REPAIR REQUIRED (REINSTALL MAY BE NEEDED IF FAILURES PERSIST)";
        if (checks.Any(c => c.Status == "WARNING")) return "ATTENTION NEEDED";
        if (pendingReboot) return "HEALTHY BUT REBOOT PENDING";
        return "HEALTHY";
    }
}

internal sealed record PendingRebootResult(bool IsPending, string Summary);
internal static class PendingRebootInspector
{
    public static PendingRebootResult Inspect()
    {
        var flags = new List<string>();
        if (KeyExists(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")) flags.Add("CBS RebootPending");
        if (KeyExists(@"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")) flags.Add("WindowsUpdate RebootRequired");
        if (ValueExists(@"SYSTEM\CurrentControlSet\Control\Session Manager", "PendingFileRenameOperations")) flags.Add("PendingFileRenameOperations");
        return new(flags.Count > 0, flags.Count > 0 ? string.Join("; ", flags) : "No pending reboot flags detected.");
    }
    private static bool KeyExists(string path) => Registry.LocalMachine.OpenSubKey(path) is not null;
    private static bool ValueExists(string path, string name) => Registry.LocalMachine.OpenSubKey(path)?.GetValue(name) is not null;
}

internal sealed record OsInfo(string Caption, string Build, string DisplayVersion, string Manufacturer, string Model, string Serial, string Hostname);
internal static class Wmi
{
    public static OsInfo QueryOs()
    {
        using var osq = new ManagementObjectSearcher("SELECT Caption,BuildNumber FROM Win32_OperatingSystem");
        using var csq = new ManagementObjectSearcher("SELECT Manufacturer,Model FROM Win32_ComputerSystem");
        using var biosq = new ManagementObjectSearcher("SELECT SerialNumber FROM Win32_BIOS");

        var os = osq.Get().Cast<ManagementObject>().First();
        var cs = csq.Get().Cast<ManagementObject>().First();
        var bios = biosq.Get().Cast<ManagementObject>().First();

        var displayVersion = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion")?.GetValue("DisplayVersion")?.ToString() ?? "Unknown";
        return new(
            os["Caption"]?.ToString() ?? "Unknown Windows",
            os["BuildNumber"]?.ToString() ?? "0",
            displayVersion,
            cs["Manufacturer"]?.ToString() ?? "Unknown",
            cs["Model"]?.ToString() ?? "Unknown",
            bios["SerialNumber"]?.ToString() ?? "Unknown",
            Environment.MachineName);
    }
}

internal static class SystemMetadata
{
    public static string BuildSummary()
    {
        var i = Wmi.QueryOs();
        return $"Host: {i.Hostname} | Serial: {i.Serial} | Manufacturer: {i.Manufacturer} | Model: {i.Model}\nOS: {i.Caption} {i.DisplayVersion} (Build {i.Build}) | Time: {DateTime.Now:yyyy-MM-dd HH:mm:ss}";
    }
}

internal static class AppLog
{
    private static readonly object LockObj = new();
    private static string _path = "";
    public static void Initialize(bool debug)
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "SystemIntegritySuite");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, $"IntegrityTool_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        Log($"Init. Debug={debug}");
    }
    public static void Log(string line){lock(LockObj){File.AppendAllText(_path,$"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {line}{Environment.NewLine}");}}
}
#else
Console.WriteLine("Build using IntegrityCheckGui.csproj on Windows.");
#endif
