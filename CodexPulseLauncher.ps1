<#
.SYNOPSIS
    CodexPulseLauncher - A sleek PowerShell script launcher with a C# WinForms GUI.
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
using System.Security.Principal;
using System.Windows.Forms;

public class CodexPulseLauncherForm : Form
{
    private readonly ListView _scriptsView = new ListView();
    private readonly TextBox _searchBox = new TextBox();
    private readonly Label _statusLabel = new Label();
    private readonly Label _pathLabel = new Label();
    private readonly Button _refreshButton = new Button();
    private readonly Button _launchButton = new Button();
    private readonly Button _openButton = new Button();
    private readonly Button _browseRootButton = new Button();
    private readonly TextBox _rootPathBox = new TextBox();
    private readonly CheckBox _autoRefreshCheck = new CheckBox();
    private readonly NumericUpDown _refreshSeconds = new NumericUpDown();
    private readonly Timer _autoRefreshTimer = new Timer();
    private readonly ContextMenuStrip _scriptMenu = new ContextMenuStrip();

    private string _rootPath;
    private readonly bool _isAdmin;

    public CodexPulseLauncherForm(string rootPath)
    {
        _rootPath = rootPath;
        _isAdmin = IsRunningAsAdmin();

        Text = "CodexPulseLauncher v1.0.1 - by Joshua Dwight";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(980, 700);
        Size = new Size(1120, 760);
        BackColor = Color.FromArgb(17, 24, 39);
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 10f, FontStyle.Regular);

        BuildLayout();
        WireEvents();
        ConfigureContextMenu();
        ConfigureAutoRefresh();
        RefreshScripts();
    }

    public string GetRootPath()
    {
        return _rootPath;
    }

    private bool IsRunningAsAdmin()
    {
        WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private void BuildLayout()
    {
        var title = new Label { Text = "CodexPulseLauncher", Font = new Font("Segoe UI Semibold", 20f, FontStyle.Bold), ForeColor = Color.White, AutoSize = true, Location = new Point(24, 18) };
        var subtitle = new Label { Text = "Fast script testing for PowerShell + Codex", Font = new Font("Segoe UI", 10f, FontStyle.Regular), ForeColor = Color.FromArgb(148, 163, 184), AutoSize = true, Location = new Point(27, 58) };

        _searchBox.BackColor = Color.FromArgb(30, 41, 59);
        _searchBox.ForeColor = Color.White;
        _searchBox.BorderStyle = BorderStyle.FixedSingle;
        _searchBox.Location = new Point(24, 126);
        _searchBox.Size = new Size(500, 30);

        _refreshButton.Text = "Refresh";
        _refreshButton.FlatStyle = FlatStyle.Flat;
        _refreshButton.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
        _refreshButton.BackColor = Color.FromArgb(30, 41, 59);
        _refreshButton.ForeColor = Color.White;
        _refreshButton.Location = new Point(540, 126);
        _refreshButton.Size = new Size(100, 30);

        _launchButton.Text = "Launch (Bypass)";
        _launchButton.FlatStyle = FlatStyle.Flat;
        _launchButton.FlatAppearance.BorderColor = Color.FromArgb(16, 185, 129);
        _launchButton.BackColor = Color.FromArgb(5, 150, 105);
        _launchButton.ForeColor = Color.White;
        _launchButton.Location = new Point(652, 126);
        _launchButton.Size = new Size(150, 30);

        _openButton.Text = "Open Folder";
        _openButton.FlatStyle = FlatStyle.Flat;
        _openButton.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
        _openButton.BackColor = Color.FromArgb(30, 41, 59);
        _openButton.ForeColor = Color.White;
        _openButton.Location = new Point(812, 126);
        _openButton.Size = new Size(120, 30);

        _scriptsView.Location = new Point(24, 171);
        _scriptsView.Size = new Size(1060, 469);
        _scriptsView.View = View.Details;
        _scriptsView.FullRowSelect = true;
        _scriptsView.MultiSelect = false;
        _scriptsView.HideSelection = false;
        _scriptsView.BackColor = Color.FromArgb(15, 23, 42);
        _scriptsView.ForeColor = Color.White;
        _scriptsView.BorderStyle = BorderStyle.FixedSingle;
        _scriptsView.Columns.Add("Script", 360);
        _scriptsView.Columns.Add("Directory", 560);
        _scriptsView.Columns.Add("Modified", 140);

        _pathLabel.Text = "Selected: (none)";
        _pathLabel.AutoEllipsis = true;
        _pathLabel.ForeColor = Color.FromArgb(148, 163, 184);
        _pathLabel.Location = new Point(24, 648);
        _pathLabel.Size = new Size(1060, 24);

        _statusLabel.Text = _isAdmin ? "Ready (Admin)" : "Ready (Standard User)";
        _statusLabel.ForeColor = Color.FromArgb(52, 211, 153);
        _statusLabel.Location = new Point(24, 673);
        _statusLabel.Size = new Size(560, 24);

        var folderLabel = new Label
        {
            Text = "Script Directory",
            ForeColor = Color.FromArgb(148, 163, 184),
            BackColor = Color.FromArgb(17, 24, 39),
            AutoSize = true,
            Location = new Point(540, 62)
        };

        _refreshSeconds.Minimum = 2;
        _refreshSeconds.Maximum = 600;
        _refreshSeconds.Value = 15;
        _refreshSeconds.Location = new Point(905, 669);
        _refreshSeconds.Size = new Size(58, 24);
        _refreshSeconds.BackColor = Color.FromArgb(30, 41, 59);
        _refreshSeconds.ForeColor = Color.White;

        _autoRefreshCheck.Text = "Auto Refresh";
        _autoRefreshCheck.ForeColor = Color.FromArgb(148, 163, 184);
        _autoRefreshCheck.BackColor = Color.FromArgb(17, 24, 39);
        _autoRefreshCheck.Location = new Point(792, 671);
        _autoRefreshCheck.Size = new Size(108, 24);

        var secondsLabel = new Label { Text = "sec", ForeColor = Color.FromArgb(148, 163, 184), AutoSize = true, Location = new Point(968, 672) };
        var rootLabel = new Label { Text = "Folder:", ForeColor = Color.FromArgb(148, 163, 184), AutoSize = true, Location = new Point(540, 92) };

        _rootPathBox.Location = new Point(590, 89);
        _rootPathBox.Size = new Size(415, 24);
        _rootPathBox.ReadOnly = true;
        _rootPathBox.BackColor = Color.FromArgb(30, 41, 59);
        _rootPathBox.ForeColor = Color.White;
        _rootPathBox.Text = _rootPath;

        _browseRootButton.Text = "Browse...";
        _browseRootButton.FlatStyle = FlatStyle.Flat;
        _browseRootButton.FlatAppearance.BorderColor = Color.FromArgb(71, 85, 105);
        _browseRootButton.BackColor = Color.FromArgb(30, 41, 59);
        _browseRootButton.ForeColor = Color.White;
        _browseRootButton.Location = new Point(1010, 88);
        _browseRootButton.Size = new Size(68, 26);

        Controls.Add(title); Controls.Add(subtitle); Controls.Add(_searchBox); Controls.Add(_refreshButton);
        Controls.Add(_launchButton); Controls.Add(_openButton); Controls.Add(_scriptsView); Controls.Add(_pathLabel);
        Controls.Add(_statusLabel); Controls.Add(folderLabel); Controls.Add(rootLabel); Controls.Add(_rootPathBox); Controls.Add(_browseRootButton);
        Controls.Add(_autoRefreshCheck); Controls.Add(_refreshSeconds); Controls.Add(secondsLabel);
    }

    private void ConfigureContextMenu()
    {
        var editItem = new ToolStripMenuItem("Edit in PowerShell ISE");
        editItem.Click += (s, e) => EditSelectedInIse(false);

        var editAdminText = _isAdmin ? "Edit in ISE as Administrator (Already Elevated)" : "Edit in ISE as Administrator";
        var editAdminItem = new ToolStripMenuItem(editAdminText);
        editAdminItem.Click += (s, e) => EditSelectedInIse(true);

        _scriptMenu.Items.Add(editItem);
        _scriptMenu.Items.Add(editAdminItem);
        _scriptsView.ContextMenuStrip = _scriptMenu;
    }

    private void ConfigureAutoRefresh()
    {
        _autoRefreshTimer.Interval = (int)_refreshSeconds.Value * 1000;
        _autoRefreshTimer.Tick += (s, e) => RefreshScripts();
    }

    private void WireEvents()
    {
        _refreshButton.Click += (s, e) => RefreshScripts();
        _searchBox.TextChanged += (s, e) => RefreshScripts();
        _launchButton.Click += (s, e) => LaunchSelectedScript();
        _openButton.Click += (s, e) => OpenSelectedFolder();
        _scriptsView.DoubleClick += (s, e) => LaunchSelectedScript();
        _scriptsView.SelectedIndexChanged += (s, e) => UpdateSelectedPathLabel();
        _scriptsView.MouseDown += ScriptsView_MouseDown;

        _autoRefreshCheck.CheckedChanged += (s, e) =>
        {
            _autoRefreshTimer.Enabled = _autoRefreshCheck.Checked;
            _statusLabel.Text = _autoRefreshCheck.Checked ? "Auto refresh enabled." : "Auto refresh disabled.";
        };

        _refreshSeconds.ValueChanged += (s, e) =>
        {
            _autoRefreshTimer.Interval = (int)_refreshSeconds.Value * 1000;
            if (_autoRefreshCheck.Checked) { _statusLabel.Text = "Auto refresh interval updated."; }
        };

        _browseRootButton.Click += (s, e) => BrowseForRootPath();
    }

    private void ScriptsView_MouseDown(object sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Right) { return; }
        var hit = _scriptsView.HitTest(e.Location);
        if (hit.Item != null)
        {
            hit.Item.Selected = true;
            UpdateSelectedPathLabel();
        }
    }

    private void BrowseForRootPath()
    {
        using (var browser = new FolderBrowserDialog())
        {
            browser.Description = "Select script directory";
            browser.SelectedPath = _rootPath;
            if (browser.ShowDialog() == DialogResult.OK && Directory.Exists(browser.SelectedPath))
            {
                _rootPath = browser.SelectedPath;
                _rootPathBox.Text = _rootPath;
                RefreshScripts();
                _statusLabel.Text = "Script directory updated.";
            }
        }
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
            if (fileName.Equals("CodexPulseLauncher.ps1", StringComparison.OrdinalIgnoreCase)) { continue; }
            if (needle.Length > 0 && fileName.IndexOf(needle, StringComparison.OrdinalIgnoreCase) < 0 && script.IndexOf(needle, StringComparison.OrdinalIgnoreCase) < 0) { continue; }

            var item = new ListViewItem(fileName);
            item.SubItems.Add(Path.GetDirectoryName(script) ?? string.Empty);
            item.SubItems.Add(File.GetLastWriteTime(script).ToString("yyyy-MM-dd HH:mm"));
            item.Tag = script;
            _scriptsView.Items.Add(item);
            count++;
        }

        _statusLabel.Text = string.Format("Ready - Found {0} script(s) in {1}", count, _rootPath);
        if (_scriptsView.Items.Count > 0) { _scriptsView.Items[0].Selected = true; }
        else { _pathLabel.Text = "Selected: (none)"; }
    }

    private string GetSelectedScript()
    {
        if (_scriptsView.SelectedItems.Count == 0) { return null; }
        return _scriptsView.SelectedItems[0].Tag as string;
    }

    private void UpdateSelectedPathLabel()
    {
        var script = GetSelectedScript();
        _pathLabel.Text = script == null ? "Selected: (none)" : "Selected: " + script;
    }

    private void EditSelectedInIse(bool runAsAdmin)
    {
        var script = GetSelectedScript();
        if (string.IsNullOrWhiteSpace(script)) { _statusLabel.Text = "Select a script first."; return; }

        try
        {
            if (runAsAdmin && !_isAdmin)
            {
                Process.Start(new ProcessStartInfo { FileName = "powershell_ise.exe", Arguments = "\"" + script + "\"", Verb = "runas", UseShellExecute = true });
                _statusLabel.Text = "Opened in ISE as Administrator (UAC prompt).";
                return;
            }

            Process.Start(new ProcessStartInfo { FileName = "powershell_ise.exe", Arguments = "\"" + script + "\"", UseShellExecute = true });
            _statusLabel.Text = runAsAdmin ? "Already elevated - opened in ISE." : "Opened in ISE.";
        }
        catch (Exception ex)
        {
            _statusLabel.Text = "Open in ISE failed: " + ex.Message;
        }
    }

    private void OpenSelectedFolder()
    {
        var script = GetSelectedScript();
        if (string.IsNullOrWhiteSpace(script)) { _statusLabel.Text = "Select a script first."; return; }

        var dir = Path.GetDirectoryName(script);
        if (dir == null) { return; }

        Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = dir, UseShellExecute = true });
        _statusLabel.Text = "Opened script folder.";
    }

    private void LaunchSelectedScript()
    {
        var script = GetSelectedScript();
        if (string.IsNullOrWhiteSpace(script)) { _statusLabel.Text = "Select a script first."; return; }

        try
        {
            var escapedPath = script.Replace("\"", "\"\"");
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + escapedPath + "\"",
                WorkingDirectory = Path.GetDirectoryName(script) ?? _rootPath,
                UseShellExecute = true
            });

            _statusLabel.Text = "Launched: " + Path.GetFileName(script);
        }
        catch (Exception ex)
        {
            _statusLabel.Text = "Launch failed: " + ex.Message;
        }
    }
}
"@

Add-Type -TypeDefinition $launcherCSharp -Language CSharp -ReferencedAssemblies System.Windows.Forms,System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[void][System.Windows.Forms.Application]::Run([CodexPulseLauncherForm]::new($RootPath))
