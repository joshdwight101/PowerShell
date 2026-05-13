using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Security.Principal;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RightClickMeApp
{
    // --- Application Entry Point ---
    public static class Program
    {
        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // --- Self-Elevation Check ---
            bool isElevated;
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                isElevated = principal.IsInRole(WindowsBuiltInRole.Administrator);
            }

            if (!isElevated)
            {
                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    UseShellExecute = true,
                    WorkingDirectory = Environment.CurrentDirectory,
                    FileName = Application.ExecutablePath,
                    Verb = "runas" // Triggers UAC prompt
                };
                
                try 
                { 
                    Process.Start(startInfo); 
                } 
                catch 
                { 
                    // User cancelled the UAC prompt
                    MessageBox.Show("Administrator privileges are required to modify the Context Menu registry.", "Elevation Required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
                return;
            }

            Application.Run(new MainForm());
        }
    }

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

    public class TemplateModel
    {
        public string Name { get; set; }
        public List<MenuItemData> Items { get; set; }
    }

    // --- Main Application Form ---
    public class MainForm : Form
    {
        private const string AppVersion = "v1.0.8";
        private const string AppAuthor = "Joshua Dwight";
        private const string AppSlogan = "The Context Menu Builder";
        
        private TreeView tvMenus;
        private TextBox txtName, txtCommand;
        private ComboBox cmbTarget, cmbCommandType;
        private CheckBox chkRunAsAdmin;
        private Button btnApply, btnAddRoot, btnAddChild, btnDelete, btnTemplates, btnExport, btnImport;

        // Template Manager fields
        private TabControl mainTabs;
        private TabPage tabBuilder, tabTemplates;
        private ListBox lstTemplates;
        private List<TemplateModel> savedTemplates = new List<TemplateModel>();
        private string templatesFilePath;

        public MainForm()
        {
            try
            {
                InitializeComponent();
            }
            catch (Exception ex)
            {
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
            ToolStripMenuItem manualMenuItem = new ToolStripMenuItem("User Manual", null, ShowUserManual);
            ToolStripMenuItem aboutMenuItem = new ToolStripMenuItem("About", null, ShowAboutDialog);
            helpMenu.DropDownItems.Add(manualMenuItem);
            helpMenu.DropDownItems.Add(aboutMenuItem);

            menuStrip.Items.Add(fileMenu);
            menuStrip.Items.Add(helpMenu);
            this.Controls.Add(menuStrip);
            this.MainMenuStrip = menuStrip;

            // --- Main Split Container ---
            SplitContainer split = new SplitContainer();
            split.Width = 1000;
            split.Height = 600;
            split.Panel1MinSize = 250;
            split.Panel2MinSize = 400;
            split.SplitterDistance = 350;
            split.Dock = DockStyle.Fill;
            
            // --- Tab Control Setup ---
            mainTabs = new TabControl { Dock = DockStyle.Fill };
            tabBuilder = new TabPage("Menu Builder");
            tabTemplates = new TabPage("Template Manager");
            
            mainTabs.TabPages.Add(tabBuilder);
            mainTabs.TabPages.Add(tabTemplates);
            
            this.Controls.Add(mainTabs);
            mainTabs.BringToFront();
            
            // Move split container to tabBuilder
            tabBuilder.Controls.Add(split);
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
            
            tabBuilder.Controls.Add(bottomPanel);
            split.Panel2.Controls.Add(rightPanel);
            
            // --- Template Manager Setup ---
            SetupTemplateManagerUI();
            LoadSavedTemplates();

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

        private void ShowUserManual(object sender, EventArgs e)
        {
            Form manualForm = new Form { Text = "RightClickMe - User Manual", Size = new Size(800, 600), StartPosition = FormStartPosition.CenterParent };
            TextBox txtManual = new TextBox { 
                Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Vertical, 
                Font = new Font("Consolas", 10F), Padding = new Padding(10), BackColor = Color.White
            };
            
            txtManual.Text = "=======================================================\r\n" +
                             "               RightClickMe - USER MANUAL              \r\n" +
                             "=======================================================\r\n\r\n" +
                             "1. CONCEPTS\r\n" +
                             "RightClickMe allows you to add custom items to your Windows right-click menu.\r\n" +
                             "- Root Menu: A primary item in the context menu.\r\n" +
                             "- Submenu: A folder-like item that contains more commands.\r\n\r\n" +
                             "2. TARGETS\r\n" +
                             "- File: Appears when right-clicking any file.\r\n" +
                             "- Folder: Appears when right-clicking a folder.\r\n" +
                             "- Background: Appears when right-clicking the empty space inside a folder or desktop.\r\n\r\n" +
                             "3. COMMAND TYPES\r\n" +
                             "- PowerShell: Runs a native PowerShell script/command.\r\n" +
                             "  * Use '%1' for the selected file path.\r\n" +
                             "  * Use '%V' for the selected folder/background path.\r\n" +
                             "- CMD: Runs a standard command prompt action.\r\n" +
                             "- EXE: Launches a program (e.g., 'notepad.exe %1').\r\n\r\n" +
                             "4. RUN AS ADMINISTRATOR\r\n" +
                             "Checking this box forces the command to prompt for UAC elevation before running.\r\n" +
                             "A shield icon will automatically appear next to your context menu item.\r\n\r\n" +
                             "5. TEMPLATE MANAGER\r\n" +
                             "You can save your current menu configurations as templates in the 'Template Manager' tab.\r\n" +
                             "This allows you to quickly switch between different toolsets without relying on manual JSON exports.\r\n\r\n" +
                             "6. EXPORT / IMPORT\r\n" +
                             "Use these buttons to save your configuration to a JSON file to share with other users or machines.\r\n\r\n" +
                             "7. APPLYING TO REGISTRY\r\n" +
                             "Once your menu is built, click 'Apply to Registry'. This safely modifies the HKCR registry hive.\r\n" +
                             "Changes take effect instantly. Right-click anywhere to test them out!\r\n";
                             
            manualForm.Controls.Add(txtManual);
            manualForm.ShowDialog();
        }

        private void SetupTemplateManagerUI()
        {
            Panel tmLeftPanel = new Panel { Dock = DockStyle.Left, Width = 300, Padding = new Padding(10) };
            lstTemplates = new ListBox { Dock = DockStyle.Fill, Font = new Font("Segoe UI", 10F) };
            tmLeftPanel.Controls.Add(lstTemplates);

            Panel tmRightPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(20) };
            Button btnLoadTemplate = new Button { Text = "Load Selected to Builder", Width = 200, Height = 40, Location = new Point(20, 20) };
            Button btnSaveTemplate = new Button { Text = "Save Current Builder as Template", Width = 200, Height = 40, Location = new Point(20, 70) };
            Button btnDeleteTemplate = new Button { Text = "Delete Selected Template", Width = 200, Height = 40, Location = new Point(20, 120), ForeColor = Color.Red };

            btnLoadTemplate.Click += LoadSelectedTemplate;
            btnSaveTemplate.Click += SaveCurrentAsTemplate;
            btnDeleteTemplate.Click += DeleteSelectedTemplate;

            tmRightPanel.Controls.Add(btnLoadTemplate);
            tmRightPanel.Controls.Add(btnSaveTemplate);
            tmRightPanel.Controls.Add(btnDeleteTemplate);

            Label lblInstructions = new Label { 
                Text = "Template Manager lets you save and manage full menu structures locally.\n\n" + 
                       "1. Build your menu in the 'Menu Builder' tab.\n" +
                       "2. Come here and click 'Save Current Builder as Template'.\n" +
                       "3. Load it back anytime!",
                Location = new Point(20, 180), Size = new Size(400, 100) 
            };
            tmRightPanel.Controls.Add(lblInstructions);

            tabTemplates.Controls.Add(tmRightPanel);
            tabTemplates.Controls.Add(tmLeftPanel);

            string appDataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "RightClickMe");
            if (!Directory.Exists(appDataDir)) Directory.CreateDirectory(appDataDir);
            templatesFilePath = Path.Combine(appDataDir, "templates.json");
        }

        private void LoadSavedTemplates()
        {
            if (File.Exists(templatesFilePath))
            {
                try
                {
                    string json = File.ReadAllText(templatesFilePath);
                    JavaScriptSerializer js = new JavaScriptSerializer();
                    savedTemplates = js.Deserialize<List<TemplateModel>>(json) ?? new List<TemplateModel>();
                }
                catch { savedTemplates = new List<TemplateModel>(); }
            }
            RefreshTemplateList();
        }

        private void SaveTemplatesToDisk()
        {
            JavaScriptSerializer js = new JavaScriptSerializer();
            string json = js.Serialize(savedTemplates);
            File.WriteAllText(templatesFilePath, json);
            RefreshTemplateList();
        }

        private void RefreshTemplateList()
        {
            lstTemplates.Items.Clear();
            foreach (var tm in savedTemplates)
            {
                lstTemplates.Items.Add(tm.Name);
            }
        }

        private void SaveCurrentAsTemplate(object sender, EventArgs e)
        {
            if (tvMenus.Nodes.Count == 0)
            {
                MessageBox.Show("The Menu Builder is empty. Nothing to save.", "Warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string name = ShowInputBox("Save Template", "Enter a name for this template:");
            if (string.IsNullOrWhiteSpace(name)) return;

            List<MenuItemData> items = new List<MenuItemData>();
            foreach (TreeNode node in tvMenus.Nodes)
            {
                items.Add(BuildDataTree(node));
            }

            TemplateModel newTemplate = new TemplateModel { Name = name, Items = items };
            savedTemplates.Add(newTemplate);
            SaveTemplatesToDisk();
            MessageBox.Show("Template saved successfully!", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void LoadSelectedTemplate(object sender, EventArgs e)
        {
            if (lstTemplates.SelectedIndex == -1) return;
            
            if (tvMenus.Nodes.Count > 0)
            {
                if (MessageBox.Show("This will clear the current Menu Builder. Continue?", "Load Template", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            }

            string selectedName = lstTemplates.SelectedItem.ToString();
            TemplateModel tm = savedTemplates.Find(t => t.Name == selectedName);
            if (tm != null)
            {
                tvMenus.Nodes.Clear();
                foreach (var item in tm.Items)
                {
                    tvMenus.Nodes.Add(BuildNodeTree(item));
                }
                mainTabs.SelectedTab = tabBuilder;
                MessageBox.Show("Loaded template '" + tm.Name + "'.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void DeleteSelectedTemplate(object sender, EventArgs e)
        {
            if (lstTemplates.SelectedIndex == -1) return;

            string selectedName = lstTemplates.SelectedItem.ToString();
            if (MessageBox.Show("Are you sure you want to delete the template '" + selectedName + "'?", "Confirm Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                savedTemplates.RemoveAll(t => t.Name == selectedName);
                SaveTemplatesToDisk();
            }
        }

        private string ShowInputBox(string title, string promptText)
        {
            Form form = new Form { Width = 400, Height = 150, FormBorderStyle = FormBorderStyle.FixedDialog, Text = title, StartPosition = FormStartPosition.CenterScreen, MinimizeBox = false, MaximizeBox = false };
            Label label = new Label { Left = 20, Top = 20, Text = promptText, AutoSize = true };
            TextBox textBox = new TextBox { Left = 20, Top = 45, Width = 340 };
            Button btnOk = new Button { Text = "OK", Left = 200, Top = 75, Width = 75, DialogResult = DialogResult.OK };
            Button btnCancel = new Button { Text = "Cancel", Left = 285, Top = 75, Width = 75, DialogResult = DialogResult.Cancel };

            form.Controls.Add(label);
            form.Controls.Add(textBox);
            form.Controls.Add(btnOk);
            form.Controls.Add(btnCancel);
            form.AcceptButton = btnOk;
            form.CancelButton = btnCancel;

            return form.ShowDialog() == DialogResult.OK ? textBox.Text : "";
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