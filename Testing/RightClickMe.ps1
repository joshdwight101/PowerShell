# RightClickMe - The Context Menu Builder
# Author: Joshua Dwight
# Version: 1.0.6
# Description: PowerShell + C# Hybrid App to manage Windows 11/10 Context Menus

[CmdletBinding()]
param (
    [switch]$DebugMode
)

$LogFile = "$env:TEMP\RightClickMe_Debug.log"
function Write-Log($Message) {
    if ($DebugMode) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] $Message"
        Write-Host -ForegroundColor Cyan $logEntry
        Add-Content -Path $LogFile -Value $logEntry
    }
}

if ($DebugMode) { 
    Clear-Content -Path $LogFile -ErrorAction SilentlyContinue
    Write-Log "Initializing RightClickMe App (v1.0.6) Debug Mode..." 
}

# --- Self-Elevation Check ---
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isElevated) {
    Write-Log "Not elevated. Requesting Administrator privileges..."
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($DebugMode) { $argList += " -DebugMode" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

Write-Log "Elevation verified. Proceeding with application execution..."

# --- C# Source Code for the Application ---
$AppSessionId = (New-Guid).Guid.Replace("-", "")
Write-Log "Generated unique AppSessionId: $AppSessionId"

$RightClickMeCode = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Web.Script.Serialization;
using System.IO;

namespace RightClickMeApp_$AppSessionId
{
    // --- Data Models ---
    public class MenuItemData
    {
        public string Name { get; set; }
        public string Target { get; set; } // File, Folder, Background
        public string CommandType { get; set; } // PowerShell, CMD, EXE
        public string Command { get; set; }
        public bool RunAsAdmin { get; set; }
        public List<MenuItemData> Children { get; set; }

        public MenuItemData()
        {
            Name = "New Item";
            Target = "File";
            CommandType = "CMD";
            Command = "";
            RunAsAdmin = false;
            Children = new List<MenuItemData>();
        }
    }

    // --- Main Application Form ---
    public class MainForm : Form
    {
        private const string AppVersion = "v1.0.6";
        private const string AppAuthor = "Joshua Dwight";
        private const string AppSlogan = "The Context Menu Builder";
        
        private TreeView tvMenus;
        private TextBox txtName, txtCommand;
        private ComboBox cmbTarget, cmbCommandType;
        private CheckBox chkRunAsAdmin;
        private Button btnApply, btnAddRoot, btnAddChild, btnDelete, btnTemplates, btnExport, btnImport;

        public MainForm()
        {
            try
            {
                InitializeComponent();
            }
            catch (Exception ex)
            {
                // Unhandled UI Exception Catcher
                MessageBox.Show("Fatal Error in InitializeComponent:\n" + ex.Message + "\n\nStackTrace:\n" + ex.StackTrace, "Debug Crash Handler", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Environment.Exit(1);
            }
        }

        private void InitializeComponent()
        {
            this.Text = "RightClickMe " + AppVersion + " - " + AppAuthor;
            this.Size = new Size(1000, 650);
            this.MinimumSize = new Size(800, 500);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point, ((byte)(0)));

            // --- Menu Strip ---
            MenuStrip menuStrip = new MenuStrip();
            ToolStripMenuItem fileMenu = new ToolStripMenuItem("File");
            ToolStripMenuItem exitMenuItem = new ToolStripMenuItem("Exit", null, (s, e) => Application.Exit());
            fileMenu.DropDownItems.Add(exitMenuItem);

            ToolStripMenuItem helpMenu = new ToolStripMenuItem("Help");
            ToolStripMenuItem aboutMenuItem = new ToolStripMenuItem("About", null, ShowAboutDialog);
            helpMenu.DropDownItems.Add(aboutMenuItem);

            menuStrip.Items.Add(fileMenu);
            menuStrip.Items.Add(helpMenu);
            this.Controls.Add(menuStrip);
            this.MainMenuStrip = menuStrip;

            // --- Main Split Container ---
            SplitContainer split = new SplitContainer();
            
            // CRITICAL FIX: Force an initial width BEFORE setting constraints to prevent the 0px .ctor bounds crash.
            split.Width = 1000;
            split.Height = 600;
            
            // Now apply settings safely
            split.Panel1MinSize = 250;
            split.Panel2MinSize = 400;
            split.SplitterDistance = 350;
            split.Dock = DockStyle.Fill;
            
            this.Controls.Add(split);
            split.BringToFront();

            // --- Left Panel (Tree) ---
            Panel leftPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(10) };
            tvMenus = new TreeView { Dock = DockStyle.Fill, HideSelection = false };
            tvMenus.AfterSelect += TvMenus_AfterSelect;
            leftPanel.Controls.Add(tvMenus);
            split.Panel1.Controls.Add(leftPanel);

            // --- Right Panel (Properties) ---
            Panel rightPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(10) };
            GroupBox gbProps = new GroupBox { Text = "Item Properties", Dock = DockStyle.Top, Height = 340, Padding = new Padding(15) };
            
            TableLayoutPanel tlpProps = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 5 };
            tlpProps.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            tlpProps.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));

            tlpProps.Controls.Add(new Label { Text = "Name:", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
            txtName = new TextBox { Dock = DockStyle.Fill, Margin = new Padding(3, 8, 3, 8) };
            txtName.TextChanged += UpdateNodeData;
            tlpProps.Controls.Add(txtName, 1, 0);

            tlpProps.Controls.Add(new Label { Text = "Target:", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 1);
            cmbTarget = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList, Margin = new Padding(3, 8, 3, 8) };
            cmbTarget.Items.AddRange(new string[] { "File", "Folder", "Background" });
            cmbTarget.SelectedIndexChanged += UpdateNodeData;
            tlpProps.Controls.Add(cmbTarget, 1, 1);

            tlpProps.Controls.Add(new Label { Text = "Command Type:", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 2);
            cmbCommandType = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList, Margin = new Padding(3, 8, 3, 8) };
            cmbCommandType.Items.AddRange(new string[] { "PowerShell", "CMD", "EXE" });
            cmbCommandType.SelectedIndexChanged += UpdateNodeData;
            tlpProps.Controls.Add(cmbCommandType, 1, 2);

            tlpProps.Controls.Add(new Label { Text = "Command/Path:", AutoSize = true, Anchor = AnchorStyles.Left | AnchorStyles.Top, Margin = new Padding(0, 8, 0, 0) }, 0, 3);
            txtCommand = new TextBox { Dock = DockStyle.Fill, Multiline = true, Height = 90, Margin = new Padding(3, 8, 3, 8) };
            txtCommand.TextChanged += UpdateNodeData;
            tlpProps.Controls.Add(txtCommand, 1, 3);

            chkRunAsAdmin = new CheckBox { Text = "Run as Administrator (Requires UAC prompt on use)", AutoSize = true, Margin = new Padding(3, 8, 3, 8) };
            chkRunAsAdmin.CheckedChanged += UpdateNodeData;
            tlpProps.Controls.Add(chkRunAsAdmin, 1, 4);

            gbProps.Controls.Add(tlpProps);

            // --- Right Panel (Actions) ---
            GroupBox gbActions = new GroupBox { Text = "Actions", Dock = DockStyle.Top, Height = 80, Padding = new Padding(15) };
            FlowLayoutPanel flpActions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
            
            btnAddRoot = new Button { Text = "Add Root Menu", AutoSize = true, Height = 30, Margin = new Padding(0, 0, 10, 0) };
            btnAddChild = new Button { Text = "Add Submenu", AutoSize = true, Height = 30, Margin = new Padding(0, 0, 10, 0) };
            btnDelete = new Button { Text = "Delete Selected", AutoSize = true, Height = 30, Margin = new Padding(0, 0, 10, 0) };
            
            btnAddRoot.Click += (s, e) => AddNode(null);
            btnAddChild.Click += (s, e) => AddNode(tvMenus.SelectedNode);
            btnDelete.Click += (s, e) => { if (tvMenus.SelectedNode != null) tvMenus.Nodes.Remove(tvMenus.SelectedNode); };

            flpActions.Controls.Add(btnAddRoot);
            flpActions.Controls.Add(btnAddChild);
            flpActions.Controls.Add(btnDelete);
            gbActions.Controls.Add(flpActions);
            
            // Add Actions first, then Props, so Props docks to the very top.
            rightPanel.Controls.Add(gbActions);
            rightPanel.Controls.Add(gbProps);

            // --- Bottom Panel (Global Actions) ---
            Panel bottomPanel = new Panel { Dock = DockStyle.Bottom, Height = 60, Padding = new Padding(10) };
            
            FlowLayoutPanel flpBottom = new FlowLayoutPanel { Dock = DockStyle.Left, AutoSize = true, WrapContents = false };
            btnExport = new Button { Text = "Export JSON", AutoSize = true, Height = 30, Margin = new Padding(0, 5, 10, 5) };
            btnImport = new Button { Text = "Import JSON", AutoSize = true, Height = 30, Margin = new Padding(0, 5, 10, 5) };
            btnTemplates = new Button { Text = "Load Templates", AutoSize = true, Height = 30, Margin = new Padding(0, 5, 10, 5) };
            
            btnExport.Click += ExportJson;
            btnImport.Click += ImportJson;
            btnTemplates.Click += LoadTemplates;

            flpBottom.Controls.Add(btnExport);
            flpBottom.Controls.Add(btnImport);
            flpBottom.Controls.Add(btnTemplates);
            
            btnApply = new Button { Text = "Apply to Registry", Dock = DockStyle.Right, Width = 150, Height = 40, BackColor = Color.LightGreen };
            btnApply.Click += ApplyToRegistry;

            bottomPanel.Controls.Add(flpBottom);
            bottomPanel.Controls.Add(btnApply);
            
            this.Controls.Add(bottomPanel);
            
            split.Panel2.Controls.Add(rightPanel);
            
            // Add Context Menu to TreeView
            ContextMenuStrip treeContext = new ContextMenuStrip();
            treeContext.Items.Add("Add Submenu", null, (s, e) => AddNode(tvMenus.SelectedNode));
            treeContext.Items.Add("Delete", null, (s, e) => { if (tvMenus.SelectedNode != null) tvMenus.Nodes.Remove(tvMenus.SelectedNode); });
            tvMenus.ContextMenuStrip = treeContext;

            UpdateUIState();
        }

        private void ShowAboutDialog(object sender, EventArgs e)
        {
            string message = "App Title: RightClickMe\n" +
                             "Slogan: " + AppSlogan + "\n" +
                             "Version: " + AppVersion + "\n" +
                             "Author: " + AppAuthor + "\n\n" +
                             "Summary: A Super Admin Tool for building and managing Windows 11 & 10 context menus via the Registry. Supports nested menus, PowerShell scripts, and elevated commands.";
            MessageBox.Show(message, "About RightClickMe", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private bool isUpdatingUI = false;

        private void TvMenus_AfterSelect(object sender, TreeViewEventArgs e)
        {
            UpdateUIState();
        }

        private void UpdateUIState()
        {
            if (tvMenus.SelectedNode == null)
            {
                txtName.Enabled = cmbTarget.Enabled = cmbCommandType.Enabled = txtCommand.Enabled = chkRunAsAdmin.Enabled = false;
                txtName.Text = txtCommand.Text = "";
                return;
            }

            txtName.Enabled = cmbTarget.Enabled = cmbCommandType.Enabled = txtCommand.Enabled = chkRunAsAdmin.Enabled = true;
            
            MenuItemData data = (MenuItemData)tvMenus.SelectedNode.Tag;
            isUpdatingUI = true;
            txtName.Text = data.Name;
            cmbTarget.SelectedItem = data.Target;
            cmbCommandType.SelectedItem = data.CommandType;
            txtCommand.Text = data.Command;
            chkRunAsAdmin.Checked = data.RunAsAdmin;
            
            // Only root nodes define the target
            cmbTarget.Enabled = (tvMenus.SelectedNode.Parent == null);
            
            // If it has children, it's a submenu, no command execution directly
            if (tvMenus.SelectedNode.Nodes.Count > 0)
            {
                cmbCommandType.Enabled = false;
                txtCommand.Enabled = false;
                chkRunAsAdmin.Enabled = false;
            }
            isUpdatingUI = false;
        }

        private void UpdateNodeData(object sender, EventArgs e)
        {
            if (isUpdatingUI || tvMenus.SelectedNode == null) return;
            
            MenuItemData data = (MenuItemData)tvMenus.SelectedNode.Tag;
            data.Name = txtName.Text;
            if (cmbTarget.SelectedItem != null) data.Target = cmbTarget.SelectedItem.ToString();
            if (cmbCommandType.SelectedItem != null) data.CommandType = cmbCommandType.SelectedItem.ToString();
            data.Command = txtCommand.Text;
            data.RunAsAdmin = chkRunAsAdmin.Checked;

            tvMenus.SelectedNode.Text = data.Name;
        }

        private void AddNode(TreeNode parent)
        {
            MenuItemData data = new MenuItemData();
            if (parent != null)
            {
                data.Target = ((MenuItemData)parent.Tag).Target; // Inherit target from parent
            }

            TreeNode node = new TreeNode(data.Name);
            node.Tag = data;

            if (parent == null) tvMenus.Nodes.Add(node);
            else { parent.Nodes.Add(node); parent.Expand(); }
            
            tvMenus.SelectedNode = node;
            UpdateUIState();
        }

        // --- Templates ---
        private void LoadTemplates(object sender, EventArgs e)
        {
            if (MessageBox.Show("This will clear current menus. Continue?", "Load Templates", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            
            tvMenus.Nodes.Clear();

            // 1. Open PowerShell Here
            MenuItemData psData = new MenuItemData { Name = "Open PowerShell Here (Admin)", Target = "Background", CommandType = "PowerShell", RunAsAdmin = true, Command = "Set-Location '%V'" };
            TreeNode psNode = new TreeNode(psData.Name) { Tag = psData };
            tvMenus.Nodes.Add(psNode);

            // 2. Copy Path
            MenuItemData cpData = new MenuItemData { Name = "Copy Path", Target = "File", CommandType = "CMD", Command = "echo %1 | clip" };
            TreeNode cpNode = new TreeNode(cpData.Name) { Tag = cpData };
            tvMenus.Nodes.Add(cpNode);

            // 3. Take Ownership
            MenuItemData toData = new MenuItemData { Name = "Take Ownership", Target = "File", CommandType = "CMD", RunAsAdmin = true, Command = "takeown /f \"%1\" && icacls \"%1\" /grant administrators:F" };
            TreeNode toNode = new TreeNode(toData.Name) { Tag = toData };
            tvMenus.Nodes.Add(toNode);
            
            // 4. Submenu Example
            MenuItemData subData = new MenuItemData { Name = "Dev Tools", Target = "Folder" };
            TreeNode subNode = new TreeNode(subData.Name) { Tag = subData };
            
            MenuItemData vsData = new MenuItemData { Name = "Open in VS Code", Target = "Folder", CommandType = "CMD", Command = "code \"%V\"" };
            TreeNode vsNode = new TreeNode(vsData.Name) { Tag = vsData };
            subNode.Nodes.Add(vsNode);
            
            tvMenus.Nodes.Add(subNode);
        }

        // --- JSON Import/Export ---
        private void ExportJson(object sender, EventArgs e)
        {
            SaveFileDialog sfd = new SaveFileDialog { Filter = "JSON files (*.json)|*.json", Title = "Export Config" };
            if (sfd.ShowDialog() == DialogResult.OK)
            {
                List<MenuItemData> rootItems = new List<MenuItemData>();
                foreach (TreeNode node in tvMenus.Nodes)
                {
                    rootItems.Add(BuildDataTree(node));
                }
                
                JavaScriptSerializer js = new JavaScriptSerializer();
                string json = js.Serialize(rootItems);
                File.WriteAllText(sfd.FileName, json);
                MessageBox.Show("Exported successfully.");
            }
        }

        private MenuItemData BuildDataTree(TreeNode node)
        {
            MenuItemData data = (MenuItemData)node.Tag;
            data.Children.Clear();
            foreach (TreeNode child in node.Nodes)
            {
                data.Children.Add(BuildDataTree(child));
            }
            return data;
        }

        private void ImportJson(object sender, EventArgs e)
        {
            OpenFileDialog ofd = new OpenFileDialog { Filter = "JSON files (*.json)|*.json", Title = "Import Config" };
            if (ofd.ShowDialog() == DialogResult.OK)
            {
                try
                {
                    string json = File.ReadAllText(ofd.FileName);
                    JavaScriptSerializer js = new JavaScriptSerializer();
                    List<MenuItemData> items = js.Deserialize<List<MenuItemData>>(json);
                    
                    tvMenus.Nodes.Clear();
                    foreach (var item in items)
                    {
                        tvMenus.Nodes.Add(BuildNodeTree(item));
                    }
                    MessageBox.Show("Imported successfully.");
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error importing: " + ex.Message);
                }
            }
        }

        private TreeNode BuildNodeTree(MenuItemData data)
        {
            TreeNode node = new TreeNode(data.Name);
            node.Tag = data;
            if (data.Children != null)
            {
                foreach (var childData in data.Children)
                {
                    node.Nodes.Add(BuildNodeTree(childData));
                }
            }
            return node;
        }

        // --- Registry Engine ---
        private void ApplyToRegistry(object sender, EventArgs e)
        {
            try
            {
                foreach (TreeNode node in tvMenus.Nodes)
                {
                    MenuItemData data = (MenuItemData)node.Tag;
                    string basePath = GetRegistryBasePath(data.Target);
                    WriteNodeToRegistry(node, basePath);
                }
                MessageBox.Show("Registry successfully updated! Right-click to test.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (UnauthorizedAccessException)
            {
                MessageBox.Show("Failed to write to registry. The tool must be run as Administrator.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Registry error: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private string GetRegistryBasePath(string target)
        {
            switch (target)
            {
                case "File": return @"*\shell";
                case "Folder": return @"Directory\shell";
                case "Background": return @"Directory\Background\shell";
                default: return @"*\shell";
            }
        }

        private string SanitizeKeyName(string name)
        {
            return name.Replace(" ", "").Replace("\\", "").Replace("/", "");
        }

        private void WriteNodeToRegistry(TreeNode node, string parentKeyPath)
        {
            MenuItemData data = (MenuItemData)node.Tag;
            string keyName = SanitizeKeyName(data.Name);
            string fullKeyPath = parentKeyPath + "\\" + keyName;

            using (RegistryKey key = Registry.ClassesRoot.CreateSubKey(fullKeyPath))
            {
                if (node.Nodes.Count > 0) // Is Submenu
                {
                    key.SetValue("MUIVerb", data.Name);
                    key.SetValue("SubCommands", ""); // Required for Win10/11 cascading
                    
                    string shellPath = fullKeyPath + "\\shell";
                    foreach (TreeNode child in node.Nodes)
                    {
                        WriteNodeToRegistry(child, shellPath);
                    }
                }
                else // Is Command
                {
                    key.SetValue("", data.Name);
                    if (data.RunAsAdmin) key.SetValue("HasLUAShield", ""); // Shows the UAC shield icon

                    using (RegistryKey cmdKey = key.CreateSubKey("command"))
                    {
                        string execCmd = BuildExecutionCommand(data);
                        cmdKey.SetValue("", execCmd);
                    }
                }
            }
        }

        private string BuildExecutionCommand(MenuItemData data)
        {
            string cmd = data.Command;
            
            // %1 is for Files, %V is for Directories/Backgrounds
            string targetVar = data.Target == "File" ? "%1" : "%V";

            if (data.CommandType == "PowerShell")
            {
                if (data.RunAsAdmin)
                {
                    // Encapsulate into Start-Process with Verb RunAs
                    return "powershell.exe -WindowStyle Hidden -Command \"Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \\\"& { " + cmd + " }\\\"' -Verb RunAs\"";
                }
                else
                {
                    return "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"& { " + cmd + " }\"";
                }
            }
            else if (data.CommandType == "CMD")
            {
                if (data.RunAsAdmin)
                {
                    return "powershell.exe -WindowStyle Hidden -Command \"Start-Process cmd.exe -ArgumentList '/c " + cmd.Replace("\"", "\\\"") + "' -Verb RunAs\"";
                }
                else
                {
                    return "cmd.exe /c " + cmd;
                }
            }
            else // EXE
            {
                return cmd;
            }
        }
    }
}
"@

# Load Required Assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions # Required for JavaScriptSerializer (JSON)

# Compile and Run
try {
    Write-Log "Compiling C# Source Code via Add-Type..."
    Add-Type -TypeDefinition $RightClickMeCode -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Web.Extensions, mscorlib -ErrorAction Stop
    
    Write-Log "Enabling Visual Styles and initializing MainForm..."
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object RightClickMeApp_$AppSessionId.MainForm
    
    Write-Log "Starting Application Message Loop..."
    [System.Windows.Forms.Application]::Run($form)
    Write-Log "Application closed normally."
}
catch {
    Write-Log "CRITICAL ERROR: Failed to compile or run the application."
    Write-Log $_.Exception.Message
    if ($DebugMode) {
        Write-Log $_.ScriptStackTrace
        Write-Log $_.Exception.StackTrace
    }
    Write-Error "Failed to compile or run the application."
    Write-Error $_.Exception.Message
    Pause
}
# SIG # Begin signature block
# MIIFiwYJKoZIhvcNAQcCoIIFfDCCBXgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUcvPba/eKdP1QwQpd9fEaWGFI
# cHSgggMcMIIDGDCCAgCgAwIBAgIQdTnGUb3fnrZCF1K2xTtGMjANBgkqhkiG9w0B
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
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUsAv+JkWQqw7Y6+HSTTr/okHqn2owDQYJ
# KoZIhvcNAQEBBQAEggEAJw85Mb1R/84GgMPehXCMkS/KanmjbyZOdDTMawCKiGj8
# q+d2t19QcWmBAIDdRri9FTMQLgt0JFMpwJW21yA93Qrimbo2nfbSjcml2fByglPG
# uabAFSn1E70Kpg1WBvjCde3U+hRJvANMqZdMJ1Hq3zFbtF+u4g4Y3RD9L8P50oWR
# OBIihtTeoISN+pMqwM9nGMTJxfNihJBnHfTM3KLRHulMdfAJLrx4yb+jXZn7Vkzh
# a66mNkzA4zMzCxNUz7L/OMcq99Ajgy7lKRq+fkqegxcFHEVUkoIz6Bz/4xv886tE
# pg7lmQgQQrze10gusDySeeUX/FswR4r/VjZegGF7EA==
# SIG # End signature block
