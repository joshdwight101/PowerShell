using System.Diagnostics;

namespace MatchboxCSharp.App.Services;

public sealed class DotnetExecutionService
{
    private CancellationTokenSource? _cts;

    public async Task ExecuteAsync(string command, string arguments, Action<string> onOutput)
    {
        _cts = new CancellationTokenSource();

        var psi = new ProcessStartInfo
        {
            FileName = "pwsh",
            Arguments = $"-NoProfile -File ..\\..\\..\\backend\\Invoke-MatchboxCommand.ps1 -Command {command} -Arguments \"{arguments}\"",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.Start();

        var stdout = Task.Run(async () =>
        {
            while (!process.StandardOutput.EndOfStream)
            {
                var line = await process.StandardOutput.ReadLineAsync();
                if (line is not null) onOutput(line);
            }
        }, _cts.Token);

        var stderr = Task.Run(async () =>
        {
            while (!process.StandardError.EndOfStream)
            {
                var line = await process.StandardError.ReadLineAsync();
                if (line is not null) onOutput($"[ERR] {line}");
            }
        }, _cts.Token);

        await Task.WhenAll(stdout, stderr, process.WaitForExitAsync(_cts.Token));
    }

    public void Cancel() => _cts?.Cancel();
}
