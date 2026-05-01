using System.Collections.Concurrent;
using System.Diagnostics;
using System.Management;
using System.Text;
using System.Windows.Forms;

var form = new Form { Text = "Windows 11 Integrity Check", Width = 1100, Height = 700 };
var output = new RichTextBox { Dock = DockStyle.Fill, ReadOnly = true, Font = new System.Drawing.Font("Consolas", 10) };
var header = new Label { Dock = DockStyle.Top, Height = 30, Text = "Running live integrity checks...", TextAlign = System.Drawing.ContentAlignment.MiddleLeft };
form.Controls.Add(output);
form.Controls.Add(header);

record CheckResult(string Name, string Status, string Details, double Seconds, string Recommendation);

var checks = new List<Func<CheckResult>>
{
    () => {
        var sw = Stopwatch.StartNew();
        using var searcher = new ManagementObjectSearcher("SELECT Caption, BuildNumber FROM Win32_OperatingSystem");
        var os = searcher.Get().Cast<ManagementObject>().First();
        var build = int.Parse(os["BuildNumber"]?.ToString() ?? "0");
        sw.Stop();
        return build < 22000
            ? new("OS Build", "Critical", $"Build {build} below Windows 11 baseline.", sw.Elapsed.TotalSeconds, "Reinstall or upgrade to Windows 11.")
            : new("OS Build", "Pass", $"{os["Caption"]} build {build}.", sw.Elapsed.TotalSeconds, "");
    },
    () => RunCheck("SFC Verify", "sfc", "/verifyonly", "did not find any integrity violations", "found integrity violations"),
    () => RunCheck("DISM CheckHealth", "DISM", "/Online /Cleanup-Image /CheckHealth", "No component store corruption detected", "component store is repairable"),
    () => {
        var sw = Stopwatch.StartNew();
        var psi = new ProcessStartInfo("bcdedit", "/enum {current}") { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true };
        using var p = Process.Start(psi)!;
        var data = p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        sw.Stop();
        return p.ExitCode == 0 && !string.IsNullOrWhiteSpace(data)
            ? new("Boot Config", "Pass", "BCD current entry accessible.", sw.Elapsed.TotalSeconds, "")
            : new("Boot Config", "Critical", "Could not read BCD current entry.", sw.Elapsed.TotalSeconds, "Repair bootloader from WinRE.");
    }
};

form.Shown += async (_, __) =>
{
    var results = new ConcurrentBag<CheckResult>();
    await Task.WhenAll(checks.Select(check => Task.Run(() =>
    {
        var result = check();
        results.Add(result);
        form.BeginInvoke(() =>
        {
            output.AppendText($"[{DateTime.Now:HH:mm:ss}] {result.Name} | {result.Status} | {result.Seconds:F1}s{Environment.NewLine}");
            output.AppendText($"  {result.Details}{Environment.NewLine}");
            if (!string.IsNullOrWhiteSpace(result.Recommendation))
                output.AppendText($"  Recommendation: {result.Recommendation}{Environment.NewLine}");
            output.AppendText(Environment.NewLine);
        });
    })));

    var overall = results.Any(r => r.Status is "Critical") ? "REINSTALL RECOMMENDED"
        : results.Any(r => r.Status is "Fail") ? "REPAIR INSTALL RECOMMENDED"
        : "HEALTHY / MINOR ISSUES";

    header.Text = $"Completed. Overall: {overall}";
    output.AppendText($"Overall Assessment: {overall}{Environment.NewLine}");
};

Application.Run(form);

static CheckResult RunCheck(string name, string file, string args, string passMarker, string failMarker)
{
    var sw = Stopwatch.StartNew();
    var psi = new ProcessStartInfo(file, args) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
    using var p = Process.Start(psi)!;
    var text = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
    p.WaitForExit();
    sw.Stop();

    if (text.Contains(passMarker, StringComparison.OrdinalIgnoreCase))
        return new(name, "Pass", "No integrity issue detected.", sw.Elapsed.TotalSeconds, "");
    if (text.Contains(failMarker, StringComparison.OrdinalIgnoreCase))
        return new(name, "Fail", "Integrity issue detected.", sw.Elapsed.TotalSeconds, "Run repair command and reevaluate.");
    return new(name, "Warning", "Could not parse command output conclusively.", sw.Elapsed.TotalSeconds, "Review raw output manually.");
}
