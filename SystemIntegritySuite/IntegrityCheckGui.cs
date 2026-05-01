using System.Diagnostics;
using System.Management;
using System.Text;

namespace IntegrityCheckGui;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private readonly Label _header;
    private readonly RichTextBox _output;
    private readonly Button _runButton;

    public MainForm()
    {
        Text = "Windows 11 Integrity Check";
        Width = 1100;
        Height = 700;

        _header = new Label
        {
            Dock = DockStyle.Top,
            Height = 30,
            Text = "Ready.",
            TextAlign = ContentAlignment.MiddleLeft
        };

        _runButton = new Button
        {
            Dock = DockStyle.Top,
            Height = 35,
            Text = "Run Integrity Check"
        };
        _runButton.Click += async (_, _) => await RunChecksAsync();

        _output = new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Font = new Font("Consolas", 10)
        };

        Controls.Add(_output);
        Controls.Add(_runButton);
        Controls.Add(_header);
    }

    private async Task RunChecksAsync()
    {
        _runButton.Enabled = false;
        _output.Clear();
        _header.Text = "Running checks...";

        var checks = new List<Func<CheckResult>>
        {
            CheckOsBuild,
            () => RunExternalCheck("SFC Verify", "sfc", "/verifyonly", "did not find any integrity violations", "found integrity violations"),
            () => RunExternalCheck("DISM CheckHealth", "DISM", "/Online /Cleanup-Image /CheckHealth", "No component store corruption detected", "component store is repairable"),
            CheckBootConfig,
            CheckFreeSpace,
            CheckCbsLog,
            () => RunExternalCheck("CHKDSK Scan", "chkdsk", $"{Environment.GetEnvironmentVariable("SystemDrive") ?? "C:"} /scan", "found no problems", "Windows has made corrections")
        };

        var tasks = checks.Select(check => Task.Run(() =>
        {
            var result = check();
            BeginInvoke(() => AppendResult(result));
            return result;
        })).ToArray();

        var results = await Task.WhenAll(tasks);

        var overall = results.Any(r => r.Status == "Critical") ? "REINSTALL RECOMMENDED"
            : results.Any(r => r.Status == "Fail") ? "REPAIR INSTALL RECOMMENDED"
            : results.Any(r => r.Status == "Warning") ? "ATTENTION NEEDED"
            : "HEALTHY";

        _header.Text = $"Completed. Overall: {overall}";
        _output.AppendText($"{Environment.NewLine}Overall Assessment: {overall}{Environment.NewLine}");
        _runButton.Enabled = true;
    }

    private void AppendResult(CheckResult result)
    {
        _output.AppendText($"[{DateTime.Now:HH:mm:ss}] {result.Name} | {result.Status} | {result.Seconds:F1}s{Environment.NewLine}");
        _output.AppendText($"  {result.Details}{Environment.NewLine}");
        if (!string.IsNullOrWhiteSpace(result.Recommendation))
        {
            _output.AppendText($"  Recommendation: {result.Recommendation}{Environment.NewLine}");
        }
        _output.AppendText(Environment.NewLine);
    }

    private static CheckResult CheckOsBuild()
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Caption, BuildNumber FROM Win32_OperatingSystem");
            var os = searcher.Get().Cast<ManagementObject>().First();
            var build = int.Parse(os["BuildNumber"]?.ToString() ?? "0");
            sw.Stop();

            return build < 22000
                ? new("OS Build", "Critical", $"Build {build} below Windows 11 baseline.", sw.Elapsed.TotalSeconds, "Reinstall or upgrade to Windows 11.")
                : new("OS Build", "Pass", $"{os["Caption"]} build {build}.", sw.Elapsed.TotalSeconds, "");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new("OS Build", "Warning", $"Unable to read OS build: {ex.Message}", sw.Elapsed.TotalSeconds, "Run as administrator and verify WMI health.");
        }
    }

    private static CheckResult CheckBootConfig()
    {
        var sw = Stopwatch.StartNew();
        var result = RunProcess("bcdedit", "/enum {current}");
        sw.Stop();

        return result.ExitCode == 0 && !string.IsNullOrWhiteSpace(result.Output)
            ? new("Boot Config", "Pass", "BCD current entry accessible.", sw.Elapsed.TotalSeconds, "")
            : new("Boot Config", "Critical", "Could not read BCD current entry.", sw.Elapsed.TotalSeconds, "Repair bootloader from WinRE.");
    }

    private static CheckResult CheckFreeSpace()
    {
        var sw = Stopwatch.StartNew();
        var systemDrive = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
        var drive = new DriveInfo(systemDrive);
        sw.Stop();

        return drive.AvailableFreeSpace < 20L * 1024 * 1024 * 1024
            ? new("Free Space", "Fail", $"Less than 20GB free on {systemDrive}.", sw.Elapsed.TotalSeconds, "Free disk space before repair operations.")
            : new("Free Space", "Pass", $"{drive.AvailableFreeSpace / (1024 * 1024 * 1024)} GB free.", sw.Elapsed.TotalSeconds, "");
    }

    private static CheckResult CheckCbsLog()
    {
        var sw = Stopwatch.StartNew();
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Logs", "CBS", "CBS.log");
        var exists = File.Exists(path);
        sw.Stop();

        return exists
            ? new("CBS Log", "Pass", "CBS.log exists for servicing diagnostics.", sw.Elapsed.TotalSeconds, "")
            : new("CBS Log", "Warning", "CBS.log not found.", sw.Elapsed.TotalSeconds, "Review servicing/logging configuration.");
    }

    private static CheckResult RunExternalCheck(string name, string file, string args, string passMarker, string failMarker)
    {
        var sw = Stopwatch.StartNew();
        var result = RunProcess(file, args);
        sw.Stop();

        if (result.Output.Contains(passMarker, StringComparison.OrdinalIgnoreCase))
        {
            return new(name, "Pass", "No integrity issue detected.", sw.Elapsed.TotalSeconds, "");
        }

        if (result.Output.Contains(failMarker, StringComparison.OrdinalIgnoreCase))
        {
            return new(name, "Fail", "Integrity issue detected.", sw.Elapsed.TotalSeconds, "Run repair command and re-evaluate.");
        }

        return new(name, "Warning", "Could not parse command output conclusively.", sw.Elapsed.TotalSeconds, "Review raw command output manually.");
    }

    private static ProcessResult RunProcess(string file, string args)
    {
        try
        {
            var psi = new ProcessStartInfo(file, args)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process is null)
            {
                return new ProcessResult(-1, "Process failed to start.");
            }

            var output = new StringBuilder();
            output.AppendLine(process.StandardOutput.ReadToEnd());
            output.AppendLine(process.StandardError.ReadToEnd());
            process.WaitForExit();

            return new ProcessResult(process.ExitCode, output.ToString());
        }
        catch (Exception ex)
        {
            return new ProcessResult(-1, ex.Message);
        }
    }

    private sealed record CheckResult(string Name, string Status, string Details, double Seconds, string Recommendation);
    private sealed record ProcessResult(int ExitCode, string Output);
}
