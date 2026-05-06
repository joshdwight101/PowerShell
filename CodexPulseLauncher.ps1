<#
.SYNOPSIS
    CodexPulseLauncher - A sleek PowerShell script launcher with a C# WinForms GUI.

.DESCRIPTION
    Designed for rapid script testing while working with Codex. Discovers PowerShell scripts
    in the repository and launches them via:
      powershell.exe -ExecutionPolicy Bypass -NoProfile -File <script>

.AUTHOR
    Joshua Dwight - https://github.com/joshdwight101
#>

[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = (Get-Location).Path
}

$RootPath = [System.IO.Path]::GetFullPath($RootPath)

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
    throw "Root path does not exist or is not a directory: $RootPath"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$launcherCSharp = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

public class CodexPulseLauncherForm : Form
{
    private readonly string _rootPath;
    private readonly ListView _scriptsView = new ListView();
    private readonly TextBox _searchBox = new TextBox();
    private readonly Label _statusLabel = new Label();
    private readonly Label _pathLabel = new Label();
    private readonly Button _refreshButton = new Button();
    private readonly Button _launchButton = new Button();
    private readonly Button _openButton = new Button();

    public CodexPulseLauncherForm(string rootPath)
    {
        _rootPath = rootPath;

        Text = "CodexPulseLauncher v1.0.0 · by Joshua Dwight";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(980, 640);
        Size = new Size(1100, 700);
        BackColor = Color.FromArgb(17, 24, 39);
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 10f, FontStyle.Regular);

        BuildLayout();
        WireEvents();
        RefreshScripts();
    }

    private void BuildLayout()
    {
        var title = new Label
        {
            Text = "CodexPulseLauncher",
            Font = new Font("Segoe UI Semibold", 20f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = true,
            Location = new Point(24, 18)
        };

        var subtitle = new Label
        {
            Text = "Fast script testing for PowerShell + Codex",
            Font = new Font("Segoe UI", 10f, FontStyle.Regular),
            ForeColor = Color.FromArgb(148, 163, 184),
            AutoSize = true,
            Location = new Point(27, 58)
        };

        _searchBox.PlaceholderText = "Search scripts...";
        _searchBox.BackColor = Color.FromArgb(30, 41, 59);
        _searchBox.ForeColor = Color.White;
        _searchBox.BorderStyle = BorderStyle.FixedSingle;
        _searchBox.Location = new Point(24, 95);
        _searchBox.Size = new Size(440, 30);

        _refreshButton.Text = "Refresh";
        _refreshButton.FlatStyle = FlatStyle.Flat;
        _refreshButton.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
        _refreshButton.BackColor = Color.FromArgb(30, 41, 59);
        _refreshButton.ForeColor = Color.White;
        _refreshButton.Location = new Point(480, 95);
        _refreshButton.Size = new Size(100, 30);

        _launchButton.Text = "Launch (Bypass)";
        _launchButton.FlatStyle = FlatStyle.Flat;
        _launchButton.FlatAppearance.BorderColor = Color.FromArgb(16, 185, 129);
        _launchButton.BackColor = Color.FromArgb(5, 150, 105);
        _launchButton.ForeColor = Color.White;
        _launchButton.Location = new Point(592, 95);
        _launchButton.Size = new Size(150, 30);

        _openButton.Text = "Open Folder";
        _openButton.FlatStyle = FlatStyle.Flat;
        _openButton.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
        _openButton.BackColor = Color.FromArgb(30, 41, 59);
        _openButton.ForeColor = Color.White;
        _openButton.Location = new Point(752, 95);
        _openButton.Size = new Size(120, 30);

        _scriptsView.Location = new Point(24, 140);
        _scriptsView.Size = new Size(1036, 460);
        _scriptsView.View = View.Details;
        _scriptsView.FullRowSelect = true;
        _scriptsView.GridLines = false;
        _scriptsView.MultiSelect = false;
        _scriptsView.HideSelection = false;
        _scriptsView.BackColor = Color.FromArgb(15, 23, 42);
        _scriptsView.ForeColor = Color.White;
        _scriptsView.BorderStyle = BorderStyle.FixedSingle;
        _scriptsView.Columns.Add("Script", 360);
        _scriptsView.Columns.Add("Directory", 510);
        _scriptsView.Columns.Add("Modified", 140);

        _pathLabel.Text = "Selected: (none)";
        _pathLabel.AutoEllipsis = true;
        _pathLabel.ForeColor = Color.FromArgb(148, 163, 184);
        _pathLabel.Location = new Point(24, 610);
        _pathLabel.Size = new Size(1036, 24);

        _statusLabel.Text = "Ready";
        _statusLabel.ForeColor = Color.FromArgb(52, 211, 153);
        _statusLabel.Location = new Point(24, 635);
        _statusLabel.Size = new Size(1036, 24);

        Controls.Add(title);
        Controls.Add(subtitle);
        Controls.Add(_searchBox);
        Controls.Add(_refreshButton);
        Controls.Add(_launchButton);
        Controls.Add(_openButton);
        Controls.Add(_scriptsView);
        Controls.Add(_pathLabel);
        Controls.Add(_statusLabel);
    }

    private void WireEvents()
    {
        _refreshButton.Click += (s, e) => RefreshScripts();
        _searchBox.TextChanged += (s, e) => RefreshScripts();
        _launchButton.Click += (s, e) => LaunchSelectedScript();
        _openButton.Click += (s, e) => OpenSelectedFolder();
        _scriptsView.DoubleClick += (s, e) => LaunchSelectedScript();
        _scriptsView.SelectedIndexChanged += (s, e) => UpdateSelectedPathLabel();
    }

    private void RefreshScripts()
    {
        _scriptsView.Items.Clear();

        var scripts = Directory.GetFiles(_rootPath, "*.ps1", SearchOption.AllDirectories);
        var needle = (_searchBox.Text ?? string.Empty).Trim();

        int count = 0;
        foreach (var script in scripts)
        {
            var fileName = Path.GetFileName(script);

            if (fileName.Equals("CodexPulseLauncher.ps1", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (needle.Length > 0 && fileName.IndexOf(needle, StringComparison.OrdinalIgnoreCase) < 0 &&
                script.IndexOf(needle, StringComparison.OrdinalIgnoreCase) < 0)
            {
                continue;
            }

            var item = new ListViewItem(fileName);
            item.SubItems.Add(Path.GetDirectoryName(script) ?? string.Empty);
            item.SubItems.Add(File.GetLastWriteTime(script).ToString("yyyy-MM-dd HH:mm"));
            item.Tag = script;
            _scriptsView.Items.Add(item);
            count++;
        }

        _statusLabel.Text = $"Ready · Found {count} script(s)";
        if (_scriptsView.Items.Count > 0)
        {
            _scriptsView.Items[0].Selected = true;
        }
        else
        {
            _pathLabel.Text = "Selected: (none)";
        }
    }

    private string? GetSelectedScript()
    {
        if (_scriptsView.SelectedItems.Count == 0)
        {
            return null;
        }

        return _scriptsView.SelectedItems[0].Tag as string;
    }

    private void UpdateSelectedPathLabel()
    {
        var script = GetSelectedScript();
        _pathLabel.Text = script == null ? "Selected: (none)" : $"Selected: {script}";
    }

    private void OpenSelectedFolder()
    {
        var script = GetSelectedScript();
        if (string.IsNullOrWhiteSpace(script))
        {
            _statusLabel.Text = "Select a script first.";
            _statusLabel.ForeColor = Color.FromArgb(251, 191, 36);
            return;
        }

        var dir = Path.GetDirectoryName(script);
        if (dir == null)
        {
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = dir,
            UseShellExecute = true
        });

        _statusLabel.Text = "Opened script folder.";
        _statusLabel.ForeColor = Color.FromArgb(52, 211, 153);
    }

    private void LaunchSelectedScript()
    {
        var script = GetSelectedScript();
        if (string.IsNullOrWhiteSpace(script))
        {
            _statusLabel.Text = "Select a script first.";
            _statusLabel.ForeColor = Color.FromArgb(251, 191, 36);
            return;
        }

        try
        {
            var escapedPath = script.Replace("\"", "\"\"");
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{escapedPath}\"",
                WorkingDirectory = Path.GetDirectoryName(script) ?? _rootPath,
                UseShellExecute = true
            });

            _statusLabel.Text = $"Launched: {Path.GetFileName(script)}";
            _statusLabel.ForeColor = Color.FromArgb(52, 211, 153);
        }
        catch (Exception ex)
        {
            _statusLabel.Text = "Launch failed: " + ex.Message;
            _statusLabel.ForeColor = Color.FromArgb(248, 113, 113);
        }
    }
}
"@

Add-Type -TypeDefinition $launcherCSharp -Language CSharp -ReferencedAssemblies System.Windows.Forms,System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[void][System.Windows.Forms.Application]::Run([CodexPulseLauncherForm]::new($RootPath))
